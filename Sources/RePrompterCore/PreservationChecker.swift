import Foundation

/// A concrete detail from the original prompt that an enhanced prompt must keep:
/// numbers, quoted text, URLs, code identifiers, acronyms, verbatim code and
/// negated instructions.
public struct PreservationAnchor: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case number
        case quotedText
        case url
        case identifier
        case acronym
        case codeBlock
        case negation
    }

    public var kind: Kind
    public var value: String
    /// For negations: the content words that must appear near a negation.
    public var keywords: [String]

    public init(kind: Kind, value: String, keywords: [String] = []) {
        self.kind = kind
        self.value = value
        self.keywords = keywords
    }
}

public struct AnchorStatus: Codable, Sendable, Equatable, Hashable {
    public var anchor: PreservationAnchor
    public var preserved: Bool
}

/// The result of comparing an enhanced prompt against the original.
public struct PreservationReport: Codable, Sendable, Equatable {
    public var statuses: [AnchorStatus]

    public init(statuses: [AnchorStatus]) { self.statuses = statuses }

    public static let empty = PreservationReport(statuses: [])

    public var missing: [PreservationAnchor] { statuses.filter { !$0.preserved }.map(\.anchor) }
    public var preservedCount: Int { statuses.filter(\.preserved).count }
    public var isComplete: Bool { statuses.allSatisfy(\.preserved) }
}

