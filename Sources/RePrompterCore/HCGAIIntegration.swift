import Foundation

// MARK: - HCG AI reprompting (future milestone)
//
// Reprompting will be provided by the HCG AI service once it is operational
// and its API has been verified. Until then the application uses
// `DisconnectedHCGAIService`, which never generates output, never performs a
// local rewrite and never touches the network.
//
// To connect the real service later, implement `HCGRepromptService` in its
// own module against the verified API and inject it into the app model. No
// other part of the app needs to change: the interface already shows the
// "Reprompt with HCG AI" control and enables it only when the service
// reports `.available`.

/// Whether reprompting can be offered right now.
public enum RepromptAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }

    public var message: String? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }
}

public enum HCGAIError: Error, Sendable, Equatable, LocalizedError {
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .notConnected: HCGAI.notConnectedMessage
        }
    }
}

/// The contract a future HCG AI client must fulfil.
public protocol HCGRepromptService: Sendable {
    var availability: RepromptAvailability { get }
    func reprompt(_ request: EnhancementRequest) async throws -> EnhancementResult
}

/// Display strings shared by the interface and documentation.
public enum HCGAI {
    public static let serviceName = "HCG AI"
    public static let actionTitle = "Reprompt with HCG AI"
    public static let notConnectedMessage = "Reprompting will be available when HCG AI is connected."
}

/// The only service shipped in this milestone: permanently unavailable.
public struct DisconnectedHCGAIService: HCGRepromptService {
    public init() {}

    public var availability: RepromptAvailability { .unavailable(reason: HCGAI.notConnectedMessage) }

    public func reprompt(_ request: EnhancementRequest) async throws -> EnhancementResult {
        throw HCGAIError.notConnected
    }
}
