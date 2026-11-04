import Foundation

public enum StoreError: Error, Sendable, Equatable, LocalizedError {
    case fileTooLarge(bytes: Int, limit: Int)
    case unsupportedSchema(Int)
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .fileTooLarge(bytes, limit): "The file is too large (\(bytes) bytes; limit \(limit))."
        case let .unsupportedSchema(version): "The file was created by a newer version of the app (schema \(version))."
        case let .writeFailed(detail): "Could not save data: \(detail)"
        case let .readFailed(detail): "Could not read data: \(detail)"
        }
    }
}

/// Atomic, owner-only JSON file persistence for a Codable value.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL
    public let maxBytes: Int

    public init(url: URL, maxBytes: Int = 64 * 1024 * 1024) {
        self.url = url
        self.maxBytes = maxBytes
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Loads the value, or returns nil when no file exists yet.
    public func load() throws -> Value? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else { throw StoreError.fileTooLarge(bytes: size, limit: maxBytes) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StoreError.readFailed(error.localizedDescription)
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    /// Loads the value; if the file is unreadable or corrupt it is moved aside
    /// (never deleted) and `fallback` is returned.
    public func loadOrRecover(fallback: @autoclosure () -> Value) -> (value: Value, recoveredFile: URL?) {
        do {
            return (try load() ?? fallback(), nil)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return (fallback(), backup)
        }
    }

    public func save(_ value: Value) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            let data = try Self.encoder.encode(value)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Removes the file if it exists.
    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// Where RePrompter keeps its local data.
public struct StorageLocation: Sendable, Equatable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// `~/Library/Application Support/HCG RePrompter/`
    public static func applicationSupport() throws -> StorageLocation {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return StorageLocation(directory: base.appendingPathComponent("HCG RePrompter", isDirectory: true))
    }

    public var libraryURL: URL { directory.appendingPathComponent("library.json") }
    public var templatesURL: URL { directory.appendingPathComponent("templates.json") }
    public var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    /// The open workspace draft, restored at launch.
    public var sessionURL: URL { directory.appendingPathComponent("workspace.json") }
}
