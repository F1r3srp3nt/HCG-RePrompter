import Foundation

public enum TemplateCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case softwareDevelopment
    case businessStrategy
    case research
    case writing
    case dataAnalysis
    case education
    case creativeWork

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .softwareDevelopment: "Software Development"
        case .businessStrategy: "Business Strategy"
        case .research: "Research"
        case .writing: "Writing"
        case .dataAnalysis: "Data Analysis"
        case .education: "Education"
        case .creativeWork: "Creative Work"
        }
    }

    public var symbolName: String {
        switch self {
        case .softwareDevelopment: "hammer"
        case .businessStrategy: "chart.line.uptrend.xyaxis"
        case .research: "magnifyingglass"
        case .writing: "pencil.line"
        case .dataAnalysis: "tablecells"
        case .education: "graduationcap"
        case .creativeWork: "sparkles"
        }
    }
}

/// A reusable starting point for a prompt. Placeholders use `{{name}}`.
public struct PromptTemplate: Codable, Identifiable, Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var category: TemplateCategory
    public var summary: String
    public var body: String
    public var suggestedMode: EnhancementMode
    public var isBuiltIn: Bool
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        category: TemplateCategory,
        summary: String,
        body: String,
        suggestedMode: EnhancementMode,
        isBuiltIn: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.body = body
        self.suggestedMode = suggestedMode
        self.isBuiltIn = isBuiltIn
        self.updatedAt = updatedAt
    }

    /// Placeholder names in order of first appearance.
    public var placeholders: [String] { TemplateRenderer.placeholders(in: body) }
}

public enum TemplateRenderer {
    public static func placeholders(in text: String) -> [String] {
        var names: [String] = []
        var remainder = text[...]
        while let open = remainder.range(of: "{{") {
            let afterOpen = remainder[open.upperBound...]
            guard let close = afterOpen.range(of: "}}") else { break }
            let name = afterOpen[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name.count <= 60, !name.contains("{"), !names.contains(name) { names.append(name) }
            remainder = afterOpen[close.upperBound...]
        }
        return names
    }

    /// Replaces `{{name}}` placeholders with the supplied values. Unfilled
    /// placeholders are left in place so the user can see what is missing.
    public static func fill(_ text: String, values: [String: String]) -> String {
        var result = text
        for (name, value) in values where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for variant in ["{{\(name)}}", "{{ \(name) }}"] {
                result = result.replacingOccurrences(of: variant, with: value)
            }
        }
        return result
    }
}

/// The initial, deliberately small template library.
public enum BuiltInTemplates {
    static let epoch = Date(timeIntervalSince1970: 1_790_000_000)

    public static let all: [PromptTemplate] = [
        PromptTemplate(
            id: "builtin.software.feature",
            name: "Feature Implementation",
            category: .softwareDevelopment,
            summary: "Brief an AI on a feature you want built, with constraints and tests.",
            body: """
            Implement {{feature}} in {{project or codebase}}.
            The code is written in {{language and framework}}.
            Users should be able to {{what users can do once it works}}.
            Do not change {{areas that must stay untouched}}.
            Include unit tests for the new behaviour.
            Explain any design decisions that are not obvious.
            """,
            suggestedMode: .developer,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.software.bug",
            name: "Bug Investigation",
            category: .softwareDevelopment,
            summary: "Describe a defect so the AI can diagnose the root cause before fixing it.",
            body: """
            Help me find the root cause of a bug in {{component}}.
            Expected behaviour: {{what should happen}}.
            Actual behaviour: {{what happens instead}}.
            Steps to reproduce: {{steps}}.
            Relevant error output: {{error message or log excerpt}}.
            Explain the likely cause before proposing a fix, and keep the fix minimal.
            """,
            suggestedMode: .developer,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.software.review",
            name: "Code Review",
            category: .softwareDevelopment,
            summary: "Ask for a focused review of a change.",
            body: """
            Review the following {{language}} code for correctness, security and maintainability.
            Focus especially on {{area of concern}}.
            List issues in order of severity and suggest a concrete fix for each.
            Do not rewrite code that has no problems.

            {{code}}
            """,
            suggestedMode: .developer,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.business.options",
            name: "Strategic Options Analysis",
            category: .businessStrategy,
            summary: "Compare strategic options against explicit criteria.",
            body: """
            Compare the following strategic options for {{organization}}: {{options}}.
            Our goal is {{goal}} within {{time frame}}.
            Evaluate each option against {{criteria}}.
            Present the comparison as a table, followed by a recommendation and its main risks.
            Base the analysis only on the information provided and state clearly where more data is needed.
            """,
            suggestedMode: .structured,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.research.scope",
            name: "Research Question Scoping",
            category: .research,
            summary: "Turn a broad topic into a researchable question and plan.",
            body: """
            I am researching {{topic}} for {{purpose or audience}}.
            Help me narrow this into one or two precise research questions.
            For each question, suggest the kinds of sources and evidence that would answer it.
            Point out terms that need definitions and any likely sources of bias.
            Do not invent citations; describe source types instead.
            """,
            suggestedMode: .structured,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.writing.email",
            name: "Professional Email",
            category: .writing,
            summary: "Draft a clear email with the right tone for the recipient.",
            body: """
            Write an email to {{recipient and relationship}} about {{subject}}.
            The purpose of the email is to {{desired outcome}}.
            Key points to include: {{key points}}.
            Keep it under {{word limit}} words and use a {{tone}} tone.
            """,
            suggestedMode: .professional,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.data.explore",
            name: "Dataset Exploration",
            category: .dataAnalysis,
            summary: "Plan an exploratory analysis of a dataset.",
            body: """
            I have a dataset of {{what the data describes}} with these columns: {{columns}}.
            I want to understand {{question you want answered}}.
            Suggest an exploratory analysis plan, including data-quality checks, summary statistics and charts.
            Use {{tool or language}} for any code.
            Flag any conclusions that the data cannot support.
            """,
            suggestedMode: .structured,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.education.explain",
            name: "Concept Explanation",
            category: .education,
            summary: "Explain a concept at the right level for a specific learner.",
            body: """
            Explain {{concept}} to {{learner and their current level}}.
            Use one concrete example from {{familiar domain}}.
            Check understanding with three short questions at the end, with answers listed separately.
            Avoid jargon unless you define it first.
            """,
            suggestedMode: .structured,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.creative.story",
            name: "Short Story Brief",
            category: .creativeWork,
            summary: "Set up a short story with clear creative direction.",
            body: """
            Write a short story about {{premise}}.
            The main character is {{character}}.
            The tone should be {{tone}}, in the style of {{style reference}}.
            It should be around {{length}} and end with {{type of ending}}.
            Avoid {{things to avoid}}.
            """,
            suggestedMode: .creative,
            isBuiltIn: true,
            updatedAt: epoch
        ),
        PromptTemplate(
            id: "builtin.creative.visual",
            name: "Visual Design Brief",
            category: .creativeWork,
            summary: "Describe an image or design for an image-generation or design assistant.",
            body: """
            Create {{type of visual}} showing {{subject}}.
            The mood should be {{mood}} with a {{colour palette}} colour palette.
            The composition should emphasise {{focal point}}.
            It will be used for {{intended use and format}}.
            Do not include {{elements to exclude}}.
            """,
            suggestedMode: .creative,
            isBuiltIn: true,
            updatedAt: epoch
        ),
    ]
}
