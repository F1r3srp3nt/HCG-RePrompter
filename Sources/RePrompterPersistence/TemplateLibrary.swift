import Foundation
import RePrompterCore

/// User changes to the template library: edited built-ins, hidden built-ins
/// and user-created templates. Built-in originals ship with the app and can
/// always be restored.
public struct TemplateLibrary: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let maxNameLength = 80
    public static let maxSummaryLength = 240
    public static let maxBodyLength = 20_000

    public var schemaVersion: Int
    public var overrides: [String: PromptTemplate]
    public var userTemplates: [PromptTemplate]
    public var hiddenBuiltInIDs: Set<String>

    public init(
        overrides: [String: PromptTemplate] = [:],
        userTemplates: [PromptTemplate] = [],
        hiddenBuiltInIDs: Set<String> = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.overrides = overrides
        self.userTemplates = userTemplates
        self.hiddenBuiltInIDs = hiddenBuiltInIDs
    }

    /// The visible templates, built-ins first (with edits applied), then user templates.
    public func resolved(builtIns: [PromptTemplate] = BuiltInTemplates.all) -> [PromptTemplate] {
        let builtIn = builtIns
            .filter { !hiddenBuiltInIDs.contains($0.id) }
            .map { overrides[$0.id] ?? $0 }
        return builtIn + userTemplates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func isModified(_ id: String) -> Bool { overrides[id] != nil }

    static func sanitized(_ template: PromptTemplate) -> PromptTemplate {
        var copy = template
        copy.name = TextSanitizer.sanitizeLine(template.name, maxLength: maxNameLength)
        if copy.name.isEmpty { copy.name = "Untitled Template" }
        copy.summary = TextSanitizer.sanitizeLine(template.summary, maxLength: maxSummaryLength)
        copy.body = String(TextSanitizer.sanitize(template.body).prefix(maxBodyLength))
        return copy
    }

    /// Saves a template: edits to built-ins are stored as overrides.
    public mutating func save(_ template: PromptTemplate, builtIns: [PromptTemplate] = BuiltInTemplates.all, now: Date = Date()) {
        var template = Self.sanitized(template)
        template.updatedAt = now
        if builtIns.contains(where: { $0.id == template.id }) {
            template.isBuiltIn = true
            overrides[template.id] = template
        } else {
            template.isBuiltIn = false
            if let index = userTemplates.firstIndex(where: { $0.id == template.id }) {
                userTemplates[index] = template
            } else {
                userTemplates.append(template)
            }
        }
    }

    /// Deletes a user template, or hides a built-in one.
    public mutating func delete(id: String, builtIns: [PromptTemplate] = BuiltInTemplates.all) {
        if builtIns.contains(where: { $0.id == id }) {
            hiddenBuiltInIDs.insert(id)
            overrides[id] = nil
        } else {
            userTemplates.removeAll { $0.id == id }
        }
    }

    /// Discards edits to a built-in template and makes it visible again.
    public mutating func resetBuiltIn(id: String) {
        overrides[id] = nil
        hiddenBuiltInIDs.remove(id)
    }

    public mutating func restoreAllBuiltIns() {
        overrides = [:]
        hiddenBuiltInIDs = []
    }

    /// Creates an editable user copy of any template.
    @discardableResult
    public mutating func duplicate(_ template: PromptTemplate, now: Date = Date()) -> PromptTemplate {
        var copy = template
        copy.id = UUID().uuidString
        copy.name = "\(template.name) (Copy)"
        copy.isBuiltIn = false
        copy.updatedAt = now
        copy = Self.sanitized(copy)
        userTemplates.append(copy)
        return copy
    }
}
