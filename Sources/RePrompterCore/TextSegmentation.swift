import Foundation

/// A unit of prompt text: a sentence, a list item, or a verbatim code block.
public struct PromptUnit: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable {
        case sentence
        case listItem
        case heading
        case codeBlock
    }

    public var kind: Kind
    /// The unit text. For list items the list marker is removed. Code blocks
    /// include their fences and are never modified.
    public var text: String
    /// Index of the paragraph (blank-line separated block) the unit came from.
    public var paragraph: Int

    public init(kind: Kind, text: String, paragraph: Int) {
        self.kind = kind
        self.text = text
        self.paragraph = paragraph
    }
}

/// Splits prompt text into units without losing any non-whitespace content.
public enum TextSegmenter {
    static let abbreviations: Set<String> = [
        "e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "ms.", "dr.", "prof.", "inc.", "ltd.",
        "approx.", "no.", "fig.", "cf.", "al.", "st.", "jr.", "sr.", "u.s.", "a.m.", "p.m.",
    ]

    public static func segment(_ text: String) -> [PromptUnit] {
        var units: [PromptUnit] = []
        var paragraph = 0
        var inCode = false
        var codeLines: [String] = []
        var previousLineBlank = false

        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inCode {
                    codeLines.append(rawLine)
                    units.append(PromptUnit(kind: .codeBlock, text: codeLines.joined(separator: "\n"), paragraph: paragraph))
                    codeLines = []
                    inCode = false
                } else {
                    inCode = true
                    codeLines = [rawLine]
                }
                previousLineBlank = false
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                if !previousLineBlank && !units.isEmpty { paragraph += 1 }
                previousLineBlank = true
                continue
            }
            previousLineBlank = false

            if let heading = headingText(trimmed) {
                units.append(PromptUnit(kind: .heading, text: heading, paragraph: paragraph))
            } else if let item = listItemText(trimmed) {
                if !item.isEmpty {
                    units.append(PromptUnit(kind: .listItem, text: item, paragraph: paragraph))
                }
            } else {
                for sentence in splitSentences(trimmed) {
                    units.append(PromptUnit(kind: .sentence, text: sentence, paragraph: paragraph))
                }
            }
        }

        // An unterminated code fence is kept verbatim.
        if inCode, !codeLines.isEmpty {
            units.append(PromptUnit(kind: .codeBlock, text: codeLines.joined(separator: "\n"), paragraph: paragraph))
        }
        return units
    }

    /// Returns the heading text for Markdown headings (`# Title`).
    static func headingText(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// Returns the item text if the line is a bullet or numbered list item.
    static func listItemText(_ line: String) -> String? {
        for marker in ["- [ ] ", "- [x] ", "- ", "* ", "• ", "+ ", "– "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        // "1. ", "12) ", "a) "
        let chars = Array(line.prefix(6))
        var i = 0
        while i < chars.count, i < 3, chars[i].isNumber { i += 1 }
        let isLetterMarker = i == 0 && !chars.isEmpty && chars[0].isLetter && chars[0].isLowercase
        if isLetterMarker { i = 1 }
        guard i > 0, i + 1 < chars.count else { return nil }
        let terminator = chars[i]
        guard terminator == ")" || (terminator == "." && !isLetterMarker), chars[i + 1] == " " else { return nil }
        return String(line.dropFirst(i + 2)).trimmingCharacters(in: .whitespaces)
    }

    /// Splits a single line into sentences. Keeps decimals, versions, URLs and
    /// common abbreviations intact.
    public static func splitSentences(_ line: String) -> [String] {
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var sentences: [String] = []
        var current: [String] = []
        for (i, word) in words.enumerated() {
            current.append(word)
            guard let last = word.last, ".!?".contains(last) else { continue }
            if abbreviations.contains(word.lowercased()) { continue }
            // Single-letter initials such as "J."
            if word.count == 2, word.first?.isUppercase == true, last == "." { continue }
            let nextIndex = i + 1
            if nextIndex < words.count, last == "." {
                guard let nextFirst = words[nextIndex].first else { continue }
                // Break when the next word plausibly starts a sentence. Casual
                // prompts often start sentences in lowercase, so a lowercase
                // start also counts unless the word looks like an abbreviation,
                // file name or version ("e.g.", "U.S.", "config.json.").
                let startsSentence = nextFirst.isUppercase || nextFirst.isNumber || "\"'“‘([".contains(nextFirst)
                let body = word.dropLast()
                let looksAbbreviated = body.contains(".") || body.filter(\.isLetter).count < 2
                if !startsSentence && (looksAbbreviated || !nextFirst.isLetter) { continue }
            }
            sentences.append(current.joined(separator: " "))
            current = []
        }
        if !current.isEmpty { sentences.append(current.joined(separator: " ")) }
        return sentences
    }
}

/// Word-level tokenization used for analysis and preservation checks.
public enum Tokenizer {
    /// Splits on whitespace and strips surrounding punctuation, keeping inner
    /// punctuation so identifiers, versions, paths and URLs survive intact.
    public static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { trimPunctuation(String($0)) }
            .filter { !$0.isEmpty }
    }

    static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'“”‘’()[]{}<>*`")

    public static func trimPunctuation(_ token: String) -> String {
        token.trimmingCharacters(in: edgePunctuation)
    }

    /// Lowercased alphabetic words, for keyword matching.
    public static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" || $0 == "-" || $0 == "+" || $0 == "#") })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'’-")) }
            .filter { !$0.isEmpty }
    }
}
