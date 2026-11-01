import Foundation
import Observation
import RePrompterCore
import RePrompterPersistence
import RePrompterProviders

/// Top-level navigation destinations.
public enum SidebarItem: String, Hashable, Identifiable, CaseIterable, Sendable {
    case workspace
    case history
    case saved
    case templates
    case settings

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .history: "History"
        case .saved: "Saved Prompts"
        case .templates: "Templates"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .workspace: "rectangle.and.pencil.and.ellipsis"
        case .history: "clock.arrow.circlepath"
        case .saved: "bookmark"
        case .templates: "doc.on.doc"
        case .settings: "gearshape"
        }
    }
}

/// Output tabs of the workspace.
public enum OutputTab: String, CaseIterable, Identifiable, Sendable {
    case enhanced
    case compare
    case changes

    public var id: String { rawValue }
    var title: String {
        switch self {
        case .enhanced: "Enhanced"
        case .compare: "Compare"
        case .changes: "Changes"
        }
    }
}

/// The state of the current enhancement.
public enum EnhancementPhase: Equatable, Sendable {
    case idle
    case running(status: String)
    case failed(EnhancementError)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// A user-facing alert.
public struct AppAlert: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    public var message: String
}

/// Result of the most recent provider connection test.
public enum ConnectionStatus: Equatable, Sendable {
    case unknown
    case checking
    case connected(String)
    case failed(String)
}

/// Creates the AI provider for the current settings, or nil when none can be
/// used. Injected so tests can supply mock providers.
public typealias ProviderFactory = @MainActor (AppSettings, any CredentialStore) -> (any AIProvider)?

/// Application state shared by all windows. All mutations happen on the
/// main actor; provider calls run concurrently and report back here.
@MainActor
@Observable
public final class AppModel {
    // MARK: Dependencies

    let location: StorageLocation?
    private let libraryStore: JSONFileStore<PromptLibrary>?
    private let templateStore: JSONFileStore<TemplateLibrary>?
    private let settingsStore: JSONFileStore<AppSettings>?
    let credentials: any CredentialStore
    private let providerFactory: ProviderFactory
    let retryPolicy: RetryPolicy

    // MARK: Persistent state

    public var settings: AppSettings {
        didSet { if settings != oldValue { persistSettings() } }
    }
    public internal(set) var library: PromptLibrary
    public internal(set) var templates: TemplateLibrary

    // MARK: Navigation & app-wide UI state

    public var selection: SidebarItem? = .workspace
    public var alert: AppAlert?
    public var transientMessage: String?
    public var storageWarning: String?
    public var isShowingProviderDisclosure = false
    /// Incremented to ask the library view to focus its search field.
    public var searchFocusRequest = 0
    /// Set when search was requested before the library view appeared.
    public var pendingSearchFocus = false
    public var librarySearchText = ""

    // MARK: Credentials

    public internal(set) var hasAPIKey = false
    public internal(set) var apiKeyHint: String?
    public var connectionStatus: ConnectionStatus = .unknown

    // MARK: Workspace

    public var title = ""
    public var originalText = "" {
        didSet { if originalText != oldValue, case .failed = phase { phase = .idle } }
    }
    public var mode: EnhancementMode
    public var customInstructions = ""
    public var processor: ProcessorChoice
    public internal(set) var phase: EnhancementPhase = .idle
    public internal(set) var result: EnhancementResult?
    /// The original text the current result was produced from.
    public internal(set) var resultSourceText: String?
    public var enhancedText = ""
    public internal(set) var reviewStatus: PromptRecord.ReviewStatus = .draft
    public internal(set) var currentRecordID: UUID?
    public var outputTab: OutputTab = .enhanced

    @ObservationIgnored var enhancementTask: Task<Void, Never>?
    @ObservationIgnored var enhancementToken: UUID?
    @ObservationIgnored var pendingEnhanceAfterDisclosure = false
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var analysisCache: (text: String, mode: EnhancementMode, analysis: PromptAnalysis)?

    // MARK: Init

    public init(
        location: StorageLocation?,
        credentials: any CredentialStore,
        retryPolicy: RetryPolicy = .standard,
        providerFactory: ProviderFactory? = nil
    ) {
        self.location = location
        self.credentials = credentials
        self.providerFactory = providerFactory ?? { settings, credentials in
            AppModel.makeDefaultProvider(settings: settings, credentials: credentials)
        }
        self.retryPolicy = retryPolicy
        let libraryStore = location.map { JSONFileStore<PromptLibrary>(url: $0.libraryURL) }
        let templateStore = location.map { JSONFileStore<TemplateLibrary>(url: $0.templatesURL) }
        let settingsStore = location.map { JSONFileStore<AppSettings>(url: $0.settingsURL) }
        self.libraryStore = libraryStore
        self.templateStore = templateStore
        self.settingsStore = settingsStore

        var warnings: [String] = []
        func load<T>(_ store: JSONFileStore<T>?, fallback: T, name: String) -> T {
            guard let store else { return fallback }
            let (value, recovered) = store.loadOrRecover(fallback: fallback)
            if let recovered {
                warnings.append("Your \(name) file could not be read and was moved to “\(recovered.lastPathComponent)”. A new one was started.")
            }
            return value
        }
        let loadedSettings = load(settingsStore, fallback: AppSettings.default, name: "settings")
        settings = loadedSettings
        library = load(libraryStore, fallback: PromptLibrary(), name: "prompt library")
        templates = load(templateStore, fallback: TemplateLibrary(), name: "templates")
        mode = loadedSettings.defaultMode
        processor = loadedSettings.defaultProcessor
        if location == nil {
            warnings.append("The application data folder is unavailable. Prompts will not be saved this session.")
        }
        storageWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        refreshCredentialState()
    }

