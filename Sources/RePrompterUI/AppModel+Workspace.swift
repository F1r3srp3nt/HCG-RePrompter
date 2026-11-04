import Foundation
import RePrompterCore
import RePrompterPersistence

extension AppModel {
    // MARK: Draft fields (bindable)

    public var title: String {
        get { draft.title }
        set { draft.title = newValue }
    }

    public var originalText: String {
        get { draft.text }
        set { draft.text = newValue }
    }

    public var currentRecordID: UUID? { draft.recordID }

    /// The saved record the open draft belongs to, if any.
    public var currentRecord: PromptRecord? { draft.baseline(in: library) }

    public var hasUnsavedChanges: Bool { draft.hasUnsavedChanges(in: library) }

    public var canSave: Bool { draft.canSave }

    public var effectiveTitle: String { draft.isBlank ? "Untitled Prompt" : draft.effectiveTitle }

    // MARK: Switching drafts (unsaved edits are protected)

    public func requestNewPrompt() { request(.newPrompt) }

    public func requestOpen(_ record: PromptRecord) {
        guard record.id != draft.recordID else {
            selection = .workspace
            workspacePane = .original
            return
        }
        request(.open(record.id))
    }

    public func requestUseTemplate(_ template: PromptTemplate) { request(.useTemplate(template)) }

    private func request(_ navigation: PendingNavigation) {
        if hasUnsavedChanges {
            pendingNavigation = navigation
        } else {
            perform(navigation)
        }
    }

    /// Completes or cancels a navigation that was held because of unsaved edits.
    public func resolvePendingNavigation(_ choice: UnsavedChangesChoice) {
        guard let navigation = pendingNavigation else { return }
        pendingNavigation = nil
        switch choice {
        case .save:
            if save() { perform(navigation) }
        case .discard:
            perform(navigation)
        case .cancel:
            break
        }
    }

    private func perform(_ navigation: PendingNavigation) {
        switch navigation {
        case .newPrompt:
            draft = .empty
        case let .open(id):
            guard let record = library.record(id: id) else {
                showMessage("That prompt no longer exists")
                return
            }
            draft = PromptDraft(record: record)
        case let .useTemplate(template):
            draft = PromptDraft(title: template.name, text: template.body)
            showMessage("Template inserted — replace the {{placeholders}} with your details")
        }
        workspacePane = .original
        selection = .workspace
    }

    // MARK: Saving

    /// Saves the open prompt to the library (⌘S). Returns false if nothing could be saved.
    @discardableResult
    public func save() -> Bool {
        let saved: PromptRecord
        do {
            saved = try draft.save(into: &library)
        } catch {
            showMessage(PromptDraft.SaveError.emptyPrompt.errorDescription ?? "Nothing to save")
            return false
        }
        draft = PromptDraft(record: saved)
        persistLibrary()
        flushSession()
        showMessage("Saved “\(saved.title)” to your library")
        return true
    }

    // MARK: Clipboard

    public var canCopyOriginal: Bool { !draft.text.isEmpty }

    public func copyOriginal() {
        guard canCopyOriginal else {
            showMessage("There is no text to copy yet")
            return
        }
        Clipboard.copy(draft.text)
        showMessage("Original prompt copied")
    }

    // MARK: HCG AI (not connected in this milestone)

    public var repromptAvailability: RepromptAvailability { repromptService.availability }

    /// Entry point for the future HCG AI integration. While the service is
    /// disconnected this does nothing: no output is generated, no local
    /// rewrite runs and nothing is sent over the network.
    public func requestReprompt() {
        guard repromptAvailability.isAvailable else { return }
        // Connect the verified HCG AI client here in a later milestone.
    }

    // MARK: Export

    public var exportDocument: ExportDocument {
        ExportDocument(
            title: effectiveTitle,
            originalPrompt: draft.text,
            enhancedPrompt: nil,
            mode: nil,
            processor: nil,
            report: nil
        )
    }

    public func exportWorkspace(as format: ExportFormat) {
        guard canCopyOriginal else {
            showMessage("Nothing to export yet")
            return
        }
        export(exportDocument, as: format)
    }

    func export(_ document: ExportDocument, as format: ExportFormat) {
        do {
            let data = try PromptExporter.export(document, as: format)
            let name = PromptExporter.suggestedFileName(for: document.title, format: format)
            if try FilePanels.save(data: data, suggestedName: name, fileExtension: format.fileExtension) {
                showMessage("Exported \(name)")
            }
        } catch {
            showAlert("Export Failed", error.localizedDescription)
        }
    }
}
