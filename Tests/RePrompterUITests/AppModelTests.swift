import AppKit
import Foundation
import SwiftUI
import Testing
@testable import RePrompterCore
@testable import RePrompterPersistence
@testable import RePrompterUI

/// A temporary data folder. Tests never touch the real application data.
@MainActor
struct Harness {
    let directory: URL
    var location: StorageLocation { StorageLocation(directory: directory) }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("reprompter-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Simulates a launch against the same data folder.
    func launch() -> AppModel { AppModel(location: location, sessionSaveDelay: 0.05) }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

/// Counts reprompt calls, to prove the disabled gate never reaches the service.
final class CountingRepromptService: HCGRepromptService, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }
    var availability: RepromptAvailability { .unavailable(reason: HCGAI.notConnectedMessage) }

    func reprompt(_ request: EnhancementRequest) async throws -> EnhancementResult {
        lock.withLock { _calls += 1 }
        throw HCGAIError.notConnected
    }
}

@Suite("Offline workspace workflow")
@MainActor
struct AppModelTests {
    static let title = "Investor update — Q3"
    static let text = "Draft an investor update.\n\n  Keep it under 300 words.\nMention Oslo 🚀 and “Project North”.  "

    @Test func createTitleSaveQuitRelaunchKeepsExactTitleAndText() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }

        let first = harness.launch()
        #expect(first.draft == .empty)
        first.title = Self.title
        first.originalText = Self.text
        #expect(first.hasUnsavedChanges)
        #expect(first.save())
        #expect(!first.hasUnsavedChanges)
        let id = try #require(first.currentRecordID)
        first.flushSession() // what the app does on quit

        let second = harness.launch()
        #expect(second.currentRecordID == id)
        #expect(second.title == Self.title)
        #expect(second.originalText == Self.text)
        #expect(!second.hasUnsavedChanges)
        let record = try #require(second.library.record(id: id))
        #expect(record.title == Self.title)
        #expect(record.originalPrompt == Self.text)
        #expect(record.isSaved)
    }

    @Test func unsavedEditsSurviveQuitWithoutSaving() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }

        let first = harness.launch()
        first.originalText = "Saved part"
        first.save()
        first.originalText = "Saved part, then more typing"

        // Wait for the autosave (no explicit flush). The model must stay alive
        // meanwhile, as it does in the app: Swift may otherwise release it
        // after its last use, and the autosave task holds it weakly.
        let sessionURL = harness.location.sessionURL
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let written = (try? JSONFileStore<WorkspaceSession>(url: sessionURL).load())?.text
            if written == "Saved part, then more typing" { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        withExtendedLifetime(first) {}

        let second = harness.launch()
        #expect(second.originalText == "Saved part, then more typing")
        #expect(second.hasUnsavedChanges)
        #expect(second.currentRecord?.originalPrompt == "Saved part")
    }

    @Test func emptyPromptIsNotSaved() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.launch()
        model.title = "Only a title"
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(model.library.records.isEmpty)
    }

    @Test func switchingDraftsProtectsUnsavedEdits() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.launch()
        model.originalText = "Saved prompt"
        model.save()
        let saved = try #require(model.currentRecord)

        model.requestNewPrompt()
        #expect(model.pendingNavigation == nil, "A clean, saved prompt switches without asking")
        #expect(model.draft == .empty)

        model.originalText = "Work in progress"
        model.requestOpen(saved)
        #expect(model.pendingNavigation == .open(saved.id))
        #expect(model.originalText == "Work in progress", "Nothing changes until the user answers")

        model.resolvePendingNavigation(.cancel)
        #expect(model.pendingNavigation == nil)
        #expect(model.originalText == "Work in progress")

        model.requestOpen(saved)
        model.resolvePendingNavigation(.save)
        #expect(model.originalText == "Saved prompt")
        #expect(model.library.records.contains { $0.originalPrompt == "Work in progress" && $0.isSaved })

        model.originalText = "Throwaway edit"
        model.requestNewPrompt()
        model.resolvePendingNavigation(.discard)
        #expect(model.draft == .empty)
        #expect(model.library.record(id: saved.id)?.originalPrompt == "Saved prompt")
    }

    @Test func templatesStartUnsavedDraftsAndAreProtectedToo() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.launch()
        let template = try #require(BuiltInTemplates.all.first)

        model.requestUseTemplate(template)
        #expect(model.originalText == template.body)
        #expect(model.title == template.name)
        #expect(model.currentRecordID == nil)
        #expect(model.hasUnsavedChanges)

        model.requestUseTemplate(template)
        #expect(model.pendingNavigation == .useTemplate(template))
    }

    @Test func deletingOpenPromptKeepsItsTextAsUnsavedDraft() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.launch()
        model.originalText = "Keep my words"
        model.save()
        let id = try #require(model.currentRecordID)

        model.deleteRecords([id])
        #expect(model.library.records.isEmpty)
        #expect(model.originalText == "Keep my words")
        #expect(model.currentRecordID == nil)
        #expect(model.hasUnsavedChanges)
    }

    @Test func existingLibraryDataIsPreserved() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        // A library written by version 0.1.0, including an enhanced record.
        let legacy = PromptRecord(
            title: "Legacy",
            originalPrompt: "Old prompt",
            enhancedPrompt: "Enhanced text from 0.1.0",
            mode: .developer,
            status: .accepted,
            isSaved: true,
            collection: "Clients"
        )
        let unsavedLegacy = PromptRecord(title: "History only", originalPrompt: "From history")
        try JSONFileStore<PromptLibrary>(url: harness.location.libraryURL).save(PromptLibrary(records: [legacy, unsavedLegacy]))

        let model = harness.launch()
        #expect(model.library.records.count == 2)
        #expect(model.unsavedHistoryCount == 1)

        model.requestOpen(legacy)
        model.originalText = "Old prompt, edited"
        model.save()

        let reloaded = harness.launch()
        let record = try #require(reloaded.library.record(id: legacy.id))
        #expect(record.originalPrompt == "Old prompt, edited")
        #expect(record.enhancedPrompt == "Enhanced text from 0.1.0")
        #expect(record.collection == "Clients")
        #expect(record.mode == .developer)
        #expect(reloaded.library.record(id: unsavedLegacy.id) != nil)
    }

    @Test func copyOriginalPutsExactTextOnPasteboard() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.launch()
        model.originalText = Self.text
        model.copyOriginal()
        #expect(NSPasteboard.general.string(forType: .string) == Self.text)
    }

    @Test func repromptingIsDisabledAndGeneratesNothing() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.launch()
        #expect(!model.repromptAvailability.isAvailable)
        #expect(model.repromptAvailability.message == "Reprompting will be available when HCG AI is connected.")

        let service = CountingRepromptService()
        let gated = AppModel(location: harness.location, repromptService: service)
        gated.originalText = "Rewrite me"
        let before = gated.draft
        gated.requestReprompt()
        #expect(service.calls == 0)
        #expect(gated.draft == before)
        #expect(gated.library.records.isEmpty)
    }
}

