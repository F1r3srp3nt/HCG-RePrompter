import Foundation
import Testing
@testable import RePrompterCore
@testable import RePrompterProviders
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Mocks

/// Records requests and replays canned HTTP responses. Never touches the network.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Canned {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var queue: [Result<Canned, Error>]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Result<Canned, Error>]) { queue = responses }
    convenience init(status: Int, body: String, headers: [String: String] = [:]) {
        self.init([.success(Canned(status: status, body: body, headers: headers))])
    }

    var lastRequest: URLRequest? { lock.withLock { requests.last } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: Result<Canned, Error> = lock.withLock {
            requests.append(request)
            return queue.count > 1 ? queue.removeFirst() : queue[0]
        }
        let canned = try next.get()
        let response = HTTPURLResponse(url: request.url!, statusCode: canned.status, httpVersion: "HTTP/1.1", headerFields: canned.headers)!
        return (Data(canned.body.utf8), response)
    }
}

/// A scripted AI provider for service-level tests.
final class MockProvider: AIProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Result<String, ProviderError>]
    private(set) var calls = 0
    let delay: Double

    init(_ script: [Result<String, ProviderError>], delay: Double = 0) {
        self.script = script
        self.delay = delay
    }

    var info: ProviderInfo { ProviderInfo(id: "mock", displayName: "Mock AI", endpointHost: "mock.invalid") }

    func complete(_ request: ProviderRequest) async throws -> ProviderResponse {
        let next: Result<String, ProviderError> = lock.withLock {
            calls += 1
            return script.count > 1 ? script.removeFirst() : script[0]
        }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return ProviderResponse(text: try next.get(), model: "mock-model-1")
    }

    func validateConnection() async throws -> ConnectionCheckResult {
        ConnectionCheckResult(model: "mock-model-1", modelDisplayName: "Mock")
    }
}

final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var delays: [Double] = []
    func record(_ seconds: Double) { lock.withLock { delays.append(seconds) } }
}

enum ProviderFixtures {
    static let testKey = "sk-ant-test-0123456789abcdefSECRET"

    static func messageBody(text: String, stop: String = "end_turn", model: String = "claude-opus-5-5") -> String {
        let content: [String: Any] = [
            "id": "msg_1", "type": "message", "role": "assistant", "model": model,
            "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]],
            "stop_reason": stop,
            "usage": ["input_tokens": 10, "output_tokens": 20],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: content), as: UTF8.self)
    }

    static let validContractJSON = ResponseValidatorTests.json()

    static func provider(
        transport: MockTransport,
        configuration: AnthropicConfiguration = .default,
        key: String? = testKey
    ) -> AnthropicProvider {
        let store = InMemoryCredentialStore(key.map { [AnthropicConfiguration.credentialAccount: $0] } ?? [:])
        return AnthropicProvider(configuration: configuration, credentials: store, transport: transport)
    }

    static let request = ProviderRequest(system: "sys", userMessage: "user", responseSchema: EnhancementContract.responseSchema)
}

func jsonObject(_ data: Data?) throws -> [String: Any] {
    let body = try #require(data)
    let object = try JSONSerialization.jsonObject(with: body)
    return try #require(object as? [String: Any])
}

// MARK: - Anthropic adapter

