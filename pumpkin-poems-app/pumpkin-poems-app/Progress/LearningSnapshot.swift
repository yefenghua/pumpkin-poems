import Foundation

/// Read-only view over the learner's records, used to build 今天 and 成长册.
struct LearningSnapshot {
    let library: PoemLibrary
    let targetKeyStage: Int?
    private let progressByID: [String: PoemProgress]

    init(progress: [PoemProgress], library: PoemLibrary = .shared, targetKeyStage: Int? = nil) {
        self.library = library
        self.targetKeyStage = targetKeyStage
        progressByID = Dictionary(progress.map { ($0.poemID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func progress(_ poemID: String) -> PoemProgress? { progressByID[poemID] }

    func status(_ poemID: String) -> PoemStatus { PoemStatus(progressByID[poemID]) }

    func count(_ status: PoemStatus) -> Int {
        library.poems.filter { PoemStatus(progressByID[$0.id]).rawValue >= status.rawValue }.count
    }

    /// The target grade maps to an existing curriculum stage, retaining content order.
    /// This is a read-only projection; records and whole-library achievements remain intact.
    var planPoems: [Poem] {
        library.poems.filter { targetKeyStage == nil || $0.keyStage == targetKeyStage }
    }

    var planTotalCount: Int { planPoems.count }
    var planPassedCount: Int { planPoems.filter { progressByID[$0.id]?.hasPassed ?? false }.count }
    var isPlanComplete: Bool { planTotalCount > 0 && planPassedCount == planTotalCount }

    /// The most recently studied, unfinished poem within the current plan.
    var inProgress: (poem: Poem, step: LearningStep)? {
        let candidates = planPoems.enumerated().filter {
            guard let progress = progressByID[$0.element.id] else { return false }
            return !progress.hasPassed && progress.step > .notStarted
        }.sorted { lhs, rhs in
            let left = progressByID[lhs.element.id]?.lastStudiedAt ?? .distantPast
            let right = progressByID[rhs.element.id]?.lastStudiedAt ?? .distantPast
            return left == right ? lhs.offset < rhs.offset : left > right
        }
        guard let poem = candidates.first?.element, let progress = progressByID[poem.id] else { return nil }
        return (poem, progress.step)
    }

    /// First unstarted poem in the current plan's content order.
    var nextUnstarted: Poem? {
        planPoems.first { (progressByID[$0.id]?.step ?? .notStarted) == .notStarted }
    }

    var hasAnyRecord: Bool {
        planPoems.contains { (progressByID[$0.id]?.step ?? .notStarted) > .notStarted }
    }

    /// Due poems in the current plan: open mistakes first, then the longest overdue.
    func dueReviews(mistakes: [Mistake], now: Date) -> [Poem] {
        let withMistakes = Set(mistakes.filter { !$0.isResolved }.map(\.poemID))
        return planPoems.enumerated()
            .filter { progressByID[$0.element.id]?.nextReviewAt.map { $0 <= now } ?? false }
            .sorted { lhs, rhs in
                let l = withMistakes.contains(lhs.element.id), r = withMistakes.contains(rhs.element.id)
                if l != r { return l }
                let left = progressByID[lhs.element.id]?.nextReviewAt ?? .distantPast
                let right = progressByID[rhs.element.id]?.nextReviewAt ?? .distantPast
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// Daily recommendations stay inside the selected plan, even when all its poems passed.
    func recommended(excluding excluded: String?, now: Date) -> Poem? {
        let pool = planPoems.filter { $0.id != excluded && !(progressByID[$0.id]?.hasPassed ?? false) }
        let candidates = pool.isEmpty ? planPoems.filter { $0.id != excluded } : pool
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        return candidates[day % candidates.count]
    }

    func passedPoems(inTheme themeID: String) -> Int {
        library.poems(inTheme: themeID).filter { progressByID[$0.id]?.hasPassed ?? false }.count
    }

    func isBadgeEarned(_ theme: PoemTheme) -> Bool {
        let poems = library.poems(inTheme: theme.id)
        return !poems.isEmpty && passedPoems(inTheme: theme.id) == poems.count
    }
}
