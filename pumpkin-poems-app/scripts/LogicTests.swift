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

let packs = try CommandLine.arguments.dropFirst().map {
    try JSONDecoder().decode(PoemContent.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
}
let content = packs[0]
let allPoems = packs.flatMap(\.poems)
let allThemes = packs.flatMap(\.themes)
let normalizer = TextNormalizer(hantToHans: content.hantToHans)

// Normalization: scripts, variants and punctuation fold together.
check(normalizer.normalize("牀前明月光，") == normalizer.normalize("床前明月光"), "牀/床 and punctuation")
check(normalizer.normalize("舉頭望明月") == "举头望明月", "Hant folds to Hans")
check(normalizer.normalize(" 低头 思故乡。") == "低头思故乡", "spaces and punctuation are dropped")

// Content integrity: 30 poems in at least 5 themes, the original 12 IDs kept, base pack bundled.
check(allPoems.count == 30, "30 poems across packs, got \(allPoems.count)")
check(Set(allPoems.map(\.id)).count == allPoems.count, "poem IDs are unique across packs")
check(Set(allThemes.map(\.id)).count >= 5, "at least 5 themes")
check(packs.allSatisfy { $0.formatVersion == 2 && $0.packID != nil }, "packs carry format version and ID")
check(content.packID == "base" && content.poems.allSatisfy { $0.pack == "base" }, "bundled content is the base pack")
let phase1IDs = ["hk-ks1-07", "hk-ks1-08", "hk-ks1-09", "hk-ks1-10", "hk-ks1-18", "hk-ks2-09", "hk-ks2-11", "hk-ks2-12",
                 "hk-ks2-13", "hk-ks2-14", "hk-ks2-15", "hk-ks2-17"]
check(phase1IDs.allSatisfy { id in content.poems.contains { $0.id == id } }, "phase-1 poem IDs are still in the base pack")
var allQuestionIDs = Set<String>()
for poem in allPoems {
    check(poem.questions.count >= 5, "\(poem.id) has at least 5 questions")
    check(Set(poem.questions.map(\.dimension)) == Set(LearningDimension.allCases), "\(poem.id) covers 理解 and 记忆")
    check(poem.questions.contains { $0.kind == .word }, "\(poem.id) has a 字词 question")
    check((1...3).contains(poem.difficulty) && !poem.imagery.isEmpty, "\(poem.id) has difficulty and imagery")
    for question in poem.questions {
        check(allQuestionIDs.insert(question.id).inserted, "\(question.id) is unique")
        check(!question.rev.isEmpty, "\(question.id) has a revision")
        check(!question.lineIDs.isEmpty && question.lineIDs.allSatisfy { id in poem.lines.contains { $0.id == id } },
              "\(question.id) points at its lines")
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
check(engine.validLines.count >= 5, "at least 5 lines contain 月, got \(engine.validLines.count)")
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
let pass = QuizResult(passed: true, usedHints: false)
let fail = QuizResult(passed: false, usedHints: false)
let hintedPass = QuizResult(passed: true, usedHints: true)
func startOfDay(_ n: Int) -> Date { calendar.startOfDay(for: day(n)) }

var state = ReviewState()
check(scheduler.apply(fail, at: day0, to: &state) == .failed, "failing first")
check(state.nextReviewAt == nil, "never-passed poem is not scheduled")
check(scheduler.apply(pass, at: day0, to: &state) == .firstPass, "first pass")
check(state.cardLevel == 1 && state.stableAt == nil, "card earned, not yet stable")
check(state.nextReviewAt == startOfDay(1), "node 1: tomorrow")
check(!scheduler.isDue(state, at: day0), "not due today")
check(scheduler.apply(pass, at: day0.addingTimeInterval(600), to: &state) == .practice, "same-day repeat is practice")
check(state.cardLevel == 1 && state.reviewStep == 0, "same-day repeat changes nothing")
check(scheduler.apply(pass, at: day(1, hour: 8), to: &state) == .reviewPassed, "day-1 review")
check(state.cardLevel == 2 && state.stableAt == nil, "one review is not yet 记忆较稳")
check(state.nextReviewAt == startOfDay(3), "node 2 is day 3 from the first pass")
check(scheduler.apply(pass, at: day(1, hour: 20), to: &state) == .practice, "again the same day is not a second review")
check(state.unaidedReviewDays.count == 1, "only one review day counted")
check(scheduler.apply(fail, at: day(3), to: &state) == .reviewFailed, "failed review")
check(state.nextReviewAt == startOfDay(4) && state.reviewStep == 1, "failed review retries the same node tomorrow")
check(scheduler.apply(hintedPass, at: day(4), to: &state) == .reviewHinted, "hinted review")
check(state.nextReviewAt == startOfDay(5) && state.reviewStep == 1 && state.unaidedReviewDays.count == 1,
      "a hinted review is not independent recall: same node again tomorrow")
check(scheduler.apply(pass, at: day(5), to: &state) == .reviewPassed, "unaided review on day 5")
check(state.stableAt == nil, "two unaided days but only 5 days since the first pass: not yet stable")
check(state.nextReviewAt == startOfDay(7), "node 3 stays on day 7 from the first pass")
// Overdue: comes back on day 12 instead of day 7. The day-14 node is 2 days later, never the same day.
check(scheduler.apply(pass, at: day(12), to: &state) == .reviewPassed, "late review still counts")
check(state.stableAt != nil, "stable: ≥2 unaided review days and ≥7 days since the first pass")
check(state.nextReviewAt == startOfDay(14), "next node from the first pass, day 14")
_ = scheduler.apply(pass, at: day(40), to: &state)
check(state.nextReviewAt == startOfDay(41), "overdue nodes are not stacked: next one from tomorrow")
_ = scheduler.apply(pass, at: day(41), to: &state)
check(state.nextReviewAt == nil && scheduler.isPlanComplete(state), "plan complete after the day-30 node")
check(state.cardLevel == ReviewScheduler.maxCardLevel, "card level capped")
var notDue = ReviewState()
_ = scheduler.apply(pass, at: day0, to: &notDue)
notDue.nextReviewAt = startOfDay(7)
check(scheduler.apply(fail, at: day(2), to: &notDue) == .failed && notDue.nextReviewAt == startOfDay(3),
      "a failed extra practice brings the review forward to tomorrow")

// Pass rule: 80% overall and at least one right in each of 理解 and 记忆.
func answer(_ kind: Question.Kind, _ correct: Bool, hinted: Bool = false) -> QuizEvaluation.Answer {
    QuizEvaluation.Answer(questionID: UUID().uuidString, kind: kind, correct: correct, hinted: hinted)
}
let six: [Question.Kind] = [.meaning, .word, .match, .fill, .next, .order]
check(QuizEvaluation(six.map { answer($0, true) }).passed, "all right passes")
check(QuizEvaluation(six.enumerated().map { answer($1, $0 != 0) }).passed, "5/6 passes")
check(!QuizEvaluation(six.enumerated().map { answer($1, $0 > 1) }).passed, "4/6 is below 80%")
let noMemory = QuizEvaluation([answer(.meaning, true), answer(.word, true), answer(.match, true), answer(.match, true),
                               answer(.fill, false)])
check(!noMemory.passed && noMemory.score * 5 >= noMemory.total * 4, "80% but no memory answer right does not pass")
let hinted = QuizEvaluation(six.enumerated().map { answer($1, true, hinted: $0 == 3) })
check(hinted.passed && hinted.usedHints, "hinted answers count but mark the round")
check(hinted.understanding.total == 3 && hinted.memory.total == 3, "dimensions split 3/3")

// Daily plan.
let today = calendar.startOfDay(for: day0)
var plan = DailyPlan(minutes: 10, pausedOn: nil, today: today, due: ["a", "b", "c", "d", "e"], reviewedToday: 0,
                     startedToday: 0, nextNew: "n")
check(plan.reviewsToday == ["a", "b", "c"] && plan.backlog == 2 && plan.newPoem == "n", "10 min: 3 reviews first, backlog later, 1 new")
plan = DailyPlan(minutes: 10, pausedOn: nil, today: today, due: ["d", "e"], reviewedToday: 3, startedToday: 1, nextNew: "m")
check(plan.reviewsToday.isEmpty && plan.backlog == 2 && plan.newPoem == nil && plan.isComplete, "quota met: rest goes to the next days")
plan = DailyPlan(minutes: 5, pausedOn: nil, today: today, due: ["a"], reviewedToday: 0, startedToday: 0, nextNew: "n")
check(plan.reviewsToday == ["a"] && plan.newPoem == nil, "5 min with reviews: no new poem")
plan = DailyPlan(minutes: 5, pausedOn: nil, today: today, due: [], reviewedToday: 0, startedToday: 0, nextNew: "n")
check(plan.newPoem == "n", "5 min without reviews: one new poem")
plan = DailyPlan(minutes: 15, pausedOn: today, today: today, due: ["a", "b"], reviewedToday: 0, startedToday: 0, nextNew: "n")
check(plan.isPaused && plan.reviewsToday.isEmpty && plan.newPoem == nil && plan.backlog == 2, "rest day keeps everything for later")

// Weekly report: separate parts, no judgement on a thin sample.
let thin = WeeklyReport(rounds: [.init(date: day0, poemID: "p", answers: [answer(.meaning, false), answer(.fill, true)],
                                       isReview: false, passed: false)],
                        activeDays: [today], dueNow: 0, now: day0, calendar: calendar)
check(!thin.understanding.isEnough && !thin.memory.isEnough, "two answers are 记录还不够")
let weakMeaning = (0..<4).map { n in
    WeeklyReport.Round(date: day(-n), poemID: "p\(n % 2)",
                       answers: [answer(.meaning, false), answer(.word, n == 0), answer(.fill, true), answer(.order, true)],
                       isReview: n == 1, passed: n == 1)
}
let report = WeeklyReport(rounds: weakMeaning, activeDays: Set((0..<4).map { calendar.startOfDay(for: day(-$0)) }),
                          dueNow: 1, now: day0, calendar: calendar)
check(report.studyDays == 4 && report.rounds == 4 && report.reviewsDone == 1, "week counts")
check(report.understanding.isEnough && report.understanding.correct == 1, "understanding 1/8")
if case .explain = report.suggestion {} else { check(false, "weak understanding suggests explaining a poem") }
check(report.commonMistakes.first?.category == .meaning, "诗意判断 is the most common mistake")
let empty = WeeklyReport(rounds: [], activeDays: [], dueNow: 0, now: day0, calendar: calendar)
check(!empty.hasEnoughRecords && empty.suggestion == .startSmall, "no records: no judgement")

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
draftCheck = PoetWorkshopCheck.check(lines: ["風吹黃葉落", "月照小橋頭"], words: chosen, normalizer: normalizer, form: 7)
check(!draftCheck.evenLength, "七言 form checks only the chosen length")
draftCheck = PoetWorkshopCheck.check(lines: ["風吹黃葉落，", "月 照 小 橋 頭"], words: chosen, normalizer: normalizer, form: 5)
check(draftCheck.evenLength && draftCheck.lengths == [5, 5], "五言 counts Han characters, ignoring punctuation and spaces")
let candidates = PoetWorkshopContent.exampleCandidates(for: PoetWorkshopContent.theme("farewell"), in: allPoems, normalizer: normalizer)
check(candidates.first?.poem.theme == "farewell", "example lines come from the theme's poems first")
check(PoetWorkshopCheck.suggestedTitle(from: ["", "風吹黃葉落，"], normalizer: normalizer) == "風吹黃葉", "title suggested from the first written line")
check(Set(PoetWorkshopContent.themes.map(\.id)).count == PoetWorkshopContent.themes.count, "workshop theme IDs are unique")
for theme in PoetWorkshopContent.themes {
    check(!theme.words.isEmpty, "\(theme.id) has imagery words")
    check(theme.libraryThemeID.map { id in allThemes.contains { $0.id == id } } ?? true, "\(theme.id) points at a real library theme")
}
let examples = PoetWorkshopContent.exampleLines(for: [autumn.words[0]], in: allPoems, normalizer: normalizer)
check(!examples.isEmpty && examples.allSatisfy { normalizer.normalize($0.line.text.hans).contains("月") }, "examples contain the chosen word")

if failures == 0 {
    print("All logic checks passed.")
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
