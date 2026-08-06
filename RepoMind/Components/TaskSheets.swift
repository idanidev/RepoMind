import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Transferable Image (for ShareLink + drag)

struct TransferableImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            item.image.jpegData(compressionQuality: 0.9) ?? Data()
        }
    }
}

// MARK: - Shared Image Helper

private func saveImageToDocuments(image: UIImage, taskId: UUID) -> String? {
    guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let imagePath = documentsPath.appendingPathComponent("task_\(taskId.uuidString).jpg")
    do {
        try data.write(to: imagePath)
        return imagePath.path
    } catch {
        #if DEBUG
        print("Error guardando imagen: \(error)")
        #endif
        return nil
    }
}

// MARK: - Photo Section (shared subview)

private struct TaskPhotoSection: View {
    @Binding var taskImage: UIImage?
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var showDeleteConfirmation: Bool

    var body: some View {
        Section {
            if let image = taskImage {
                VStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onDrag { NSItemProvider(object: image) }
                        .contextMenu {
                            ShareLink(
                                item: TransferableImage(image: image),
                                preview: SharePreview(
                                    String(localized: "photo_section_header"),
                                    image: Image(uiImage: image)
                                )
                            ) {
                                Label("share_image", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                if let data = image.pngData() {
                                    UIPasteboard.general.setData(data, forPasteboardType: "public.png")
                                }
                                ToastManager.shared.show(
                                    String(localized: "image_copied_toast"), style: .success)
                            } label: {
                                Label("copy_image", systemImage: "doc.on.doc")
                            }
                        }

                    HStack {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("photo_change", systemImage: "photo.badge.arrow.down")
                        }
                        Spacer()
                        ShareLink(
                            item: TransferableImage(image: image),
                            preview: SharePreview(
                                String(localized: "photo_section_header"),
                                image: Image(uiImage: image)
                            )
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.image = image
                            ToastManager.shared.show(
                                String(localized: "image_copied_toast"), style: .success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("photo_remove", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.subheadline)
                }
            } else {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text("photo_add")
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        } header: {
            Text("photo_section_header")
        }
    }
}

// MARK: - Task Edit Sheet

struct TaskEditSheet: View {
    @Bindable var task: TaskItem
    var columns: [KanbanColumn]
    /// Called after save with the task and its column *before* editing, so callers can
    /// detect a column change (e.g. to sync the move to GitHub Issues).
    var onSave: ((TaskItem, KanbanColumn?) -> Void)? = nil
    /// Called when the user deletes from this sheet. Routed out rather than handled here: the
    /// sheet used to only drop the task from its column's array, which left the row in the
    /// database — it came back on relaunch — and never closed the linked GitHub issue.
    var onDelete: ((TaskItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var editedContent: String = ""
    @State private var selectedColumn: KanbanColumn?
    @State private var originalColumn: KanbanColumn?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var taskImage: UIImage?
    @State private var showDeleteConfirmation = false
    @State private var showDeleteTaskConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("content") {
                    TextField("description_placeholder", text: $editedContent, axis: .vertical)
                        .lineLimit(3...6)
                }

                TaskPhotoSection(
                    taskImage: $taskImage,
                    selectedPhoto: $selectedPhoto,
                    showDeleteConfirmation: $showDeleteConfirmation
                )

                Section("column") {
                    Picker("column", selection: $selectedColumn) {
                        ForEach(columns) { column in
                            HStack {
                                Circle()
                                    .fill(Color(hex: column.colorHex))
                                    .frame(width: 12, height: 12)
                                Text(column.name)
                            }
                            .tag(column as KanbanColumn?)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteTaskConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("delete_task_button", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("edit_task_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Two items, one per side, so the title sits centred. A third button here pushed
                // it off-centre, and the taller detent below already makes delete visible without
                // needing a duplicate up here.
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") { saveTask() }
                        .disabled(editedContent.isEmpty)
                }
            }
            .onAppear {
                editedContent = task.content
                selectedColumn = task.column
                originalColumn = task.column
                loadExistingImage()
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data)
                    {
                        taskImage = image
                    }
                }
            }
            .alert("photo_delete_confirm_title", isPresented: $showDeleteConfirmation) {
                Button("cancel", role: .cancel) {}
                Button("photo_remove", role: .destructive) {
                    taskImage = nil
                    task.imagePath = nil
                    task.imageData = nil
                }
            }
            // Deleting a task also deletes its GitHub issue, and neither comes back. That was
            // happening on a single tap, with no confirmation at all.
            .alert("delete_task_confirm_title", isPresented: $showDeleteTaskConfirmation) {
                Button("cancel", role: .cancel) {}
                Button("delete_task_button", role: .destructive) { deleteTaskAndDismiss() }
            } message: {
                Text(task.issueNumber == nil
                    ? "delete_task_confirm_message"
                    : "delete_task_confirm_message_issue")
            }
        }
        // Opens tall enough that the whole form — including the delete row at the bottom — is on
        // screen without dragging. `.medium` cut it off exactly where the delete button was.
        .presentationDetents([.fraction(0.85), .large])
        .frame(idealWidth: 480)
    }

    private func loadExistingImage() {
        if let data = task.imageData, let image = UIImage(data: data) {
            taskImage = image
        } else if let imagePath = task.imagePath,
                  let data = FileManager.default.contents(atPath: imagePath),
                  let image = UIImage(data: data)
        {
            taskImage = image
        }
    }

    private func saveTask() {
        task.content = editedContent
        task.column = selectedColumn

        if let image = taskImage {
            task.imageData = image.jpegData(compressionQuality: 0.7)
            if let savedPath = saveImageToDocuments(image: image, taskId: task.id) {
                task.imagePath = savedPath
            }
        } else {
            if let oldPath = task.imagePath {
                try? FileManager.default.removeItem(atPath: oldPath)
            }
            task.imagePath = nil
            task.imageData = nil
        }

        onSave?(task, originalColumn)
        dismiss()
    }

    private func deleteTaskAndDismiss() {
        if let imagePath = task.imagePath {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        onDelete?(task)
        dismiss()
    }
}

// MARK: - Add Task Sheet

struct AddTaskSheet: View {
    @Binding var content: String
    var columns: [KanbanColumn]
    var preselectedColumn: KanbanColumn?

    let onSave: (String, KanbanColumn, Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColumn: KanbanColumn?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var taskImage: UIImage?
    @State private var showDeleteConfirmation = false
    @FocusState private var isContentFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("task_section") {
                    TextField("task_placeholder", text: $content, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isContentFocused)
                }

                TaskPhotoSection(
                    taskImage: $taskImage,
                    selectedPhoto: $selectedPhoto,
                    showDeleteConfirmation: $showDeleteConfirmation
                )

                Section("column") {
                    Picker("column", selection: $selectedColumn) {
                        ForEach(columns) { column in
                            Text(column.name).tag(column as KanbanColumn?)
                        }
                    }
                }
            }
            .navigationTitle("new_task_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("create") {
                        if let col = selectedColumn {
                            let imageData = taskImage?.jpegData(compressionQuality: 0.7)
                            onSave(content, col, imageData)
                            dismiss()
                        }
                    }
                    .disabled(content.isEmpty || selectedColumn == nil)
                }
            }
            // `.defaultFocus` is the API meant for this: when it lands, the keyboard rises with
            // the sheet and there is no visible pause. Inside a sheet it is unreliable though —
            // SwiftUI often evaluates it before the field has joined the view hierarchy and then
            // the keyboard never opens at all, which is worse than the lag it was fixing. So keep
            // it for the good case and re-assert afterwards for the bad one; when it already
            // worked, the check below does nothing.
            .defaultFocus($isContentFocused, true)
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                if !isContentFocused { isContentFocused = true }
            }
            .onAppear {
                selectedColumn = preselectedColumn ?? columns.first
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data)
                    {
                        taskImage = image
                    }
                }
            }
            .alert("photo_delete_confirm_title", isPresented: $showDeleteConfirmation) {
                Button("cancel", role: .cancel) {}
                Button("photo_remove", role: .destructive) {
                    taskImage = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
        .frame(idealWidth: 480)
    }
}
