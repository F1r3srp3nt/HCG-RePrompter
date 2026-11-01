import Foundation

/// Normalizes untrusted text. Prompt text is always treated as data: this type
/// never interprets or executes it, it only removes characters that have no
/// place in a prompt (NUL and other C0/C1 control characters, bidi overrides).
public enum TextSanitizer {
    /// Normalizes line endings to `\n` and removes disallowed control characters.
    /// Tabs and newlines are preserved.
    public static func sanitize(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars where isAllowed(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Sanitizes a single-line field such as a title: collapses whitespace,
    /// trims, and caps length.
    public static func sanitizeLine(_ text: String, maxLength: Int) -> String {
        let cleaned = sanitize(text)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(cleaned.prefix(maxLength))
    }

    static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A: return true // tab, newline
        case 0x00...0x1F, 0x7F: return false // C0 controls, DEL
        case 0x80...0x9F: return false // C1 controls
        case 0x202A...0x202E, 0x2066...0x2069: return false // bidi embedding/override/isolate
        case 0xFEFF: return false // BOM / zero-width no-break space
        default: return true
        }
    }
}
