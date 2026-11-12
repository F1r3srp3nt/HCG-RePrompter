import SwiftUI
import RePrompterCore

/// Layout constants for the workspace.
///
/// The workspace deliberately avoids nested split views, the system inspector
/// and minimum-width frames: its size is decided from the space it is given,
/// so it can never ask for more width than the window allows (the earlier
/// layout required ~1,170 pt inside a 980 pt minimum window).
enum WorkspaceLayout {
    static let inspectorWidth: CGFloat = 260
    /// Below this content width, Original and Result are shown one at a time.
    static let splitThreshold: CGFloat = 760
    /// Share of the content width given to the Original editor in the split layout.
    static let originalShare: CGFloat = 0.64
}

/// The offline prompt workspace: title, original prompt editor, result pane
/// (empty until HCG AI is connected) and an optional inspector.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let showInspector = model.settings.showInspector
            let inspectorSpace = showInspector ? WorkspaceLayout.inspectorWidth + 1 : 0
            let contentWidth = max(0, proxy.size.width - inspectorSpace)
            let isWide = contentWidth >= WorkspaceLayout.splitThreshold
            HStack(spacing: 0) {
                WorkspaceContent(isWide: isWide, contentWidth: contentWidth)
                    .frame(width: contentWidth)
                if showInspector {
                    Divider()
                    InspectorView()
                        .frame(width: WorkspaceLayout.inspectorWidth)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background(Theme.background)
        .navigationTitle(model.effectiveTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.canSave)
                .help("Save to your library (⌘S)")

                Button {
                    model.copyOriginal()
                } label: {
                    Label("Copy Original", systemImage: "doc.on.doc")
                }
                .disabled(!model.canCopyOriginal)
                .help("Copy the original prompt (⇧⌘C)")

                Button {
                    model.settings.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector (⌥⌘I)")
            }
        }
    }
}

struct WorkspaceContent: View {
    @Environment(AppModel.self) private var model
    let isWide: Bool
    let contentWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(isWide: isWide)
            Divider()
            HStack(spacing: 0) {
                // The Original pane keeps the same position in the view tree in
                // both layouts, so its editor is not recreated when the window
                // crosses the split threshold. The text itself lives in the
                // model and is never held by a view.
                if isWide || model.workspacePane == .original {
                    OriginalPane()
                        .frame(width: isWide ? (contentWidth * WorkspaceLayout.originalShare).rounded() : contentWidth)
                }
                if isWide {
                    Divider()
                }
                if isWide || model.workspacePane == .result {
                    ResultPane()
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct WorkspaceHeader: View {
    @Environment(AppModel.self) private var model
    let isWide: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            TextField("Untitled Prompt", text: $model.title)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .accessibilityLabel("Prompt title")
                .help("The name shown in your library and used for exports")
            SaveStateBadge()
            if !isWide {
                Picker("Pane", selection: $model.workspacePane) {
                    ForEach(WorkspacePane.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Switch between the original prompt and the result")
                .accessibilityLabel("Show pane")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }
}

struct SaveStateBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.hasUnsavedChanges {
            Badge(text: "Unsaved", systemImage: "circle.fill", tint: Theme.warning)
                .help("This prompt has changes that are not in your library yet. They are kept if you quit.")
        } else if model.currentRecord != nil {
            Badge(text: "Saved", systemImage: "checkmark", tint: Theme.success)
        }
    }
}

// MARK: - Original prompt

struct OriginalPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            PaneHeader("Original Prompt", systemImage: "text.alignleft") {
                Text(counts)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            PromptEditor(
                text: $model.originalText,
                placeholder: "Write the prompt you want to work on…",
                accessibilityLabel: "Original prompt"
            )
            ViewThatFits(in: .horizontal) {
                OriginalActions(compact: false)
                OriginalActions(compact: true)
            }
        }
        .padding(14)
    }

    private var counts: String {
        let words = model.originalText.split(whereSeparator: { $0.isWhitespace }).count
        return "\(words) words · \(model.originalText.count) characters"
    }
}

struct OriginalActions: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.copyOriginal()
            } label: {
                actionLabel("Copy Original", systemImage: "doc.on.doc")
            }
            .disabled(!model.canCopyOriginal)
            .help("Copy the original prompt (⇧⌘C)")

            Button {
                model.save()
            } label: {
                actionLabel("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSave)
            .help("Save to your library (⌘S)")

            Spacer(minLength: 8)

            RepromptButton()
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if compact {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

/// The future HCG AI action. Visible, and disabled until the service is connected.
struct RepromptButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let availability = model.repromptAvailability
        Button {
            model.requestReprompt()
        } label: {
            Label(HCGAI.actionTitle, systemImage: "wand.and.stars")
        }
        .disabled(!availability.isAvailable)
        .help(availability.message ?? HCGAI.actionTitle)
        .accessibilityHint(availability.message ?? "")
    }
}

// MARK: - Result

/// Empty until HCG AI is connected; states why.
struct ResultPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaneHeader("Result", systemImage: "sparkles")
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.accent.opacity(0.75))
                    .accessibilityHidden(true)
                Text(model.repromptAvailability.message ?? "No result yet.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
            .accessibilityElement(children: .combine)
        }
        .padding(14)
    }
}
