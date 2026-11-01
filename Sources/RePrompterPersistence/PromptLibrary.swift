import Foundation
import RePrompterCore

/// The user's local prompt history and saved library. A value type: all
/// operations are pure and persisted by `JSONFileStore`.
public struct PromptLibrary: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public enum Scope: String, Sendable, CaseIterable {
        /// Every record (history).
        case all
        /// Records saved to the library.
        case saved
    }

    public var schemaVersion: Int
    public private(set) var records: [PromptRecord]

    public init(records: [PromptRecord] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.records = records
    }

    public func record(id: UUID) -> PromptRecord? { records.first { $0.id == id } }

    /// Inserts or replaces a record and stamps `updatedAt`.
    public mutating func upsert(_ record: PromptRecord, now: Date = Date()) {
        var record = record
        record.updatedAt = now
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    @discardableResult
    public mutating func rename(id: UUID, to title: String, now: Date = Date()) -> Bool {
        let cleaned = TextSanitizer.sanitizeLine(title, maxLength: PromptRecord.maxTitleLength)
        guard !cleaned.isEmpty, let index = records.firstIndex(where: { $0.id == id }) else { return false }
        records[index].title = cleaned
        records[index].updatedAt = now
        return true
    }

    /// Permanently deletes records. Returns how many were removed.
    @discardableResult
    public mutating func delete(ids: Set<UUID>) -> Int {
        let before = records.count
        records.removeAll { ids.contains($0.id) }
        return before - records.count
    }

    /// Creates a copy with a new identity, placed alongside the original.
    @discardableResult
    public mutating func duplicate(id: UUID, now: Date = Date()) -> PromptRecord? {
        guard let original = record(id: id) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.title = TextSanitizer.sanitizeLine("\(original.title) (Copy)", maxLength: PromptRecord.maxTitleLength)
        copy.createdAt = now
        copy.updatedAt = now
        records.append(copy)
        return copy
    }

    @discardableResult
    public mutating func setSaved(id: UUID, _ saved: Bool, collection: String? = nil, now: Date = Date()) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
        records[index].isSaved = saved
        if saved, let collection { records[index].collection = Self.normalizeCollection(collection) }
        if !saved { records[index].collection = nil }
        records[index].updatedAt = now
        return true
    }

    @discardableResult
    public mutating func setCollection(id: UUID, _ collection: String?, now: Date = Date()) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
        records[index].collection = collection.flatMap(Self.normalizeCollection)
        records[index].updatedAt = now
        return true
    }

    static func normalizeCollection(_ name: String) -> String? {
        let cleaned = TextSanitizer.sanitizeLine(name, maxLength: PromptRecord.maxCollectionLength)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Deletes history entries that are not saved to the library. Saved
    /// prompts are kept. Returns how many were removed.
    @discardableResult
    public mutating func clearHistory() -> Int {
        let before = records.count
        records.removeAll { !$0.isSaved }
        return before - records.count
    }

    /// Keeps at most `limit` unsaved records, removing the oldest first.
    /// Saved prompts are never removed by the limit.
    @discardableResult
    public mutating func enforceHistoryLimit(_ limit: Int) -> Int {
        let unsaved = records.filter { !$0.isSaved }.sorted { $0.updatedAt > $1.updatedAt }
        guard unsaved.count > limit else { return 0 }
        let toRemove = Set(unsaved.dropFirst(max(0, limit)).map(\.id))
        return delete(ids: toRemove)
    }

    /// Distinct collection names among saved prompts.
    public var collections: [String] {
        Array(Set(records.filter(\.isSaved).compactMap(\.collection)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Case- and diacritic-insensitive search. All whitespace-separated terms
    /// must match the title, prompt text or collection. Most recent first.
    public func search(_ query: String, scope: Scope = .all, collection: String? = nil) -> [PromptRecord] {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        return records
            .filter { scope == .all || $0.isSaved }
            .filter { collection == nil || $0.collection == collection }
            .filter { record in
                guard !terms.isEmpty else { return true }
                let haystack = [record.title, record.originalPrompt, record.enhancedPrompt ?? "", record.collection ?? ""]
                    .joined(separator: "\n")
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                return terms.allSatisfy { haystack.contains($0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