@Suite("Anthropic provider")
struct AnthropicProviderTests {
    @Test func buildsDocumentedMessagesRequest() async throws {
        let transport = MockTransport(status: 200, body: ProviderFixtures.messageBody(text: ProviderFixtures.validContractJSON))
        let provider = ProviderFixtures.provider(transport: transport)
        _ = try await provider.complete(ProviderFixtures.request)

        let request = try #require(transport.lastRequest)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == ProviderFixtures.testKey)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let body = try jsonObject(request.httpBody)
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["max_tokens"] as? Int == 16_000)
        #expect(body["system"] as? String == "sys")
        #expect(body["fallbacks"] as? String == "default")
        // Sampling parameters are rejected by API version 2026-10-21 and must never be sent.
        #expect(body["temperature"] == nil && body["top_p"] == nil && body["top_k"] == nil)
        let outputConfig = try #require(body["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] as? String == "medium")
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect((format["schema"] as? [String: Any])?["additionalProperties"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
    }

    @Test func omitsFallbackAndEffortWhenNotApplicable() throws {
        let configuration = AnthropicConfiguration(model: "claude-haiku-5-5", effort: .modelDefault)
        let provider = ProviderFixtures.provider(transport: MockTransport(status: 200, body: "{}"), configuration: configuration)
        let request = try provider.buildMessagesRequest(ProviderFixtures.request)
        let body = try jsonObject(request.httpBody)
        #expect(body["fallbacks"] == nil)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let outputConfig = try #require(body["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] == nil)
    }

    @Test func parsesTextBlocksAndSkipsThinking() async throws {
        let transport = MockTransport(status: 200, body: ProviderFixtures.messageBody(text: "{\"a\":1}", model: "claude-sonnet-5-5"), headers: ["request-id": "req_123"])
        let response = try await ProviderFixtures.provider(transport: transport).complete(ProviderFixtures.request)
        #expect(response.text == "{\"a\":1}")
        #expect(response.model == "claude-sonnet-5-5")
        #expect(response.requestID == "req_123")
    }

    @Test func missingKeyIsReportedWithoutNetworkCall() async {
        let transport = MockTransport(status: 200, body: "{}")
        await #expect(throws: ProviderError.missingAPIKey) {
            try await ProviderFixtures.provider(transport: transport, key: nil).complete(ProviderFixtures.request)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func insecureEndpointIsRejected() async {
        let transport = MockTransport(status: 200, body: "{}")
        let configuration = AnthropicConfiguration(baseURL: URL(string: "http://api.anthropic.com")!)
        await #expect(throws: ProviderError.insecureEndpoint) {
            try await ProviderFixtures.provider(transport: transport, configuration: configuration).complete(ProviderFixtures.request)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func configurationValidation() {
        #expect(throws: ProviderError.invalidConfiguration("Choose a model.")) {
            try AnthropicConfiguration(model: "  ").validate()
        }
        #expect(throws: ProviderError.invalidConfiguration("The model name contains invalid characters.")) {
            try AnthropicConfiguration(model: "claude opus; rm -rf").validate()
        }
        #expect(throws: (any Error).self) { try AnthropicConfiguration(maxOutputTokens: 10).validate() }
        #expect(throws: (any Error).self) { try AnthropicConfiguration(requestTimeout: 1).validate() }
        #expect(throws: Never.self) { try AnthropicConfiguration.default.validate() }
    }

    @Test(arguments: [
        (401, ProviderError.authenticationFailed),
        (404, ProviderError.modelNotFound("claude-opus-5-5")),
        (413, ProviderError.requestTooLarge),
        (529, ProviderError.overloaded),
        (500, ProviderError.serverError(status: 500)),
        (503, ProviderError.serverError(status: 503)),
        (418, ProviderError.unexpectedStatus(418)),
    ])
    func providerFailuresMapToTypedErrors(status: Int, expected: ProviderError) async {
        let body = "{\"type\":\"error\",\"error\":{\"type\":\"x\",\"message\":\"m\"}}"
        let provider = ProviderFixtures.provider(transport: MockTransport(status: status, body: body))
        await #expect(throws: expected) { try await provider.complete(ProviderFixtures.request) }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let provider = ProviderFixtures.provider(transport: MockTransport(status: 429, body: "{}", headers: ["retry-after": "7"]))
        await #expect(throws: ProviderError.rateLimited(retryAfter: 7)) { try await provider.complete(ProviderFixtures.request) }
    }

    @Test func badRequestMessageIsRedacted() async {
        let body = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"bad key sk-ant-abcdefghijklmnop used\"}}"
        let provider = ProviderFixtures.provider(transport: MockTransport(status: 400, body: body))
        do {
            _ = try await provider.complete(ProviderFixtures.request)
            Issue.record("Expected an error")
        } catch let error as ProviderError {
            guard case let .badRequest(message) = error else { Issue.record("Unexpected \(error)"); return }
            #expect(!message.contains("abcdefghijklmnop"))
            #expect(message.contains(SecretRedactor.placeholder))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func refusalAndTruncationAreErrors() async {
        let refusal = "{\"model\":\"m\",\"content\":[],\"stop_reason\":\"refusal\",\"stop_details\":{\"type\":\"refusal\",\"category\":\"cyber\"}}"
        await #expect(throws: ProviderError.refused(category: "cyber")) {
            try await ProviderFixtures.provider(transport: MockTransport(status: 200, body: refusal)).complete(ProviderFixtures.request)
        }
        let truncated = ProviderFixtures.messageBody(text: "{\"enhanced", stop: "max_tokens")
        await #expect(throws: ProviderError.truncated) {
            try await ProviderFixtures.provider(transport: MockTransport(status: 200, body: truncated)).complete(ProviderFixtures.request)
        }
    }

