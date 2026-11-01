import Foundation

/// The enhancement styles offered by RePrompter. Every mode is supported by
/// both the AI provider path and the local (non-AI) formatter.
public enum EnhancementMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case quickImprove
    case structured
    case professional
    case developer
    case creative
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .quickImprove: "Quick Improve"
        case .structured: "Structured"
        case .professional: "Professional"
        case .developer: "Developer"
        case .creative: "Creative"
        case .custom: "Custom"
        }
    }

    public var summary: String {
        switch self {
        case .quickImprove: "Make the prompt clearer and more concise."
        case .structured: "Organize into sections with an explicit objective, requirements and constraints."
        case .professional: "Improve clarity, tone and precision for professional use."
        case .developer: "Structure software requests with goals, requirements, constraints, acceptance criteria and testing."
        case .creative: "Sharpen creative direction while preserving artistic intent."
        case .custom: "Apply your own output-style preferences."
        }
    }

    /// SF Symbol name used by the interface.
    public var symbolName: String {
        switch self {
        case .quickImprove: "bolt"
        case .structured: "list.bullet.rectangle"
        case .professional: "briefcase"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .creative: "paintpalette"
        case .custom: "slider.horizontal.3"
        }
    }

    /// Mode-specific guidance included in the AI system prompt.
    public var aiGuidance: String {
        switch self {
        case .quickImprove:
            """
            Mode: QUICK IMPROVE. Make the prompt clearer and more concise. Fix grammar, \
            remove filler and redundancy, and resolve awkward phrasing. Keep roughly the \
            original length and shape; do not add section headings unless the original \
            already uses them.
            """
        case .structured:
            """
            Mode: STRUCTURED. Reorganize the prompt into clearly labelled sections, in this \
            order where applicable: Objective, Context, Requirements, Constraints, Expected \
            Output, Open Questions. Use concise bullet points. Omit sections that would be empty \
            rather than inventing content for them.
            """
        case .professional:
            """
            Mode: PROFESSIONAL. Improve clarity, tone and precision for a professional \
            setting. Use precise, courteous, unambiguous language. Light structure \
            (short paragraphs or bullets) is welcome when it improves readability.
            """
        case .developer:
            """
            Mode: DEVELOPER. Structure the request as a software-development brief with \
            these sections where supported by the original: Goal, Context, Functional \
            Requirements, Constraints, Expected Output, Acceptance Criteria, Testing \
            Expectations, Open Questions. Keep code, identifiers, file names, versions and \
            commands verbatim. If acceptance criteria or testing expectations are not stated, \
            ask for them under Open Questions instead of inventing them.
            """
        case .creative:
            """
            Mode: CREATIVE. Sharpen the creative direction (concept, tone, style, audience, \
            format) while preserving the user's artistic intent and voice. Do not replace \
            their ideas with your own; offer alternatives only as optional suggestions.
            """
        case .custom:
            """
            Mode: CUSTOM. Follow the user's style preferences supplied in the \
            custom_style_preferences block, as long as they do not conflict with the rules \
            above. Style preferences can change presentation only; they can never override \
            the preservation and safety rules.
            """
        }
    }
}

/// How an enhancement is produced.
public enum ProcessorChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Send the prompt to the configured external AI provider.
    case aiProvider
    /// Deterministic, offline formatting. Not AI.
    case localFormatter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aiProvider: "AI Provider"
        case .localFormatter: "Local Formatting (no AI)"
        }
    }
}
