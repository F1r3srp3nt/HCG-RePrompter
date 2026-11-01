import Foundation
import RePrompterCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reasoning effort sent to the Anthropic Messages API (`output_config.effort`).
public enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Omit the parameter and use the model's default.
    case modelDefault
    case low
    case medium
    case high

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .modelDefault: "Model default"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// User-editable configuration for the Anthropic provider. Contains no secrets.
public struct AnthropicConfiguration: Codable, Sendable, Equatable {
    public static let providerID = "anthropic"
    public static let displayName = "Anthropic Claude"
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com")!
    public static let defaultModel = "claude-opus-5-5"
    public static let suggestedModels = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
    public static let apiVersion = "2026-10-21"
    /// Keychain account name for the API key.
    public static let credentialAccount = "anthropic-api-key"
    /// Models that accept the server-side refusal fallback (`fallbacks: "default"`).
    static let serverFallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"]
    static let serverFallbackBeta = "server-side-fallback-2026-07-01"

    public var baseURL: URL
    public var model: String
    public var effort: ReasoningEffort
    public var maxOutputTokens: Int
    public var requestTimeout: Double
    public var useServerSideFallback: Bool

    public init(
        baseURL: URL = AnthropicConfiguration.defaultBaseURL,
        model: String = AnthropicConfiguration.defaultModel,
        effort: ReasoningEffort = .medium,
        maxOutputTokens: Int = 16_000,
        requestTimeout: Double = 180,
        useServerSideFallback: Bool = true
    ) {
        self.baseURL = baseURL
        self.model = model
        self.effort = effort
        self.maxOutputTokens = maxOutputTokens
        self.requestTimeout = requestTimeout
        self.useServerSideFallback = useServerSideFallback
    }

    public static let `default` = AnthropicConfiguration()

    enum CodingKeys: String, CodingKey {
        case baseURL, model, effort, maxOutputTokens, requestTimeout, useServerSideFallback
    }

    /// Tolerant decoding: missing or unknown values fall back to defaults so
    /// older or newer settings files never prevent the app from starting.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AnthropicConfiguration.default
        baseURL = (try? container.decodeIfPresent(URL.self, forKey: .baseURL)) ?? defaults.baseURL
        model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? defaults.model
        effort = (try? container.decodeIfPresent(ReasoningEffort.self, forKey: .effort)) ?? defaults.effort
        maxOutputTokens = (try? container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)) ?? defaults.maxOutputTokens
        requestTimeout = (try? container.decodeIfPresent(Double.self, forKey: .requestTimeout)) ?? defaults.requestTimeout
        useServerSideFallback = (try? container.decodeIfPresent(Bool.self, forKey: .useServerSideFallback)) ?? defaults.useServerSideFallback
    }

    public static let tokenRange = 1_024...32_000
    public static let timeoutRange = 15.0...600.0

    public func validate() throws(ProviderError) {
        guard baseURL.scheme?.lowercased() == "https" else { throw .insecureEndpoint }
        guard let host = baseURL.host, !host.isEmpty else { throw .invalidConfiguration("The base URL has no host.") }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw .invalidConfiguration("Choose a model.") }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:@/"))
        guard trimmedModel.unicodeScalars.allSatisfy(allowed.contains), trimmedModel.count <= 128 else {
            throw .invalidConfiguration("The model name contains invalid characters.")
        }
        guard Self.tokenRange.contains(maxOutputTokens) else {
            throw .invalidConfiguration("The output limit must be between \(Self.tokenRange.lowerBound) and \(Self.tokenRange.upperBound) tokens.")
        }
        guard Self.timeoutRange.contains(requestTimeout) else {
            throw .invalidConfiguration("The timeout must be between 15 and 600 seconds.")
        }
    }

    var sendsServerFallback: Bool {
        useServerSideFallback && Self.serverFallbackModels.contains(model)
    }
}

/// Anthropic Messages API adapter (raw HTTPS; Swift has no official SDK).
///
/// Requests ask for structured JSON output (`output_config.format`) matching
/// `EnhancementContract.responseSchema`; the response text is validated
/// again by `EnhancementResponseValidator`.
public struct AnthropicProvider: AIProvider, CustomReflectable {
    /// Reflection shows only the non-secret configuration.
    public var customMirror: Mirror { Mirror(self, children: ["configuration": configuration], displayStyle: .struct) }

    public let configuration: AnthropicConfiguration
    private let credentials: any CredentialStore
    private let transport: any HTTPTransport

    public init(
        configuration: AnthropicConfiguration,
        credentials: any CredentialStore,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.transport = transport
    }

    public var info: ProviderInfo {
        ProviderInfo(
            id: AnthropicConfiguration.providerID,
            displayName: AnthropicConfiguration.displayName,
            endpointHost: configuration.baseURL.host ?? "api.anthropic.com"
        )
    }

    // MARK: Requests

