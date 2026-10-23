import Foundation

// 小小诗人简版 (product doc §4.3, P2): themes, imagery word banks, sentence patterns and the gentle
// checks that run before saving. Pure logic, no UI, so it is covered by scripts/LogicTests.swift.

/// An imagery word the child can pick. `id` is the Simplified form so saved drafts share one key.
struct ImageryWord: Hashable, Identifiable {
    let text: LocalizedText
    var id: String { text.hans }

    init(_ hant: String, _ hans: String? = nil) {
        text = LocalizedText(hant: hant, hans: hans ?? hant)
    }
}

/// One writing theme with its word bank and a short invitation.
struct PoetWorkshopTheme: Identifiable, Hashable {
    let id: String
    let name: LocalizedText
    let invitation: LocalizedText
    let words: [ImageryWord]
    /// The library theme whose poems make the best examples for this writing theme.
    let libraryThemeID: String?
}

enum PoetWorkshopContent {
    static let themes: [PoetWorkshopTheme] = [
        PoetWorkshopTheme(
            id: "autumn",
            name: LocalizedText(hant: "秋天", hans: "秋天"),
            invitation: LocalizedText(hant: "風涼了，葉子黃了，你看見了什麼？", hans: "风凉了，叶子黄了，你看见了什么？"),
            words: [ImageryWord("月"), ImageryWord("風", "风"), ImageryWord("葉", "叶"), ImageryWord("雁"),
                    ImageryWord("霜"), ImageryWord("菊"), ImageryWord("露"), ImageryWord("桂")],
            libraryThemeID: "seasons"
        ),
        PoetWorkshopTheme(
            id: "spring",
            name: LocalizedText(hant: "春日", hans: "春日"),
            invitation: LocalizedText(hant: "花開了，鳥叫了，春天是什麼顏色？", hans: "花开了，鸟叫了，春天是什么颜色？"),
            words: [ImageryWord("花"), ImageryWord("鳥", "鸟"), ImageryWord("雨"), ImageryWord("柳"),
                    ImageryWord("草"), ImageryWord("燕"), ImageryWord("風", "风"), ImageryWord("桃")],
            libraryThemeID: "seasons"
        ),
        PoetWorkshopTheme(
            id: "school",
            name: LocalizedText(hant: "校園", hans: "校园"),
            invitation: LocalizedText(hant: "鈴聲響了，操場上、課室裏，有哪些聲音和光？", hans: "铃声响了，操场上、课室里，有哪些声音和光？"),
            words: [ImageryWord("書", "书"), ImageryWord("窗"), ImageryWord("鈴", "铃"), ImageryWord("樹", "树"),
                    ImageryWord("筆", "笔"), ImageryWord("燈", "灯"), ImageryWord("球"), ImageryWord("歌")],
            libraryThemeID: nil
        ),
        PoetWorkshopTheme(
            id: "longing",
            name: LocalizedText(hant: "思念", hans: "思念"),
            invitation: LocalizedText(hant: "想念一個人、一個地方的時候，你會看着什麼？", hans: "想念一个人、一个地方的时候，你会看着什么？"),
            words: [ImageryWord("月"), ImageryWord("家"), ImageryWord("燈", "灯"), ImageryWord("夢", "梦"),
                    ImageryWord("路"), ImageryWord("信"), ImageryWord("雲", "云"), ImageryWord("窗")],
            libraryThemeID: "moon"
        ),
        PoetWorkshopTheme(
            id: "landscape",
            name: LocalizedText(hant: "山水", hans: "山水"),
            invitation: LocalizedText(hant: "站在山上、坐在船上，遠處和近處各有什麼？", hans: "站在山上、坐在船上，远处和近处各有什么？"),
            words: [ImageryWord("山"), ImageryWord("水"), ImageryWord("舟"), ImageryWord("雲", "云"),
                    ImageryWord("橋", "桥"), ImageryWord("溪"), ImageryWord("石"), ImageryWord("松")],
            libraryThemeID: "landscape"
        ),
        PoetWorkshopTheme(
            id: "summerNight",
            name: LocalizedText(hant: "夏夜", hans: "夏夜"),
            invitation: LocalizedText(hant: "天黑了還很熱，院子裏、池塘邊有什麼在動？", hans: "天黑了还很热，院子里、池塘边有什么在动？"),
            words: [ImageryWord("星"), ImageryWord("螢", "萤"), ImageryWord("荷"), ImageryWord("蛙"),
                    ImageryWord("扇"), ImageryWord("蟬", "蝉"), ImageryWord("涼", "凉"), ImageryWord("風", "风")],
            libraryThemeID: "seasons"
        ),
    ]

