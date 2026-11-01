import SwiftUI

/// HCG design tokens: deep navy / near-black surfaces with restrained blue
/// and violet accents.
enum Theme {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.078)
    static let surface = Color(red: 0.058, green: 0.071, blue: 0.122)
    static let surfaceRaised = Color(red: 0.082, green: 0.098, blue: 0.165)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)

    static let accent = Color(red: 0.36, green: 0.52, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.45, blue: 0.98)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.42)

    static let success = Color(red: 0.36, green: 0.78, blue: 0.56)
    static let warning = Color(red: 0.98, green: 0.72, blue: 0.32)
    static let danger = Color(red: 0.96, green: 0.42, blue: 0.45)

    static let inserted = Color(red: 0.36, green: 0.78, blue: 0.56).opacity(0.22)
    static let removed = Color(red: 0.96, green: 0.42, blue: 0.45).opacity(0.22)

    static let accentGradient = LinearGradient(colors: [accent, violet], startPoint: .leading, endPoint: .trailing)

    static let cornerRadius: CGFloat = 10
    static let editorFont = Font.system(size: 13.5)
}

/// A rounded surface used for panes and cards.
struct Card: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.border))
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View { modifier(Card(padding: padding)) }
}

/// Small uppercase heading for pane sections.
struct PaneHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, systemImage: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(Theme.accent)
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            trailing()
        }
        .accessibilityElement(children: .contain)
    }
}

/// Compact label used for status, mode and processor indicators.
struct Badge: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

/// Placeholder content for empty states.
struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "sparkles"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.accentGradient)
            Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A plain text editor styled for the dark workstation surfaces.
struct PromptEditor: View {
    @Binding var text: String
    var placeholder: String
    var isEditable = true
    var accessibilityLabel: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(Theme.editorFont)
                .scrollContentBackground(.hidden)
                .disabled(!isEditable)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .accessibilityLabel(accessibilityLabel)
            if text.isEmpty {
                Text(placeholder)
                    .font(Theme.editorFont)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
    }
}
