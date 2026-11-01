import SwiftUI
import RePrompterCore

/// The main window: sidebar navigation and the selected destination.
public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            DetailView()
                .background(Theme.background)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) { model.alert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .sheet(isPresented: $model.isShowingProviderDisclosure, onDismiss: {
            // Dismissing without a choice cancels the pending request.
            if model.isShowingProviderDisclosure == false { model.acknowledgeDisclosure(proceed: false) }
        }) {
            ProviderDisclosureSheet()
        }
        .overlay(alignment: .bottom) {
            if let message = model.transientMessage {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderStrong))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.transientMessage)
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let warning = model.storageWarning {
                StorageWarningBanner(message: warning)
            }
            switch model.selection ?? .workspace {
            case .workspace: WorkspaceView()
            case .history: LibraryView(scope: .all)
            case .saved: LibraryView(scope: .saved)
            case .templates: TemplatesView()
            case .settings: SettingsView().frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
    }
}

struct StorageWarningBanner: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(message).font(.callout).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Dismiss") { model.storageWarning = nil }
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Theme.warning.opacity(0.12))
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                Button {
                    model.newPrompt()
                } label: {
                    Label("New Prompt", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Start a new prompt (⌘N)")

                row(.workspace)
            }
            Section("Library") {
                row(.history, count: model.historyCount)
                row(.saved, count: model.savedCount)
                row(.templates)
            }
            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                HCGLogoView(height: 22)
                Text("\(AppInfo.shortName) \(AppInfo.version)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .accessibilityElement(children: .combine)
        }
    }

    private func row(_ item: SidebarItem, count: Int? = nil) -> some View {
        Label(item.title, systemImage: item.symbolName)
            .badge(count ?? 0)
            .tag(item)
    }
}

/// Explicit disclosure shown before the first prompt is sent to an external provider.
struct ProviderDisclosureSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accentGradient)
                Text("Send this prompt to an external AI provider?")
                    .font(.title3.weight(.semibold))
            }
            Text("""
            AI enhancement sends the text of your prompt (and any custom style instructions) over HTTPS to \
            \(AnthropicDisplay.name) at \(model.providerHost), using your own API key. The provider processes it \
            under the terms of your Anthropic account.
            """)
            .fixedSize(horizontal: false, vertical: true)
            Text("""
            Nothing is sent unless you choose Enhance with the AI provider selected. History stays on this Mac. \
            Local Formatting (no AI) never sends anything.
            """)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", role: .cancel) { model.acknowledgeDisclosure(proceed: false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use Local Formatting") { model.acknowledgeDisclosure(proceed: false, useLocalInstead: true) }
                Button("Send and Don’t Ask Again") { model.acknowledgeDisclosure(proceed: true) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 520)
    }
}

enum AnthropicDisplay {
    static let name = "Anthropic"
}