    @Test(arguments: ["not json", "{\"content\": 5}", "{\"content\": []}"])
    func malformedBodiesAreErrors(_ body: String) async {
        let provider = ProviderFixtures.provider(transport: MockTransport(status: 200, body: body))
        await #expect(throws: ProviderError.self) { try await provider.complete(ProviderFixtures.request) }
    }

    @Test func networkErrorsAreMapped() async {
        let timeout = MockTransport([.failure(URLError(.timedOut))])
        await #expect(throws: ProviderError.timeout) {
            try await ProviderFixtures.provider(transport: timeout).complete(ProviderFixtures.request)
        }
        let cancelled = MockTransport([.failure(URLError(.cancelled))])
        await #expect(throws: CancellationError.self) {
            try await ProviderFixtures.provider(transport: cancelled).complete(ProviderFixtures.request)
        }
    }

    @Test func connectionValidationUsesModelsEndpoint() async throws {
        let transport = MockTransport(status: 200, body: "{\"id\":\"claude-opus-5-5\",\"display_name\":\"Claude Opus 5.5\"}")
        let result = try await ProviderFixtures.provider(transport: transport).validateConnection()
        #expect(result.modelDisplayName == "Claude Opus 5.5")
        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models/claude-opus-5-5")
        #expect(request.httpBody == nil)
    }

    @Test func configurationDecodingIsTolerant() throws {
        let decoded = try JSONDecoder().decode(AnthropicConfiguration.self, from: Data("{\"model\":\"claude-sonnet-5-5\",\"effort\":\"bogus\"}".utf8))
        #expect(decoded.model == "claude-sonnet-5-5")
        #expect(decoded.effort == AnthropicConfiguration.default.effort)
        #expect(decoded.baseURL == AnthropicConfiguration.defaultBaseURL)
    }
}

// MARK: - Enhancement service

@Suite("Enhancement service")
struct EnhancementServiceTests {
    let request = EnhancementRequest(originalPrompt: "write haiku about 5 cats", mode: .quickImprove)

    func service(_ provider: MockProvider?, recorder: SleepRecorder = SleepRecorder(), policy: RetryPolicy = .standard) -> EnhancementService {
        EnhancementService(provider: provider, retryPolicy: policy, sleeper: { recorder.record($0) })
    }

    @Test func aiEnhancementProducesValidatedResult() async throws {
        let provider = MockProvider([.success(ProviderFixtures.validContractJSON)])
        let result = try await service(provider).enhance(request, processor: .aiProvider)
        #expect(result.processor == .ai(providerID: "mock", providerName: "Mock AI", model: "mock-model-1"))
        #expect(result.enhancedPrompt.hasPrefix("Rewritten"))
        #expect(result.report.structuralChanges == ["Clarified"])
        #expect(provider.calls == 1)
    }

