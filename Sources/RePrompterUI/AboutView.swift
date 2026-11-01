import SwiftUI
import RePrompterCore

/// The About window.
public struct AboutView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 14) {
            AppIconView(size: 112)
            VStack(spacing: 4) {
                Text(AppInfo.name)
                    .font(.title2.weight(.semibold))
                Text(AppInfo.versionString)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("An intelligent prompt-engineering workstation. Improve the instruction without changing the intention.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Badge(text: AppInfo.releaseStatus, systemImage: "hammer", tint: Theme.warning)
            Divider()
            HCGLogoView(height: 34)
            Text("Developed by \(AppInfo.company)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(AppInfo.copyright)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(28)
        .frame(width: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }
}
