import Foundation
import Testing
@testable import RePrompterCore
@testable import RePrompterProviders
@testable import RePrompterPersistence

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("reprompter-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func record(_ prompt: String, saved: Bool = false, collection: String? = nil, minutesAgo: Double = 0) -> PromptRecord {
    let date = Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60)
    return PromptRecord(originalPrompt: prompt, isSaved: saved, collection: collection, createdAt: date)
}

// MARK: - Records & library

@Suite("Prompt history and library")
struct PromptLibraryTests {
    @Test func titlesAreDerivedFromPrompts() {
        #expect(PromptRecord.makeTitle(from: "\n\n  # Write a release note for v2\nMore") == "Write a release note for v2")
        #expect(PromptRecord.makeTitle(from: "   ") == "Untitled Prompt")
        let long = PromptRecord.makeTitle(from: String(repeating: "word ", count: 40))
        #expect(long.count <= 61 && long.hasSuffix("…"))
        #expect(PromptRecord.makeTitle(from: "```\ncode\n```\nExplain it") == "code")
    }

    @Test func upsertInsertsThenReplaces() {
        var library = PromptLibrary()
        var item = record("First")
        library.upsert(item)
        item.enhancedPrompt = "Better"
        library.upsert(item)
        #expect(library.records.count == 1)
        #expect(library.record(id: item.id)?.enhancedPrompt == "Better")
    }

    @Test func renameSanitizesAndRejectsEmpty() {
        var library = PromptLibrary(records: [record("A")])
        let id = library.records[0].id
        let renamed = library.rename(id: id, to: "  New\nName\u{0000}  ")
        #expect(renamed)
        #expect(library.records[0].title == "New Name")
        let renamedEmpty = library.rename(id: id, to: "   ")
        #expect(!renamedEmpty)
        let renamedMissing = library.rename(id: UUID(), to: "x")
        #expect(!renamedMissing)
    }

    @Test func duplicateCreatesIndependentCopy() throws {
        var library = PromptLibrary(records: [record("Original", saved: true, collection: "Work")])
        let duplicated = library.duplicate(id: library.records[0].id)
        let copy = try #require(duplicated)
        #expect(library.records.count == 2)
        #expect(copy.id != library.records[0].id)
        #expect(copy.title.hasSuffix("(Copy)"))
        #expect(copy.originalPrompt == "Original")
        #expect(copy.collection == "Work")
    }

    @Test func deleteRemovesOnlyRequested() {
        let a = record("A"), b = record("B"), c = record("C")
        var library = PromptLibrary(records: [a, b, c])
        #expect(library.delete(ids: [a.id, c.id]) == 2)
        #expect(library.records.map(\.id) == [b.id])
        #expect(library.delete(ids: [UUID()]) == 0)
    }

    @Test func clearHistoryKeepsSavedPrompts() {
        var library = PromptLibrary(records: [record("A"), record("B", saved: true), record("C")])
        #expect(library.clearHistory() == 2)
        #expect(library.records.map(\.originalPrompt) == ["B"])
    }

    @Test func historyLimitRemovesOldestUnsaved() {
        var library = PromptLibrary(records: [
            record("old", minutesAgo: 30), record("mid", minutesAgo: 20), record("new", minutesAgo: 10),
            record("ancient saved", saved: true, minutesAgo: 100),
        ])
        #expect(library.enforceHistoryLimit(2) == 1)
        #expect(Set(library.records.map(\.originalPrompt)) == ["mid", "new", "ancient saved"])
    }

    @Test func saveAndOrganizeIntoCollections() {
        var library = PromptLibrary(records: [record("A"), record("B")])
        let id = library.records[0].id
        library.setSaved(id: id, true, collection: "  Client X ")
        #expect(library.records[0].isSaved)
        #expect(library.collections == ["Client X"])
        library.setCollection(id: id, "   ")
        #expect(library.records[0].collection == nil)
        library.setSaved(id: id, true, collection: "Z")
        library.setSaved(id: id, false)
        #expect(!library.records[0].isSaved && library.records[0].collection == nil)
    }

