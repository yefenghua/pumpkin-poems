import Foundation

/// A source-attributed, punctuation-free five/seven-character line for poetry games.
/// These are game materials; only hasLearningPage entries have authored lessons/quizzes.
nonisolated struct GameVerse: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let poemID: String
    let title: LocalizedText
    let author: LocalizedText
    let text: LocalizedText
    let companion: LocalizedText?
    let hasLearningPage: Bool
}

struct GameContent: Decodable {
    let version: String
    let verses: [GameVerse]
    let hantToHans: [String: String]
    let poems: [GamePoem]?

    init(version: String, verses: [GameVerse], hantToHans: [String: String], poems: [GamePoem]? = nil) {
        self.version = version
        self.verses = verses
        self.hantToHans = hantToHans
        self.poems = poems
    }
}

/// Source classifications are retained; extension poems without a curriculum stage are
/// deliberately not assigned an invented school year.
struct GamePoem: Decodable, Hashable, Identifiable {
    let id: String
    let title: LocalizedText
    let author: LocalizedText
    let authorID: String
    let genre: LocalizedText
    let dynasty: LocalizedText
    let keyStages: [Int]
    let lineLengths: [Int]
    let hasLearningPage: Bool
}

final class GameCorpus {
    static let shared: GameCorpus = {
        guard let url = Bundle.main.url(forResource: "GameContent", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode(GameContent.self, from: data) else {
            // Keep the game hub usable with existing authored lessons if an older package is loaded.
            let library = PoemLibrary.shared
            let verses = library.poems.flatMap { poem in
                poem.lines.enumerated().compactMap { index, line -> GameVerse? in
                    let text = LocalizedText(hant: String(line.text.hant.filter(TextNormalizer.isHan)),
                                             hans: String(line.text.hans.filter(TextNormalizer.isHan)))
                    guard [5, 7].contains(text.hans.count), text.hant.count == text.hans.count else { return nil }
                    let partner = index.isMultiple(of: 2) ? index + 1 : index - 1
                    let companion = poem.lines.indices.contains(partner) ? poem.lines[partner].text : nil
                    return GameVerse(id: line.id, poemID: poem.id, title: poem.title, author: poem.author.name,
                                     text: text, companion: companion, hasLearningPage: true)
                }
            }
            return GameCorpus(verses: verses, normalizer: library.normalizer)
        }
        return GameCorpus(verses: content.verses, normalizer: TextNormalizer(hantToHans: content.hantToHans), poems: content.poems ?? [])
    }()

    let verses: [GameVerse]
    let normalizer: TextNormalizer
    let poems: [GamePoem]

    init(verses: [GameVerse], normalizer: TextNormalizer, poems: [GamePoem] = []) {
        self.verses = verses
        self.normalizer = normalizer
        let available = Set(verses.map(\.poemID))
        var seen: Set<String> = []
        var metadata = poems.filter { available.contains($0.id) && seen.insert($0.id).inserted }
        for verse in verses where seen.insert(verse.poemID).inserted {
            metadata.append(GamePoem(id: verse.poemID, title: verse.title, author: verse.author,
                authorID: normalizer.normalize(verse.author.hans),
                genre: LocalizedText(hant: "未分類", hans: "未分类"),
                dynasty: LocalizedText(hant: "", hans: ""), keyStages: [],
                lineLengths: Set(verses.filter { $0.poemID == verse.poemID }.map { $0.text.hans.count }).sorted(),
                hasLearningPage: verse.hasLearningPage))
        }
        self.poems = metadata
    }
}
