import Foundation

/// A user's request to enhance a prompt.
public struct EnhancementRequest: Sendable, Equatable {
    public var originalPrompt: String
    public var mode: EnhancementMode
    /// Only used by `.custom` mode.
    public var customInstructions: String?

    public init(originalPrompt: String, mode: EnhancementMode, customInstructions: String? = nil) {
        self.originalPrompt = originalPrompt
        self.mode = mode
        self.customInstructions = customInstructions
    }
}

/// Structured explanation of what an enhancement did. Produced by the AI
/// provider (validated against the response contract) or by the local formatter.
public struct EnhancementReport: Codable, Sendable, Equatable {
    public var objective: String
    public var explicitRequirements: [String]
    public var constraints: [String]
    public var intendedOutput: String
    public var structuralChanges: [String]
    public var optionalSuggestions: [String]
    public var missingInformation: [String]
    public var assumptions: [String]
    public var ambiguities: [String]

    public init(
        objective: String = "",
        explicitRequirements: [String] = [],
        constraints: [String] = [],
        intendedOutput: String = "",
        structuralChanges: [String] = [],
        optionalSuggestions: [String] = [],
        missingInformation: [String] = [],
        assumptions: [String] = [],
        ambiguities: [String] = []
    ) {
        self.objective = objective
        self.explicitRequirements = explicitRequirements
        self.constraints = constraints
        self.intendedOutput = intendedOutput
        self.structuralChanges = structuralChanges
        self.optionalSuggestions = optionalSuggestions
        self.missingInformation = missingInformation
        self.assumptions = assumptions
        self.ambiguities = ambiguities
    }

    public static let empty = EnhancementReport()
}

/// Identifies what produced an enhancement.
public enum ProcessorKind: Codable, Sendable, Equatable, Hashable {
    case ai(providerID: String, providerName: String, model: String)
    case localFormatter

    public var isAI: Bool {
        if case .ai = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case let .ai(_, providerName, model): "\(providerName) · \(model)"
        case .localFormatter: "Local formatting (no AI)"
        }
    }
}

/// A non-fatal issue discovered while validating an enhancement.
public struct ValidationWarning: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case possiblyDroppedContent
        case possiblyDroppedConstraint
        case unchanged
        case lengthChange
        case customInstructionsIgnored
        case truncatedReport
        case providerNote
    }

    public var kind: Kind
    public var message: String
    public var id: String { kind.rawValue + ":" + message }

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// The complete, validated output of an enhancement.
public struct EnhancementResult: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var enhancedPrompt: String
    public var report: EnhancementReport
    public var processor: ProcessorKind
    public var mode: EnhancementMode
    public var preservation: PreservationReport
    public var warnings: [ValidationWarning]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        enhancedPrompt: String,
        report: EnhancementReport,
        processor: ProcessorKind,
        mode: EnhancementMode,
        preservation: PreservationReport,
        warnings: [ValidationWarning],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.enhancedPrompt = enhancedPrompt
        self.report = report
        self.processor = processor
        self.mode = mode
        self.preservation = preservation
        self.warnings = warnings
        self.createdAt = createdAt
    }
}
