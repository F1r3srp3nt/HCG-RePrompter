import Foundation

/// Static product identity for HCG RePrompter.
public enum AppInfo {
    public static let name = "HCG RePrompter"
    public static let shortName = "RePrompter"
    public static let company = "Hakmi Capital Group"
    public static let companyShortName = "HCG"
    public static let version = "0.1.0"
    public static let build = "1"
    public static let bundleIdentifier = "com.hakmicapital.reprompter"
    /// The application is not commercially released.
    public static let releaseStatus = "Pre-release development build — not commercially released."
    public static let copyright = "© 2026 Hakmi Capital Group. All rights reserved."

    public static var versionString: String { "Version \(version) (\(build))" }
}