    @Test func missingProviderFailsInsteadOfFakingAI() async {
        await #expect(throws: EnhancementError.provider(.notConfigured)) {
            try await service(nil).enhance(request, processor: .aiProvider)
        }
    }

    @Test func localFormatterWorksWithoutProviderAndIsLabelled() async throws {
        let result = try await service(nil).enhance(request, processor: .localFormatter)
        #expect(result.processor == .localFormatter)
        #expect(!result.processor.isAI)
    }

    @Test func emptyInputNeverReachesProvider() async {
        let provider = MockProvider([.success(ProviderFixtures.validContractJSON)])
        await #expect(throws: EnhancementError.input(.emptyPrompt)) {
            try await service(provider).enhance(EnhancementRequest(originalPrompt: "  ", mode: .structured), processor: .aiProvider)
        }
        #expect(provider.calls == 0)
    }

    @Test func transientFailuresAreRetriedWithBackoff() async throws {
        let provider = MockProvider([.failure(.overloaded), .failure(.serverError(status: 500)), .success(ProviderFixtures.validContractJSON)])
        let recorder = SleepRecorder()
        let result = try await service(provider, recorder: recorder).enhance(request, processor: .aiProvider)
        #expect(provider.calls == 3)
        #expect(recorder.delays == [1.5, 3.0])
        #expect(!result.enhancedPrompt.isEmpty)
    }

    @Test func retryAfterIsHonoured() async throws {
        let provider = MockProvider([.failure(.rateLimited(retryAfter: 4)), .success(ProviderFixtures.validContractJSON)])
        let recorder = SleepRecorder()
        _ = try await service(provider, recorder: recorder).enhance(request, processor: .aiProvider)
        #expect(recorder.delays == [4])
    }

    @Test func givesUpAfterMaxAttempts() async {
        let provider = MockProvider([.failure(.overloaded)])
        await #expect(throws: EnhancementError.provider(.overloaded)) {
            try await service(provider).enhance(request, processor: .aiProvider)
        }
        #expect(provider.calls == RetryPolicy.standard.maxAttempts)
    }

    @Test(arguments: [ProviderError.authenticationFailed, .badRequest("x"), .refused(category: nil), .truncated, .modelNotFound("m")])
    func permanentFailuresAreNotRetried(_ error: ProviderError) async {
        let provider = MockProvider([.failure(error)])
        await #expect(throws: EnhancementError.provider(error)) {
            try await service(provider).enhance(request, processor: .aiProvider)
        }
        #expect(provider.calls == 1)
    }

    @Test func longRateLimitIsSurfacedNotAwaited() async {
        let provider = MockProvider([.failure(.rateLimited(retryAfter: 120))])
        let recorder = SleepRecorder()
        await #expect(throws: EnhancementError.provider(.rateLimited(retryAfter: 120))) {
            try await service(provider, recorder: recorder).enhance(request, processor: .aiProvider)
        }
        #expect(recorder.delays.isEmpty)
    }

    @Test func malformedProviderOutputIsAContractError() async {
        let provider = MockProvider([.success("Sure! Here is your improved prompt: ...")])
        await #expect(throws: EnhancementError.contract(.notJSON)) {
            try await service(provider).enhance(request, processor: .aiProvider)
        }
        #expect(EnhancementError.contract(.notJSON).canRetry)
    }

    @Test func cancellationStopsInFlightRequest() async {
        let provider = MockProvider([.success(ProviderFixtures.validContractJSON)], delay: 10)
        let service = EnhancementService(provider: provider)
        let task = Task { try await service.enhance(request, processor: .aiProvider) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 5)
        switch result {
        case .success: Issue.record("Expected cancellation")
        case let .failure(error): #expect(error as? EnhancementError == .cancelled)
        }
    }

    @Test func cancellationDuringRetryWait() async {
        let provider = MockProvider([.failure(.overloaded)])
        let service = EnhancementService(provider: provider, retryPolicy: RetryPolicy(maxAttempts: 5, baseDelay: 30, maxDelay: 30))
        let task = Task { try await service.enhance(request, processor: .aiProvider) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let result = await task.result
        if case let .failure(error) = result {
            #expect(error as? EnhancementError == .cancelled)
        } else {
            Issue.record("Expected cancellation")
        }
        #expect(provider.calls == 1)
    }

    @Test func emitsProgressEvents() async throws {
        final class Events: @unchecked Sendable {
            let lock = NSLock()
            var items: [EnhancementEvent] = []
        }
        let events = Events()
        let provider = MockProvider([.failure(.overloaded), .success(ProviderFixtures.validContractJSON)])
        _ = try await service(provider).enhance(request, processor: .aiProvider) { event in
            events.lock.withLock { events.items.append(event) }
        }
        #expect(events.items.first == .sending(attempt: 1))
        #expect(events.items.contains(.sending(attempt: 2)))
        #expect(events.items.last == .validating)
    }
}

// MARK: - Credentials

