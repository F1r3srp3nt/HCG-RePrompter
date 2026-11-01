import SwiftUI
import RePrompterCore
import RePrompterPersistence
import RePrompterProviders

/// Application settings, shown in the Settings window (⌘,) and the sidebar.
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            ProviderSettingsTab()
                .tabItem { Label("AI Provider", systemImage: "cpu") }
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettingsTab()
                .tabItem { Label("Data & Privacy", systemImage: "lock.shield") }
        }
        .padding(.top, 8)
        .preferredColorScheme(.dark)
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Defaults for new prompts") {
                Picker("Enhancement mode", selection: $model.settings.defaultMode) {
                    ForEach(EnhancementMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Processor", selection: $model.settings.defaultProcessor) {
                    ForEach(ProcessorChoice.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Workspace") {
                Toggle("Show inspector", isOn: $model.settings.showInspector)
            }
        }
        .formStyle(.grouped)
    }
}

struct ProviderSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var keyInput = ""
    @State private var keyError: String?
    @State private var baseURLText = ""
    @State private var baseURLError: String?
    @State private var confirmRemoveKey = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("Provider", value: AnthropicConfiguration.displayName)
                Text("RePrompter sends prompt text to the Anthropic Messages API only when you press Enhance with “AI · Claude” selected. Requests use HTTPS and your own API key.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Provider")
            }

            Section {
                LabeledContent("Status") {
                    if model.hasAPIKey {
                        Label("Stored in Keychain (\(model.apiKeyHint ?? "••••"))", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.success)
                    } else {
                        Label("Not configured", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Theme.warning)
                    }
                }
                SecureField(model.hasAPIKey ? "Replace API key" : "Paste API key", text: $keyInput)
                    .accessibilityLabel("API key")
                    .onSubmit(saveKey)
                if let keyError {
                    Text(keyError).font(.caption).foregroundStyle(Theme.danger)
                }
                HStack {
                    Button("Save to Keychain", action: saveKey)
                        .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.hasAPIKey {
                        Button("Remove Key…", role: .destructive) { confirmRemoveKey = true }
                    }
                    Spacer()
                    Button("Test Connection") { Task { await model.testConnection() } }
                        .disabled(!model.hasAPIKey || model.connectionStatus == .checking)
                }
                connectionStatusView
            } header: {
                Text("API Key")
            } footer: {
                Text("Create a key in your Anthropic Console account. The key is stored only in the macOS Keychain — never in settings files, history, exports or logs. Testing the connection checks the key and model without sending any prompt text.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Section("Model") {
                HStack {
                    TextField("Model ID", text: $model.settings.anthropic.model)
                        .accessibilityLabel("Model identifier")
                    Menu("Suggestions") {
                        ForEach(AnthropicConfiguration.suggestedModels, id: \.self) { id in
                            Button(id) { model.settings.anthropic.model = id }
                        }
                    }
                    .fixedSize()
                }
                Picker("Reasoning effort", selection: $model.settings.anthropic.effort) {
                    ForEach(ReasoningEffort.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper(
                    "Output limit: \(model.settings.anthropic.maxOutputTokens.formatted()) tokens",
                    value: $model.settings.anthropic.maxOutputTokens,
                    in: AnthropicConfiguration.tokenRange,
                    step: 1_024
                )
                Stepper(
                    "Timeout: \(Int(model.settings.anthropic.requestTimeout)) seconds",
                    value: $model.settings.anthropic.requestTimeout,
                    in: AnthropicConfiguration.timeoutRange,
                    step: 15
                )
                Toggle("Retry declined requests on a fallback model (server-side)", isOn: $model.settings.anthropic.useServerSideFallback)
                    .help("Applies to models that support Anthropic’s server-side fallback. The request is handled within the same API call.")
                if let problem = configurationProblem {
                    Text(problem).font(.caption).foregroundStyle(Theme.danger)
                }
            }

            Section {
                HStack {
                    TextField("Base URL", text: $baseURLText)
                        .onSubmit(applyBaseURL)
                        .accessibilityLabel("API base URL")
                    Button("Apply", action: applyBaseURL)
                        .disabled(baseURLText == model.settings.anthropic.baseURL.absoluteString)
                }
                if let baseURLError {
                    Text(baseURLError).font(.caption).foregroundStyle(Theme.danger)
                }
                Button("Restore Provider Defaults") {
                    model.settings.anthropic = .default
                    baseURLText = AnthropicConfiguration.defaultBaseURL.absoluteString
                    baseURLError = nil
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Only HTTPS endpoints are accepted.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear { baseURLText = model.settings.anthropic.baseURL.absoluteString }
        .confirmationDialog("Remove the API key from the Keychain?", isPresented: $confirmRemoveKey, titleVisibility: .visible) {
            Button("Remove Key", role: .destructive) { model.removeAPIKey() }
        } message: {
            Text("AI enhancement will be unavailable until you add a key again.")
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch model.connectionStatus {
        case .unknown:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.caption)
            }
        case let .connected(name):
            Label("Connected — \(name) is available.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.success)
        case let .failed(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var configurationProblem: String? {
        do {
            try model.settings.anthropic.validate()
            return nil
        } catch {
            return error.errorDescription
        }
    }

    private func saveKey() {
        do {
            try model.saveAPIKey(keyInput)
            keyInput = ""
            keyError = nil
        } catch let problem as APIKeyValidator.Problem {
            keyError = problem.errorDescription
        } catch {
            keyError = (error as? LocalizedError)?.errorDescription ?? "The key could not be saved to the Keychain."
        }
    }

    private func applyBaseURL() {
        let trimmed = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host != nil else {
            baseURLError = "Enter a valid HTTPS URL, for example \(AnthropicConfiguration.defaultBaseURL.absoluteString)."
            return
        }
        model.settings.anthropic.baseURL = url
        baseURLError = nil
    }
}

struct PrivacySettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Privacy") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Prompts are treated as confidential.", systemImage: "lock.shield")
                    Text("""
                    • Nothing is sent anywhere unless you press Enhance with the AI provider selected.
                    • Local Formatting never leaves this Mac.
                    • No telemetry or analytics are collected.
                    • History, saved prompts and templates are stored only on this Mac, readable only by your user account.
                    """)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Show the external-provider notice again before the next AI request", isOn: Binding(
                    get: { !model.settings.hasAcknowledgedProviderDisclosure },
                    set: { model.settings.hasAcknowledgedProviderDisclosure = !$0 }
                ))
            }

            Section("History") {
                Toggle("Keep a history of enhanced prompts", isOn: $model.settings.saveHistory)
                Stepper(
                    "Keep up to \(model.settings.historyLimit) unsaved entries",
                    value: $model.settings.historyLimit,
                    in: AppSettings.historyLimitRange,
                    step: 50
                )
                .disabled(!model.settings.saveHistory)
                LabeledContent("Stored prompts", value: "\(model.historyCount) total · \(model.savedCount) saved")
                Button("Clear History…", role: .destructive) { confirmClear = true }
                    .disabled(model.historyCount == model.savedCount)
            }

            Section {
                HStack {
                    Button("Export Backup…") { model.exportBackup() }
                    Button("Import Backup…") { model.importBackup() }
                    Spacer()
                    Button("Show Data Folder") { model.revealDataFolder() }
                        .disabled(model.location == nil)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Backups contain your prompts and templates as JSON. API keys are never included. Imported files are validated and merged without overwriting existing prompts.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear History?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete Unsaved History", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Entries not saved to your library are permanently deleted. Saved prompts are kept.")
        }
    }
}
