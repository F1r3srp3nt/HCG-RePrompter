import Foundation
import Testing
@testable import RePrompterCore
@testable import RePrompterPersistence

@Suite("Workspace drafts and sessions")
struct WorkspaceDraftTests {
    static let multilineText = "Line one with  double  spaces\n\n  indented line\n\u{1F680} emoji, “quotes” and trailing space "

    @Test func newBlankDraftHasNoUnsavedChanges() {
        let library = PromptLibrary()
        #expect(!PromptDraft.empty.hasUnsavedChanges(in: library))
        #expect(!PromptDraft(title: "  ", text: "\n").hasUnsavedChanges(in: library))
        #expect(PromptDraft(text: "Something").hasUnsavedChanges(in: library))
        #expect(PromptDraft(title: "Only a title").hasUnsavedChanges(in: library))
    }

    @Test func emptyPromptCannotBeSaved() {
        var library = PromptLibrary()
        #expect(throws: PromptDraft.SaveError.emptyPrompt) {
            try PromptDraft(title: "Title", text: "   \n").save(into: &library)
        }
        #expect(library.records.isEmpty)
    }

    @Test func savingStoresExactTitleAndTextAndClearsDirtyState() throws {
        var library = PromptLibrary()
        let draft = PromptDraft(title: "Quarterly board email", text: Self.multilineText)
        let record = try draft.save(into: &library)

        #expect(record.title == "Quarterly board email")
        #expect(record.originalPrompt == Self.multilineText)
        #expect(record.isSaved)
        #expect(library.records.count == 1)

        let reopened = PromptDraft(record: record)
        #expect(!reopened.hasUnsavedChanges(in: library))
    }

    @Test func untitledDraftGetsDerivedTitle() throws {
        var library = PromptLibrary()
        let record = try PromptDraft(text: "Summarize the Oslo report\nfor the board").save(into: &library)
        #expect(record.title == "Summarize the Oslo report")
    }

    @Test func editsToSavedRecordAreDetectedAndUpdateInPlace() throws {
        var library = PromptLibrary()
        var draft = PromptDraft(record: try PromptDraft(title: "A", text: "First").save(into: &library))

        draft.text += " and more"
        #expect(draft.hasUnsavedChanges(in: library))
        draft.text = "First"
        #expect(!draft.hasUnsavedChanges(in: library))
        draft.title = "Renamed"
        #expect(draft.hasUnsavedChanges(in: library))

        let saved = try draft.save(into: &library)
        #expect(library.records.count == 1)
        #expect(saved.id == draft.recordID)
        #expect(saved.title == "Renamed")
    }

    @Test func savingPreservesFieldsFromEarlierVersions() throws {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let legacy = PromptRecord(
            title: "Legacy",
            originalPrompt: "Old text",
            enhancedPrompt: "Enhanced by an earlier version",
            mode: .developer,
            customInstructions: nil,
            result: nil,
            status: .accepted,
            isSaved: false,
            collection: "Clients",
            createdAt: created
        )
        var library = PromptLibrary(records: [legacy])
        var draft = PromptDraft(record: legacy)
        draft.text = "New text"
        let saved = try draft.save(into: &library)

        #expect(saved.enhancedPrompt == "Enhanced by an earlier version")
        #expect(saved.mode == .developer)
        #expect(saved.status == .accepted)
        #expect(saved.collection == "Clients")
        #expect(saved.createdAt == created)
        #expect(saved.isSaved)
        #expect(saved.originalPrompt == "New text")
    }

    @Test func draftLinkedToDeletedRecordSavesAsNewRecord() throws {
        var library = PromptLibrary()
        let original = try PromptDraft(title: "Gone", text: "Text").save(into: &library)
        let draft = PromptDraft(record: original)
        library.delete(ids: [original.id])
        #expect(draft.hasUnsavedChanges(in: library))
        let saved = try draft.save(into: &library)
        #expect(saved.id != original.id)
        #expect(library.records.count == 1)
    }

    @Test func sessionRestoresUnsavedEditsAndDropsMissingLinks() throws {
        var library = PromptLibrary()
        let record = try PromptDraft(title: "Saved", text: "Saved text").save(into: &library)

        var edited = PromptDraft(record: record)
        edited.text = "Saved text plus unsaved edits"
        let restored = WorkspaceSession.restoredDraft(from: WorkspaceSession(draft: edited), library: library)
        #expect(restored == edited)
        #expect(restored.hasUnsavedChanges(in: library))

        let orphan = WorkspaceSession(draft: PromptDraft(recordID: UUID(), title: "T", text: "Keep me"))
        let restoredOrphan = WorkspaceSession.restoredDraft(from: orphan, library: library)
        #expect(restoredOrphan.recordID == nil)
        #expect(restoredOrphan.text == "Keep me")

        #expect(WorkspaceSession.restoredDraft(from: nil, library: library) == .empty)
        var future = WorkspaceSession(draft: edited)
        future.schemaVersion = 99
        #expect(WorkspaceSession.restoredDraft(from: future, library: library) == .empty)
    }

    /// The milestone workflow end to end on disk: save, "quit", reload from
    /// files, and confirm the exact title and text.
    @Test func saveQuitRelaunchRoundTripOnDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = StorageLocation(directory: directory)
        let libraryStore = JSONFileStore<PromptLibrary>(url: location.libraryURL)
        let sessionStore = JSONFileStore<WorkspaceSession>(url: location.sessionURL)

        // First launch: write and save a prompt, then keep editing without saving.
        var library = PromptLibrary()
        let saved = try PromptDraft(title: "Investor update", text: Self.multilineText).save(into: &library)
        try libraryStore.save(library)
        var draft = PromptDraft(record: saved)
        draft.text += "\nUnsaved line"
        try sessionStore.save(WorkspaceSession(draft: draft))

        // Relaunch.
        let reloadedLibrary = try #require(try libraryStore.load())
        let reloadedRecord = try #require(reloadedLibrary.record(id: saved.id))
        #expect(reloadedRecord.title == "Investor update")
        #expect(reloadedRecord.originalPrompt == Self.multilineText)

        let restored = WorkspaceSession.restoredDraft(from: try sessionStore.load(), library: reloadedLibrary)
        #expect(restored.recordID == saved.id)
        #expect(restored.text == Self.multilineText + "\nUnsaved line")
        #expect(restored.hasUnsavedChanges(in: reloadedLibrary))

        let mode = try FileManager.default.attributesOfItem(atPath: location.sessionURL.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }
}

@Suite("HCG AI integration point")
struct HCGAIIntegrationTests {
    @Test func disconnectedServiceIsUnavailableAndNeverGenerates() async {
        let service = DisconnectedHCGAIService()
        #expect(!service.availability.isAvailable)
        #expect(service.availability.message == "Reprompting will be available when HCG AI is connected.")
        await #expect(throws: HCGAIError.notConnected) {
            try await service.reprompt(EnhancementRequest(originalPrompt: "Anything", mode: .structured))
        }
    }
}
