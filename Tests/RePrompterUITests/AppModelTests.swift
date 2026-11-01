import Foundation
import Testing
@testable import RePrompterCore
@testable import RePrompterPersistence
@testable import RePrompterProviders
@testable import RePrompterUI

/// Scripted provider: returns a valid contract response after an optional delay.
final class ScriptedProvider: AIProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    let delay: Double
    let failure: ProviderError?

    init(delay: Double = 0, failure: ProviderError? = nil) {
        self.delay = delay
        self.failure = failure
    }

    var calls: Int { lock.withLock { _calls } }
    var info: ProviderInfo { ProviderInfo(id: "scripted", displayName: "Scripted AI", endpointHost: "scripted.invalid") }

    func complete(_ request: ProviderRequest) async throws -> ProviderResponse {
        lock.withLock { _calls += 1 }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if let failure { throw failure }
        let json = """
        {"enhanced_prompt":"Write a short poem about the sea in 3 stanzas.","objective":"Poem","intended_output":"Poem",
         "explicit_requirements":["about the sea"],"constraints":["3 stanzas"],"structural_changes":["Clarified length"],
         "optional_suggestions":[],"missing_information":[],"assumptions":[],"ambiguities":[]}
        """
        return ProviderResponse(text: json, model: "scripted-1")
    }

    func validateConnection() async throws -> ConnectionCheckResult {
        ConnectionCheckResult(model: "scripted-1", modelDisplayName: "Scripted Model")
    }
}

@MainActor
struct Harness {
    let directory: URL
    let credentials = InMemoryCredentialStore()
    let model: AppModel

