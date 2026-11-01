import Foundation
import RePrompterCore
import RePrompterPersistence
import RePrompterProviders

extension AppModel {
    // MARK: Derived state

    public var isRunning: Bool { phase.isRunning }

    public var hasResult: Bool { result != nil }

    /// The enhanced text differs from what the processor produced.
    public var hasManualEdits: Bool {
        guard let result else { return false }
        return enhancedText != result.enhancedPrompt
    }

    /// The original prompt changed after the current result was produced.
    public var isResultStale: Bool {
        guard let source = resultSourceText else { return false }
        return source != originalText
    }

    public var canEnhance: Bool {
        !isRunning && !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (mode != .custom || !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    public var canCopyEnhanced: Bool { !enhancedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var effectiveTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? PromptRecord.makeTitle(from: originalText) : trimmed
    }

    public var currentRecord: PromptRecord? { currentRecordID.flatMap { library.record(id: $0) } }

    // MARK: Workspace lifecycle

    /// Clears the workspace for a new prompt.
    public func newPrompt() {
        cancelEnhancement()
        title = ""
        originalText = ""
        customInstructions = ""
        mode = settings.defaultMode
        processor = settings.defaultProcessor
        clearResult()
        currentRecordID = nil
        phase = .idle
        selection = .workspace
    }

    func clearResult() {
        result = nil
        resultSourceText = nil
        enhancedText = ""
        reviewStatus = .draft
        outputTab = .enhanced
    }

    /// Loads a saved or historical prompt into the workspace.
    public func open(_ record: PromptRecord) {
        cancelEnhancement()
        title = record.title
        originalText = record.originalPrompt
        mode = record.mode
        customInstructions = record.customInstructions ?? ""
        result = record.result
        resultSourceText = record.result == nil ? nil : record.originalPrompt
        enhancedText = record.enhancedPrompt ?? record.result?.enhancedPrompt ?? ""
        reviewStatus = record.status
        currentRecordID = record.id
        if let processorKind = record.result?.processor {
            processor = processorKind.isAI ? .aiProvider : .localFormatter
        }
        phase = .idle
        outputTab = .enhanced
        selection = .workspace
    }

    /// Starts a new prompt from a template.
    public func useTemplate(_ template: PromptTemplate) {
        newPrompt()
        title = template.name
        originalText = template.body
        mode = template.suggestedMode
        showMessage("Template inserted — replace the {{placeholders}} with your details")
    }

    // MARK: Enhancement

    /// Starts enhancing the current prompt with the selected processor.
    public func enhance() {
        guard !isRunning else { return }
        let request = EnhancementRequest(
            originalPrompt: originalText,
            mode: mode,
            customInstructions: mode == .custom ? customInstructions : nil
        )
        do {
            _ = try InputValidator.validate(request)
        } catch {
            phase = .failed(.input(error))
            return
        }

        if processor == .aiProvider {
            guard hasAPIKey else {
                phase = .failed(.provider(.notConfigured))
                return
            }
            if !settings.hasAcknowledgedProviderDisclosure {
                pendingEnhanceAfterDisclosure = true
                isShowingProviderDisclosure = true
                return
            }
        }

        let service = makeService()
        let processor = self.processor
        let sourceText = originalText
        phase = .running(status: processor == .aiProvider ? "Sending to \(providerHost)…" : "Formatting locally…")

        // AppModel is main-actor isolated (and therefore Sendable); the task
        // holds it only until the enhancement finishes.
        // A token identifies this run so a cancelled run can never overwrite
        // the state of a newer one.
        let model = self
        let token = UUID()
        enhancementToken = token
        enhancementTask = Task {
            do {
                let result = try await service.enhance(request, processor: processor) { event in
                    Task { @MainActor in model.handle(event, token: token) }
                }
                guard model.enhancementToken == token else { return }
                model.apply(result, sourceText: sourceText)
            } catch {
                guard model.enhancementToken == token else { return }
                model.phase = error == .cancelled ? .idle : .failed(error)
            }
            model.enhancementToken = nil
            model.enhancementTask = nil
        }
    }

    func handle(_ event: EnhancementEvent, token: UUID) {
        guard isRunning, enhancementToken == token else { return }
        switch event {
        case let .sending(attempt):
            phase = .running(status: attempt == 1 ? "Waiting for \(providerHost)…" : "Retrying (attempt \(attempt))…")
        case let .waitingToRetry(seconds, reason):
            phase = .running(status: "\(reason) Retrying in \(Int(seconds.rounded(.up)))s…")
        case .validating:
            phase = .running(status: "Validating response…")
        }
    }

    func apply(_ result: EnhancementResult, sourceText: String) {
        self.result = result
        resultSourceText = sourceText
        enhancedText = result.enhancedPrompt
        reviewStatus = .enhanced
        phase = .idle
        outputTab = .enhanced
        recordInHistory()
    }

    /// Called from the disclosure sheet.
    public func acknowledgeDisclosure(proceed: Bool, useLocalInstead: Bool = false) {
        isShowingProviderDisclosure = false
        let shouldEnhance = pendingEnhanceAfterDisclosure
        pendingEnhanceAfterDisclosure = false
        if proceed {
            settings.hasAcknowledgedProviderDisclosure = true
            if shouldEnhance { enhance() }
        } else if useLocalInstead {
            processor = .localFormatter
            if shouldEnhance { enhance() }
        }
    }

    public func cancelEnhancement() {
        let wasRunning = isRunning
        enhancementTask?.cancel()
        enhancementTask = nil
        enhancementToken = nil
        if wasRunning {
            phase = .idle
            showMessage("Enhancement cancelled")
        }
    }

    public func retry() {
        phase = .idle
        enhance()
    }

    public func dismissError() {
        if case .failed = phase { phase = .idle }
    }

    /// Switches to the non-AI formatter after an AI failure and runs it.
    public func useLocalFormatting() {
        processor = .localFormatter
        phase = .idle
        enhance()
    }

    // MARK: Review

    public func accept() {
        guard hasResult else { return }
        reviewStatus = .accepted
        recordInHistory()
        showMessage("Enhanced prompt accepted")
    }

    public func reject() {
        guard let result else { return }
        reviewStatus = .rejected
        enhancedText = result.enhancedPrompt
        recordInHistory()
        showMessage("Enhancement rejected — the original prompt is kept")
    }

    public func revertEdits() {
        guard let result else { return }
        enhancedText = result.enhancedPrompt
    }

    /// Continue iterating: the enhanced prompt becomes the new original.
    public func useEnhancedAsOriginal() {
        guard canCopyEnhanced else { return }
        let text = enhancedText
        let keepTitle = title
        cancelEnhancement()
        clearResult()
        currentRecordID = nil
        originalText = text
        title = keepTitle
    }

    // MARK: Clipboard

    public func copyEnhanced() {
        guard canCopyEnhanced else {
            showMessage("There is no enhanced prompt to copy yet")
            return
        }
        Clipboard.copy(enhancedText)
        showMessage("Enhanced prompt copied")
    }

    public func copyOriginal() {
        guard !originalText.isEmpty else { return }
        Clipboard.copy(originalText)
        showMessage("Original prompt copied")
    }

    // MARK: Saving

    /// Builds a record from the workspace state.
    func makeRecord(saved: Bool? = nil) -> PromptRecord {
        let existing = currentRecord
        return PromptRecord(
            id: currentRecordID ?? UUID(),
            title: effectiveTitle,
            originalPrompt: originalText,
            enhancedPrompt: enhancedText.isEmpty ? nil : enhancedText,
            mode: mode,
            customInstructions: mode == .custom ? customInstructions : nil,
            result: result,
            status: reviewStatus,
            isSaved: saved ?? existing?.isSaved ?? false,
            collection: existing?.collection,
            createdAt: existing?.createdAt ?? Date()
        )
    }

    /// Writes the workspace to history when history is enabled, or updates
    /// an existing saved record.
    func recordInHistory() {
        let isSaved = currentRecord?.isSaved ?? false
        guard settings.saveHistory || isSaved else { return }
        let record = makeRecord()
        currentRecordID = record.id
        library.upsert(record)
        library.enforceHistoryLimit(settings.historyLimit)
        persistLibrary()
    }

    /// Saves the workspace prompt to the library (Cmd+S).
    public func saveToLibrary() {
        guard !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showMessage("Enter a prompt before saving")
            return
        }
        let record = makeRecord(saved: true)
        currentRecordID = record.id
        library.upsert(record)
        persistLibrary()
        showMessage("Saved to your library")
    }

    // MARK: Export

    public var exportDocument: ExportDocument {
        ExportDocument(
            title: effectiveTitle,
            originalPrompt: originalText,
            enhancedPrompt: (reviewStatus == .rejected || enhancedText.isEmpty) ? nil : enhancedText,
            mode: mode,
            processor: result?.processor,
            report: reviewStatus == .rejected ? nil : result?.report
        )
    }

    public func exportWorkspace(as format: ExportFormat) {
        guard !originalText.isEmpty else {
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
