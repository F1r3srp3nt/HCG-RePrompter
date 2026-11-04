import Foundation
import RePrompterCore
import RePrompterPersistence

extension AppModel {
    // MARK: Prompt library

    /// ⌘F: shows the prompt list (the Library unless All Prompts is open) and focuses search.
    public func focusSearch() {
        if selection != .saved && selection != .history { selection = .saved }
        pendingSearchFocus = true
        searchFocusRequest += 1
    }

    public func records(in scope: PromptLibrary.Scope, query: String, collection: String? = nil) -> [PromptRecord] {
        library.search(query, scope: scope, collection: collection)
    }

    public var historyCount: Int { library.records.count }
    public var savedCount: Int { library.records.filter(\.isSaved).count }

    public func renameRecord(_ id: UUID, to title: String) {
        guard library.rename(id: id, to: title) else {
            showMessage("Enter a name")
            return
        }
        if id == currentRecordID, let renamed = library.record(id: id) { draft.title = renamed.title }
        persistLibrary()
    }

    /// Permanently deletes prompts. If the open prompt is deleted, its text
    /// stays in the workspace as an unsaved draft.
    public func deleteRecords(_ ids: Set<UUID>) {
        let removed = library.delete(ids: ids)
        if let current = currentRecordID, ids.contains(current) { draft.recordID = nil }
        persistLibrary()
        if removed > 0 { showMessage(removed == 1 ? "Prompt deleted" : "\(removed) prompts deleted") }
    }

    @discardableResult
    public func duplicateRecord(_ id: UUID) -> PromptRecord? {
        let copy = library.duplicate(id: id)
        persistLibrary()
        if copy != nil { showMessage("Prompt duplicated") }
        return copy
    }

    public func setSaved(_ id: UUID, _ saved: Bool) {
        library.setSaved(id: id, saved)
        persistLibrary()
        showMessage(saved ? "Added to your library" : "Removed from your library (still under All Prompts)")
    }

    public func setCollection(_ id: UUID, _ collection: String?) {
        library.setCollection(id: id, collection)
        persistLibrary()
    }

    /// Number of stored prompts that are not in the library (from earlier versions).
    public var unsavedHistoryCount: Int { historyCount - savedCount }

    /// Deletes prompts that are not saved to the library. Saved prompts are kept.
    public func clearHistory() {
        let removed = library.clearHistory()
        if let current = currentRecordID, library.record(id: current) == nil { draft.recordID = nil }
        persistLibrary()
        showMessage(removed == 1 ? "1 history entry deleted" : "\(removed) history entries deleted")
    }

    /// Exports a prompt's title and original text.
    public func exportRecord(_ record: PromptRecord, as format: ExportFormat) {
        let document = ExportDocument(
            title: record.title,
            originalPrompt: record.originalPrompt,
            enhancedPrompt: nil,
            mode: nil,
            processor: nil,
            report: nil
        )
        export(document, as: format)
    }

    public func copyRecord(_ record: PromptRecord) {
        Clipboard.copy(record.originalPrompt)
        showMessage("Original prompt copied")
    }

    // MARK: Backup

    public func exportBackup() {
        do {
            let backup = LibraryBackup(records: library.records, userTemplates: templates.userTemplates)
            let name = "RePrompter Backup \(Self.fileDateFormatter.string(from: Date())).json"
            if try FilePanels.save(data: try backup.encoded(), suggestedName: name, fileExtension: "json") {
                showMessage("Backup exported")
            }
        } catch {
            showAlert("Backup Failed", error.localizedDescription)
        }
    }

    public func importBackup() {
        guard let url = FilePanels.openJSON() else { return }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let backup = try BackupImporter.decode(data)
            var library = self.library
            var templates = self.templates
            let summary = BackupImporter.merge(backup, into: &library, templates: &templates)
            self.library = library
            self.templates = templates
            persistLibrary()
            persistTemplates()
            var message = "Imported \(summary.importedRecords) prompt(s) and \(summary.importedTemplates) template(s)."
            if summary.skipped > 0 { message += " \(summary.skipped) invalid item(s) were skipped." }
            showAlert("Import Complete", message)
        } catch let error as BackupImporter.ImportError {
            showAlert("Import Failed", error.errorDescription ?? "The file could not be imported.")
        } catch {
            showAlert("Import Failed", "The file could not be read.")
        }
    }

    static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: Templates

    public var allTemplates: [PromptTemplate] { templates.resolved() }

    public func saveTemplate(_ template: PromptTemplate) {
        templates.save(template)
        persistTemplates()
        showMessage("Template saved")
    }

    public func deleteTemplate(_ template: PromptTemplate) {
        templates.delete(id: template.id)
        persistTemplates()
        showMessage(template.isBuiltIn ? "Built-in template hidden" : "Template deleted")
    }

    public func resetTemplate(_ template: PromptTemplate) {
        templates.resetBuiltIn(id: template.id)
        persistTemplates()
        showMessage("Template restored to its original version")
    }

    public func restoreBuiltInTemplates() {
        templates.restoreAllBuiltIns()
        persistTemplates()
        showMessage("Built-in templates restored")
    }

    @discardableResult
    public func duplicateTemplate(_ template: PromptTemplate) -> PromptTemplate {
        let copy = templates.duplicate(template)
        persistTemplates()
        return copy
    }

    @discardableResult
    public func createTemplate() -> PromptTemplate {
        let template = PromptTemplate(
            name: "New Template",
            category: .writing,
            summary: "",
            body: "Describe the task here. Use {{placeholders}} for details that change.",
            suggestedMode: .structured
        )
        templates.save(template)
        persistTemplates()
        return template
    }

    /// Saves the current workspace prompt as a new user template.
    @discardableResult
    public func saveWorkspaceAsTemplate() -> PromptTemplate? {
        let body = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            showMessage("Enter a prompt first")
            return nil
        }
        let template = PromptTemplate(name: effectiveTitle, category: .writing, summary: "", body: body, suggestedMode: settings.defaultMode)
        templates.save(template)
        persistTemplates()
        showMessage("Saved as a template")
        return template
    }

    /// Opens the data folder in Finder.
    public func revealDataFolder() {
        guard let location else { return }
        FilePanels.reveal(location.directory)
    }
}
