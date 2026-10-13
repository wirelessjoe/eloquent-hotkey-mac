import Foundation

struct TranscriptCleanupValidator: Sendable {
    func requiresModelRefinement(for text: String) -> Bool {
        Self.words(in: text).count >= 6
    }

    func accepts(_ cleaned: String, comparedTo original: String) -> Bool {
        let originalWords = Self.words(in: original)
        let cleanedWords = Self.words(in: cleaned)
        guard !originalWords.isEmpty, !cleanedWords.isEmpty else {
            return false
        }

        let originalLowercased = original.lowercased()
        let cleanedLowercased = cleaned.lowercased()
        // Guided generation can occasionally echo its schema instructions into
        // the string field. These are never cleanup when absent from the input.
        for marker in ["respond using the following json format:", "here is the cleaned transcript:"] {
            if cleanedLowercased.contains(marker), !originalLowercased.contains(marker) {
                return false
            }
        }

        // A retained transcript with a new preface or trailing sentence is model
        // commentary, regardless of how small it is relative to a long dictation.
        if cleanedWords.count > originalWords.count,
           cleanedWords.starts(with: originalWords)
            || cleanedWords.suffix(originalWords.count).elementsEqual(originalWords) {
            return false
        }

        // A small edit can reverse a command or change an amount even when almost
        // every other word survives. Preserve these tokens on transcripts of any length.
        guard Self.protectedWords(in: originalWords) == Self.protectedWords(in: cleanedWords),
              Self.negatedWords(in: originalWords) == Self.negatedWords(in: cleanedWords),
              Self.numbers(in: original) == Self.numbers(in: cleaned) else {
            return false
        }

        let ratio = Double(cleaned.count) / Double(max(original.count, 1))
        if originalWords.count < 6 {
            // Short commands have too little context to safely accept word changes.
            return originalWords == cleanedWords && ratio >= 0.4 && ratio <= 1.6
        }

        guard ratio >= 0.8, ratio <= 1.25 else {
            return false
        }

        let maximumEdits = originalWords.count * 12 / 100
        return Self.isWithinEditBudget(originalWords, cleanedWords, maximumEdits: maximumEdits)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { character in
                !(character.isLetter || character.isNumber || "/_-'".contains(character))
            })
            .flatMap { word -> [String] in
                switch word {
                case "cannot", "can't": return ["can", "not"]
                case "won't": return ["will", "not"]
                case "shan't": return ["shall", "not"]
                default:
                    if word.hasSuffix("n't") {
                        return [String(word.dropLast(3)), "not"]
                    }
                    let normalized = word.replacingOccurrences(of: "'", with: "")
                    return normalized.isEmpty ? [] : [normalized]
                }
            }
    }

    private static let negations: Set<String> = ["no", "not", "never", "without", "neither", "nor"]

    private static func protectedWords(in words: [String]) -> [String] {
        words.filter { negations.contains($0) || $0.contains(where: \.isNumber) }
    }

    private static func negatedWords(in words: [String]) -> [String?] {
        words.indices.filter { negations.contains(words[$0]) }.map { index in
            index + 1 < words.count ? words[index + 1] : nil
        }
    }

    // Keep numeric punctuation as well: "1.5" and "1,5" otherwise split into
    // identical word tokens. Signs, decimals, dates, and times can carry meaning.
    private static let numberPattern = try! NSRegularExpression(pattern: #"[+-]?\p{N}+(?:[.,:/-]\p{N}+)*"#)

    private static func numbers(in text: String) -> [String] {
        numberPattern.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
            .map { (text as NSString).substring(with: $0.range) }
    }

    private static func isWithinEditBudget(
        _ original: [String],
        _ cleaned: [String],
        maximumEdits: Int
    ) -> Bool {
        guard abs(original.count - cleaned.count) <= maximumEdits else {
            return false
        }
        if original == cleaned {
            return true
        }
        guard maximumEdits > 0 else {
            return false
        }

        // Banded Levenshtein distance counts insertions, deletions, and substitutions.
        // Unlike a greedy subsequence scan, one correction cannot consume the entire
        // remaining candidate. Only inspect alignments within the allowed edit budget.
        let outsideBudget = maximumEdits + 1
        var previous = (0...cleaned.count).map { min($0, outsideBudget) }
        for originalIndex in 1...original.count {
            var current = Array(repeating: outsideBudget, count: cleaned.count + 1)
            current[0] = min(originalIndex, outsideBudget)
            let lowerBound = max(1, originalIndex - maximumEdits)
            let upperBound = min(cleaned.count, originalIndex + maximumEdits)
            var best = current[0]

            for cleanedIndex in lowerBound...upperBound {
                let substitution = previous[cleanedIndex - 1]
                    + (original[originalIndex - 1] == cleaned[cleanedIndex - 1] ? 0 : 1)
                current[cleanedIndex] = min(
                    substitution,
                    previous[cleanedIndex] + 1,
                    current[cleanedIndex - 1] + 1
                )
                best = min(best, current[cleanedIndex])
            }

            guard best <= maximumEdits else {
                return false
            }
            previous = current
        }

        return previous[cleaned.count] <= maximumEdits
    }
}
