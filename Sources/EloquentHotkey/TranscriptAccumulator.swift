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

    private struct Snapshot {
        let transcript: String
        let words: [String]
        let firstSegmentStart: TimeInterval
        let lastSegmentEnd: TimeInterval

        var score: Int {
            (words.count * 1_000) + transcript.count
        }
    }

    private var bestSnapshot: Snapshot?
    private var earliestObservedStart: TimeInterval?

    mutating func ingest(formattedTranscript: String, segments: [Segment]) -> Update {
        let currentTranscript = formattedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTranscript.isEmpty else {
            return Update(
                transcript: bestSnapshot?.transcript ?? "",
                recognizerTranscriptShrank: false
            )
        }

        let currentSnapshot = makeSnapshot(
            transcript: currentTranscript,
            segments: segments
        )
        let anchorStart = min(earliestObservedStart ?? currentSnapshot.firstSegmentStart, currentSnapshot.firstSegmentStart)
        earliestObservedStart = anchorStart

        guard let bestSnapshot else {
            self.bestSnapshot = currentSnapshot
            return Update(
                transcript: currentSnapshot.transcript,
                recognizerTranscriptShrank: false
            )
        }

        if shouldReplaceBest(
            previous: bestSnapshot,
            current: currentSnapshot,
            anchorStart: anchorStart
        ) {
            self.bestSnapshot = currentSnapshot
            return Update(
                transcript: currentSnapshot.transcript,
                recognizerTranscriptShrank: false
            )
        }

        return Update(
            transcript: bestSnapshot.transcript,
            recognizerTranscriptShrank: bestSnapshot.transcript != currentSnapshot.transcript
        )
    }

    private func makeSnapshot(transcript: String, segments: [Segment]) -> Snapshot {
        let words = Self.normalizedWords(in: transcript)
        let trimmedSegments = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let firstSegmentStart = trimmedSegments.first?.timestamp ?? 0
        let lastSegmentEnd = trimmedSegments.last.map { $0.timestamp + $0.duration } ?? 0

        return Snapshot(
            transcript: transcript,
            words: words,
            firstSegmentStart: firstSegmentStart,
            lastSegmentEnd: lastSegmentEnd
        )
    }

    private func shouldReplaceBest(
        previous: Snapshot,
        current: Snapshot,
        anchorStart: TimeInterval
    ) -> Bool {
        guard !current.words.isEmpty else {
            return false
        }

        if isLikelyWrappedDuplicate(previous: previous.words, current: current.words) {
            return true
        }

        let currentPreservesOpening = current.firstSegmentStart <= anchorStart + 1.0
        let previousPreservesOpening = previous.firstSegmentStart <= anchorStart + 1.0

        if previousPreservesOpening != currentPreservesOpening {
            return currentPreservesOpening
        }

        if isClearRegression(previous: previous, current: current) {
            return false
        }

        let startDelta = current.firstSegmentStart - previous.firstSegmentStart
        let endDelta = current.lastSegmentEnd - previous.lastSegmentEnd
        let currentRetentionInPrevious = Self.orderedWordRetention(
            reference: current.words,
            candidate: previous.words
        )
        let previousRetentionInCurrent = Self.orderedWordRetention(
            reference: previous.words,
            candidate: current.words
        )
        let coverageStable = abs(startDelta) <= 0.1 && abs(endDelta) <= 0.35

        if coverageStable && current.transcript != previous.transcript {
            return true
        }

        if current.firstSegmentStart + 0.5 < previous.firstSegmentStart {
            return true
        }

        if endDelta > 0.6 && current.firstSegmentStart <= previous.firstSegmentStart + 0.75 {
            return true
        }

        // Do not let the best snapshot drift forward a few hundred milliseconds at a time
        // unless the recognizer also extends the captured tail in a meaningful way.
        if startDelta > 0.15 && endDelta < 0.5 {
            return false
        }

        if current.score > previous.score,
           current.firstSegmentStart <= previous.firstSegmentStart + 0.5,
           current.lastSegmentEnd >= previous.lastSegmentEnd - 0.2 {
            return true
        }

        if current.score >= previous.score,
           previousRetentionInCurrent >= 0.88,
           currentRetentionInPrevious < 0.98 {
            return true
        }

        return false
    }

    private func isClearRegression(previous: Snapshot, current: Snapshot) -> Bool {
        guard !previous.words.isEmpty, !current.words.isEmpty else {
            return false
        }

        let wordLoss = previous.words.count - current.words.count
        let startDelta = current.firstSegmentStart - previous.firstSegmentStart
        let endDelta = current.lastSegmentEnd - previous.lastSegmentEnd
        let currentRetentionInPrevious = Self.orderedWordRetention(
            reference: current.words,
            candidate: previous.words
        )

        if startDelta >= 0.25,
           wordLoss >= 1,
           currentRetentionInPrevious >= 0.9,
           endDelta <= 0.35 {
            return true
        }

        if startDelta >= 0.75,
           wordLoss >= 2,
           currentRetentionInPrevious >= 0.9,
           endDelta <= 0.5 {
            return true
        }

        if wordLoss >= 2,
           currentRetentionInPrevious >= 0.95,
           startDelta >= -0.1,
           endDelta <= 0.25 {
            return true
        }

        return false
    }

    private func isLikelyWrappedDuplicate(previous: [String], current: [String]) -> Bool {
        guard previous.count > current.count else {
            return false
        }

        let extraWordCount = previous.count - current.count
        guard extraWordCount >= 1 else {
            return false
        }

        if Array(previous.suffix(current.count)) == current {
            let duplicatedPrefix = Array(previous.prefix(extraWordCount))
            return duplicatedPrefix == Array(current.suffix(extraWordCount))
        }

        if Array(previous.prefix(current.count)) == current {
            let duplicatedSuffix = Array(previous.suffix(extraWordCount))
            return duplicatedSuffix == Array(current.prefix(extraWordCount))
        }

        return false
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
