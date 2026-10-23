// Command-line checks for the app's pure logic (no simulator needed).
// Run: pumpkin-poems-app/scripts/run_logic_tests.sh
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

let contentURL = URL(fileURLWithPath: CommandLine.arguments[1])
let content = try JSONDecoder().decode(PoemContent.self, from: Data(contentsOf: contentURL))
let normalizer = TextNormalizer(hantToHans: content.hantToHans)

// Normalization: scripts, variants and punctuation fold together.
check(normalizer.normalize("牀前明月光，") == normalizer.normalize("床前明月光"), "牀/床 and punctuation")
check(normalizer.normalize("舉頭望明月") == "举头望明月", "Hant folds to Hans")
check(normalizer.normalize(" 低头 思故乡。") == "低头思故乡", "spaces and punctuation are dropped")

// Content integrity.
check(content.poems.count == 12, "12 featured poems")
for poem in content.poems {
    check(poem.questions.count == 5, "\(poem.id) has 5 questions")
    for question in poem.questions {
        if question.kind == .order {
            check(question.answerOrder.map { Set($0) == Set(question.options.indices) } ?? false, "\(question.id) order is a permutation")
        } else if let answer = question.answer {
            check(question.options.indices.contains(answer), "\(question.id) answer in range")
        } else {
            check(false, "\(question.id) has no answer")
        }
    }
    for line in poem.lines {
        check(line.keyword.count == 2 && line.keyword[0] < line.keyword[1], "\(line.id) keyword range")
    }
    for note in poem.annotations {
        for spot in note.occurrences.hant {
            let text = poem.lines.first { $0.id == spot.lineID }?.text.hant ?? ""
            check(text.characters(from: spot.start, to: spot.end) == note.term.hant, "\(note.id) Hant position")
        }
        for spot in note.occurrences.hans {
            let text = poem.lines.first { $0.id == spot.lineID }?.text.hans ?? ""
            check(text.characters(from: spot.start, to: spot.end) == note.term.hans, "\(note.id) Hans position")
        }
    }
}

// 飞花令 judging.
let moon = content.feiHuaLing.first { $0.hans == "月" }!
var engine = FeiHuaLingEngine(character: moon, poems: content.poems, normalizer: normalizer)
check(engine.validLines.count == 5, "5 lines contain 月, got \(engine.validLines.count)")
if case .accepted = engine.submit("牀前明月光") {} else { check(false, "Hant input accepted") }
if case .alreadyUsed = engine.submit("床前明月光。") {} else { check(false, "Hans duplicate detected") }
if case .missingCharacter = engine.submit("疑是地上霜") {} else { check(false, "library line without 月") }
if case .notCollected = engine.submit("海上生明月") {} else { check(false, "unknown line is not judged wrong") }
check(engine.submit("  ") == .empty, "empty input")
check(engine.hint().map { !engine.used.contains($0) } ?? false, "hint is unused")
let rounds = engine.entryRounds(count: 5)
check(rounds.count == 5, "5 entry rounds")
for round in rounds {
    let containing = round.options.filter { engine.validLines.contains($0) }
    check(containing.count == 1 && round.options[round.answer] == containing[0], "entry round has exactly one answer")
}

// Review scheduling.
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
let scheduler = ReviewScheduler(calendar: calendar)
let day0 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 19))!
func day(_ n: Int, hour: Int = 19) -> Date {
    calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: day0))!.addingTimeInterval(Double(hour) * 3600)
}
var state = ReviewState()
check(scheduler.apply(passed: false, hadMistakes: true, at: day0, to: &state) == .failed, "failing first")
check(state.nextReviewAt == nil, "never-passed poem is not scheduled")
check(scheduler.apply(passed: true, hadMistakes: false, at: day0, to: &state) == .firstPass, "first pass")
check(state.cardLevel == 1 && state.stableAt == nil, "card earned, not yet stable")
check(state.nextReviewAt == calendar.startOfDay(for: day(1)), "review tomorrow")
check(!scheduler.isDue(state, at: day0), "not due today")
check(scheduler.apply(passed: true, hadMistakes: false, at: day0.addingTimeInterval(600), to: &state) == .repeatedSameDay, "same-day repeat")
check(state.cardLevel == 1, "same-day repeat gives no extra level")
check(scheduler.isDue(state, at: day(1, hour: 8)), "due next morning")
check(scheduler.apply(passed: true, hadMistakes: false, at: day(1, hour: 8), to: &state) == .reviewPassed, "cross-day review")
check(state.stableAt != nil && state.cardLevel == 2, "stable after cross-day review")
check(state.nextReviewAt == calendar.startOfDay(for: day(4)), "then +3 days")
_ = scheduler.apply(passed: true, hadMistakes: true, at: day(4), to: &state)
check(state.nextReviewAt == calendar.startOfDay(for: day(5)), "mistakes bring review forward to tomorrow")
_ = scheduler.apply(passed: false, hadMistakes: true, at: day(5), to: &state)
check(state.nextReviewAt == calendar.startOfDay(for: day(6)) && state.stableAt != nil, "failure reschedules, keeps earned state")

// 小小诗人: gentle checks, never a score.
let autumn = PoetWorkshopContent.theme("autumn")!
let chosen = [autumn.words[0], autumn.words[2]] // 月, 叶
var draftCheck = PoetWorkshopCheck.check(lines: ["風吹黃葉落", "月照小橋頭"], words: chosen, normalizer: normalizer)
check(draftCheck.hasLines && draftCheck.usesWord && draftCheck.evenLength, "five-character couplet using 葉/月 passes every check")
check(draftCheck.lengths == [5, 5], "lengths ignore punctuation and count characters")
draftCheck = PoetWorkshopCheck.check(lines: ["風吹黃葉落。", ""], words: chosen, normalizer: normalizer)
check(!draftCheck.hasLines && !draftCheck.canSave, "a blank line blocks saving")
draftCheck = PoetWorkshopCheck.check(lines: ["天很藍", "我很開心啊"], words: chosen, normalizer: normalizer)
check(draftCheck.hasLines && draftCheck.canSave && !draftCheck.usesWord && !draftCheck.evenLength, "uneven lines without imagery still save, with hints")
draftCheck = PoetWorkshopCheck.check(lines: ["叶子飞", "月亮圆"], words: chosen, normalizer: normalizer)
check(draftCheck.usesWord, "Simplified input matches Traditional imagery words")
check(PoetWorkshopCheck.suggestedTitle(from: ["", "風吹黃葉落，"], normalizer: normalizer) == "風吹黃葉", "title suggested from the first written line")
check(Set(PoetWorkshopContent.themes.map(\.id)).count == PoetWorkshopContent.themes.count, "workshop theme IDs are unique")
for theme in PoetWorkshopContent.themes {
    check(!theme.words.isEmpty, "\(theme.id) has imagery words")
    check(theme.libraryThemeID.map { id in content.themes.contains { $0.id == id } } ?? true, "\(theme.id) points at a real library theme")
}
let examples = PoetWorkshopContent.exampleLines(for: [autumn.words[0]], in: content.poems, normalizer: normalizer)
check(!examples.isEmpty && examples.allSatisfy { normalizer.normalize($0.line.text.hans).contains("月") }, "examples contain the chosen word")

if failures == 0 {
    print("All logic checks passed.")
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
