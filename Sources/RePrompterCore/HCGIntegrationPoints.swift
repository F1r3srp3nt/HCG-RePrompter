import Foundation

// MARK: - Future HCG integration points (interfaces only)
//
// Version 0.1.0 is fully standalone. These protocols document where future
// HCG platform services could attach. Nothing in the application implements,
// instantiates or calls them, they contain no endpoints or credentials, and
// none may be activated without explicit founder approval.
// See docs/ROADMAP.md → "HCG integration boundaries".

/// A signed-in HCG identity (future HCG Shared Identity / HCG Connect).
/// RePrompter does not implement its own authentication.
public struct HCGIdentitySnapshot: Sendable, Equatable {
    public var subjectID: String
    public var displayName: String
    public var organizationID: String?

    public init(subjectID: String, displayName: String, organizationID: String?) {
        self.subjectID = subjectID
        self.displayName = displayName
        self.organizationID = organizationID
    }
}

/// Future: supplies the current HCG identity, if the user chose to sign in.
public protocol HCGIdentityProviding: Sendable {
    func currentIdentity() async throws -> HCGIdentitySnapshot?
}

/// Future: central licensing and application permissions.
public protocol HCGEntitlementChecking: Sendable {
    func isFeatureEnabled(_ featureKey: String) async -> Bool
}

/// Future: product metadata for the HCG Product Registry (name, version only —
/// never prompt content).
public protocol HCGProductRegistryReporting: Sendable {
    func registerInstallation(productID: String, version: String) async throws
}
