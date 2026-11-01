import Foundation
import RePrompterCore

/// A portable backup of the user's prompts and templates.
public struct LibraryBackup: Codable, Sendable, Equatable {
    public static let formatIdentifier = "hcg-reprompter-backup"
    public static let currentSchemaVersion = 1

    public var format: String
    public var schemaVersion: Int
    public var appVersion: String
    public var exportedAt: Date
    public var records: [PromptRecord]
    public var userTemplates: [PromptTemplate]

    public init(records: [PromptRecord], userTemplates: [PromptTemplate], exportedAt: Date = Date()) {
        format = Self.formatIdentifier
        schemaVersion = Self.currentSchemaVersion
        appVersion = AppInfo.version
        self.exportedAt = exportedAt
        self.records = records
        self.userTemplates = userTemplates
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// Validates and merges untrusted backup files. Imported data is treated as
/// untrusted: size-limited, schema-checked, sanitized, and given fresh IDs
/// on collision. Nothing in it is executed.
public enum BackupImporter {
    public static let maxBytes = 20 * 1024 * 1024
    public static let maxRecords = 10_000
    public static let maxTemplates = 1_000
    public static let maxPromptCharacters = 200_000

    public enum ImportError: Error, Sendable, Equatable, LocalizedError {
        case tooLarge(bytes: Int)
        case notABackup
        case newerSchema(Int)
        case tooManyItems

        public var errorDescription: String? {
            switch self {
            case let .tooLarge(bytes): "The file is too large to import (\(bytes / 1024 / 1024) MB; limit \(BackupImporter.maxBytes / 1024 / 1024) MB)."
            case .notABackup: "This file is not an HCG RePrompter backup."
            case let .newerSchema(version): "This backup was created by a newer version of HCG RePrompter (schema \(version))."
            case .tooManyItems: "The backup contains more items than can be imported at once."
            }
        }
    }

    public struct Summary: Sendable, Equatable {
        public var importedRecords: Int
        public var importedTemplates: Int
        public var skipped: Int
    }

    public static func decode(_ data: Data) throws(ImportError) -> LibraryBackup {
        guard data.count <= maxBytes else { throw .tooLarge(bytes: data.count) }
        struct Header: Decodable { var format: String?; var schemaVersion: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == LibraryBackup.formatIdentifier,
              let version = header.schemaVersion
        else { throw .notABackup }
        guard version <= LibraryBackup.currentSchemaVersion else { throw .newerSchema(version) }
        guard let backup = try? JSONDecoder().decode(LibraryBackup.self, from: data) else { throw .notABackup }
        guard backup.records.count <= maxRecords, backup.userTemplates.count <= maxTemplates else { throw .tooManyItems }
        return backup
    }

    public static func merge(
        _ backup: LibraryBackup,
        into library: inout PromptLibrary,
        templates: inout TemplateLibrary,
        now: Date = Date()
    ) -> Summary {
        var summary = Summary(importedRecords: 0, importedTemplates: 0, skipped: 0)
        var usedIDs = Set(library.records.map(\.id))

        for record in backup.records {
            guard let clean = sanitize(record, now: now) else {
                summary.skipped += 1
                continue
            }
            var imported = clean
            if usedIDs.contains(imported.id) { imported.id = UUID() }
            usedIDs.insert(imported.id)
            library.upsert(imported, now: imported.updatedAt)
            summary.importedRecords += 1
        }

        var usedTemplateIDs = Set(templates.userTemplates.map(\.id) + BuiltInTemplates.all.map(\.id))
        for template in backup.userTemplates {
            guard !template.body.isEmpty, template.body.count <= TemplateLibrary.maxBodyLength * 2 else {
                summary.skipped += 1
                continue
            }
            var imported = template
            imported.isBuiltIn = false
            if usedTemplateIDs.contains(imported.id) { imported.id = UUID().uuidString }
            usedTemplateIDs.insert(imported.id)
            templates.save(imported, now: now)
            summary.importedTemplates += 1
        }
        return summary
    }

    static func sanitize(_ record: PromptRecord, now: Date) -> PromptRecord? {
        let original = TextSanitizer.sanitize(record.originalPrompt)
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              original.count <= maxPromptCharacters
        else { return nil }
        var clean = record
        clean.originalPrompt = original
        clean.title = TextSanitizer.sanitizeLine(record.title, maxLength: PromptRecord.maxTitleLength)
        if clean.title.isEmpty { clean.title = PromptRecord.makeTitle(from: original) }
        if let enhanced = record.enhancedPrompt {
            let sanitized = TextSanitizer.sanitize(enhanced)
            clean.enhancedPrompt = sanitized.count <= maxPromptCharacters ? sanitized : nil
        }
        if let custom = record.customInstructions {
            clean.customInstructions = String(TextSanitizer.sanitize(custom).prefix(InputLimits.standard.maxCustomInstructionCharacters))
        }
        clean.collection = record.collection.flatMap { PromptLibrary.normalizeCollection($0) }
        if clean.enhancedPrompt == nil, clean.status == .enhanced || clean.status == .accepted {
            clean.status = .draft
            clean.result = nil
        }
        // Dates from the future are clamped.
        if clean.createdAt > now { clean.createdAt = now }
        if clean.updatedAt > now { clean.updatedAt = now }
        return clean
    }
}
