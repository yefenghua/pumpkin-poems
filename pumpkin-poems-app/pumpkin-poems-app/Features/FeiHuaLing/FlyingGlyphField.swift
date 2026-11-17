import Foundation

/// Owns the timing and geometry of the falling characters. Rendering never mutates this state.
/// Pass monotonically increasing elapsed seconds to update/position/shake; UIKit is not required.
struct FlyingGlyphField {
    struct Glyph: Identifiable, Hashable {
        let id: UInt64
        let text: LocalizedText
        let born: Double
        let lane: Int
        let row: Int
        let offsetX: Double
        let normalizedKey: String
    }

    struct Position: Equatable {
        let x: Double
        let y: Double
    }

    static let tileWidth = 44.0
    static let tileHeight = 48.0
    static let minimumVerticalSpacing = 64.0
    static let speed = 56.0
    static let boostDuration = 6.0
    static let neededInterval = 5.0

    let width: Double
    let height: Double
    let reduceMotion: Bool
    let laneCount: Int
    private(set) var glyphs: [Glyph] = []
    private(set) var nextSpawnAt = 0.0
    private(set) var boostedUntil = -Double.infinity
    private var generator: Generator
    private var nextID: UInt64 = 1
    private var lastUpdateAt = 0.0
    private var neededKey: String?
    private var neededDeadline = 0.0
    private var wasBoosted = false
    private var lastBirthAt: Double?
    private let horizontalPadding: Double
    private let rowCount: Int
    private let startY = -28.0

    private var lifetime: Double { (height + Self.tileHeight / 2 - startY) / Self.speed }
    private var normalCapacity: Int { reduceMotion ? min(4, laneCount * rowCount) : 4 }
    private var boostCapacity: Int { reduceMotion ? min(7, laneCount * rowCount) : 7 }

    /// One steady beat, sized to let the oldest token leave before its capacity slot is needed.
    /// At the app's 300-point field height this is exactly 1.8 seconds.
    var normalInterval: Double { max(1.8, lifetime / Double(normalCapacity) + 0.15) }

    init(width: Double, height: Double, reduceMotion: Bool = false,
         seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.width = max(Self.tileWidth, width.isFinite ? width : Self.tileWidth)
        self.height = max(Self.tileHeight, height.isFinite ? height : Self.tileHeight)
        self.reduceMotion = reduceMotion
        horizontalPadding = min(8, max(0, (self.width - Self.tileWidth) / 2))
        laneCount = max(1, min(5, Int((self.width - horizontalPadding * 2 + 12) / (Self.tileWidth + 12))))
        rowCount = max(1, Int((self.height - 16 + 16) / Self.minimumVerticalSpacing))
        generator = Generator(state: seed)
        reset(at: 0)
    }

    /// Reset between questions. Every ordinary token is born offscreen, never aged into view.
    mutating func reset(at elapsed: Double = 0) {
        let now = elapsed.isFinite ? elapsed : 0
        glyphs.removeAll()
        boostedUntil = -Double.infinity
        lastUpdateAt = now
        neededKey = nil
        neededDeadline = now + Self.neededInterval
        wasBoosted = false
        lastBirthAt = nil
        nextSpawnAt = now + Double.random(in: 0.45...1.05, using: &generator)
    }

    func isBoosted(at elapsed: Double) -> Bool { elapsed < boostedUntil }

    /// During the short retreat window, allow normal-cadence births alongside the old boost
    /// tokens. This prevents an artificial pause while the extra tokens drift out naturally.
    func limit(at elapsed: Double) -> Int {
        elapsed < boostedUntil + lifetime ? boostCapacity : normalCapacity
    }

    /// Shaking changes only future scheduling. It never adds, repositions or accelerates a live glyph.
    mutating func shake(at elapsed: Double) {
        guard elapsed.isFinite else { return }
        let now = max(lastUpdateAt, elapsed)
        boostedUntil = now + Self.boostDuration
        wasBoosted = true
        nextSpawnAt = min(nextSpawnAt, now + Double.random(in: 0.4...0.75, using: &generator))
    }

    /// A tap removes exactly one glyph. The next scheduled birth stays unchanged.
    @discardableResult
    mutating func remove(id: UInt64) -> LocalizedText? {
        guard let index = glyphs.firstIndex(where: { $0.id == id }) else { return nil }
        return glyphs.remove(at: index).text
    }

