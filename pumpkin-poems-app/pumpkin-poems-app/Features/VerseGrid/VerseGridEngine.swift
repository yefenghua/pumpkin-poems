import Foundation

/// A solvable single-character board. The stored paths are generation witnesses / hints;
/// players may connect unused cells in the same row or column, including across gaps.
nonisolated struct VerseGridPuzzle: Sendable {
    struct Cell: Identifiable, Hashable, Sendable {
        let id: Int
        let text: LocalizedText
    }

    struct Target: Identifiable, Sendable {
        let verse: GameVerse
        let path: [Int]
        var id: String { verse.id }
    }

    let size: Int
    let cells: [Cell]
    let targets: [Target]

    static func make(verses: [GameVerse], size: Int, targetCount: Int,
                     normalizer: TextNormalizer) -> VerseGridPuzzle? {
        var generator = SystemRandomNumberGenerator()
        return make(verses: verses, size: size, targetCount: targetCount,
                    normalizer: normalizer, using: &generator)
    }

    static func make<G: RandomNumberGenerator>(verses: [GameVerse], size: Int, targetCount: Int,
                                              normalizer: TextNormalizer, using generator: inout G) -> VerseGridPuzzle? {
        guard (4...9).contains(size), (1...6).contains(targetCount) else { return nil }
        var seen: Set<String> = []
        let pool = verses.filter { verse in
            let hant = Array(verse.text.hant), hans = Array(verse.text.hans)
            let key = normalizer.normalize(verse.text.hans)
            return [5, 7].contains(hans.count) && hant.count == hans.count
                && hans.allSatisfy(TextNormalizer.isHan) && hant.allSatisfy(TextNormalizer.isHan)
                && seen.insert(key).inserted
        }
        guard pool.count >= targetCount else { return nil }
        let selected = Array(pool.shuffled(using: &generator).prefix(targetCount))
        guard selected.reduce(0, { $0 + $1.text.hans.count }) <= size * size else { return nil }
        var paths: [[Int]] = []
        var unused = Set(0..<(size * size))
        for verse in selected {
            let count = verse.text.hans.count
            // Nearby horizontal/vertical turns make each answer comfortable to drag.
            var path: [Int] = []
            for _ in 0..<80 {
                if Task<Never, Never>.isCancelled { return nil }
                guard let first = unused.sorted().randomElement(using: &generator) else { break }
                var candidate = [first]
                while candidate.count < count {
                    let last = candidate.last!
                    let neighbours = unused.filter {
                        !candidate.contains($0) && abs($0 / size - last / size)
                            + abs($0 % size - last % size) == 1
                    }.sorted()
                    guard let next = neighbours.randomElement(using: &generator) else { break }
                    candidate.append(next)
                }
                if candidate.count == count { path = candidate; break }
            }
            if path.isEmpty { break }
            paths.append(path)
            unused.subtract(path)
        }
        if paths.count != selected.count {
            // Fragmented leftovers cannot justify a diagonal. Re-layout every answer
            // along one continuous snake, with a random orientation and starting offset.
            // Any set of lengths fitting the board is therefore always placeable.
            let transpose = Bool.random(using: &generator)
            let flipRows = Bool.random(using: &generator)
            let flipColumns = Bool.random(using: &generator)
            let snake = (0..<(size * size)).map { index in
                var row = index / size
                var column = row.isMultiple(of: 2) ? index % size : size - 1 - index % size
                if transpose { swap(&row, &column) }
                if flipRows { row = size - 1 - row }
                if flipColumns { column = size - 1 - column }
                return row * size + column
            }
            let needed = selected.reduce(0) { $0 + $1.text.hans.count }
            var offset = Int.random(in: 0...(size * size - needed), using: &generator)
            paths = selected.map { verse in
                let end = offset + verse.text.hans.count
                defer { offset = end }
                return Array(snake[offset..<end])
            }
        }
        var board = [LocalizedText?](repeating: nil, count: size * size)
        var targets: [Target] = []
        for (verse, path) in zip(selected, paths) {
            let hant = Array(verse.text.hant), hans = Array(verse.text.hans)
            for (position, index) in path.enumerated() {
                board[index] = LocalizedText(hant: String(hant[position]), hans: String(hans[position]))
            }
            targets.append(Target(verse: verse, path: path))
        }
        let filler = selected.flatMap { verse in
            zip(verse.text.hant, verse.text.hans).map { LocalizedText(hant: String($0.0), hans: String($0.1)) }
        }
        guard !filler.isEmpty else { return nil }
        let cells = board.indices.map { index in
            Cell(id: index, text: board[index] ?? filler.randomElement(using: &generator)!)
        }
        return VerseGridPuzzle(size: size, cells: cells, targets: targets)
    }
}

nonisolated struct VerseGridEngine {
    enum SelectionChange: Equatable { case added, backtracked, ignored }
    enum Verdict: Equatable {
        case found(String), alreadyFound(String), notTarget, empty
    }

    let puzzle: VerseGridPuzzle
    private let normalizer: TextNormalizer
    private(set) var selection: [Int] = []
    private(set) var foundIDs: Set<String> = []
    private(set) var foundPaths: [String: [Int]] = [:]
    private(set) var attempts = 0
    private(set) var hintsUsed = 0

    init(puzzle: VerseGridPuzzle, normalizer: TextNormalizer) {
        self.puzzle = puzzle
        self.normalizer = normalizer
    }

    var isComplete: Bool { foundIDs.count == puzzle.targets.count && !puzzle.targets.isEmpty }
    var longestTarget: Int { puzzle.targets.map { $0.path.count }.max() ?? 0 }

    @discardableResult
    mutating func select(_ index: Int) -> SelectionChange {
        guard !isComplete, puzzle.cells.indices.contains(index), selection.last != index else { return .ignored }
        if selection.count >= 2, selection[selection.count - 2] == index {
            selection.removeLast()
            return .backtracked
        }
        guard !selection.contains(index), selection.count < longestTarget else { return .ignored }
        if let last = selection.last {
            guard last / puzzle.size == index / puzzle.size || last % puzzle.size == index % puzzle.size else { return .ignored }
        }
        selection.append(index)
        return .added
    }

    mutating func clearSelection() { selection.removeAll() }
    mutating func undo() { if !selection.isEmpty { selection.removeLast() } }

    func selectedText(_ script: Script) -> String {
        selection.map { puzzle.cells[$0].text(script) }.joined()
    }

    mutating func submit() -> Verdict {
        guard !selection.isEmpty else { return .empty }
        defer { selection.removeAll() }
        attempts += 1
        let key = normalizer.normalize(selectedText(.hans))
        guard let target = puzzle.targets.first(where: { normalizer.normalize($0.verse.text.hans) == key }) else {
            return .notTarget
        }
        guard foundIDs.insert(target.id).inserted else { return .alreadyFound(target.id) }
        foundPaths[target.id] = selection
        return .found(target.id)
    }

    mutating func revealStart() -> Int? {
        guard let target = puzzle.targets.first(where: { !foundIDs.contains($0.id) }) else { return nil }
        hintsUsed += 1
        return target.path.first
    }
}
