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

    private struct SegmentKey: Hashable {
        let centiseconds: Int
        let durationCentiseconds: Int
    }

    private var segmentTexts: [SegmentKey: String] = [:]
    private var orderedKeys: [SegmentKey] = []
    private var bestTranscript = ""

    mutating func ingest(formattedTranscript: String, segments: [Segment]) -> Update {
        let formatted = formattedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        merge(segments)

        let merged = mergedTranscript()
        let previousBest = bestTranscript
        let preferred = preferredTranscript(formatted: formatted, merged: merged, previous: previousBest)
        let recognizerTranscriptShrank = !formatted.isEmpty && transcriptScore(previousBest) > transcriptScore(formatted)

        if transcriptScore(preferred) >= transcriptScore(bestTranscript) {
            bestTranscript = preferred
        }

        return Update(
            transcript: bestTranscript,
            recognizerTranscriptShrank: recognizerTranscriptShrank
        )
    }

    private mutating func merge(_ segments: [Segment]) {
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            let key = SegmentKey(
                centiseconds: Self.quantize(segment.timestamp),
                durationCentiseconds: max(1, Self.quantize(segment.duration))
            )

            if segmentTexts.updateValue(text, forKey: key) == nil {
                orderedKeys.append(key)
            }
        }

        orderedKeys.sort {
            if $0.centiseconds == $1.centiseconds {
                return $0.durationCentiseconds < $1.durationCentiseconds
            }
            return $0.centiseconds < $1.centiseconds
        }
    }

    private func mergedTranscript() -> String {
        orderedKeys
            .compactMap { segmentTexts[$0] }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredTranscript(formatted: String, merged: String, previous: String) -> String {
        [formatted, merged, previous]
            .filter { !$0.isEmpty }
            .max(by: { transcriptScore($0) < transcriptScore($1) }) ?? ""
    }

    private func transcriptScore(_ transcript: String) -> Int {
        (Self.wordCount(in: transcript) * 1_000) + transcript.count
    }

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func quantize(_ interval: TimeInterval) -> Int {
        Int((interval * 100).rounded())
    }
}
