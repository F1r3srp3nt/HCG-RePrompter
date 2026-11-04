import SwiftUI
import RePrompterCore

/// Native menu commands and keyboard shortcuts.
///
/// ⌘N new prompt · ⌘S save · ⇧⌘C copy original · ⌘F search prompts ·
/// ⌥⌘1 / ⌥⌘2 show Original / Result · ⌥⌘I inspector · ⌘1–⌘5 sections ·
/// ⌘, settings (provided by the Settings scene).
///
/// There is no generation command or shortcut in this milestone: the only
/// AI item is "Reprompt with HCG AI", disabled until HCG AI is connected.
public struct AppCommands: Commands {
    let model: AppModel
    let openAbout: () -> Void

    public init(model: AppModel, openAbout: @escaping () -> Void) {
        self.model = model
        self.openAbout = openAbout
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.name)", action: openAbout)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Prompt") { model.requestNewPrompt() }
                .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save to Library") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSave)
            Menu("Export Original") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) { model.exportWorkspace(as: format) }
                }
            }
            .disabled(!model.canCopyOriginal)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Original Prompt") { model.copyOriginal() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canCopyOriginal)
        }

        CommandGroup(after: .textEditing) {
            Button("Search Prompts…") { model.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Prompt") {
            Button("Show Original") {
                model.selection = .workspace
                model.workspacePane = .original
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Show Result") {
                model.selection = .workspace
                model.workspacePane = .result
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            Divider()
            Button(HCGAI.actionTitle) { model.requestReprompt() }
                .disabled(!model.repromptAvailability.isAvailable)
        }

        CommandGroup(before: .sidebar) {
            Button(model.settings.showInspector ? "Hide Inspector" : "Show Inspector") {
                model.settings.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { model.selection = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
        }
    }
}
