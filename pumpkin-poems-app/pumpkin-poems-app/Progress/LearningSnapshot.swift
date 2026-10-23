import Foundation

/// Read-only view over the learner's records, used to build 今天 and 成长册.
struct LearningSnapshot {
    let library: PoemLibrary
    private let progressByID: [String: PoemProgress]

    init(progress: [PoemProgress], library: PoemLibrary = .shared) {
        self.library = library
        progressByID = Dictionary(progress.map { ($0.poemID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func progress(_ poemID: String) -> PoemProgress? { progressByID[poemID] }

    func status(_ poemID: String) -> PoemStatus { PoemStatus(progressByID[poemID]) }

    func count(_ status: PoemStatus) -> Int {
        library.poems.filter { PoemStatus(progressByID[$0.id]).rawValue >= status.rawValue }.count
    }

    /// The most recently studied poem that has not been passed yet.
    var inProgress: (poem: Poem, step: LearningStep)? {
        let candidates = progressByID.values
            .filter { !$0.hasPassed && $0.step > .notStarted }
            .sorted { ($0.lastStudiedAt ?? .distantPast) > ($1.lastStudiedAt ?? .distantPast) }
        guard let progress = candidates.first, let poem = library.poem(progress.poemID) else { return nil }
        return (poem, progress.step)
    }

    /// First poem in library order that has never been opened.
    var nextUnstarted: Poem? {
        library.poems.first { (progressByID[$0.id]?.step ?? .notStarted) == .notStarted }
    }

    var hasAnyRecord: Bool {
        progressByID.values.contains { $0.step > .notStarted }
    }

    /// Poems due for review today. Poems with open mistakes come first, then the longest overdue.
    func dueReviews(mistakes: [Mistake], now: Date) -> [Poem] {
        let withMistakes = Set(mistakes.filter { !$0.isResolved }.map(\.poemID))
        return progressByID.values
            .filter { progress in progress.nextReviewAt.map { $0 <= now } ?? false }
            .sorted { lhs, rhs in
                let l = withMistakes.contains(lhs.poemID), r = withMistakes.contains(rhs.poemID)
                if l != r { return l }
                return (lhs.nextReviewAt ?? .distantPast) < (rhs.nextReviewAt ?? .distantPast)
            }
            .compactMap { library.poem($0.poemID) }
    }

    /// A different poem to suggest, rotating daily among the ones not yet passed.
    func recommended(excluding excluded: String?, now: Date) -> Poem? {
        let pool = library.poems.filter { $0.id != excluded && !(progressByID[$0.id]?.hasPassed ?? false) }
        let candidates = pool.isEmpty ? library.poems.filter { $0.id != excluded } : pool
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