    @Test func searchIsCaseAndDiacriticInsensitiveWithAllTerms() {
        var library = PromptLibrary()
        library.upsert(record("Café menu for Oslo restaurant", saved: true, collection: "Food"), now: Date(timeIntervalSince1970: 1))
        library.upsert(record("Swift CSV parser"), now: Date(timeIntervalSince1970: 2))
        library.upsert(record("Oslo travel plan"), now: Date(timeIntervalSince1970: 3))

        #expect(library.search("CAFE").map(\.originalPrompt) == ["Café menu for Oslo restaurant"])
        #expect(library.search("oslo").map(\.originalPrompt) == ["Oslo travel plan", "Café menu for Oslo restaurant"])
        #expect(library.search("oslo plan").count == 1)
        #expect(library.search("").count == 3)
        #expect(library.search("oslo", scope: .saved).count == 1)
        #expect(library.search("", scope: .saved, collection: "Food").count == 1)
        #expect(library.search("food").count == 1) // matches collection
        #expect(library.search("nothing-matches").isEmpty)
    }

    @Test func exportDocumentRespectsRejection() {
        var item = record("Original")
        item.enhancedPrompt = "Enhanced"
        item.status = .accepted
        #expect(item.effectivePrompt == "Enhanced")
        #expect(item.exportDocument.enhancedPrompt == "Enhanced")
        item.status = .rejected
        #expect(item.effectivePrompt == "Original")
        #expect(item.exportDocument.enhancedPrompt == nil)
    }
}

// MARK: - File store

@Suite("Persistence")
struct FileStoreTests {
    @Test func libraryRoundTripsThroughDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore<PromptLibrary>(url: directory.appendingPathComponent("nested/library.json"))
        #expect(try store.load() == nil)

        var library = PromptLibrary()
        var item = record("Persist me", saved: true, collection: "Work")
        item.result = try LocalEnhancer.enhance(EnhancementRequest(originalPrompt: "Persist me", mode: .structured))
        item.enhancedPrompt = item.result?.enhancedPrompt
        item.status = .accepted
        library.upsert(item)
        try store.save(library)

        let loaded = try #require(try store.load())
        #expect(loaded == library)
    }

    @Test func filesAreOwnerOnly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("private/settings.json")
        try JSONFileStore<AppSettings>(url: url).save(.default)
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        let dirMode = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        #expect(fileMode?.intValue == 0o600)
        #expect(dirMode?.intValue == 0o700)
    }

    @Test func corruptFileIsMovedAsideNotDeleted() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        try Data("{ this is not json".utf8).write(to: url)
        let (value, backup) = JSONFileStore<PromptLibrary>(url: url).loadOrRecover(fallback: PromptLibrary())
        #expect(value.records.isEmpty)
        let backupURL = try #require(backup)
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func oversizedFilesAreRefused() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("big.json")
        try Data(repeating: 0x20, count: 2_000).write(to: url)
        #expect(throws: StoreError.fileTooLarge(bytes: 2_000, limit: 1_000)) {
            try JSONFileStore<PromptLibrary>(url: url, maxBytes: 1_000).load()
        }
    }

    @Test func deletionRemovesFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore<PromptLibrary>(url: directory.appendingPathComponent("library.json"))
        try store.save(PromptLibrary(records: [record("x")]))
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete() // idempotent
    }
}

// MARK: - Settings

@Suite("Settings")
struct SettingsTests {
    @Test func decodesEmptyAndPartialFilesWithDefaults() throws {
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)) == .default)
        let partial = try JSONDecoder().decode(AppSettings.self, from: Data("{\"defaultMode\":\"developer\",\"historyLimit\":999999,\"unknown\":true}".utf8))
        #expect(partial.defaultMode == .developer)
        #expect(partial.historyLimit == AppSettings.historyLimitRange.upperBound)
        #expect(partial.anthropic == .default)
    }

    @Test func settingsNeverContainCredentials() throws {
        let store = InMemoryCredentialStore([AnthropicConfiguration.credentialAccount: ProviderFixtures.testKey])
        _ = store
        let data = try JSONEncoder().encode(AppSettings.default)
        #expect(!String(decoding: data, as: UTF8.self).contains("sk-ant"))
    }
}

// MARK: - Templates

@Suite("Template library")
struct TemplateLibraryTests {
    @Test func editingBuiltInStoresOverrideAndCanReset() throws {
        var library = TemplateLibrary()
        var template = try #require(BuiltInTemplates.all.first)
        template.body = "Edited {{x}}"
        library.save(template)
        #expect(library.isModified(template.id))
        #expect(library.resolved().first?.body == "Edited {{x}}")
        #expect(library.resolved().first?.isBuiltIn == true)
        library.resetBuiltIn(id: template.id)
        #expect(library.resolved().first == BuiltInTemplates.all.first)
    }

