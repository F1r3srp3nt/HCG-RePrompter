import AppKit
import SwiftUI

/// Loads HCG brand artwork. Lookup never traps: it checks the app bundle's
/// Resources folder (packaged app), then SwiftPM resource bundles next to the
/// app or executable (`swift run`, Xcode), and returns nil if nothing is found.
@MainActor
public enum BrandAssets {
    static let resourceBundleName = "HCGRePrompter_RePrompterUI.bundle"
    private static var cache: [String: NSImage] = [:]

    public static var logo: NSImage? { image(named: "HCGLogo") }
    public static var appIcon: NSImage? { image(named: "AppIcon") }

    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        for url in candidateURLs(for: name) {
            if let image = NSImage(contentsOf: url) {
                cache[name] = image
                return image
            }
        }
        return nil
    }

    static func candidateURLs(for name: String) -> [URL] {
        var urls: [URL] = []
        if let direct = Bundle.main.url(forResource: name, withExtension: "png") { urls.append(direct) }
        var bundleLocations: [URL] = []
        if let resources = Bundle.main.resourceURL { bundleLocations.append(resources) }
        bundleLocations.append(Bundle.main.bundleURL)
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() { bundleLocations.append(executable) }
        for location in bundleLocations {
            let bundleURL = location.appendingPathComponent(resourceBundleName)
            guard let bundle = Bundle(url: bundleURL) else { continue }
            if let url = bundle.url(forResource: name, withExtension: "png")
                ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources") {
                urls.append(url)
            }
        }
        return urls
    }
}

/// The HCG logo wordmark, with a text fallback if the artwork is unavailable.
public struct HCGLogoView: View {
    var height: CGFloat

    public init(height: CGFloat = 28) { self.height = height }

    public var body: some View {
        Group {
            if let logo = BrandAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: height)
            } else {
                Text("HCG")
                    .font(.system(size: height * 0.7, weight: .heavy, design: .rounded))
                    .tracking(height * 0.05)
                    .foregroundStyle(Theme.accentGradient)
                    .frame(height: height)
            }
        }
        .accessibilityLabel("Hakmi Capital Group")
    }
}

/// The square application icon (HCG logo on the HCG dark field).
public struct AppIconView: View {
    var size: CGFloat

    public init(size: CGFloat) { self.size = size }

    public var body: some View {
        Group {
            if let icon = BrandAssets.appIcon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(Theme.background)
                    .overlay(HCGLogoView(height: size * 0.3))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("HCG RePrompter icon")
    }
}
