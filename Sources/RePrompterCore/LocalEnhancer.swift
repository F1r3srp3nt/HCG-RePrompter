import Foundation

/// Produces an `EnhancementResult` with the deterministic local formatter.
/// Results are always labelled `.localFormatter` so the interface never
/// presents them as AI output.
public enum LocalEnhancer {
    public static func enhance(_ request: EnhancementRequest, limits: InputLimits = .standard) throws(InputValidationError) -> EnhancementResult {
        let validated = try InputValidator.validate(request, limits: limits)
        let output = LocalFormatter.format(validated)
        let preservation = PreservationChecker.check(original: validated.originalPrompt, enhanced: output.text)
        var warnings = output.warnings
        warnings += PreservationChecker.warnings(for: preservation)
        warnings += EnhancementResponseValidator.qualityWarnings(original: validated.originalPrompt, enhanced: output.text)
        return EnhancementResult(
            enhancedPrompt: output.text,
            report: output.report,
            processor: .localFormatter,
            mode: validated.mode,
            preservation: preservation,
            warnings: warnings
        )
    }
}