    static func theme(_ id: String) -> PoetWorkshopTheme? { themes.first { $0.id == id } }

    /// Sentence shapes a child can borrow. Brackets are what they fill in.
    static let patterns: [LocalizedText] = [
        LocalizedText(hant: "〔地方〕有〔景物〕", hans: "〔地方〕有〔景物〕"),
        LocalizedText(hant: "〔景物〕像〔東西〕", hans: "〔景物〕像〔东西〕"),
        LocalizedText(hant: "〔景物〕〔動作〕〔地方〕", hans: "〔景物〕〔动作〕〔地方〕"),
        LocalizedText(hant: "看見〔景物〕，想起〔人／事〕", hans: "看见〔景物〕，想起〔人／事〕"),
    ]

    /// Allowed line counts for the first version: a couplet or a quatrain.
    static let lineCounts = [2, 4]
    /// Suggested characters per line (五言 / 七言), used by the gentle check only.
    static let suggestedLengths = 5...7

    /// Library lines that use at least one chosen word, as examples to read before writing.
    static func exampleLines(for words: [ImageryWord], in poems: [Poem], normalizer: TextNormalizer, limit: Int = 4) -> [(poem: Poem, line: PoemLine)] {
        let keys = words.map { normalizer.normalize($0.id) }
        guard !keys.isEmpty else { return [] }
        var result: [(Poem, PoemLine)] = []
        for poem in poems {
            for line in poem.lines {
                let text = normalizer.normalize(line.text.hans)
                if keys.contains(where: { text.contains($0) }) {
                    result.append((poem, line))
                    if result.count == limit { return result }
                }
            }
        }
        return result
    }
}

/// Gentle, deterministic checks on a draft. Only `hasLines` blocks saving; the others are hints,
/// never a score, and nothing here judges beauty or 平仄.
struct PoetWorkshopCheck: Equatable {
    /// Every requested line has some text.
    let hasLines: Bool
    /// At least one chosen imagery word appears in the lines (either script).
    let usesWord: Bool
    /// All lines have the same character count, within the suggested range.
    let evenLength: Bool
    /// Characters per line, punctuation and spaces removed.
    let lengths: [Int]

    var canSave: Bool { hasLines }

    static func check(lines: [String], words: [ImageryWord], normalizer: TextNormalizer) -> PoetWorkshopCheck {
        let cleaned = lines.map { normalizer.normalize($0) }
        let lengths = cleaned.map(\.count)
        let hasLines = !cleaned.isEmpty && cleaned.allSatisfy { !$0.isEmpty }
        let keys = words.map { normalizer.normalize($0.id) }
        let usesWord = hasLines && cleaned.contains { line in keys.contains { !$0.isEmpty && line.contains($0) } }
        let evenLength = hasLines && Set(lengths).count == 1
            && PoetWorkshopContent.suggestedLengths.contains(lengths[0])
        return PoetWorkshopCheck(hasLines: hasLines, usesWord: usesWord, evenLength: evenLength, lengths: lengths)
    }

    /// A title when the child leaves it blank: the first few characters of the first line.
    static func suggestedTitle(from lines: [String], normalizer: TextNormalizer) -> String {
        guard let first = lines.first(where: { !normalizer.normalize($0).isEmpty }) else { return "" }
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(4)).trimmingCharacters(in: .punctuationCharacters)
    }
}
