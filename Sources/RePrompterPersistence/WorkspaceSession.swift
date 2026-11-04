import Foundation
import RePrompterCore

/// The prompt currently open in the workspace: a title and the original
/// text, optionally linked to a saved record.
public struct PromptDraft: Sendable, Equatable {
    public enum SaveError: Error, Sendable, Equatable, LocalizedError {
        case emptyPrompt

        public var errorDescription: String? {
            switch self {
            case .emptyPrompt: "Write a prompt before saving."
            }
        }
    }

    public var recordID: UUID?
    public var title: String
    public var text: String

    public init(recordID: UUID? = nil, title: String = "", text: String = "") {
        self.recordID = recordID
        self.title = title
        self.text = text
    }

    public init(record: PromptRecord) {
        self.init(recordID: record.id, title: record.title, text: record.originalPrompt)
    }

    public static let empty = PromptDraft()

    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The title that will be stored: the typed title, or one derived from the text.
    public var effectiveTitle: String {
        let typed = TextSanitizer.sanitizeLine(title, maxLength: PromptRecord.maxTitleLength)
        return typed.isEmpty ? PromptRecord.makeTitle(from: text) : typed
    }

    /// The saved record this draft is linked to, if it still exists.
    public func baseline(in library: PromptLibrary) -> PromptRecord? {
        recordID.flatMap { library.record(id: $0) }
    }

    /// True when the draft differs from its saved record, or has content and was never saved.
    public func hasUnsavedChanges(in library: PromptLibrary) -> Bool {
        guard let record = baseline(in: library) else { return !isBlank }
        return text != record.originalPrompt || effectiveTitle != record.title
    }

    /// Saves the draft to the library and returns the stored record.
    ///
    /// Existing records keep every other field (mode, collection, creation
    /// date and any results from earlier versions of the app). Text is stored
    /// exactly as typed.
    @discardableResult
    public func save(into library: inout PromptLibrary, now: Date = Date()) throws(SaveError) -> PromptRecord {
        guard canSave else { throw .emptyPrompt }
        var record: PromptRecord
        if let existing = baseline(in: library) {
            record = existing
            record.title = effectiveTitle
            record.originalPrompt = text
        } else {
            record = PromptRecord(title: effectiveTitle, originalPrompt: text, createdAt: now)
        }
        record.isSaved = true
        library.upsert(record, now: now)
        return library.record(id: record.id) ?? record
    }
}

/// The workspace state written to disk so the app reopens where the user
/// left off, including edits that were not saved to the library.
public struct WorkspaceSession: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    static let maxTitleLength = 1_000

    public var schemaVersion: Int
    public var recordID: UUID?
    public var title: String
    public var text: String
    public var savedAt: Date

    public init(draft: PromptDraft, savedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        recordID = draft.recordID
        title = draft.title
        text = draft.text
        self.savedAt = savedAt
    }

    public var draft: PromptDraft { PromptDraft(recordID: recordID, title: title, text: text) }

    /// The draft to show at launch. A session from a newer schema is ignored,
    /// and a link to a record that no longer exists becomes an unsaved draft
    /// so its text is never lost.
    public static func restoredDraft(from session: WorkspaceSession?, library: PromptLibrary) -> PromptDraft {
        guard let session, session.schemaVersion <= currentSchemaVersion else { return .empty }
        var draft = session.draft
        draft.title = String(draft.title.prefix(maxTitleLength))
        if let id = draft.recordID, library.record(id: id) == nil {
            draft.recordID = nil
        }
        return draft
    }
}
