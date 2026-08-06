import SwiftData
import SwiftUI

/// Picks the folder a repository belongs to, and manages the folder list while it is open.
///
/// Folder management lives here rather than in its own screen because creating a folder is almost
/// always something you realise you need *while* filing a repo, not before.
struct FolderPickerSheet: View {
    let repo: ProjectRepo

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RepoFolder.orderIndex) private var folders: [RepoFolder]

    @State private var newFolderName = ""
    @State private var folderPendingDeletion: RepoFolder?
    @State private var folderBeingRenamed: RepoFolder?
    @State private var renameText = ""

    private static let palette = [
        "#5B6CFF", "#3FB950", "#D29922", "#F85149", "#A371F7", "#39C5CF",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        repo.folder = nil
                        save()
                    } label: {
                        HStack {
                            Label("folder_none", systemImage: "tray")
                            Spacer()
                            if repo.folder == nil {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)

                    ForEach(folders) { folder in
                        Button {
                            repo.folder = folder
                            save()
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color(hex: folder.colorHex))
                                Text(folder.name)
                                Spacer()
                                Text("\(folder.repos?.count ?? 0)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                if repo.folder?.id == folder.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                folderPendingDeletion = folder
                            } label: {
                                Label("delete_task", systemImage: "trash")
                            }
                            Button {
                                renameText = folder.name
                                folderBeingRenamed = folder
                            } label: {
                                Label("folder_rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text("folder_picker_section")
                }

                Section {
                    HStack {
                        TextField("folder_new_placeholder", text: $newFolderName)
                            .submitLabel(.done)
                            .onSubmit(createFolder)
                        Button("folder_create", action: createFolder)
                            .disabled(trimmedNewName.isEmpty)
                    }
                } header: {
                    Text("folder_new_section")
                }
            }
            .navigationTitle("folder_picker_title")
            #if !targetEnvironment(macCatalyst)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("done_button") { dismiss() }
                }
            }
            .alert("folder_delete_confirm_title", isPresented: deletionBinding) {
                Button("cancel_button", role: .cancel) { folderPendingDeletion = nil }
                Button("delete_task", role: .destructive) { deletePendingFolder() }
            } message: {
                Text("folder_delete_confirm_message")
            }
            .alert("folder_rename", isPresented: renameBinding) {
                TextField("folder_new_placeholder", text: $renameText)
                Button("cancel_button", role: .cancel) { folderBeingRenamed = nil }
                Button("save") { commitRename() }
            }
        }
        .presentationDetents([.medium, .large])
        .frame(idealWidth: 420)
    }

    // MARK: - Actions

    private var trimmedNewName: String {
        newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { folderPendingDeletion != nil },
            set: { if !$0 { folderPendingDeletion = nil } })
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { folderBeingRenamed != nil },
            set: { if !$0 { folderBeingRenamed = nil } })
    }

    private func createFolder() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }

        let folder = RepoFolder(
            name: name,
            colorHex: Self.palette[folders.count % Self.palette.count],
            orderIndex: (folders.map(\.orderIndex).max() ?? -1) + 1
        )
        context.insert(folder)
        repo.folder = folder
        newFolderName = ""
        save()
    }

    /// Removes the folder only. The repos inside it are untouched and reappear at the top level.
    private func deletePendingFolder() {
        guard let folder = folderPendingDeletion else { return }
        context.delete(folder)
        folderPendingDeletion = nil
        try? context.save()
    }

    private func commitRename() {
        guard let folder = folderBeingRenamed else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { folder.name = name }
        folderBeingRenamed = nil
        try? context.save()
    }

    private func save() {
        try? context.save()
    }
}
