import Foundation

struct TranscriptAccumulator {
    struct Segment {
        let timestamp: TimeInterval
        let duration: TimeInterval
        let text: String
    }

    struct Update {
        let transcript: String
        let recognizerTranscriptShrank: Bool
    }

    private static let duplicateTolerance: TimeInterval = 0.05

    private var mergedSegments: [Segment] = []
    private var bestTranscript = ""

    mutating func ingest(formattedTranscript: String, segments: [Segment]) -> Update {
        let formatted = formattedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSegments = normalized(segments)
        if !normalizedSegments.isEmpty {
            merge(normalizedSegments)
        }

        let merged = mergedTranscript()
        let previousBest = bestTranscript
        let preferred = preferredTranscript(
            formatted: formatted,
            merged: merged,
            previous: previousBest
        )

        if !preferred.isEmpty {
            bestTranscript = preferred
        }

        return Update(
            transcript: bestTranscript,
            recognizerTranscriptShrank: !formatted.isEmpty && bestTranscript != formatted
        )
    }

    private mutating func merge(_ newSegments: [Segment]) {
        var updatedSegments = mergedSegments

        for segment in newSegments {
            updatedSegments.removeAll { existing in
                shouldReplace(existing, with: segment)
            }
            updatedSegments.append(segment)
        }

        updatedSegments.sort(using: KeyPathComparator(\.timestamp))
        mergedSegments = deduplicatedSegments(updatedSegments)
    }

    private func deduplicatedSegments(_ segments: [Segment]) -> [Segment] {
        var result: [Segment] = []

        for segment in segments {
            guard let previous = result.last else {
                result.append(segment)
                continue
            }

            if isLikelyDuplicate(previous, segment) {
                result[result.count - 1] = preferredDuplicateSegment(previous, segment)
            } else {
                result.append(segment)
            }
        }

        return result
    }

    private func mergedTranscript() -> String {
        mergedSegments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredTranscript(formatted: String, merged: String, previous: String) -> String {
        guard !formatted.isEmpty else {
            if !merged.isEmpty {
                return merged
            }
            return previous
        }

        if shouldPreferMerged(formatted: formatted, merged: merged) {
            return merged
        }

        if shouldPreservePrevious(previous: previous, current: formatted) {
            return previous
        }

        return formatted
    }

    private func shouldPreferMerged(formatted: String, merged: String) -> Bool {
        guard !merged.isEmpty else {
            return false
        }

        let formattedScore = transcriptScore(formatted)
        let mergedScore = transcriptScore(merged)
        guard mergedScore > formattedScore else {
            return false
        }

        let formattedWords = Self.normalizedWords(in: formatted)
        let mergedWords = Self.normalizedWords(in: merged)
        guard !formattedWords.isEmpty else {
            return true
        }

        let orderedContainment = Self.orderedWordRetention(reference: formattedWords, candidate: mergedWords)
        return orderedContainment >= 0.9 && mergedWords.count >= formattedWords.count + 2
    }

    private func shouldPreservePrevious(previous: String, current: String) -> Bool {
        guard !previous.isEmpty else {
            return false
        }

        let previousScore = transcriptScore(previous)
        let currentScore = transcriptScore(current)
        guard previousScore > 0 else {
            return false
        }

        let shrinkRatio = Double(currentScore) / Double(previousScore)
        if shrinkRatio >= 0.65 {
            return false
        }

        return previous.localizedCaseInsensitiveContains(current)
    }

    private func transcriptScore(_ transcript: String) -> Int {
        (Self.normalizedWords(in: transcript).count * 1_000) + transcript.count
    }

    private func normalized(_ segments: [Segment]) -> [Segment] {
        segments
            .map { segment in
                Segment(
                    timestamp: segment.timestamp,
                    duration: max(segment.duration, 0.01),
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty }
            .sorted(using: KeyPathComparator(\.timestamp))
    }

    private func shouldReplace(_ existing: Segment, with incoming: Segment) -> Bool {
        let existingMidpoint = existing.timestamp + (existing.duration / 2)
        let incomingMidpoint = incoming.timestamp + (incoming.duration / 2)
        let threshold = max(min(existing.duration, incoming.duration) * 0.55, 0.08)
        return abs(existingMidpoint - incomingMidpoint) <= threshold
    }

    private func isLikelyDuplicate(_ lhs: Segment, _ rhs: Segment) -> Bool {
        guard lhs.text.compare(rhs.text, options: .caseInsensitive) == .orderedSame else {
            return false
        }

        return abs(lhs.timestamp - rhs.timestamp) <= Self.duplicateTolerance
    }

    private func preferredDuplicateSegment(_ lhs: Segment, _ rhs: Segment) -> Segment {
        transcriptScore(lhs.text) >= transcriptScore(rhs.text) ? lhs : rhs
    }

    private static func normalizedWords(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { character in
            !(character.isLetter || character.isNumber || character == "/" || character == "_" || character == "-")
        }).map(String.init)
    }

    private static func orderedWordRetention(reference: [String], candidate: [String]) -> Double {
        guard !reference.isEmpty else {
            return 1
        }

        var candidateIndex = 0
        var matches = 0

        for word in reference {
            while candidateIndex < candidate.count {
                if candidate[candidateIndex] == word {
                    matches += 1
                    candidateIndex += 1
                    break
                }

                candidateIndex += 1
            }
        }

        return Double(matches) / Double(reference.count)
    }
}
