import Foundation
import RePrompterCore
import RePrompterProviders

/// Non-secret application settings. API keys are stored only in the
/// Keychain and are never part of this type.
public struct AppSettings: Codable, Sendable, Equatable {
    public static let historyLimitRange = 10...5_000

    public var anthropic: AnthropicConfiguration
    public var defaultMode: EnhancementMode
    public var defaultProcessor: ProcessorChoice
    /// When false, enhancements are not written to history (saved prompts are still kept when explicitly saved).
    public var saveHistory: Bool
    public var historyLimit: Int
    /// The user has read the disclosure that prompts are sent to the external provider.
    public var hasAcknowledgedProviderDisclosure: Bool
    public var showInspector: Bool

    public init(
        anthropic: AnthropicConfiguration = .default,
        defaultMode: EnhancementMode = .structured,
        defaultProcessor: ProcessorChoice = .aiProvider,
        saveHistory: Bool = true,
        historyLimit: Int = 500,
        hasAcknowledgedProviderDisclosure: Bool = false,
        showInspector: Bool = true
    ) {
        self.anthropic = anthropic
        self.defaultMode = defaultMode
        self.defaultProcessor = defaultProcessor
        self.saveHistory = saveHistory
        self.historyLimit = historyLimit
        self.hasAcknowledgedProviderDisclosure = hasAcknowledgedProviderDisclosure
        self.showInspector = showInspector
    }

    public static let `default` = AppSettings()

    enum CodingKeys: String, CodingKey {
        case anthropic, defaultMode, defaultProcessor, saveHistory, historyLimit
        case hasAcknowledgedProviderDisclosure, showInspector
    }

    /// Tolerant decoding: unknown or missing values fall back to defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        anthropic = (try? c.decodeIfPresent(AnthropicConfiguration.self, forKey: .anthropic)) ?? d.anthropic
        defaultMode = (try? c.decodeIfPresent(EnhancementMode.self, forKey: .defaultMode)) ?? d.defaultMode
        defaultProcessor = (try? c.decodeIfPresent(ProcessorChoice.self, forKey: .defaultProcessor)) ?? d.defaultProcessor
        saveHistory = (try? c.decodeIfPresent(Bool.self, forKey: .saveHistory)) ?? d.saveHistory
        let limit = (try? c.decodeIfPresent(Int.self, forKey: .historyLimit)) ?? d.historyLimit
        historyLimit = min(max(limit, Self.historyLimitRange.lowerBound), Self.historyLimitRange.upperBound)
        hasAcknowledgedProviderDisclosure = (try? c.decodeIfPresent(Bool.self, forKey: .hasAcknowledgedProviderDisclosure)) ?? false
        showInspector = (try? c.decodeIfPresent(Bool.self, forKey: .showInspector)) ?? d.showInspector
    }
}