    func position(of glyph: Glyph, at elapsed: Double) -> Position {
        let span = width - Self.tileWidth - horizontalPadding * 2
        let laneX = laneCount == 1 ? width / 2
            : Self.tileWidth / 2 + horizontalPadding + Double(glyph.lane) * span / Double(laneCount - 1)
        let x = laneX + glyph.offsetX
        if reduceMotion {
            // Stable grid positions respect both tile bounds and minimum spacing.
            let y = Self.tileHeight / 2 + 8 + Double(glyph.row) * Self.minimumVerticalSpacing
            return Position(x: x, y: min(height - Self.tileHeight / 2, y))
        }
        return Position(x: x, y: startY + max(0, elapsed - glyph.born) * Self.speed)
    }

    /// Call on a modest cadence (for example 10 Hz), not once per animation frame.
    /// Large time jumps create at most one current-time token, so resume cannot produce a burst.
    mutating func update(at elapsed: Double, game: FlyingFlowerEngine) {
        guard elapsed.isFinite else { return }
        let now = max(lastUpdateAt, elapsed)
        lastUpdateAt = now
        let lifetime = self.lifetime
        glyphs.removeAll { now - $0.born >= lifetime }
        let maximum = limit(at: now)
        guard game.current != nil, !game.resolved else {
            glyphs.removeAll()
            return
        }

        let boosted = isBoosted(at: now)
        if wasBoosted && !boosted {
            // Return directly to a normal beat after the last boost birth, without waiting
            // for all extra tokens to leave or retaining the shorter boost deadline.
            if let lastBirthAt { nextSpawnAt = lastBirthAt + normalInterval }
            wasBoosted = false
        }

        let nextKey = game.nextNeededLetter.map(game.letterKey)
        if nextKey != neededKey {
            neededKey = nextKey
            neededDeadline = now + Self.neededInterval
        }
        if let nextKey, glyphs.contains(where: { $0.normalizedKey == nextKey }) {
            neededDeadline = now + Self.neededInterval
        }
        guard now >= nextSpawnAt else { return }
        // Normal beats advance from their absolute deadline, so a 10 Hz UI does not add
        // its sampling delay to every interval. A missed whole beat resets the phase and
        // permits only one current-time birth; no backdated catch-up burst is produced.
        let interval: Double
        if boosted {
            let safeMinimum = max(0.65, lifetime / Double(boostCapacity) + 0.12,
                                  reduceMotion ? 0 : Self.minimumVerticalSpacing / (Self.speed * Double(laneCount)) + 0.15)
            let lower = min(normalInterval, safeMinimum)
            interval = Double.random(in: lower...min(normalInterval, lower + 0.2), using: &generator)
        } else {
            interval = normalInterval
        }
        let deadline = nextSpawnAt
        nextSpawnAt = now - deadline >= interval ? now + interval : deadline + interval
        guard !game.full, glyphs.count < maximum else { return }

        let places = availablePlaces(at: now)
        guard let place = places.randomElement(using: &generator) else { return }
        let visible = Set(glyphs.map(\.normalizedKey))
        guard let letter = game.fallingLetter(excluding: visible,
                                              prioritizeNeeded: now >= neededDeadline,
                                              using: &generator) else { return }
        let key = game.letterKey(letter)
        guard !visible.contains(key) else { return }
        let span = width - Self.tileWidth - horizontalPadding * 2
        let laneSpacing = laneCount > 1 ? span / Double(laneCount - 1) : width
        // Two adjacent glyphs may move toward each other by at most twice this amount.
        // Retain an eight-point gap and keep even outer lanes within the field's bounds.
        let horizontalSlack = laneCount > 1
            ? min(horizontalPadding, max(0, (laneSpacing - Self.tileWidth - 8) / 2))
            : min(8, (width - Self.tileWidth) / 2)
        let offsetX = Double.random(in: -horizontalSlack...horizontalSlack, using: &generator)
        glyphs.append(Glyph(id: nextID, text: letter, born: now, lane: place.lane,
                            row: place.row, offsetX: offsetX, normalizedKey: key))
        lastBirthAt = now
        nextID &+= 1
        if key == neededKey { neededDeadline = now + Self.neededInterval }
    }

    private func availablePlaces(at now: Double) -> [(lane: Int, row: Int)] {
        if reduceMotion {
            return (0..<rowCount).flatMap { row in
                (0..<laneCount).compactMap { lane in
                    glyphs.contains { $0.lane == lane && $0.row == row } ? nil : (lane, row)
                }
            }
        }
        // Every falling glyph travels at one speed with its own fixed x. A safe birth gap
        // therefore proves non-overlap for the entire life of the pair, not only this frame.
        return (0..<laneCount).compactMap { lane in
            let safe = glyphs.filter { $0.lane == lane }.allSatisfy {
                position(of: $0, at: now).y - startY >= Self.minimumVerticalSpacing
            }
            return safe ? (lane, 0) : nil
        }
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
}
