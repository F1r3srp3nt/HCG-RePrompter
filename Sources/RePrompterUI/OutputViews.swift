import SwiftUI
import RePrompterCore

// MARK: - Enhanced (editable)

struct EnhancedOutputView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            if let result = model.result, !result.warnings.isEmpty {
                WarningSummary(warnings: result.warnings)
            }
            PromptEditor(
                text: $model.enhancedText,
                placeholder: "",
                accessibilityLabel: "Enhanced prompt, editable"
            )
            actionRow
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            if let processor = model.result?.processor {
                Badge(
                    text: processor.label,
                    systemImage: processor.isAI ? "cpu" : "desktopcomputer",
                    tint: processor.isAI ? Theme.accent : Theme.violet
                )
            }
            Badge(text: model.reviewStatus.displayName, tint: statusTint)
            if model.hasManualEdits {
                Badge(text: "Edited", systemImage: "pencil", tint: Theme.textSecondary)
            }
            if model.isResultStale {
                Badge(text: "Original changed — enhance again", systemImage: "arrow.triangle.2.circlepath", tint: Theme.warning)
            }
            Spacer()
        }
    }

    private var statusTint: Color {
        switch model.reviewStatus {
        case .accepted: Theme.success
        case .rejected: Theme.danger
        case .enhanced, .draft: Theme.textSecondary
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                model.accept()
            } label: {
                Label("Accept", systemImage: "checkmark")
            }
            .disabled(model.reviewStatus == .accepted)
            .help("Accept the enhanced prompt (including your edits)")

            Button {
                model.reject()
            } label: {
                Label("Reject", systemImage: "xmark")
            }
            .disabled(model.reviewStatus == .rejected)
            .help("Reject the enhancement and keep the original prompt")

            if model.hasManualEdits {
                Button("Revert Edits") { model.revertEdits() }
                    .help("Discard your manual edits")
            }
            Spacer()
            Button("Use as Original") { model.useEnhancedAsOriginal() }
                .help("Continue refining: move the enhanced prompt into the original editor")
            Button {
                model.copyEnhanced()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canCopyEnhanced)
            .help("Copy the enhanced prompt (⇧⌘C)")
        }
    }
}

struct WarningSummary: View {
    @Environment(AppModel.self) private var model
    let warnings: [ValidationWarning]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(warnings.count == 1 ? "1 item to review" : "\(warnings.count) items to review")
                    .font(.callout.weight(.medium))
                Text(warnings[0].message)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Review") { model.outputTab = .changes }
                .buttonStyle(.link)
        }
        .padding(10)
        .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Comparison

struct ComparisonView: View {
    @Environment(AppModel.self) private var model
    @State private var layout: Layout = .sideBySide

    enum Layout: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side"
        case inline = "Inline Changes"
        var id: String { rawValue }
    }

    var body: some View {
        let source = model.resultSourceText ?? model.originalText
        let diff = TextDiff.diff(source, model.enhancedText)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Layout", selection: $layout) {
                    ForEach(Layout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Spacer()
                Text("+\(diff.summary.insertedWords) / −\(diff.summary.removedWords) words")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("\(diff.summary.insertedWords) words added, \(diff.summary.removedWords) words removed")
                if diff.summary.isApproximate {
                    Badge(text: "Line-level", tint: Theme.textSecondary)
                        .help("The texts are large, so changes are compared line by line.")
                }
            }

            switch layout {
            case .sideBySide:
                HStack(spacing: 10) {
                    TextColumn(title: "Original", text: AttributedString(source))
                    TextColumn(title: "Enhanced", text: Self.highlighted(diff.segments, showRemoved: false))
                }
            case .inline:
                TextColumn(title: "Changes (added highlighted, removed struck through)", text: Self.highlighted(diff.segments, showRemoved: true))
            }

            Text("The comparison shows what changed. It does not score whether the new prompt is “better”; review the Changes tab for what was preserved, suggested and left open.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func highlighted(_ segments: [DiffSegment], showRemoved: Bool) -> AttributedString {
        var output = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .equal:
                break
            case .inserted:
                part.backgroundColor = Theme.inserted
            case .removed:
                guard showRemoved else { continue }
                part.backgroundColor = Theme.removed
                part.strikethroughStyle = .single
                part.foregroundColor = Theme.textSecondary
            }
            output += part
        }
        return output
    }
}

