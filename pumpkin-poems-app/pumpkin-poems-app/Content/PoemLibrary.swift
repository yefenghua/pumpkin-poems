import Foundation

/// The built-in, read-only poem library bundled with the app.
final class PoemLibrary {
    static let shared = PoemLibrary.loadBundled()

    let version: String
    let themes: [PoemTheme]
    let poems: [Poem]
    let feiHuaLingCharacters: [LocalizedText]
    let normalizer: TextNormalizer

    private let poemsByID: [String: Poem]
    private let searchKeys: [String: String]

    init(content: PoemContent) {
        version = content.version
        themes = content.themes
        poems = content.poems
        feiHuaLingCharacters = content.feiHuaLing
        let normalizer = TextNormalizer(hantToHans: content.hantToHans)
        self.normalizer = normalizer
        poemsByID = Dictionary(uniqueKeysWithValues: content.poems.map { ($0.id, $0) })

        var keys: [String: String] = [:]
        for poem in content.poems {
            let parts = [poem.title, poem.author.name] + poem.lines.map(\.text)
            keys[poem.id] = parts.map { normalizer.normalize($0.hant) + "|" + normalizer.normalize($0.hans) }
                .joined(separator: "|")
        }
        searchKeys = keys
    }

    static func loadBundled() -> PoemLibrary {
        guard let url = Bundle.main.url(forResource: "PoemContent", withExtension: "json") else {
            fatalError("PoemContent.json is missing from the app bundle; run scripts/build_content.py")
        }
        do {
            let data = try Data(contentsOf: url)
            return PoemLibrary(content: try JSONDecoder().decode(PoemContent.self, from: data))
        } catch {
            fatalError("PoemContent.json could not be decoded: \(error)")
        }
    }

    func poem(_ id: String) -> Poem? { poemsByID[id] }

    func theme(_ id: String) -> PoemTheme? { themes.first { $0.id == id } }

    func poems(inTheme themeID: String) -> [Poem] { poems.filter { $0.theme == themeID } }

    /// Matches titles, authors and lines in either script.
    func matches(_ poem: Poem, query: String) -> Bool {
        let key = normalizer.normalize(query)
        guard !key.isEmpty else { return true }
        return searchKeys[poem.id]?.contains(key) ?? false
    }

    /// Distinct authors in library order.
    var authors: [PoemAuthor] {
        var seen = Set<String>()
        return poems.compactMap { seen.insert($0.author.id).inserted ? $0.author : nil }
    }
}
