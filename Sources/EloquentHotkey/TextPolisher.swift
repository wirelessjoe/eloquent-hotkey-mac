import Foundation

struct TextPolisher {
    func polish(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return text
        }

        text = Self.lineBreaksAndTabs.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: " "
        )
        text = Self.leadingFillers.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: ""
        )
        text = Self.inlineFillers.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: "$1"
        )
        text = Self.duplicateFunctionWords.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: "$1"
        )
        text = Self.repeatedPunctuation.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: "$1"
        )
        text = Self.spaceBeforePunctuation.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: "$1"
        )
        text = Self.missingSpaceAfterPunctuation.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: "$1 $2"
        )
        text = Self.extraSpaces.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: " "
        )
        text = Self.looseEdgePunctuation.stringByReplacingMatches(
            in: text,
            options: [],
            range: text.fullRange,
            withTemplate: "$1"
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        text = normalizeSentenceCase(text)
        text = normalizeTechnicalTerms(text)
        text = normalizeTrailingPunctuation(text)
        return text
    }

    private func normalizeSentenceCase(_ input: String) -> String {
        var output = input

        if let firstLetter = output.first(where: \.isLetter),
           let range = output.range(of: String(firstLetter)) {
            output.replaceSubrange(range, with: String(firstLetter).uppercased())
        }

        output = Self.standaloneI.stringByReplacingMatches(
            in: output,
            options: [],
            range: output.fullRange,
            withTemplate: "I"
        )

        let characters = Array(output)
        var capitalized = String()
        capitalized.reserveCapacity(characters.count)
        var shouldUppercaseNextLetter = false

        for character in characters {
            if shouldUppercaseNextLetter, character.isLetter {
                capitalized.append(contentsOf: String(character).uppercased())
                shouldUppercaseNextLetter = false
                continue
            }

            capitalized.append(character)

            if ".!?".contains(character) {
                shouldUppercaseNextLetter = true
            } else if !character.isWhitespace && character != "\"" && character != "'" && character != ")" {
                shouldUppercaseNextLetter = false
            }
        }

        return capitalized
    }

    private func normalizeTrailingPunctuation(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else {
            return trimmed
        }

        if ".!?".contains(last) {
            return trimmed
        }

        if ",;:".contains(last) {
            return String(trimmed.dropLast()) + "."
        }

        return trimmed + "."
    }

    private func normalizeTechnicalTerms(_ input: String) -> String {
        var output = input

        for (pattern, replacement) in Self.technicalPhraseReplacements {
            output = pattern.stringByReplacingMatches(
                in: output,
                options: [],
                range: output.fullRange,
                withTemplate: replacement
            )
        }

        if prefersCodingCorrections(in: output) {
            for (pattern, replacement) in Self.codingContextReplacements {
                output = pattern.stringByReplacingMatches(
                    in: output,
                    options: [],
                    range: output.fullRange,
                    withTemplate: replacement
                )
            }
        }

        return output
    }

    private func prefersCodingCorrections(in input: String) -> Bool {
        Self.codingContextHints.contains { pattern in
            pattern.firstMatch(in: input, options: [], range: input.fullRange) != nil
        }
    }

    private static let lineBreaksAndTabs = regex(#"[\t\r\n]+"#)
    private static let leadingFillers = regex(#"(?i)^\s*(?:um+|uh+|mm+|hmm+|er+|ah+|you know|i mean)\b[\s,.-]*"#)
    private static let inlineFillers = regex(#"(?i)(^|[\s(])(?:um+|uh+|mm+|hmm+|er+|ah+|you know|i mean)\b(?:\s*,\s*|\s+)"#)
    private static let duplicateFunctionWords = regex(#"(?i)\b(i|the|a|an|and|but|or|to|of|in|for|we|you|it|that)\s+\1\b"#)
    private static let repeatedPunctuation = regex(#"([,.;:!?])(?:\s*\1)+"#)
    private static let spaceBeforePunctuation = regex(#"\s+([,.;:!?])"#)
    private static let missingSpaceAfterPunctuation = regex(#"([,.;:!?])([^\s,.;:!?])"#)
    private static let extraSpaces = regex(#"\s{2,}"#)
    private static let looseEdgePunctuation = regex(#"^[,.;:!?]+\s*|\s*([,.;:!?])\s*$"#)
    private static let standaloneI = regex(#"(?i)\bi\b"#)
    private static let technicalPhraseReplacements: [(NSRegularExpression, String)] = [
        (regex(#"(?i)\bgit\s*hub\b"#), "GitHub"),
        (regex(#"(?i)\bget\s+her\b"#), "GitHub"),
        (regex(#"(?i)\bmac\s*os\b"#), "macOS"),
        (regex(#"(?i)\bios\b"#), "iOS"),
        (regex(#"(?i)\bipad\s*os\b"#), "iPadOS"),
        (regex(#"(?i)\bwatch\s*os\b"#), "watchOS"),
        (regex(#"(?i)\bvision\s*os\b"#), "visionOS"),
        (regex(#"(?i)\bread\s+me\b"#), "README"),
        (regex(#"(?i)\bswift\s*ui\b"#), "SwiftUI"),
        (regex(#"(?i)\bx\s*code\b"#), "Xcode"),
        (regex(#"(?i)\bopen\s*ai\b"#), "OpenAI"),
        (regex(#"(?i)\bchat\s*gpt\b"#), "ChatGPT"),
        (regex(#"(?i)\bjava\s*script\b"#), "JavaScript"),
        (regex(#"(?i)\btype\s*script\b"#), "TypeScript"),
        (regex(#"(?i)\bgraph\s*q\s*l\b"#), "GraphQL"),
        (regex(#"(?i)\bpost\s*gre\s*s(?:\s*q\s*l)?\b"#), "PostgreSQL"),
        (regex(#"(?i)\boauth\b"#), "OAuth"),
        (regex(#"(?i)\bapi\b"#), "API"),
        (regex(#"(?i)\burl\b"#), "URL"),
        (regex(#"(?i)\bjson\b"#), "JSON"),
        (regex(#"(?i)\bsql\b"#), "SQL"),
        (regex(#"(?i)\bcli\b"#), "CLI"),
    ]
    private static let codingContextHints: [NSRegularExpression] = [
        regex(#"(?i)\bGitHub\b"#),
        regex(#"(?i)\brepo(?:sitory)?\b"#),
        regex(#"(?i)\bREADME\b"#),
        regex(#"(?i)\bpull request\b"#),
        regex(#"(?i)\bPR\b"#),
        regex(#"(?i)\bbranch\b"#),
        regex(#"(?i)\bcommit\b"#),
        regex(#"(?i)\bmerge\b"#),
        regex(#"(?i)\brebase\b"#),
        regex(#"(?i)\bSwift(?:UI)?\b"#),
        regex(#"(?i)\bXcode\b"#),
        regex(#"(?i)\bCodex\b"#),
        regex(#"(?i)\bOpenAI\b"#),
        regex(#"(?i)\bJSON\b"#),
        regex(#"(?i)\bAPI\b"#),
        regex(#"(?i)\bCLI\b"#),
        regex(#"(?i)\bTerminal\b"#),
    ]
    private static let codingContextReplacements: [(NSRegularExpression, String)] = [
        (regex(#"(?i)\bmaine\b"#), "main"),
        (regex(#"(?i)\borigin\s+main\b"#), "origin/main"),
        (regex(#"(?i)\borigin\s+maine\b"#), "origin/main"),
        (regex(#"(?i)\bpool\s+request\b"#), "pull request"),
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
}

private extension String {
    var fullRange: NSRange {
        NSRange(startIndex..<endIndex, in: self)
    }
}