/// Hosts the real interface in a window and drives the interactions that
/// triggered the constraint-update crash: minimum size, repeated resizing,
/// toggling the inspector and switching panes. An uncaught AppKit layout
/// exception terminates the test process, so this test failing (or the run
/// crashing) is the regression signal.
@Suite("Window layout")
@MainActor
struct WindowLayoutTests {
    static func settle() async throws {
        try await Task.sleep(nanoseconds: 30_000_000)
    }

    @Test func workspaceSurvivesResizingInspectorAndPaneSwitching() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let model = harness.launch()
        let text = String(repeating: "A long line of prompt text that wraps in the editor. ", count: 40)
        model.title = "Layout check"
        model.originalText = text

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: RootView().environment(model))
        window.orderFrontRegardless()
        defer { window.close() }

        let widths: [CGFloat] = [860, 880, 1000, 1020, 1100, 1280, 1600, 1021, 1019, 860]
        for showInspector in [true, false, true] {
            model.settings.showInspector = showInspector
            for width in widths {
                window.setContentSize(NSSize(width: width, height: 560))
                window.layoutIfNeeded()
                window.displayIfNeeded()
                try await Self.settle()
            }
        }

        // Narrow window: switch panes back and forth.
        window.setContentSize(NSSize(width: 860, height: 560))
        for pane in [WorkspacePane.result, .original, .result, .original] {
            model.workspacePane = pane
            window.layoutIfNeeded()
            try await Self.settle()
        }

        // Other sections at minimum size.
        for item in SidebarItem.allCases {
            model.selection = item
            window.layoutIfNeeded()
            window.displayIfNeeded()
            try await Self.settle()
        }
        model.selection = .workspace
        try await Self.settle()

        #expect(model.originalText == text)
        #expect(model.title == "Layout check")
        #expect(window.contentView != nil)
    }
}
