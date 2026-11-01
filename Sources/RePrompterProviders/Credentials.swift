import Foundation
import RePrompterCore

public enum CredentialStoreError: Error, Sendable, Equatable, LocalizedError {
    case unavailable
    case osStatus(Int32)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Secure credential storage is not available on this system."
        case let .osStatus(status): "Keychain error \(status)."
        case .invalidData: "The stored credential is not valid text."
        }
    }
}

/// Secure storage for provider secrets. Secrets are never written to
/// settings files, history or logs.
public protocol CredentialStore: Sendable {
    func secret(for account: String) throws -> String?
    func setSecret(_ secret: String, for account: String) throws
    func deleteSecret(for account: String) throws
}

/// In-memory store for tests and previews. Never persists anything.
public final class InMemoryCredentialStore: CredentialStore, CustomReflectable, @unchecked Sendable {
    /// Reflection never exposes stored secrets (e.g. via `dump`).
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .class) }

    private let lock = NSLock()
    private var storage: [String: String]

    public init(_ initial: [String: String] = [:]) { storage = initial }

    public func secret(for account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }

    public func setSecret(_ secret: String, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = secret
    }

    public func deleteSecret(for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = nil
    }
}

#if canImport(Security)
import Security

/// macOS Keychain-backed credential store (generic password items).
public struct KeychainCredentialStore: CredentialStore {
    public let service: String

    public init(service: String = AppInfo.bundleIdentifier + ".credentials") {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func secret(for account: String) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
                throw CredentialStoreError.invalidData
            }
            return text
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.osStatus(status)
        }
    }

    public func setSecret(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = baseQuery(account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            add[kSecAttrLabel as String] = "\(AppInfo.name) — \(account)"
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CredentialStoreError.osStatus(addStatus) }
        default:
            throw CredentialStoreError.osStatus(status)
        }
    }

    public func deleteSecret(for account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.osStatus(status)
        }
    }
}
#endif

/// Validates API keys entered by the user before they are stored.
public enum APIKeyValidator {
    public enum Problem: Error, Sendable, Equatable, LocalizedError {
        case empty
        case containsWhitespace
        case invalidCharacters
        case tooLong

        public var errorDescription: String? {
            switch self {
            case .empty: "Enter an API key."
            case .containsWhitespace: "The API key contains spaces or line breaks. Paste only the key."
            case .invalidCharacters: "The API key contains characters that are not allowed."
            case .tooLong: "The API key is too long."
            }
        }
    }

    /// Returns the trimmed key, or throws if it cannot be a valid key.
    public static func normalize(_ input: String) throws(Problem) -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .empty }
        guard key.count <= 512 else { throw .tooLong }
        guard !key.contains(where: \.isWhitespace) else { throw .containsWhitespace }
        guard key.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }) else {
            throw .invalidCharacters
        }
        return key
    }

    /// A display-safe hint such as `sk-ant-…4f2a`.
    public static func maskedHint(_ key: String) -> String {
        guard key.count > 10 else { return "••••" }
        let prefix = key.hasPrefix("sk-ant-") ? "sk-ant-" : String(key.prefix(3))
        return prefix + "…" + String(key.suffix(4))
    }
}

/// Removes secrets from text before it is displayed or logged.
public enum SecretRedactor {
    public static let placeholder = "[REDACTED]"

    public static func redact(_ text: String, knownSecrets: [String] = []) -> String {
        var result = text
        for secret in knownSecrets where secret.count >= 8 {
            result = result.replacingOccurrences(of: secret, with: placeholder)
        }
        // Anthropic-style keys and bearer tokens.
        result = redactPattern(prefix: "sk-ant-", in: result)
        result = redactPattern(prefix: "Bearer ", in: result)
        return result
    }

    private static func redactPattern(prefix: String, in text: String) -> String {
        var output = ""
        var remainder = text[...]
        while let range = remainder.range(of: prefix) {
            output += remainder[..<range.lowerBound]
            var end = range.upperBound
            while end < remainder.endIndex, isTokenCharacter(remainder[end]) {
                end = remainder.index(after: end)
            }
            output += end == range.upperBound ? String(remainder[range]) : placeholder
            remainder = remainder[end...]
        }
        output += remainder
        return output
    }

    private static func isTokenCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." || c == "=")
    }
}

/// Wraps a secret so that string interpolation, `print`, `dump` and debug
/// descriptions never reveal it.
public struct RedactedSecret: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let value: String
    public init(_ value: String) { self.value = value }
    public var description: String { SecretRedactor.placeholder }
    public var debugDescription: String { SecretRedactor.placeholder }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}
