import Foundation

/// Export formats for a prompt and its enhancement.
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case plainText
    case markdown
    case json

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .plainText: "Plain Text (.txt)"
        case .markdown: "Markdown (.md)"
        case .json: "JSON (.json)"
        }
    }
    public var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .markdown: "md"
        case .json: "json"
        }
    }
}

/// The data needed to export a prompt.
public struct ExportDocument: Codable, Sendable, Equatable {
    public var title: String
    public var originalPrompt: String
    public var enhancedPrompt: String?
    public var mode: EnhancementMode?
    public var processor: ProcessorKind?
    public var report: EnhancementReport?
    public var exportedAt: Date
    public var application: String

    public init(
        title: String,
        originalPrompt: String,
        enhancedPrompt: String?,
        mode: EnhancementMode?,
        processor: ProcessorKind?,
        report: EnhancementReport?,
        exportedAt: Date = Date()
    ) {
        self.title = title
        self.originalPrompt = originalPrompt
        self.enhancedPrompt = enhancedPrompt
        self.mode = mode
        self.processor = processor
        self.report = report
        self.exportedAt = exportedAt
        self.application = "\(AppInfo.name) \(AppInfo.version)"
    }
}

public enum PromptExporter {
    public static func export(_ document: ExportDocument, as format: ExportFormat) throws -> Data {
        switch format {
        case .plainText:
            return Data((document.enhancedPrompt ?? document.originalPrompt).utf8)
        case .markdown:
            return Data(markdown(document).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(document)
        }
    }

    public static func markdown(_ document: ExportDocument) -> String {
        var lines: [String] = ["# \(document.title)", ""]
        var meta: [String] = []
        if let mode = document.mode { meta.append("Mode: \(mode.displayName)") }
        if let processor = document.processor { meta.append("Processed by: \(processor.label)") }
        meta.append("Exported: \(ISO8601DateFormatter().string(from: document.exportedAt))")
        lines.append("_" + meta.joined(separator: " · ") + "_")
        lines.append("")
        if let enhanced = document.enhancedPrompt {
            lines += ["## Enhanced Prompt", "", fenced(enhanced), ""]
        }
        lines += ["## Original Prompt", "", fenced(document.originalPrompt), ""]
        if let report = document.report {
            func section(_ title: String, _ items: [String]) {
                guard !items.isEmpty else { return }
                lines.append("## \(title)")
                lines.append("")
                lines += items.map { "- " + $0 }
                lines.append("")
            }
            section("Changes", report.structuralChanges)
            section("Requirements", report.explicitRequirements)
            section("Constraints", report.constraints)
            section("Optional Suggestions", report.optionalSuggestions)
            section("Open Questions", report.missingInformation)
            section("Assumptions", report.assumptions)
        }
        lines.append("---")
        lines.append("Generated with \(AppInfo.name) \(AppInfo.version)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Wraps text in a code fence long enough not to collide with fences inside it.
    static func fenced(_ text: String) -> String {
        var fence = "```"
        while text.contains(fence) { fence += "`" }
        return fence + "text\n" + text + "\n" + fence
    }

    /// A filesystem-safe file name derived from a title.
    public static func suggestedFileName(for title: String, format: ExportFormat) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        var base = title.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "Prompt" }
        return String(base.prefix(80)) + "." + format.fileExtension
    }
}
