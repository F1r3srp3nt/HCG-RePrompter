import SwiftUI
import RePrompterCore

/// Live analysis of the original prompt plus validation details of the
/// current result. The analysis is deterministic and runs locally.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let analysis = model.liveAnalysis
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Detected on this Mac by heuristic analysis (no AI). Updates as you type.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Start typing a prompt to see its objective, requirements and gaps.")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    InspectorGroup(title: "Objective", systemImage: "scope", items: analysis.objective.map { [$0] } ?? [], empty: "No clear objective detected.")
                    InspectorGroup(title: "Detected requirements", systemImage: "checklist", items: analysis.requirements, empty: "None detected.")
                    InspectorGroup(title: "Constraints", systemImage: "hand.raised", items: analysis.constraints, empty: "None detected.")
                    InspectorGroup(title: "Expected output", systemImage: "doc.plaintext", items: analysis.outputExpectations, empty: "Not specified.")
                    InspectorGroup(title: "Missing information", systemImage: "questionmark.circle", items: analysis.missingInformation, empty: "Nothing obvious is missing.", tint: Theme.warning)
                    InspectorGroup(title: "Ambiguities", systemImage: "exclamationmark.bubble", items: analysis.ambiguities.map { "\($0.note) \($0.suggestion)" }, empty: "No vague wording found.", tint: Theme.warning)
                    Text("Domain: \(domainName(analysis.domain)) · \(analysis.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

                if let result = model.result {
                    Divider()
                    InspectorGroup(title: "Improvement summary", systemImage: "sparkles", items: Array(result.report.structuralChanges.prefix(6)), empty: "No changes reported.")
                    InspectorGroup(title: "Validation warnings", systemImage: "checkmark.shield", items: result.warnings.map(\.message), empty: "No warnings.", tint: Theme.danger)
                }
            }
            .padding(14)
        }
        .background(Theme.surface)
    }

    private func domainName(_ domain: PromptDomain) -> String {
        switch domain {
        case .software: "Software"
        case .writing: "Writing"
        case .research: "Research"
        case .dataAnalysis: "Data analysis"
        case .business: "Business"
        case .education: "Education"
        case .creative: "Creative"
        case .general: "General"
        }
    }
}

struct InspectorGroup: View {
    let title: String
    let systemImage: String
    let items: [String]
    let empty: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            if items.isEmpty {
                Text(empty).font(.caption).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