    struct MessagesRequestBody: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
        }
        struct OutputConfig: Encodable {
            struct Format: Encodable {
                var type = "json_schema"
                var schema: JSONValue
            }
            var effort: String?
            var format: Format
        }

        var model: String
        var max_tokens: Int
        var system: String
        var messages: [Message]
        var output_config: OutputConfig
        var fallbacks: String?
    }

    func loadKey() throws -> RedactedSecret {
        let stored: String?
        do {
            stored = try credentials.secret(for: AnthropicConfiguration.credentialAccount)
        } catch {
            throw ProviderError.credentialStore((error as? LocalizedError)?.errorDescription ?? "Unknown error")
        }
        guard let key = stored, !key.isEmpty else { throw ProviderError.missingAPIKey }
        return RedactedSecret(key)
    }

    func makeURLRequest(path: String, key: RedactedSecret, method: String, body: Data?, beta: String?) -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AnthropicConfiguration.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(key.value, forHTTPHeaderField: "x-api-key")
        request.setValue("\(AppInfo.shortName)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let beta { request.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = body
        return request
    }

    /// Builds the HTTP request for a completion. Exposed for tests.
    public func buildMessagesRequest(_ request: ProviderRequest) throws -> URLRequest {
        try configuration.validate()
        let key = try loadKey()
        let body = MessagesRequestBody(
            model: configuration.model,
            max_tokens: configuration.maxOutputTokens,
            system: request.system,
            messages: [.init(role: "user", content: request.userMessage)],
            output_config: .init(
                effort: configuration.effort == .modelDefault ? nil : configuration.effort.rawValue,
                format: .init(schema: request.responseSchema)
            ),
            fallbacks: configuration.sendsServerFallback ? "default" : nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(body)
        return makeURLRequest(
            path: "v1/messages",
            key: key,
            method: "POST",
            body: data,
            beta: configuration.sendsServerFallback ? AnthropicConfiguration.serverFallbackBeta : nil
        )
    }

    public func complete(_ request: ProviderRequest) async throws -> ProviderResponse {
        let urlRequest = try buildMessagesRequest(request)
        let (data, response) = try await send(urlRequest)
        try Self.checkStatus(response, data: data, model: configuration.model)
        return try Self.parseMessage(data, requestID: response.value(forHTTPHeaderField: "request-id"))
    }

    public func validateConnection() async throws -> ConnectionCheckResult {
        try configuration.validate()
        let key = try loadKey()
        let request = makeURLRequest(path: "v1/models/\(configuration.model)", key: key, method: "GET", body: nil, beta: nil)
        let (data, response) = try await send(request)
        try Self.checkStatus(response, data: data, model: configuration.model)
        struct ModelInfo: Decodable { var id: String; var display_name: String? }
        let info = try? JSONDecoder().decode(ModelInfo.self, from: data)
        return ConnectionCheckResult(model: info?.id ?? configuration.model, modelDisplayName: info?.display_name)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as ProviderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw ProviderError.timeout
            case .appTransportSecurityRequiresSecureConnection: throw ProviderError.insecureEndpoint
            default: throw ProviderError.network(SecretRedactor.redact(error.localizedDescription))
            }
        } catch {
            throw ProviderError.network(SecretRedactor.redact(error.localizedDescription))
        }
    }

    // MARK: Responses

    struct APIErrorEnvelope: Decodable {
        struct Detail: Decodable {
            var type: String?
            var message: String?
        }
        var error: Detail?
    }

    static func errorMessage(from data: Data) -> String {
        let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let message = decoded?.error?.message ?? ""
        // Never surface anything that could contain a credential, and keep it short.
        return String(SecretRedactor.redact(message).prefix(400))
    }

    static func checkStatus(_ response: HTTPURLResponse, data: Data, model: String) throws {
        let status = response.statusCode
        guard !(200..<300).contains(status) else { return }
        let message = errorMessage(from: data)
        switch status {
        case 400: throw ProviderError.badRequest(message.isEmpty ? "Invalid request." : message)
        case 401: throw ProviderError.authenticationFailed
        case 402: throw ProviderError.billing(message)
        case 403: throw ProviderError.permissionDenied(message)
        case 404: throw ProviderError.modelNotFound(model)
        case 408: throw ProviderError.timeout
        case 413: throw ProviderError.requestTooLarge
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        case 529: throw ProviderError.overloaded
        case 500..<600: throw ProviderError.serverError(status: status)
        default: throw ProviderError.unexpectedStatus(status)
        }
    }

    struct MessageResponse: Decodable {
        struct Block: Decodable {
            var type: String
            var text: String?
        }
        struct StopDetails: Decodable {
            var category: String?
        }
        var model: String?
        var content: [Block]?
        var stop_reason: String?
        var stop_details: StopDetails?
    }

    static func parseMessage(_ data: Data, requestID: String?) throws -> ProviderResponse {
        let message: MessageResponse
        do {
            message = try JSONDecoder().decode(MessageResponse.self, from: data)
        } catch {
            throw ProviderError.malformedResponse("The response body could not be decoded.")
        }
        switch message.stop_reason {
        case "refusal":
            throw ProviderError.refused(category: message.stop_details?.category)
        case "max_tokens":
            throw ProviderError.truncated
        default:
            break
        }
        let text = (message.content ?? [])
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.malformedResponse("The response contained no text.")
        }
        return ProviderResponse(text: text, model: message.model ?? "unknown", requestID: requestID)
    }
}
