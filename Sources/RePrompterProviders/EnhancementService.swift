import Foundation
import RePrompterCore

/// Unified error for an enhancement attempt.
public enum EnhancementError: Error, Sendable, Equatable, LocalizedError {
    case input(InputValidationError)
    case provider(ProviderError)
    case contract(ContractViolation)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .input(error): error.errorDescription
        case let .provider(error): error.errorDescription
        case let .contract(error): (error.errorDescription ?? "") + " Nothing was changed; you can retry."
        case .cancelled: "Enhancement cancelled."
        }
    }

    /// Whether offering a "Retry" action makes sense.
    public var canRetry: Bool {
        switch self {
        case .input: false
        case let .provider(error):
            error.isRetryable || error == .truncated || {
                if case .malformedResponse = error { return true }
                return false
            }()
        case .contract, .cancelled: true
        }
    }
}

/// Progress events surfaced to the interface.
public enum EnhancementEvent: Sendable, Equatable {
    case sending(attempt: Int)
    case waitingToRetry(seconds: Double, reason: String)
    case validating
}

/// Orchestrates an enhancement: validates input, chooses the processor,
/// calls the provider with retries for transient failures, validates the
/// response against the contract and produces an `EnhancementResult`.
///
/// It never silently substitutes the local formatter for AI processing: if
/// AI is requested and no provider is available, it fails with
/// `.notConfigured`.
public struct EnhancementService: Sendable {
    public typealias Sleeper = @Sendable (Double) async throws -> Void

    private let provider: (any AIProvider)?
    private let retryPolicy: RetryPolicy
    private let limits: InputLimits
    private let sleeper: Sleeper

    public init(
        provider: (any AIProvider)?,
        retryPolicy: RetryPolicy = .standard,
        limits: InputLimits = .standard,
        sleeper: @escaping Sleeper = { seconds in try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
    ) {
        self.provider = provider
        self.retryPolicy = retryPolicy
        self.limits = limits
        self.sleeper = sleeper
    }

    public var providerInfo: ProviderInfo? { provider?.info }

    public func enhance(
        _ request: EnhancementRequest,
        processor: ProcessorChoice,
        onEvent: @escaping @Sendable (EnhancementEvent) -> Void = { _ in }
    ) async throws(EnhancementError) -> EnhancementResult {
        let validated: EnhancementRequest
        do {
            validated = try InputValidator.validate(request, limits: limits)
        } catch {
            throw .input(error)
        }

        switch processor {
        case .localFormatter:
            do {
                return try LocalEnhancer.enhance(validated, limits: limits)
            } catch {
                throw .input(error)
            }
        case .aiProvider:
            guard let provider else { throw .provider(.notConfigured) }
            return try await enhanceWithAI(validated, provider: provider, onEvent: onEvent)
        }
    }

    private func enhanceWithAI(
        _ request: EnhancementRequest,
        provider: any AIProvider,
        onEvent: @escaping @Sendable (EnhancementEvent) -> Void
    ) async throws(EnhancementError) -> EnhancementResult {
        let prompt = EnhancementContract.buildPrompt(for: request)
        let providerRequest = ProviderRequest(
            system: prompt.system,
            userMessage: prompt.userMessage,
            responseSchema: EnhancementContract.responseSchema
        )

        var failures = 0
        var response: ProviderResponse?
        while response == nil {
            if Task.isCancelled { throw .cancelled }
            onEvent(.sending(attempt: failures + 1))
            do {
                response = try await provider.complete(providerRequest)
            } catch is CancellationError {
                throw .cancelled
            } catch let error as ProviderError {
                if Task.isCancelled { throw .cancelled }
                failures += 1
                guard let delay = retryPolicy.delay(afterFailures: failures, error: error) else {
                    throw .provider(error)
                }
                onEvent(.waitingToRetry(seconds: delay, reason: error.errorDescription ?? "Temporary error"))
                do {
                    try await sleeper(delay)
                } catch {
                    throw .cancelled
                }
            } catch {
                if Task.isCancelled { throw .cancelled }
                throw .provider(.network(SecretRedactor.redact(error.localizedDescription)))
            }
        }
        guard let response else { throw .provider(.malformedResponse("No response.")) }
        if Task.isCancelled { throw .cancelled }

        onEvent(.validating)
        let validated: EnhancementResponseValidator.Validated
        do {
            validated = try EnhancementResponseValidator.validate(rawText: response.text, request: request)
        } catch {
            throw .contract(error)
        }
        return EnhancementResult(
            enhancedPrompt: validated.enhancedPrompt,
            report: validated.report,
            processor: .ai(providerID: provider.info.id, providerName: provider.info.displayName, model: response.model),
            mode: request.mode,
            preservation: validated.preservation,
            warnings: validated.warnings
        )
    }
}