    /// The production configuration: Application Support storage and the Keychain.
    public static func live() -> AppModel {
        #if canImport(Security)
        let credentials: any CredentialStore = KeychainCredentialStore()
        #else
        let credentials: any CredentialStore = InMemoryCredentialStore()
        #endif
        return AppModel(location: try? StorageLocation.applicationSupport(), credentials: credentials)
    }

    public static func makeDefaultProvider(settings: AppSettings, credentials: any CredentialStore) -> (any AIProvider)? {
        AnthropicProvider(configuration: settings.anthropic, credentials: credentials)
    }

    // MARK: Persistence

    func persistLibrary() {
        guard let libraryStore else { return }
        do {
            try libraryStore.save(library)
        } catch {
            storageWarning = (error as? LocalizedError)?.errorDescription ?? "Could not save the prompt library."
        }
    }

    func persistTemplates() {
        guard let templateStore else { return }
        do {
            try templateStore.save(templates)
        } catch {
            storageWarning = (error as? LocalizedError)?.errorDescription ?? "Could not save templates."
        }
    }

    private func persistSettings() {
        guard let settingsStore else { return }
        do {
            try settingsStore.save(settings)
        } catch {
            storageWarning = (error as? LocalizedError)?.errorDescription ?? "Could not save settings."
        }
    }

    // MARK: Messages

    func showMessage(_ message: String) {
        transientMessage = message
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.transientMessage = nil
        }
    }

    func showAlert(_ title: String, _ message: String) {
        alert = AppAlert(title: title, message: message)
    }

    // MARK: Credentials

    func refreshCredentialState() {
        do {
            let key = try credentials.secret(for: AnthropicConfiguration.credentialAccount)
            hasAPIKey = !(key ?? "").isEmpty
            apiKeyHint = key.map(APIKeyValidator.maskedHint)
        } catch {
            hasAPIKey = false
            apiKeyHint = nil
        }
    }

    /// Validates and stores an API key in the Keychain. The key is not kept in memory.
    public func saveAPIKey(_ input: String) throws {
        let key = try APIKeyValidator.normalize(input)
        try credentials.setSecret(key, for: AnthropicConfiguration.credentialAccount)
        refreshCredentialState()
        connectionStatus = .unknown
        showMessage("API key saved to the Keychain")
    }

    public func removeAPIKey() {
        do {
            try credentials.deleteSecret(for: AnthropicConfiguration.credentialAccount)
            refreshCredentialState()
            connectionStatus = .unknown
            showMessage("API key removed")
        } catch {
            showAlert("Could Not Remove Key", (error as? LocalizedError)?.errorDescription ?? "Keychain error.")
        }
    }

    /// Checks the key and model without sending any prompt text.
    public func testConnection() async {
        guard hasAPIKey else {
            connectionStatus = .failed(ProviderError.missingAPIKey.errorDescription ?? "")
            return
        }
        guard let provider = providerFactory(settings, credentials) else {
            connectionStatus = .failed(ProviderError.notConfigured.errorDescription ?? "")
            return
        }
        connectionStatus = .checking
        do {
            let result = try await provider.validateConnection()
            connectionStatus = .connected(result.modelDisplayName ?? result.model)
        } catch let error as ProviderError {
            connectionStatus = .failed(error.errorDescription ?? "Connection failed.")
        } catch {
            connectionStatus = .failed(SecretRedactor.redact(error.localizedDescription))
        }
    }

    // MARK: Provider

    /// Whether AI enhancement can be attempted right now.
    public var isAIProviderReady: Bool { hasAPIKey && (try? settings.anthropic.validate()) != nil }

    var providerHost: String { settings.anthropic.baseURL.host ?? "api.anthropic.com" }

    func makeService() -> EnhancementService {
        let provider = hasAPIKey ? providerFactory(settings, credentials) : nil
        return EnhancementService(provider: provider, retryPolicy: retryPolicy)
    }

    // MARK: Analysis

    /// Deterministic analysis of the current original prompt (memoized).
    public var liveAnalysis: PromptAnalysis {
        if let cache = analysisCache, cache.text == originalText, cache.mode == mode { return cache.analysis }
        let analysis = PromptAnalyzer.analyze(originalText, mode: mode)
        analysisCache = (originalText, mode, analysis)
        return analysis
    }
}
