import Foundation
import RePrompterCore

/// A prompt in the user's local history or library.
public struct PromptRecord: Codable, Identifiable, Sendable, Equatable {
    public enum ReviewStatus: String, Codable, Sendable, CaseIterable {
        /// Original prompt only; not enhanced yet.
        case draft
        /// Enhanced; awaiting the user's decision.
        case enhanced
        /// The user accepted the enhanced prompt (possibly after editing it).
        case accepted
        /// The user rejected the enhancement and kept the original.
        case rejected

        public var displayName: String {
            switch self {
            case .draft: "Draft"
            case .enhanced: "Enhanced"
            case .accepted: "Accepted"
            case .rejected: "Rejected"
            }
        }
    }

    public static let maxTitleLength = 120
    public static let maxCollectionLength = 60

    public var id: UUID
    public var title: String
    public var originalPrompt: String
    /// The current enhanced text, including any manual edits.
    public var enhancedPrompt: String?
    public var mode: EnhancementMode
    public var customInstructions: String?
    /// The validated enhancement result as produced (before manual edits).
    public var result: EnhancementResult?
    public var status: ReviewStatus
    /// True when the user saved the prompt to their library.
    public var isSaved: Bool
    /// Optional library collection (folder) name.
    public var collection: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        originalPrompt: String,
        enhancedPrompt: String? = nil,
        mode: EnhancementMode = .structured,
        customInstructions: String? = nil,
        result: EnhancementResult? = nil,
        status: ReviewStatus = .draft,
        isSaved: Bool = false,
        collection: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title.map { TextSanitizer.sanitizeLine($0, maxLength: Self.maxTitleLength) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.makeTitle(from: originalPrompt)
        self.originalPrompt = originalPrompt
        self.enhancedPrompt = enhancedPrompt
        self.mode = mode
        self.customInstructions = customInstructions
        self.result = result
        self.status = status
        self.isSaved = isSaved
        self.collection = collection
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// A short title derived from the first meaningful line of a prompt.
    public static func makeTitle(from prompt: String) -> String {
        let firstLine = prompt
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("```") } ?? ""
        let cleaned = TextSanitizer.sanitizeLine(
            firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "#-*• ")),
            maxLength: 500
        )
        guard !cleaned.isEmpty else { return "Untitled Prompt" }
        if cleaned.count <= 60 { return cleaned }
        let cut = cleaned.prefix(60)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > 30 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    /// The text to copy or export: the enhanced prompt if accepted/enhanced, otherwise the original.
    public var effectivePrompt: String {
        switch status {
        case .rejected, .draft: originalPrompt
        case .enhanced, .accepted: enhancedPrompt ?? originalPrompt
        }
    }

    public var exportDocument: ExportDocument {
        ExportDocument(
            title: title,
            originalPrompt: originalPrompt,
            enhancedPrompt: status == .rejected ? nil : enhancedPrompt,
            mode: mode,
            processor: result?.processor,
            report: status == .rejected ? nil : result?.report
        )
    }
}
