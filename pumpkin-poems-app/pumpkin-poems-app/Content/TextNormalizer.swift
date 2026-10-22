import Foundation

/// Folds Traditional and Simplified text onto one comparable form, so that
/// "牀前明月光", "床前明月光" and "床前明月光。" all match the same line.
struct TextNormalizer {
    let hantToHans: [Character: Character]

    init(hantToHans: [String: String]) {
        var map: [Character: Character] = [:]
        for (hant, hans) in hantToHans {
            if let from = hant.first, let to = hans.first {
                map[from] = to
            }
        }
        self.hantToHans = map
    }

    /// Keeps only Han characters and maps each Traditional character to Simplified.
    /// Both the input and the stored text go through the same map, so a character that is
    /// mapped in one direction only (e.g. 乾) still compares equal.
    func normalize(_ text: String) -> String {
        var result = ""
        for character in text where Self.isHan(character) {
            result.append(hantToHans[character] ?? character)
        }
        return result
    }

    static func isHan(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return scalar.properties.isIdeographic
    }
}

extension String {
    /// Characters in [start, end), clamped to the string.
    func characters(from start: Int, to end: Int) -> String {
        let chars = Array(self)
        let lower = max(0, min(start, chars.count))
        let upper = max(lower, min(end, chars.count))
        return String(chars[lower..<upper])
    }

    /// The line without its trailing punctuation.
    var withoutTrailingPunctuation: String {
        var text = self
        while let last = text.last, !TextNormalizer.isHan(last) {
            text.removeLast()
        }
        return text
    }
}
