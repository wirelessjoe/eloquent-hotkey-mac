import Foundation

struct TextPolisher {
    func polish(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return text
        }

        let replacements: [(String, String)] = [
            (#"(?i)\b(um+|uh+|mm+|er+|ah+)\b[,\s]*"#, ""),
            (#"(?i)\b(you know|i mean)\b[,\s]*"#, ""),
            (#"\s+([,.;:!?])"#, "$1"),
            (#"([,.;:!?])([^\s])"#, "$1 $2"),
            (#"\s{2,}"#, " "),
        ]

        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        text = normalizeSentenceCase(text)
        text = normalizeTrailingPunctuation(text)
        return text
    }

    private func normalizeSentenceCase(_ input: String) -> String {
        guard let firstLetter = input.first(where: \.isLetter) else {
            return input
        }

        let uppercased = String(firstLetter).uppercased()
        guard let range = input.range(of: String(firstLetter)) else {
            return input
        }

        var output = input
        output.replaceSubrange(range, with: uppercased)
        output = output.replacingOccurrences(
            of: #"(?i)\bi\b"#,
            with: "I",
            options: .regularExpression
        )
        return output
    }

    private func normalizeTrailingPunctuation(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else {
            return trimmed
        }

        if ".!?".contains(last) {
            return trimmed
        }

        return trimmed + "."
    }
}
