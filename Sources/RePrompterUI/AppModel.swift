import Foundation
import Observation
import RePrompterCore
import RePrompterPersistence

/// Top-level navigation destinations.
public enum SidebarItem: String, Hashable, Identifiable, CaseIterable, Sendable {
    case workspace
    case saved
    case history
    case templates
    case settings

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .saved: "Library"
        case .history: "All Prompts"
        case .templates: "Templates"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .workspace: "rectangle.and.pencil.and.ellipsis"
        case .saved: "books.vertical"
        case .history: "clock.arrow.circlepath"
        case .templates: "doc.on.doc"
        case .settings: "gearshape"
        }
    }
}

/// The two workspace panes. On narrow windows only one is shown at a time.
public enum WorkspacePane: String, CaseIterable, Identifiable, Sendable {
    case original
    case result

    public var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original"
        case .result: "Result"
        }
    }
}

/// A navigation that would replace the open draft.
public enum PendingNavigation: Equatable, Sendable {
    case newPrompt
    case open(UUID)
    case useTemplate(PromptTemplate)
}

/// The user's answer when switching away from unsaved edits.
public enum UnsavedChangesChoice: Sendable {
    case save
    case discard
    case cancel
}

/// A user-facing alert.
public struct AppAlert: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    public var message: String
}

/// Application state shared by all windows. All mutations happen on the main actor.
///
/// This milestone is an offline prompt workspace: nothing here sends prompt
/// text anywhere, reads credentials, or generates output. Reprompting is
/// routed through `repromptService`, which is `DisconnectedHCGAIService`
/// until the HCG AI service is connected.
@MainActor
@Observable
public final class AppModel {
    // MARK: Dependencies

    let location: StorageLocation?
    private let libraryStore: JSONFileStore<PromptLibrary>?
    private let templateStore: JSONFileStore<TemplateLibrary>?
    private let settingsStore: JSONFileStore<AppSettings>?
    private let sessionStore: JSONFileStore<WorkspaceSession>?
    let repromptService: any HCGRepromptService
    /// How long after the last edit the open draft is written to disk.
    let sessionSaveDelay: Double

    // MARK: Persistent state

    public var settings: AppSettings {
        didSet { if settings != oldValue { persistSettings() } }
    }
    public internal(set) var library: PromptLibrary
    public internal(set) var templates: TemplateLibrary

    /// The prompt open in the workspace. Every edit is autosaved to the
    /// workspace session (not the library) so nothing is lost on quit.
    public internal(set) var draft: PromptDraft {
        didSet { if draft != oldValue { scheduleSessionSave() } }
    }

    // MARK: Navigation & app-wide UI state

    public var selection: SidebarItem? = .workspace
    public var workspacePane: WorkspacePane = .original
    public internal(set) var pendingNavigation: PendingNavigation?
    public var alert: AppAlert?
    public var transientMessage: String?
    public var storageWarning: String?
    /// Incremented to ask the library view to focus its search field.
    public var searchFocusRequest = 0
    /// Set when search was requested before the library view appeared.
    public var pendingSearchFocus = false
    public var librarySearchText = ""

    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var sessionSaveTask: Task<Void, Never>?
    @ObservationIgnored private var analysisCache: (text: String, analysis: PromptAnalysis)?

    // MARK: Init

    public init(
        location: StorageLocation?,
        repromptService: any HCGRepromptService = DisconnectedHCGAIService(),
        sessionSaveDelay: Double = 0.5
    ) {
        self.location = location
        self.repromptService = repromptService
        self.sessionSaveDelay = sessionSaveDelay
        let libraryStore = location.map { JSONFileStore<PromptLibrary>(url: $0.libraryURL) }
        let templateStore = location.map { JSONFileStore<TemplateLibrary>(url: $0.templatesURL) }
        let settingsStore = location.map { JSONFileStore<AppSettings>(url: $0.settingsURL) }
        let sessionStore = location.map { JSONFileStore<WorkspaceSession>(url: $0.sessionURL) }
        self.libraryStore = libraryStore
        self.templateStore = templateStore
        self.settingsStore = settingsStore
        self.sessionStore = sessionStore

        var warnings: [String] = []
        func load<T>(_ store: JSONFileStore<T>?, fallback: T, name: String) -> T {
            guard let store else { return fallback }
            let (value, recovered) = store.loadOrRecover(fallback: fallback)
            if let recovered {
                warnings.append("Your \(name) file could not be read and was moved to “\(recovered.lastPathComponent)”. A new one was started.")
            }
            return value
        }
        settings = load(settingsStore, fallback: AppSettings.default, name: "settings")
        let loadedLibrary = load(libraryStore, fallback: PromptLibrary(), name: "prompt library")
        library = loadedLibrary
        templates = load(templateStore, fallback: TemplateLibrary(), name: "templates")
        let session = load(sessionStore, fallback: WorkspaceSession(draft: .empty), name: "open prompt")
        draft = WorkspaceSession.restoredDraft(from: session, library: loadedLibrary)
        if location == nil {
            warnings.append("The application data folder is unavailable. Prompts will not be saved this session.")
        }
        storageWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    /// The production configuration: `~/Library/Application Support/HCG RePrompter/`.
    public static func live() -> AppModel {
        AppModel(location: try? StorageLocation.applicationSupport())
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

    private func scheduleSessionSave() {
        sessionSaveTask?.cancel()
        let delay = sessionSaveDelay
        sessionSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.flushSession()
        }
    }

    /// Writes the open draft to disk now. Called on quit and after saving.
    public func flushSession() {
        sessionSaveTask?.cancel()
        sessionSaveTask = nil
        guard let sessionStore else { return }
        do {
            try sessionStore.save(WorkspaceSession(draft: draft))
        } catch {
            storageWarning = (error as? LocalizedError)?.errorDescription ?? "Could not save the open prompt."
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

    // MARK: Analysis

    /// Deterministic, local analysis of the open prompt (memoized). Not AI.
    public var liveAnalysis: PromptAnalysis {
        if let cache = analysisCache, cache.text == draft.text { return cache.analysis }
        let analysis = PromptAnalyzer.analyze(draft.text, mode: currentRecord?.mode ?? settings.defaultMode)
        analysisCache = (draft.text, analysis)
        return analysis
    }
}
