import Foundation

/// Selection/grouping remains independent of UI and storage so no implicit "all poems"
/// fallback can leak into a puzzle when the user has chosen an empty library.
struct GameLibraryCatalog {
    enum Category: String, CaseIterable, Identifiable {
        case stage, author, genre, meter
        var id: String { rawValue }
        var title: LocalizedText {
            switch self {
            case .stage: return .init(hant: "按年級", hans: "按年级")
            case .author: return .init(hant: "按作者", hans: "按作者")
            case .genre: return .init(hant: "按詩類型", hans: "按诗类型")
            case .meter: return .init(hant: "按字數", hans: "按字数")
            }
        }
    }

    struct Group: Identifiable {
        let id: String
        let title: LocalizedText
        let poemIDs: Set<String>
    }

    let poems: [GamePoem]
    let normalizer: TextNormalizer
    var validIDs: Set<String> { Set(poems.map(\.id)) }

    func validated(_ selection: Set<String>) -> Set<String> { selection.intersection(validIDs) }

    func matching(_ query: String) -> [GamePoem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return poems }
        let key = normalizer.normalize(trimmed)
        return poems.filter { poem in
            let texts = [poem.title, poem.author, poem.genre, poem.dynasty]
            if !key.isEmpty {
                return texts.contains { normalizer.normalize($0.hant).contains(key) || normalizer.normalize($0.hans).contains(key) }
            }
            return texts.contains { $0.hant.localizedCaseInsensitiveContains(trimmed) || $0.hans.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    func groups(_ category: Category) -> [Group] {
        switch category {
        case .stage:
            let titles = [
                LocalizedText(hant: "小一至小三", hans: "小一至小三"),
                LocalizedText(hant: "小四至小六", hans: "小四至小六"),
                LocalizedText(hant: "中一至中三", hans: "中一至中三"),
                LocalizedText(hant: "中四至中六", hans: "中四至中六")
            ]
            var result = titles.enumerated().map { offset, title in
                Group(id: "stage-\(offset + 1)", title: title, poemIDs: Set(poems.filter { $0.keyStages.contains(offset + 1) }.map(\.id)))
            }
            result.append(Group(id: "stage-extension", title: .init(hant: "拓展篇目 · 未分年級", hans: "拓展篇目 · 未分年级"),
                                poemIDs: Set(poems.filter { $0.keyStages.isEmpty }.map(\.id))))
            return result.filter { !$0.poemIDs.isEmpty }
        case .author:
            let grouped = Dictionary(grouping: poems, by: \.authorID)
            return grouped.keys.sorted().compactMap { key in
                guard let values = grouped[key], let first = values.first else { return nil }
                return Group(id: "author-" + key, title: first.author, poemIDs: Set(values.map(\.id)))
            }.sorted { $0.title.hans.localizedStandardCompare($1.title.hans) == .orderedAscending }
        case .genre:
            let grouped = Dictionary(grouping: poems) { normalizer.normalize($0.genre.hans) }
            return grouped.keys.sorted().compactMap { key in
                guard let values = grouped[key], let first = values.first else { return nil }
                return Group(id: "genre-" + key, title: first.genre, poemIDs: Set(values.map(\.id)))
            }.sorted { $0.title.hans.localizedStandardCompare($1.title.hans) == .orderedAscending }
        case .meter:
            return [5, 7].map { count in
                Group(id: "meter-\(count)", title: .init(hant: count == 5 ? "含五字詩句" : "含七字詩句", hans: count == 5 ? "含五字诗句" : "含七字诗句"),
                      poemIDs: Set(poems.filter { $0.lineLengths.contains(count) }.map(\.id)))
            }.filter { !$0.poemIDs.isEmpty }
        }
    }

    /// Batch selections are a union; removing a group is an explicit separate action.
    func adding(_ ids: Set<String>, to selection: Set<String>) -> Set<String> {
        validated(selection.union(ids))
    }
    func removing(_ ids: Set<String>, from selection: Set<String>) -> Set<String> {
        validated(selection.subtracting(ids))
    }
}

struct SavedGameLibrary: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var poemIDs: [String]
    var updatedAt: Date
}

/// Named libraries persist separately from learning records, with defensive decoding and
/// stale-source removal when the content package changes. No SwiftData migration required.
struct GameLibraryStore {
    enum SaveProblem: Error { case emptyName, emptySelection, duplicateName, storageFailure }
    private let defaults: UserDefaults
    private let key = "games.savedLibraries.v1"
    private let validIDs: Set<String>

    init(defaults: UserDefaults = .standard, validIDs: Set<String>) {
        self.defaults = defaults
        self.validIDs = validIDs
    }

    func load() -> [SavedGameLibrary] {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([SavedGameLibrary].self, from: data) else { return [] }
        var seen: Set<UUID> = []
        return saved.compactMap { value in
            guard seen.insert(value.id).inserted else { return nil }
            let ids = Set(value.poemIDs).intersection(validIDs).sorted()
            let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !ids.isEmpty else { return nil }
            return SavedGameLibrary(id: value.id, name: name, poemIDs: ids, updatedAt: value.updatedAt)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func save(name: String, selection: Set<String>, replacing id: UUID? = nil) throws -> SavedGameLibrary {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !name.isEmpty else { throw SaveProblem.emptyName }
        let ids = selection.intersection(validIDs).sorted()
        guard !ids.isEmpty else { throw SaveProblem.emptySelection }
        var all = load()
        guard !all.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            throw SaveProblem.duplicateName
        }
        let record = SavedGameLibrary(id: id ?? UUID(), name: String(name.prefix(30)), poemIDs: ids, updatedAt: Date())
        all.removeAll { $0.id == record.id }
        all.insert(record, at: 0)
        guard let encoded = try? JSONEncoder().encode(all) else { throw SaveProblem.storageFailure }
        defaults.set(encoded, forKey: key)
        return record
    }

    func delete(_ id: UUID) {
        let all = load().filter { $0.id != id }
        if let encoded = try? JSONEncoder().encode(all) { defaults.set(encoded, forKey: key) }
    }
}
