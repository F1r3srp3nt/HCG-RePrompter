import SwiftUI
import RePrompterCore

/// Native menu commands and keyboard shortcuts.
///
/// ⌘N new prompt · ⌘↩ enhance · ⌘. cancel · ⇧⌘C copy enhanced · ⌘S save ·
/// ⌘F search prompts · ⌥⌘I inspector · ⌘, settings (provided by the Settings scene).
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
            Button("New Prompt") { model.newPrompt() }
                .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save to Library") { model.saveToLibrary() }
                .keyboardShortcut("s", modifiers: .command)
            Menu("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) { model.exportWorkspace(as: format) }
                }
            }
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Enhanced Prompt") { model.copyEnhanced() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Copy Original Prompt") { model.copyOriginal() }
        }

        CommandGroup(after: .textEditing) {
            Button("Search Prompts…") { model.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Prompt") {
            Button("Enhance") { model.enhance() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canEnhance)
            Button("Cancel Enhancement") { model.cancelEnhancement() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isRunning)
            Divider()
            Picker("Mode", selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                ForEach(EnhancementMode.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Processor", selection: Binding(get: { model.processor }, set: { model.processor = $0 })) {
                ForEach(ProcessorChoice.allCases) { Text($0.displayName).tag($0) }
            }
            Divider()
            Button("Accept Enhanced Prompt") { model.accept() }
                .disabled(!model.hasResult)
            Button("Reject Enhancement") { model.reject() }
                .disabled(!model.hasResult)
            Button("Use Enhanced as Original") { model.useEnhancedAsOriginal() }
                .disabled(!model.canCopyEnhanced)
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