    init(provider: ScriptedProvider? = ScriptedProvider(), withKey: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("reprompter-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if withKey { try credentials.setSecret("sk-ant-test-key-1234567890", for: AnthropicConfiguration.credentialAccount) }
        model = AppModel(
            location: StorageLocation(directory: directory),
            credentials: credentials,
            retryPolicy: .none,
            providerFactory: { _, _ in provider }
        )
    }

    func waitUntilIdle(timeout: Double = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while model.isRunning {
            if Date() > deadline { Issue.record("Timed out waiting for enhancement"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@Suite("App workflows")
@MainActor
struct AppModelTests {
    @Test func localEnhancementIsRecordedInHistoryAndPersisted() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.processor = .localFormatter
        model.mode = .structured
        model.originalText = "write a poem about the sea. keep it under 100 words"
        model.enhance()
        try await harness.waitUntilIdle()

        let result = try #require(model.result)
        #expect(result.processor == .localFormatter)
        #expect(model.enhancedText == result.enhancedPrompt)
        #expect(model.reviewStatus == .enhanced)
        #expect(model.library.records.count == 1)

        let reloaded = AppModel(location: StorageLocation(directory: harness.directory), credentials: harness.credentials)
        #expect(reloaded.library.records.first?.originalPrompt == model.originalText)
    }

    @Test func aiWithoutKeyFailsClearlyAndNeverFallsBack() async throws {
        let provider = ScriptedProvider()
        let harness = try Harness(provider: provider, withKey: false)
        defer { harness.cleanUp() }
        let model = harness.model
        model.processor = .aiProvider
        model.originalText = "Summarize this"
        model.enhance()
        try await harness.waitUntilIdle()
        #expect(model.phase == .failed(.provider(.notConfigured)))
        #expect(model.result == nil)
        #expect(provider.calls == 0)
    }

    @Test func disclosureIsShownBeforeFirstExternalRequest() async throws {
        let provider = ScriptedProvider()
        let harness = try Harness(provider: provider)
        defer { harness.cleanUp() }
        let model = harness.model
        model.processor = .aiProvider
        model.originalText = "write a poem about the sea in 3 stanzas"
        model.enhance()
        #expect(model.isShowingProviderDisclosure)
        #expect(provider.calls == 0)

        model.acknowledgeDisclosure(proceed: true)
        try await harness.waitUntilIdle()
        #expect(provider.calls == 1)
        #expect(model.settings.hasAcknowledgedProviderDisclosure)
        #expect(model.result?.processor == .ai(providerID: "scripted", providerName: "Scripted AI", model: "scripted-1"))
    }

    @Test func cancellationLeavesNoResult() async throws {
        let provider = ScriptedProvider(delay: 5)
        let harness = try Harness(provider: provider)
        defer { harness.cleanUp() }
        let model = harness.model
        model.settings.hasAcknowledgedProviderDisclosure = true
        model.processor = .aiProvider
        model.originalText = "Explain gravity"
        model.enhance()
        #expect(model.isRunning)
        try await Task.sleep(nanoseconds: 100_000_000)
        model.cancelEnhancement()
        #expect(!model.isRunning)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(model.result == nil)
        #expect(model.phase == .idle)
    }

    @Test func providerFailureIsSurfaced() async throws {
        let harness = try Harness(provider: ScriptedProvider(failure: .authenticationFailed))
        defer { harness.cleanUp() }
        let model = harness.model
        model.settings.hasAcknowledgedProviderDisclosure = true
        model.processor = .aiProvider
        model.originalText = "Explain gravity"
        model.enhance()
        try await harness.waitUntilIdle()
        #expect(model.phase == .failed(.provider(.authenticationFailed)))
    }

    @Test func acceptRejectAndManualEdits() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.processor = .localFormatter
        model.originalText = "explain recursion to a beginner with one example"
        model.enhance()
        try await harness.waitUntilIdle()

        model.enhancedText += "\nUse Python."
        #expect(model.hasManualEdits)
        model.accept()
        #expect(model.reviewStatus == .accepted)
        #expect(model.currentRecord?.enhancedPrompt?.hasSuffix("Use Python.") == true)

        model.reject()
        #expect(model.reviewStatus == .rejected)
        #expect(!model.hasManualEdits)
        #expect(model.currentRecord?.effectivePrompt == model.originalText)
    }

    @Test func savingDeletingAndClearingHistory() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.originalText = "Saved prompt"
        model.saveToLibrary()
        let savedID = try #require(model.currentRecordID)

        model.newPrompt()
        model.processor = .localFormatter
        model.originalText = "History only prompt about cats"
        model.enhance()
        try await harness.waitUntilIdle()
        #expect(model.historyCount == 2)
        #expect(model.savedCount == 1)

        model.clearHistory()
        #expect(model.library.records.map(\.id) == [savedID])

        model.deleteRecords([savedID])
        #expect(model.library.records.isEmpty)
    }

    @Test func historyCanBeDisabled() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.settings.saveHistory = false
        model.processor = .localFormatter
        model.originalText = "Do not remember this prompt"
        model.enhance()
        try await harness.waitUntilIdle()
        #expect(model.result != nil)
        #expect(model.library.records.isEmpty)
    }

    @Test func apiKeyLivesOnlyInCredentialStore() throws {
        let harness = try Harness(withKey: false)
        defer { harness.cleanUp() }
        let model = harness.model
        #expect(!model.hasAPIKey)
        #expect(throws: APIKeyValidator.Problem.self) { try model.saveAPIKey("   ") }
        try model.saveAPIKey("  sk-ant-api-secret-value-9876\n")
        #expect(model.hasAPIKey)
        #expect(model.apiKeyHint == "sk-ant-…9876")
        #expect(try harness.credentials.secret(for: AnthropicConfiguration.credentialAccount) == "sk-ant-api-secret-value-9876")

        model.settings.defaultMode = .developer // forces a settings write
        let files = try FileManager.default.contentsOfDirectory(at: harness.directory, includingPropertiesForKeys: nil)
        for file in files {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            #expect(!text.contains("secret-value"), "\(file.lastPathComponent) contains the key")
        }

        model.removeAPIKey()
        #expect(!model.hasAPIKey)
    }

    @Test func templatesAndOpeningRecords() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.model
        let template = try #require(BuiltInTemplates.all.first)
        model.useTemplate(template)
        #expect(model.originalText == template.body)
        #expect(model.mode == template.suggestedMode)

        model.saveToLibrary()
        let record = try #require(model.currentRecord)
        model.newPrompt()
        #expect(model.originalText.isEmpty)
        model.open(record)
        #expect(model.originalText == template.body)
        #expect(model.selection == .workspace)
    }
}
