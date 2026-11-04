import SwiftUI
import RePrompterCore
import RePrompterPersistence

/// The Library (saved prompts) and All Prompts (including older entries
/// that were never saved to the library).
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let scope: PromptLibrary.Scope

    @State private var selectedID: UUID?
    @State private var collectionFilter: String?
    @State private var renaming: PromptRecord?
    @State private var renameText = ""
    @State private var movingToCollection: PromptRecord?
    @State private var collectionText = ""
    @State private var pendingDeletion: PromptRecord?
    @State private var confirmClearHistory = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        let records = model.records(in: scope, query: model.librarySearchText, collection: scope == .saved ? collectionFilter : nil)
        // A fixed-width list beside a flexible preview: no split view and no
        // minimum widths, so the window can always be resized safely.
        HStack(spacing: 0) {
            Group {
                if records.isEmpty {
                    EmptyStateView(
                        title: model.librarySearchText.isEmpty ? emptyTitle : "No matches",
                        message: model.librarySearchText.isEmpty ? emptyMessage : "No prompts match “\(model.librarySearchText)”.",
                        systemImage: scope == .saved ? "bookmark" : "clock"
                    )
                } else {
                    List(selection: $selectedID) {
                        ForEach(records) { record in
                            RecordRow(record: record).tag(record.id)
                        }
                    }
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let id = ids.first, let record = model.library.record(id: id) {
                            contextMenu(for: record)
                        }
                    } primaryAction: { ids in
                        if let id = ids.first, let record = model.library.record(id: id) { model.requestOpen(record) }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .onDeleteCommand {
                        if let id = selectedID { pendingDeletion = model.library.record(id: id) }
                    }
                }
            }
            .frame(width: 280)
            .frame(maxHeight: .infinity)

            Divider()

            Group {
                if let id = selectedID, let record = model.library.record(id: id) {
                    RecordPreview(record: record, onDelete: { pendingDeletion = record })
                } else {
                    EmptyStateView(title: "Select a prompt", message: "Choose a prompt to preview it. Double-click or press Open to continue working on it.", systemImage: "text.magnifyingglass")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(scope == .saved ? "Library" : "All Prompts")
        .searchable(text: $model.librarySearchText, placement: .toolbar, prompt: "Search prompts")
        .searchFocused($searchFocused)
        .onAppear {
            if model.pendingSearchFocus {
                searchFocused = true
                model.pendingSearchFocus = false
            }
        }
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
            model.pendingSearchFocus = false
        }
        .toolbar {
            if scope == .saved, !model.library.collections.isEmpty {
                ToolbarItem {
                    Picker("Collection", selection: $collectionFilter) {
                        Text("All Collections").tag(String?.none)
                        ForEach(model.library.collections, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .help("Filter by collection")
                }
            }
            if scope == .all {
                ToolbarItem {
                    Button {
                        confirmClearHistory = true
                    } label: {
                        Label("Remove Unsaved Entries", systemImage: "trash")
                    }
                    .help("Delete entries from earlier versions that are not in your library")
                    .disabled(model.unsavedHistoryCount == 0)
                }
            }
        }
        .alert("Rename Prompt", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let record = renaming { model.renameRecord(record.id, to: renameText) }
                renaming = nil
            }
        }
        .alert("Move to Collection", isPresented: Binding(get: { movingToCollection != nil }, set: { if !$0 { movingToCollection = nil } })) {
            TextField("Collection name (leave empty for none)", text: $collectionText)
            Button("Cancel", role: .cancel) { movingToCollection = nil }
            Button("Move") {
                if let record = movingToCollection {
                    if !record.isSaved { model.setSaved(record.id, true) }
                    model.setCollection(record.id, collectionText)
                }
                movingToCollection = nil
            }
        } message: {
            Text("Collections organize your saved prompts.")
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.title ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let record = pendingDeletion {
                    model.deleteRecords([record.id])
                    if selectedID == record.id { selectedID = nil }
                }
                pendingDeletion = nil
            }
        } message: {
            Text("The prompt is removed from your library on this Mac. This cannot be undone. If it is open in the workspace, its text stays there as an unsaved draft.")
        }
        .confirmationDialog("Remove unsaved entries?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Delete \(model.unsavedHistoryCount) Entries", role: .destructive) {
                model.clearHistory()
                selectedID = nil
            }
        } message: {
            Text("Entries that are not in your library are permanently deleted. Saved prompts are kept.")
        }
    }

    private var emptyTitle: String { scope == .saved ? "Your library is empty" : "No prompts yet" }
    private var emptyMessage: String {
        "Write a prompt in the workspace and press ⌘S to save it here."
    }

    @ViewBuilder
    private func contextMenu(for record: PromptRecord) -> some View {
        Button("Open in Workspace") { model.requestOpen(record) }
        Button("Copy Original Text") { model.copyRecord(record) }
        Divider()
        Button("Rename…") {
            renameText = record.title
            renaming = record
        }
        Button("Duplicate") { model.duplicateRecord(record.id) }
        if record.isSaved {
            Button("Move to Collection…") {
                collectionText = record.collection ?? ""
                movingToCollection = record
            }
            Button("Remove from Library") { model.setSaved(record.id, false) }
        } else {
            Button("Save to Library") { model.setSaved(record.id, true) }
        }
        Menu("Export") {
            ForEach(ExportFormat.allCases) { format in
                Button(format.displayName) { model.exportRecord(record, as: format) }
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { pendingDeletion = record }
    }
}

struct RecordRow: View {
    @Environment(AppModel.self) private var model
    let record: PromptRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if record.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Saved")
                }
                Text(record.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(record.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(record.originalPrompt)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            if !record.isSaved || record.collection != nil {
                HStack(spacing: 6) {
                    if !record.isSaved {
                        Badge(text: "Not in library", tint: Theme.textSecondary)
                    }
                    if let collection = record.collection {
                        Badge(text: collection, systemImage: "folder", tint: Theme.accentSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open in Workspace") { model.requestOpen(record) }
    }
}

struct RecordPreview: View {
    @Environment(AppModel.self) private var model
    let record: PromptRecord
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Open") { model.requestOpen(record) }
                        .buttonStyle(.borderedProminent)
                        .help("Open in the workspace")
                }
                Text("Created \(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · Updated \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)

                PreviewBlock(title: "Original Prompt", text: record.originalPrompt)

                HStack {
                    Button("Copy Original") { model.copyRecord(record) }
                    Menu("Export") {
                        ForEach(ExportFormat.allCases) { format in
                            Button(format.displayName) { model.exportRecord(record, as: format) }
                        }
                    }
                    .fixedSize()
                    Spacer(minLength: 8)
                    Button("Delete…", role: .destructive, action: onDelete)
                }
            }
            .padding(16)
        }
    }
}

struct PreviewBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(Theme.editorFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 10)
        }
    }
}