    @Test func deletingBuiltInHidesItAndRestoreBringsItBack() throws {
        var library = TemplateLibrary()
        let id = BuiltInTemplates.all[0].id
        library.delete(id: id)
        #expect(!library.resolved().contains { $0.id == id })
        library.restoreAllBuiltIns()
        #expect(library.resolved().contains { $0.id == id })
    }

    @Test func userTemplatesCanBeCreatedEditedDuplicatedAndDeleted() {
        var library = TemplateLibrary()
        var mine = PromptTemplate(name: "  Mine\n", category: .writing, summary: "s", body: "Body {{a}}", suggestedMode: .quickImprove, isBuiltIn: true)
        library.save(mine)
        #expect(library.userTemplates.count == 1)
        #expect(library.userTemplates[0].name == "Mine")
        #expect(library.userTemplates[0].isBuiltIn == false)
        mine.body = "Changed"
        library.save(mine)
        #expect(library.userTemplates.count == 1 && library.userTemplates[0].body == "Changed")
        let copy = library.duplicate(BuiltInTemplates.all[0])
        #expect(!copy.isBuiltIn && copy.id != BuiltInTemplates.all[0].id)
        #expect(library.userTemplates.count == 2)
        library.delete(id: mine.id)
        #expect(library.userTemplates.map(\.id) == [copy.id])
        #expect(library.resolved().count == BuiltInTemplates.all.count + 1)
    }
}

// MARK: - Backup import/export

@Suite("Backup import and export")
struct BackupTests {
    @Test func backupRoundTripsAndMergesWithoutClobbering() throws {
        let existing = record("Existing")
        var library = PromptLibrary(records: [existing])
        var templates = TemplateLibrary()
        let mine = PromptTemplate(id: "user-1", name: "Mine", category: .research, summary: "", body: "B", suggestedMode: .structured)

        let backup = LibraryBackup(records: [existing, record("Imported")], userTemplates: [mine])
        let decoded = try BackupImporter.decode(try backup.encoded())
        let summary = BackupImporter.merge(decoded, into: &library, templates: &templates)

        #expect(summary == .init(importedRecords: 2, importedTemplates: 1, skipped: 0))
        #expect(library.records.count == 3) // colliding ID received a fresh one
        #expect(Set(library.records.map(\.id)).count == 3)
        #expect(templates.userTemplates.map(\.name) == ["Mine"])
    }

    @Test func rejectsFilesThatAreNotBackups() {
        #expect(throws: BackupImporter.ImportError.notABackup) { try BackupImporter.decode(Data("{\"records\": []}".utf8)) }
        #expect(throws: BackupImporter.ImportError.notABackup) { try BackupImporter.decode(Data("garbage".utf8)) }
        #expect(throws: BackupImporter.ImportError.newerSchema(99)) {
            try BackupImporter.decode(Data("{\"format\":\"hcg-reprompter-backup\",\"schemaVersion\":99}".utf8))
        }
        let huge = Data(count: BackupImporter.maxBytes + 1)
        #expect(throws: BackupImporter.ImportError.tooLarge(bytes: huge.count)) { try BackupImporter.decode(huge) }
    }

    @Test func importedRecordsAreSanitized() throws {
        var hostile = record("Prompt\u{0000} with control\u{202E} characters")
        hostile.title = String(repeating: "T", count: 500) + "\n\u{0007}"
        hostile.collection = "   "
        hostile.status = .accepted
        hostile.enhancedPrompt = String(repeating: "x", count: BackupImporter.maxPromptCharacters + 1)
        hostile.updatedAt = Date(timeIntervalSinceNow: 1_000_000)
        let empty = record("    ")

        var library = PromptLibrary()
        var templates = TemplateLibrary()
        let now = Date()
        let summary = BackupImporter.merge(LibraryBackup(records: [hostile, empty], userTemplates: []), into: &library, templates: &templates, now: now)
        #expect(summary.skipped == 1)
        let imported = try #require(library.records.first)
        #expect(!imported.originalPrompt.contains("\u{0000}") && !imported.originalPrompt.contains("\u{202E}"))
        #expect(imported.title.count <= PromptRecord.maxTitleLength)
        #expect(imported.collection == nil)
        #expect(imported.enhancedPrompt == nil)
        #expect(imported.status == .draft)
        #expect(imported.updatedAt <= now)
    }

    @Test func duplicateIDsInsideABackupAreKept() throws {
        let item = record("Twice")
        var library = PromptLibrary()
        var templates = TemplateLibrary()
        _ = BackupImporter.merge(LibraryBackup(records: [item, item], userTemplates: []), into: &library, templates: &templates)
        #expect(library.records.count == 2)
    }
}
