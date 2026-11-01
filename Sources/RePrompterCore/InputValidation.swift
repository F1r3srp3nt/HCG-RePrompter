import Foundation

/// Limits applied to user input before any processing.
public struct InputLimits: Sendable, Equatable {
    /// Maximum characters in an original prompt.
    public var maxPromptCharacters: Int
    /// Maximum characters in custom-mode instructions.
    public var maxCustomInstructionCharacters: Int

    public init(maxPromptCharacters: Int = 100_000, maxCustomInstructionCharacters: Int = 4_000) {
        self.maxPromptCharacters = maxPromptCharacters
        self.maxCustomInstructionCharacters = maxCustomInstructionCharacters
    }

    public static let standard = InputLimits()
}

public enum InputValidationError: Error, Sendable, Equatable, LocalizedError {
    case emptyPrompt
    case promptTooLong(characters: Int, limit: Int)
    case missingCustomInstructions
    case customInstructionsTooLong(characters: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            "Enter a prompt to enhance."
        case let .promptTooLong(characters, limit):
            "The prompt is \(characters.formatted()) characters; the limit is \(limit.formatted())."
        case .missingCustomInstructions:
            "Custom mode needs style instructions. Describe how you want the prompt rewritten."
        case let .customInstructionsTooLong(characters, limit):
            "Custom instructions are \(characters.formatted()) characters; the limit is \(limit.formatted())."
        }
    }
}

public enum InputValidator {
    /// Validates and normalizes a request. Returns a sanitized copy.
    public static func validate(
        _ request: EnhancementRequest,
        limits: InputLimits = .standard
    ) throws(InputValidationError) -> EnhancementRequest {
        let prompt = TextSanitizer.sanitize(request.originalPrompt)
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .emptyPrompt
        }
        if prompt.count > limits.maxPromptCharacters {
            throw .promptTooLong(characters: prompt.count, limit: limits.maxPromptCharacters)
        }

        var custom: String? = nil
        if request.mode == .custom {
            let instructions = TextSanitizer.sanitize(request.customInstructions ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if instructions.isEmpty { throw .missingCustomInstructions }
            if instructions.count > limits.maxCustomInstructionCharacters {
                throw .customInstructionsTooLong(
                    characters: instructions.count,
                    limit: limits.maxCustomInstructionCharacters
                )
            }
            custom = instructions
        }
        return EnhancementRequest(originalPrompt: prompt, mode: request.mode, customInstructions: custom)
    }
}
