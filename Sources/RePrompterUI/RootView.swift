import SwiftUI
import RePrompterCore

/// The main window: sidebar navigation and the selected destination.
public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
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
        // Switching away from a prompt with unsaved edits. Dialog actions run
        // before the dialog is dismissed, so the setter only acts when the
        // dialog closes without a choice.
        .confirmationDialog(
            "Save changes to “\(model.effectiveTitle)”?",
            isPresented: Binding(
                get: { model.pendingNavigation != nil },
                set: { if !$0 { model.resolvePendingNavigation(.cancel) } }
            ),
            titleVisibility: .visible
        ) {
            Button("Save") { model.resolvePendingNavigation(.save) }
            Button("Don’t Save", role: .destructive) { model.resolvePendingNavigation(.discard) }
            Button("Cancel", role: .cancel) { model.resolvePendingNavigation(.cancel) }
        } message: {
            Text("This prompt has edits that are not in your library. If you don’t save, they will be lost.")
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
            case .saved: LibraryView(scope: .saved)
            case .history: LibraryView(scope: .all)
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
                    model.requestNewPrompt()
                } label: {
                    Label("New Prompt", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Start a new prompt (⌘N)")

                row(.workspace)
            }
            Section("Prompts") {
                row(.saved, count: model.savedCount)
                row(.history, count: model.historyCount)
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
                Text("\(AppInfo.shortName) \(AppInfo.version) · Offline workspace")
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