@Suite("Sensitive credential handling")
struct CredentialTests {
    @Test func inMemoryStoreRoundTrip() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.secret(for: "a") == nil)
        try store.setSecret("value", for: "a")
        #expect(try store.secret(for: "a") == "value")
        try store.deleteSecret(for: "a")
        #expect(try store.secret(for: "a") == nil)
    }

    @Test func apiKeyNormalization() throws {
        #expect(try APIKeyValidator.normalize("  sk-ant-abc123\n") == "sk-ant-abc123")
        #expect(throws: APIKeyValidator.Problem.empty) { try APIKeyValidator.normalize("   ") }
        #expect(throws: APIKeyValidator.Problem.containsWhitespace) { try APIKeyValidator.normalize("sk-ant abc") }
        #expect(throws: APIKeyValidator.Problem.invalidCharacters) { try APIKeyValidator.normalize("sk-ant-é") }
        #expect(throws: APIKeyValidator.Problem.tooLong) { try APIKeyValidator.normalize(String(repeating: "a", count: 600)) }
    }

    @Test func maskedHintRevealsOnlySuffix() {
        let hint = APIKeyValidator.maskedHint(ProviderFixtures.testKey)
        #expect(hint == "sk-ant-…CRET")
        #expect(!hint.contains("0123456789"))
    }

    @Test func redactorRemovesKeysFromText() {
        let text = "Request failed for key \(ProviderFixtures.testKey) with header Bearer abc.def-ghi and sk-ant- alone"
        let redacted = SecretRedactor.redact(text)
        #expect(!redacted.contains("0123456789"))
        #expect(!redacted.contains("abc.def-ghi"))
        #expect(redacted.contains("sk-ant- alone"))
        #expect(SecretRedactor.redact("custom secret value", knownSecrets: ["secret value"]) == "custom \(SecretRedactor.placeholder)")
    }

    @Test func redactedSecretNeverPrints() {
        let secret = RedactedSecret(ProviderFixtures.testKey)
        #expect("\(secret)" == SecretRedactor.placeholder)
        #expect(String(reflecting: secret) == SecretRedactor.placeholder)
        var dumped = ""
        dump(secret, to: &dumped)
        #expect(!dumped.contains("SECRET"))
        #expect(secret.value == ProviderFixtures.testKey)
    }

    @Test func errorDescriptionsNeverContainTheKey() async {
        let errors: [ProviderError] = [
            .authenticationFailed, .missingAPIKey, .badRequest(SecretRedactor.redact("oops \(ProviderFixtures.testKey)")),
            .network(SecretRedactor.redact("failed \(ProviderFixtures.testKey)")),
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").contains("0123456789abcdef"))
        }
    }

    @Test func providerDescriptionDoesNotExposeKey() {
        let provider = ProviderFixtures.provider(transport: MockTransport(status: 200, body: "{}"))
        var dumped = ""
        dump(provider, to: &dumped)
        #expect(!dumped.contains("0123456789abcdef"))
        #expect(!String(describing: provider).contains("0123456789abcdef"))
    }

    @Test func configurationEncodingContainsNoSecret() throws {
        let data = try JSONEncoder().encode(AnthropicConfiguration.default)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("sk-ant"))
        #expect(!text.lowercased().contains("apikey"))
    }

    #if canImport(Security)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REPROMPTER_KEYCHAIN_TESTS"] == "1"))
    func keychainRoundTrip() throws {
        let store = KeychainCredentialStore(service: "com.hakmicapital.reprompter.tests.\(UUID().uuidString)")
        defer { try? store.deleteSecret(for: "test") }
        #expect(try store.secret(for: "test") == nil)
        try store.setSecret("first", for: "test")
        try store.setSecret("second", for: "test") // update path
        #expect(try store.secret(for: "test") == "second")
        try store.deleteSecret(for: "test")
        #expect(try store.secret(for: "test") == nil)
        try store.deleteSecret(for: "test") // deleting a missing item is not an error
    }
    #endif
}

@Suite("Retry policy")
struct RetryPolicyTests {
    @Test func backoffIsExponentialAndCapped() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 1, maxDelay: 5)
        #expect(policy.delay(afterFailures: 1, error: .overloaded) == 1)
        #expect(policy.delay(afterFailures: 2, error: .overloaded) == 2)
        #expect(policy.delay(afterFailures: 3, error: .overloaded) == 4)
        #expect(policy.delay(afterFailures: 4, error: .overloaded) == 5)
        #expect(policy.delay(afterFailures: 1, error: .authenticationFailed) == nil)
        #expect(RetryPolicy.none.delay(afterFailures: 1, error: .overloaded) == nil)
    }
}
