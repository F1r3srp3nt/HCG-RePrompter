import AppKit
import UniformTypeIdentifiers

/// System clipboard access.
@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Save/open panels. Files are only read or written where the user chooses.
@MainActor
enum FilePanels {
    /// Shows a save panel and writes the data. Returns false if cancelled.
    static func save(data: Data, suggestedName: String, fileExtension: String) throws -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let type = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: [.atomic])
        return true
    }

    static func openJSON() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an HCG RePrompter backup file"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