/// Deterministic check that concrete details survive an enhancement. This is a
/// safety net, not a semantic judge: it flags details that appear to be missing
/// so the user can review them.
public enum PreservationChecker {
    static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "for", "with", "by", "at", "from",
        "is", "are", "be", "it", "this", "that", "these", "those", "as", "any", "all", "my", "your", "our",
        "do", "does", "don't", "dont", "not", "never", "no", "avoid", "without", "must", "mustn't", "should",
        "shouldn't", "can't", "cannot", "won't", "use", "using", "please", "you", "we", "i", "me", "us",
        "them", "they", "their", "its", "into", "than", "then", "so", "if", "else", "also", "just", "only",
        "will", "would", "could", "can", "have", "has", "had", "was", "were", "been", "being", "make", "sure",
    ]
    static let negationWords = [
        "don't", "dont", "do not", "never", "avoid", "must not", "mustn't", "should not", "shouldn't",
        "without", "no ", "not ", "exclude", "cannot", "can't", "won't", "refrain", "prohibit", "forbid",
        "free of", "omit",
    ]

    // MARK: Extraction

    public static func anchors(in original: String) -> [PreservationAnchor] {
        var anchors: [PreservationAnchor] = []
        var seen = Set<String>()
        func add(_ anchor: PreservationAnchor) {
            let key = anchor.kind.rawValue + "|" + anchor.value.lowercased()
            if seen.insert(key).inserted { anchors.append(anchor) }
        }

        let units = TextSegmenter.segment(TextSanitizer.sanitize(original))
        for unit in units {
            if unit.kind == .codeBlock {
                add(PreservationAnchor(kind: .codeBlock, value: unit.text))
                continue
            }
            for quoted in quotedSegments(in: unit.text) { add(PreservationAnchor(kind: .quotedText, value: quoted)) }
            for token in Tokenizer.tokens(unit.text) {
                if let kind = classifyToken(token) { add(PreservationAnchor(kind: kind, value: token)) }
            }
            if let negation = negationAnchor(for: unit.text) { add(negation) }
        }
        return anchors
    }

    static func classifyToken(_ token: String) -> PreservationAnchor.Kind? {
        let lower = token.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") { return .url }
        if token.contains(where: \.isNumber) {
            // Ordinals such as "1st" and list-like numbers are still details worth keeping.
            return token.contains(where: \.isLetter) && !token.first!.isNumber ? .identifier : .number
        }
        let letters = token.filter(\.isLetter)
        guard letters.count >= 2 else { return nil }
        // Acronyms: API, JSON, HCG (all caps, 2–8 letters).
        if letters.count <= 8, token.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "-" || $0 == "&" }) {
            return .acronym
        }
        // Code-like identifiers: snake_case, dotted.names, file.ext, paths, camelCase, PascalCase with inner caps.
        if token.contains("_") || token.contains("/") || token.contains("::") || token.contains("()") { return .identifier }
        if token.contains("."), !token.hasSuffix("."), token.split(separator: ".").count >= 2,
           token.split(separator: ".").allSatisfy({ !$0.isEmpty }) {
            return .identifier
        }
        let innerCapitals = token.dropFirst().filter(\.isUppercase).count
        let lowercase = token.filter(\.isLowercase).count
        if innerCapitals >= 1, lowercase >= 1 { return .identifier } // camelCase, SwiftUI, macOS, PostgreSQL
        return nil
    }

    static func quotedSegments(in text: String) -> [String] {
        var results: [String] = []
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("`", "`")]
        for (open, close) in pairs {
            var current: String? = nil
            for character in text {
                if var buffer = current {
                    if character == close {
                        let trimmed = buffer.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty, trimmed.count <= 200 { results.append(trimmed) }
                        current = nil
                    } else {
                        buffer.append(character)
                        current = buffer
                    }
                } else if character == open {
                    current = ""
                }
            }
        }
        return results
    }

    static func negationAnchor(for sentence: String) -> PreservationAnchor? {
        let lower = " " + sentence.lowercased() + " "
        guard negationWords.contains(where: { lower.contains(" " + $0) }) else { return nil }
        let keywords = contentWords(sentence)
        guard !keywords.isEmpty else { return nil }
        return PreservationAnchor(kind: .negation, value: sentence, keywords: Array(keywords.prefix(6)))
    }

    static func contentWords(_ text: String) -> [String] {
        var seen = Set<String>()
        return Tokenizer.words(text).filter { word in
            word.count >= 3 && !stopWords.contains(word) && seen.insert(word).inserted
        }
    }

    // MARK: Checking

    public static func check(original: String, enhanced: String) -> PreservationReport {
        check(anchors: anchors(in: original), enhanced: enhanced)
    }

    public static func check(anchors: [PreservationAnchor], enhanced: String) -> PreservationReport {
        let sanitized = TextSanitizer.sanitize(enhanced)
        let lowerEnhanced = sanitized.lowercased()
        let tokenSet = Set(Tokenizer.tokens(sanitized).map { $0.lowercased() })
        let sentences = TextSegmenter.segment(sanitized).map { " " + $0.text.lowercased() + " " }
        let compactEnhanced = collapseWhitespace(sanitized)

        let statuses = anchors.map { anchor -> AnchorStatus in
            let preserved: Bool
            switch anchor.kind {
            case .number, .identifier, .acronym:
                preserved = tokenSet.contains(anchor.value.lowercased())
                    || lowerEnhanced.contains(anchor.value.lowercased()) && anchor.value.count >= 4
            case .url, .quotedText:
                preserved = lowerEnhanced.contains(anchor.value.lowercased())
            case .codeBlock:
                preserved = compactEnhanced.contains(collapseWhitespace(stripFences(anchor.value)))
            case .negation:
                preserved = negationPreserved(keywords: anchor.keywords, sentences: sentences)
            }
            return AnchorStatus(anchor: anchor, preserved: preserved)
        }
        return PreservationReport(statuses: statuses)
    }

    /// A negated instruction is preserved when some sentence of the enhanced
    /// prompt contains a negation together with most of its content words.
    static func negationPreserved(keywords: [String], sentences: [String]) -> Bool {
        guard !keywords.isEmpty else { return true }
        let required = max(1, Int((Double(keywords.count) * 0.6).rounded(.up)))
        for sentence in sentences where negationWords.contains(where: { sentence.contains(" " + $0) }) {
            let words = Set(Tokenizer.words(sentence))
            let hits = keywords.filter { keyword in words.contains(keyword) || sentence.contains(keyword) }.count
            if hits >= required { return true }
        }
        return false
    }

    static func stripFences(_ code: String) -> String {
        var lines = code.components(separatedBy: "\n")
        if let first = lines.first?.trimmingCharacters(in: .whitespaces), first.hasPrefix("```") || first.hasPrefix("~~~") {
            lines.removeFirst()
        }
        if let last = lines.last?.trimmingCharacters(in: .whitespaces), last.hasPrefix("```") || last.hasPrefix("~~~") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Converts missing anchors into user-facing warnings.
    public static func warnings(for report: PreservationReport) -> [ValidationWarning] {
        report.missing.prefix(20).map { anchor in
            switch anchor.kind {
            case .negation:
                ValidationWarning(
                    kind: .possiblyDroppedConstraint,
                    message: "A restriction from the original may be missing or weakened: “\(truncate(anchor.value, 140))”"
                )
            case .codeBlock:
                ValidationWarning(kind: .possiblyDroppedContent, message: "A code block from the original is not reproduced verbatim.")
            default:
                ValidationWarning(kind: .possiblyDroppedContent, message: "“\(truncate(anchor.value, 80))” from the original does not appear in the enhanced prompt.")
            }
        }
    }

    static func truncate(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
