import SwiftUI
import RePrompterCore
import RePrompterPersistence

/// Application settings, shown in the Settings window (⌘,) and the sidebar.
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            HCGAISettingsTab()
                .tabItem { Label(HCGAI.serviceName, systemImage: "bolt.horizontal.circle") }
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
            Section("Workspace") {
                Toggle("Show inspector", isOn: $model.settings.showInspector)
                Text("On narrow windows, the Original and Result panes are shown one at a time. Use the switcher above the editor to move between them; your text is kept.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// Read-only status of the future HCG AI integration. No keys, sign-in or endpoints.
struct HCGAISettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section(HCGAI.serviceName) {
                LabeledContent("Status") {
                    Label(model.repromptAvailability.isAvailable ? "Connected" : "Not connected", systemImage: "bolt.horizontal.circle")
                        .foregroundStyle(model.repromptAvailability.isAvailable ? Theme.success : Theme.textSecondary)
                }
                Text(model.repromptAvailability.message ?? "Reprompting is available.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This version is an offline prompt workspace. It does not ask for API keys or a sign-in, does not generate output, and never sends your prompts over the network.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

struct PrivacySettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Privacy") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Your prompts stay on this Mac.", systemImage: "lock.shield")
                    Text("""
                    • Nothing is sent over the network.
                    • No telemetry or analytics are collected.
                    • Your library, templates and open prompt are stored only on this Mac, readable only by your user account.
                    """)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Library") {
                LabeledContent("Stored prompts", value: "\(model.savedCount) in library · \(model.historyCount) total")
                if model.unsavedHistoryCount > 0 {
                    Button("Remove \(model.unsavedHistoryCount) Unsaved Entries…", role: .destructive) { confirmClear = true }
                        .help("Entries from earlier versions that are not in your library")
                }
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
                Text("Backups contain your prompts and templates as JSON. Imported files are validated and merged without overwriting existing prompts.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove unsaved entries?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete \(model.unsavedHistoryCount) Entries", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Entries that are not in your library are permanently deleted. Saved prompts are kept.")
        }
    }
}
