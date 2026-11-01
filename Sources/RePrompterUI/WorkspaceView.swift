import SwiftUI
import RePrompterCore
import RePrompterProviders

/// The prompt-engineering workspace: original prompt, controls, output and inspector.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            OriginalPane()
                .frame(minWidth: 340, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            OutputPane()
                .frame(minWidth: 380, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(model.effectiveTitle)
        .inspector(isPresented: $model.settings.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 250, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TextField("Untitled Prompt", text: $model.title)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .help("Prompt name used in history, the library and exports")
                    .accessibilityLabel("Prompt name")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.saveToLibrary()
                } label: {
                    Label("Save", systemImage: "bookmark")
                }
                .help("Save to your library (⌘S)")

                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.displayName) { model.exportWorkspace(as: format) }
                    }
                    Divider()
                    Button("Save Original as Template") { model.saveWorkspaceAsTemplate() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export the prompt")

                Button {
                    model.settings.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector (⌥⌘I)")
            }
        }
    }
}

// MARK: - Original prompt

struct OriginalPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            PaneHeader("Original Prompt", systemImage: "text.alignleft") {
                Text(counts)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            PromptEditor(
                text: $model.originalText,
                placeholder: "Write or paste the prompt you want to improve…",
                accessibilityLabel: "Original prompt"
            )
            EnhancementControls()
        }
        .padding(14)
    }

    private var counts: String {
        let words = model.originalText.split(whereSeparator: { $0.isWhitespace }).count
        return "\(words) words · \(model.originalText.count) characters"
    }
}

struct EnhancementControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Mode", selection: $model.mode) {
                    ForEach(EnhancementMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 230)
                .accessibilityHint("Choose how the prompt is rewritten")

                Text(model.mode.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            if model.mode == .custom {
                TextField(
                    "Describe how you want the prompt rewritten (e.g. “numbered steps, formal tone, under 150 words”)",
                    text: $model.customInstructions,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Custom style instructions")
            }

            HStack(spacing: 10) {
                Picker("Processor", selection: $model.processor) {
                    Text("AI · Claude").tag(ProcessorChoice.aiProvider)
                    Text("Local · no AI").tag(ProcessorChoice.localFormatter)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel("Processor")
                .disabled(model.isRunning)

                Spacer()

                if model.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.cancelEnhancement() }
                        .help("Cancel the request (⌘.)")
                } else {
                    Text("⌘↩")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                    Button {
                        model.enhance()
                    } label: {
                        Label("Enhance", systemImage: "wand.and.stars")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canEnhance)
                    .help("Enhance the prompt (⌘↩)")
                }
            }

            ProcessorNotice()
        }
        .card(padding: 12)
    }
}

/// States clearly where the prompt goes before anything is sent.
struct ProcessorNotice: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.processor {
            case .aiProvider where !model.hasAPIKey:
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warning)
                    Text("No AI provider is configured.")
                    Spacer()
                    Button("Add API Key…") { model.selection = .settings }
                    Button("Use Local") { model.processor = .localFormatter }
                }
            case .aiProvider:
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").foregroundStyle(Theme.accent)
                    Text("Enhancing sends this prompt over HTTPS to \(model.providerHost) (model \(model.settings.anthropic.model)).")
                }
            case .localFormatter:
                HStack(spacing: 6) {
                    Image(systemName: "desktopcomputer").foregroundStyle(Theme.violet)
                    Text("Runs on this Mac. Reorganizes your own words — this is not AI and nothing is sent.")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .buttonStyle(.link)
    }
}

// MARK: - Output

struct OutputPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            PaneHeader("Result", systemImage: "sparkles") {
                Picker("View", selection: $model.outputTab) {
                    ForEach(OutputTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .disabled(!model.hasResult)
            }

            switch model.phase {
            case let .running(status):
                RunningView(status: status)
            case let .failed(error):
                ErrorCard(error: error)
                if model.hasResult { Spacer(minLength: 0) }
            case .idle:
                if model.hasResult {
                    switch model.outputTab {
                    case .enhanced: EnhancedOutputView()
                    case .compare: ComparisonView()
                    case .changes: ChangesView()
                    }
                } else {
                    EmptyStateView(
                        title: "Ready when you are",
                        message: "Write a prompt on the left, pick a mode and press Enhance. RePrompter keeps your intent and explains every change.",
                        systemImage: "wand.and.stars"
                    )
                    .card()
                }
            }
        }
        .padding(14)
    }
}

struct RunningView: View {
    @Environment(AppModel.self) private var model
    let status: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(status)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Cancel") { model.cancelEnhancement() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Enhancing. \(status)")
    }
}

struct ErrorCard: View {
    @Environment(AppModel.self) private var model
    let error: EnhancementError

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.danger)
            Text(error.errorDescription ?? "Something went wrong.")
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack {
                if needsSettings {
                    Button("Open Settings") { model.selection = .settings }
                }
                if isNotConfigured {
                    Button("Use Local Formatting (no AI)") { model.useLocalFormatting() }
                }
                Spacer()
                Button("Dismiss") { model.dismissError() }
                if error.canRetry {
                    Button("Retry") { model.retry() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .card(padding: 16)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch error {
        case .input: "Check your prompt"
        case .provider: "The AI provider could not complete the request"
        case .contract: "The provider’s response could not be used"
        case .cancelled: "Cancelled"
        }
    }

    private var isNotConfigured: Bool {
        error == .provider(.notConfigured) || error == .provider(.missingAPIKey)
    }

    private var needsSettings: Bool {
        guard case let .provider(providerError) = error else { return false }
        switch providerError {
        case .notConfigured, .missingAPIKey, .authenticationFailed, .invalidConfiguration, .insecureEndpoint,
             .modelNotFound, .truncated, .timeout, .credentialStore:
            return true
        default:
            return false
        }
    }
}
