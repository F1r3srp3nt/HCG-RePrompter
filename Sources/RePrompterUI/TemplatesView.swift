import SwiftUI
import RePrompterCore

/// Browse, edit and use prompt templates.
struct TemplatesView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?
    @State private var draft: PromptTemplate?
    @State private var pendingDeletion: PromptTemplate?
    @State private var confirmReplaceWorkspace: PromptTemplate?

    var body: some View {
        let templates = model.allTemplates
        HSplitView {
            List(selection: $selectedID) {
                ForEach(TemplateCategory.allCases) { category in
                    let items = templates.filter { $0.category == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { template in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(template.name).lineLimit(1)
                                        if !template.isBuiltIn {
                                            Image(systemName: "person.crop.circle")
                                                .font(.caption2)
                                                .foregroundStyle(Theme.violet)
                                                .accessibilityLabel("Your template")
                                        } else if model.templates.isModified(template.id) {
                                            Image(systemName: "pencil.circle")
                                                .font(.caption2)
                                                .foregroundStyle(Theme.textSecondary)
                                                .accessibilityLabel("Edited")
                                        }
                                    }
                                    if !template.summary.isEmpty {
                                        Text(template.summary)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 2)
                                .tag(template.id)
                            }
                        } header: {
                            Label(category.displayName, systemImage: category.symbolName)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 420, maxHeight: .infinity)

            Group {
                if let binding = Binding($draft) {
                    TemplateEditor(
                        draft: binding,
                        original: templates.first { $0.id == binding.wrappedValue.id },
                        isModifiedBuiltIn: model.templates.isModified(binding.wrappedValue.id),
                        onUse: { useTemplate($0) },
                        onDelete: { pendingDeletion = $0 },
                        onDuplicate: { selectedID = model.duplicateTemplate($0).id }
                    )
                } else {
                    EmptyStateView(
                        title: "Templates",
                        message: "Pick a template to view or edit it, then press “Use Template” to start a prompt from it.",
                        systemImage: "doc.on.doc"
                    )
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Templates")
        .onChange(of: selectedID) {
            draft = selectedID.flatMap { id in model.allTemplates.first { $0.id == id } }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    let template = model.createTemplate()
                    selectedID = template.id
                } label: {
                    Label("New Template", systemImage: "plus")
                }
                .help("Create a new template")
                Menu {
                    Button("Restore Built-in Templates") { model.restoreBuiltInTemplates() }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            pendingDeletion?.isBuiltIn == true ? "Hide “\(pendingDeletion?.name ?? "")”?" : "Delete “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button(pendingDeletion?.isBuiltIn == true ? "Hide" : "Delete", role: .destructive) {
                if let template = pendingDeletion {
                    model.deleteTemplate(template)
                    selectedID = nil
                    draft = nil
                }
                pendingDeletion = nil
            }
        } message: {
            Text(pendingDeletion?.isBuiltIn == true
                 ? "Built-in templates can be restored later from the More menu."
                 : "This template is permanently deleted.")
        }
        .confirmationDialog(
            "Replace the current prompt?",
            isPresented: Binding(get: { confirmReplaceWorkspace != nil }, set: { if !$0 { confirmReplaceWorkspace = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace") {
                if let template = confirmReplaceWorkspace { model.useTemplate(template) }
                confirmReplaceWorkspace = nil
            }
        } message: {
            Text("The workspace contains a prompt. Using this template starts a new prompt; the current one stays in History if it was enhanced.")
        }
    }

    private func useTemplate(_ template: PromptTemplate) {
        if model.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.useTemplate(template)
        } else {
            confirmReplaceWorkspace = template
        }
    }
}

struct TemplateEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: PromptTemplate
    let original: PromptTemplate?
    let isModifiedBuiltIn: Bool
    let onUse: (PromptTemplate) -> Void
    let onDelete: (PromptTemplate) -> Void
    let onDuplicate: (PromptTemplate) -> Void

    private var isDirty: Bool { original.map { $0 != draft } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Template name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .accessibilityLabel("Template name")
                if draft.isBuiltIn {
                    Badge(text: isModifiedBuiltIn ? "Built-in · edited" : "Built-in", tint: Theme.textSecondary)
                }
            }
            HStack(spacing: 12) {
                Picker("Category", selection: $draft.category) {
                    ForEach(TemplateCategory.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 260)
                Picker("Suggested mode", selection: $draft.suggestedMode) {
                    ForEach(EnhancementMode.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 260)
            }
            TextField("Short description", text: $draft.summary)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Template description")
            PromptEditor(text: $draft.body, placeholder: "Template text. Use {{placeholders}} for details that change.", accessibilityLabel: "Template text")

            let placeholders = draft.placeholders
            if !placeholders.isEmpty {
                HStack(spacing: 6) {
                    Text("Placeholders:").font(.caption).foregroundStyle(Theme.textSecondary)
                    ForEach(placeholders.prefix(6), id: \.self) { Badge(text: $0, tint: Theme.violet) }
                    if placeholders.count > 6 {
                        Text("+\(placeholders.count - 6)").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            HStack {
                Button(draft.isBuiltIn ? "Hide…" : "Delete…", role: .destructive) { onDelete(draft) }
                if isModifiedBuiltIn {
                    Button("Reset to Original") {
                        model.resetTemplate(draft)
                        if let restored = model.allTemplates.first(where: { $0.id == draft.id }) { draft = restored }
                    }
                }
                Button("Duplicate") { onDuplicate(draft) }
                    .help("Create an editable copy")
                Spacer()
                if isDirty {
                    Button("Revert") { if let original { draft = original } }
                    Button("Save") { model.saveTemplate(draft) }
                        .help("Save template changes")
                }
                Button("Use Template") { onUse(draft) }
                    .buttonStyle(.borderedProminent)
                    .help("Start a new prompt from this template")
            }
        }
        .padding(16)
    }
}
