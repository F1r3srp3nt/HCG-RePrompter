import Foundation

/// A run of text in a diff.
public struct DiffSegment: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable { case equal, inserted, removed }
    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct DiffSummary: Sendable, Equatable {
    public var unchangedWords: Int
    public var insertedWords: Int
    public var removedWords: Int
    /// True when the inputs were too large for a word-level diff and a coarser
    /// line-level comparison was used.
    public var isApproximate: Bool
}

/// Longest-common-subsequence diff over words (or lines for very large inputs).
public enum TextDiff {
    /// Upper bound on the LCS table size (cells) to keep memory bounded.
    public static let maxCells = 4_000_000

    public static func diff(_ old: String, _ new: String) -> (segments: [DiffSegment], summary: DiffSummary) {
        let oldWords = wordTokens(old)
        let newWords = wordTokens(new)
        if oldWords.count * newWords.count <= maxCells {
            let segments = lcsDiff(oldWords, newWords)
            return (segments, summarize(segments, approximate: false))
        }
        let oldLines = old.components(separatedBy: "\n").map { $0 + "\n" }
        let newLines = new.components(separatedBy: "\n").map { $0 + "\n" }
        if oldLines.count * newLines.count <= maxCells {
            let segments = lcsDiff(oldLines, newLines)
            return (segments, summarize(segments, approximate: true))
        }
        let segments = [DiffSegment(kind: .removed, text: old), DiffSegment(kind: .inserted, text: new)]
        return (segments, summarize(segments, approximate: true))
    }

    /// Splits text into words, keeping the trailing whitespace attached so the
    /// segments reassemble into the original text exactly.
    static func wordTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWhitespace = false
        for character in text {
            if character.isWhitespace {
                inWhitespace = true
                current.append(character)
            } else {
                if inWhitespace, !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inWhitespace = false
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func lcsDiff(_ a: [String], _ b: [String]) -> [DiffSegment] {
        let n = a.count, m = b.count
        if n == 0 { return b.isEmpty ? [] : [DiffSegment(kind: .inserted, text: b.joined())] }
        if m == 0 { return [DiffSegment(kind: .removed, text: a.joined())] }

        // Compare on trimmed tokens so whitespace-only changes are not noise.
        let ka = a.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let kb = b.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        let width = m + 1
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i * width + j] = ka[i] == kb[j]
                    ? table[(i + 1) * width + j + 1] + 1
                    : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }

        var segments: [DiffSegment] = []
        func append(_ kind: DiffSegment.Kind, _ text: String) {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].text += text
            } else {
                segments.append(DiffSegment(kind: kind, text: text))
            }
        }
        var i = 0, j = 0
        while i < n, j < m {
            if ka[i] == kb[j] {
                append(.equal, b[j]); i += 1; j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                append(.removed, a[i]); i += 1
            } else {
                append(.inserted, b[j]); j += 1
            }
        }
        while i < n { append(.removed, a[i]); i += 1 }
        while j < m { append(.inserted, b[j]); j += 1 }
        return segments
    }

    static func summarize(_ segments: [DiffSegment], approximate: Bool) -> DiffSummary {
        var summary = DiffSummary(unchangedWords: 0, insertedWords: 0, removedWords: 0, isApproximate: approximate)
        for segment in segments {
            let count = segment.text.split(whereSeparator: { $0.isWhitespace }).count
            switch segment.kind {
            case .equal: summary.unchangedWords += count
            case .inserted: summary.insertedWords += count
            case .removed: summary.removedWords += count
            }
        }
        return summary
    }
}
