import Foundation
import RePrompterCore

/// Describes an AI provider for display and disclosure purposes.
public struct ProviderInfo: Sendable, Equatable {
    public var id: String
    public var displayName: String
    /// Host that receives prompt text, shown in the privacy disclosure.
    public var endpointHost: String

    public init(id: String, displayName: String, endpointHost: String) {
        self.id = id
        self.displayName = displayName
        self.endpointHost = endpointHost
    }
}

/// A provider-neutral completion request built from `EnhancementContract`.
public struct ProviderRequest: Sendable, Equatable {
    public var system: String
    public var userMessage: String
    public var responseSchema: JSONValue

    public init(system: String, userMessage: String, responseSchema: JSONValue) {
        self.system = system
        self.userMessage = userMessage
        self.responseSchema = responseSchema
    }
}

public struct ProviderResponse: Sendable, Equatable {
    /// The model's text output (expected to be JSON per the contract).
    public var text: String
    /// The model that actually produced the response.
    public var model: String
    public var requestID: String?

    public init(text: String, model: String, requestID: String? = nil) {
        self.text = text
        self.model = model
        self.requestID = requestID
    }
}

public struct ConnectionCheckResult: Sendable, Equatable {
    public var model: String
    public var modelDisplayName: String?

    public init(model: String, modelDisplayName: String?) {
        self.model = model
        self.modelDisplayName = modelDisplayName
    }
}

/// An external AI service that can execute an enhancement request.
public protocol AIProvider: Sendable {
    var info: ProviderInfo { get }
    func complete(_ request: ProviderRequest) async throws -> ProviderResponse
    /// Verifies credentials and model availability without generating output.
    func validateConnection() async throws -> ConnectionCheckResult
}

/// Errors from AI providers. Descriptions are user-facing and never contain
/// credentials.
public enum ProviderError: Error, Sendable, Equatable, LocalizedError {
    case notConfigured
    case missingAPIKey
    case invalidConfiguration(String)
    case insecureEndpoint
    case authenticationFailed
    case permissionDenied(String)
    case billing(String)
    case modelNotFound(String)
    case badRequest(String)
    case requestTooLarge
    case rateLimited(retryAfter: Double?)
    case overloaded
    case serverError(status: Int)
    case timeout
    case network(String)
    case refused(category: String?)
    case truncated
    case malformedResponse(String)
    case unexpectedStatus(Int)
    case credentialStore(String)

    /// Whether repeating the identical request may succeed.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .serverError, .timeout, .network: true
        default: false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No AI provider is configured. Add an API key in Settings, or choose Local Formatting (no AI)."
        case .missingAPIKey:
            "No API key is stored for this provider. Add one in Settings → AI Provider."
        case let .invalidConfiguration(detail):
            "The provider configuration is invalid: \(detail)"
        case .insecureEndpoint:
            "Provider requests must use HTTPS."
        case .authenticationFailed:
            "The provider rejected the API key. Check the key in Settings."
        case let .permissionDenied(detail):
            "The API key does not have permission for this request. \(detail)"
        case let .billing(detail):
            "The provider reported a billing problem. \(detail)"
        case let .modelNotFound(model):
            "The model “\(model)” was not found or is not available to this API key."
        case let .badRequest(detail):
            "The provider rejected the request: \(detail)"
        case .requestTooLarge:
            "The prompt is too large for the provider to accept."
        case let .rateLimited(retryAfter):
            if let retryAfter { "The provider is rate limiting requests. Try again in \(Int(retryAfter.rounded(.up))) seconds." }
            else { "The provider is rate limiting requests. Try again shortly." }
        case .overloaded:
            "The provider is temporarily overloaded. Try again shortly."
        case let .serverError(status):
            "The provider had an internal error (HTTP \(status)). Try again shortly."
        case .timeout:
            "The request timed out. Try again, or increase the timeout in Settings."
        case let .network(detail):
            "A network error occurred: \(detail)"
        case let .refused(category):
            if let category { "The provider declined this request (\(category))." }
            else { "The provider declined this request." }
        case .truncated:
            "The provider's response was cut off before it finished. Increase the output limit in Settings or shorten the prompt."
        case let .malformedResponse(detail):
            "The provider returned an unexpected response: \(detail)"
        case let .unexpectedStatus(status):
            "The provider returned an unexpected status (HTTP \(status))."
        case let .credentialStore(detail):
            "The API key could not be read from the Keychain: \(detail)"
        }
    }
}