struct TextColumn: View {
    let title: String
    let text: AttributedString

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            ScrollView {
                Text(text)
                    .font(Theme.editorFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - Changes report

struct ChangesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let result = model.result {
            let source = model.resultSourceText ?? model.originalText
            // Re-checked against the current (possibly edited) text.
            let preservation = PreservationChecker.check(original: source, enhanced: model.enhancedText)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ReportSection(
                        title: "What changed",
                        systemImage: "arrow.triangle.branch",
                        items: result.report.structuralChanges,
                        empty: "No changes were reported."
                    )
                    PreservationSection(report: result.report, preservation: preservation)
                    ReportSection(
                        title: "Optional suggestions (not applied)",
                        systemImage: "lightbulb",
                        items: result.report.optionalSuggestions,
                        empty: "No suggestions.",
                        tint: Theme.violet
                    )
                    ReportSection(
                        title: "Questions to clarify",
                        systemImage: "questionmark.bubble",
                        items: result.report.missingInformation,
                        empty: "No missing information was identified.",
                        tint: Theme.warning
                    )
                    ReportSection(
                        title: "Potential ambiguities",
                        systemImage: "exclamationmark.bubble",
                        items: result.report.ambiguities,
                        empty: "No ambiguities were identified.",
                        tint: Theme.warning
                    )
                    ReportSection(
                        title: "Assumptions made",
                        systemImage: "hand.raised",
                        items: result.report.assumptions,
                        empty: "No assumptions were made.",
                        tint: Theme.warning
                    )
                    ReportSection(
                        title: "Validation warnings",
                        systemImage: "checkmark.shield",
                        items: result.warnings.map(\.message),
                        empty: "The response passed validation.",
                        tint: Theme.danger
                    )
                }
                .padding(.bottom, 8)
            }
        }
    }
}

struct PreservationSection: View {
    let report: EnhancementReport
    let preservation: PreservationReport
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Requirements preserved", systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(Theme.success)
            if !report.objective.isEmpty {
                Text("Objective: \(report.objective)").font(.callout)
            }
            ForEach(Array((report.explicitRequirements + report.constraints).enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
            }
            if !preservation.statuses.isEmpty {
                let missing = preservation.missing
                Text(missing.isEmpty
                     ? "All \(preservation.statuses.count) concrete details from the original (numbers, names, identifiers, quotes, restrictions, code) appear in the enhanced prompt."
                     : "\(preservation.preservedCount) of \(preservation.statuses.count) concrete details found. Review these:")
                    .font(.callout)
                    .foregroundStyle(missing.isEmpty ? Theme.textSecondary : Theme.warning)
                ForEach(Array(missing.enumerated()), id: \.offset) { _, anchor in
                    Label(anchor.kind == .codeBlock ? "Code block" : anchor.value, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(Theme.warning)
                        .lineLimit(3)
                }
                DisclosureGroup("All checked details", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(preservation.statuses.enumerated()), id: \.offset) { _, status in
                            Label(
                                status.anchor.kind == .codeBlock ? "Code block" : status.anchor.value,
                                systemImage: status.preserved ? "checkmark" : "xmark"
                            )
                            .font(.caption)
                            .foregroundStyle(status.preserved ? Theme.textSecondary : Theme.warning)
                            .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct ReportSection: View {
    let title: String
    let systemImage: String
    let items: [String]
    let empty: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            if items.isEmpty {
                Text(empty).font(.callout).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Theme.textTertiary)
                        Text(item)
                            .font(.callout)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }
}
