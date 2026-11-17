import Foundation

/// The read-only poem library: the bundled base pack plus any downloaded theme packs.
/// `shared` follows `ContentStore`, so views that read it re-render when a pack is installed or removed.
final class PoemLibrary {
    static var shared: PoemLibrary { ContentStore.shared.library }

    /// Newest content version among the loaded packs, recorded with learning events.
    let version: String
    /// Pack ID → version, for 设置 and 主题包.
    let packVersions: [String: String]
    let themes: [PoemTheme]
    let poems: [Poem]
    let feiHuaLingCharacters: [LocalizedText]
    let sceneMatch: SceneMatchContent?
    let normalizer: TextNormalizer
    /// Questions withdrawn after release: never asked, and old records about them no longer count.
    let withdrawnQuestions: Set<String>

    private let poemsByID: [String: Poem]
    private let searchKeys: [String: String]

    convenience init(content: PoemContent) {
        self.init(packs: [content])
    }

    /// The first pack is the base; later packs add themes and poems. A poem ID that appears twice keeps its first copy.
    init(packs: [PoemContent], withdrawnQuestions: Set<String> = []) {
        self.withdrawnQuestions = withdrawnQuestions
        version = packs.map(\.version).max() ?? ""
        packVersions = Dictionary(packs.map { ($0.packID ?? "base", $0.version) }, uniquingKeysWith: { first, _ in first })

        var seenThemes = Set<String>()
        themes = packs.flatMap(\.themes).filter { seenThemes.insert($0.id).inserted }
        var seenPoems = Set<String>()
        poems = packs.flatMap(\.poems)
            .filter { seenPoems.insert($0.id).inserted }
            .map { $0.removingQuestions(withdrawnQuestions) }
        feiHuaLingCharacters = packs.first?.feiHuaLing ?? []
        sceneMatch = packs.lazy.compactMap(\.sceneMatch).first

        var hantToHans: [String: String] = [:]
        for pack in packs {
            hantToHans.merge(pack.hantToHans) { current, _ in current }
        }
        let normalizer = TextNormalizer(hantToHans: hantToHans)
        self.normalizer = normalizer
        poemsByID = Dictionary(poems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var keys: [String: String] = [:]
        for poem in poems {
            let parts = [poem.title, poem.author.name] + poem.lines.map(\.text)
            keys[poem.id] = parts.map { normalizer.normalize($0.hant) + "|" + normalizer.normalize($0.hans) }
                .joined(separator: "|")
        }
        searchKeys = keys
    }

    static func loadBundledContent() -> PoemContent {
        guard let url = Bundle.main.url(forResource: "PoemContent", withExtension: "json") else {
            fatalError("PoemContent.json is missing from the app bundle; run scripts/build_content.py")
        }
        do {
            return try JSONDecoder().decode(PoemContent.self, from: Data(contentsOf: url))
        } catch {
            fatalError("PoemContent.json could not be decoded: \(error)")
        }
    }

    func poem(_ id: String) -> Poem? { poemsByID[id] }

    func theme(_ id: String) -> PoemTheme? { themes.first { $0.id == id } }

    func poems(inTheme themeID: String) -> [Poem] { poems.filter { $0.theme == themeID } }

    /// The question with its poem, searching every loaded pack.
    func question(_ id: String) -> (poem: Poem, question: Question)? {
        for poem in poems {
            if let question = poem.question(id) { return (poem, question) }
        }
        return nil
    }

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
