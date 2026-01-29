import SwiftData
import SwiftUI

// MARK: - Kanban View (Vertical Mobile-Friendly)

struct KanbanView: View {
    let project: ProjectRepo

    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TaskItem]

    @State private var voiceManager = VoiceManager()
    @State private var editingTask: TaskItem?
    @State private var showEditSheet = false
    @State private var showAddSheet = false
    @State private var draggedTask: TaskItem?
    @State private var newTaskContent = ""
    @State private var newTaskStatus: TaskStatus = .todo

    init(project: ProjectRepo) {
        self.project = project
        let projectID = project.persistentModelID
        self._allTasks = Query(
            filter: #Predicate<TaskItem> { task in
                task.project?.persistentModelID == projectID
            },
            sort: [SortDescriptor(\TaskItem.createdAt, order: .reverse)]
        )
    }

    private func tasks(for status: TaskStatus) -> [TaskItem] {
        allTasks.filter { $0.status == status }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(spacing: 24, pinnedViews: .sectionHeaders) {
                    ForEach(TaskStatus.allCases) { status in
                        KanbanSection(
                            status: status,
                            tasks: tasks(for: status),
                            draggedTask: $draggedTask,
                            onDrop: { task in
                                moveTask(task, to: status)
                            },
                            onEdit: { task in
                                editingTask = task
                                showEditSheet = true
                            },
                            onDelete: { task in
                                deleteTask(task)
                            },
                            onMove: { task, newStatus in
                                moveTask(task, to: newStatus)
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }

            // Voice FAB
            VoiceFAB(voiceManager: voiceManager) {
                createTaskFromVoice()
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newTaskContent = ""
                    newTaskStatus = .todo
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let task = editingTask {
                TaskEditSheet(task: task)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet(
                content: $newTaskContent,
                status: $newTaskStatus,
                onSave: { content, status in
                    createTask(content: content, status: status)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .task {
            await voiceManager.requestPermissions()
        }
    }

    // MARK: - Actions

    private func moveTask(_ task: TaskItem, to status: TaskStatus) {
        guard task.status != status else { return }
        withAnimation(.snappy(duration: 0.35)) {
            task.status = status
        }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    private func deleteTask(_ task: TaskItem) {
        withAnimation(.easeOut(duration: 0.3)) {
            context.delete(task)
        }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    private func createTask(content: String, status: TaskStatus) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let task = TaskItem(content: content, status: status, project: project)
        withAnimation(.snappy) {
            context.insert(task)
        }
    }

    private func createTaskFromVoice() {
        let text = voiceManager.transcribedText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let task = TaskItem(content: text, status: .brainstorming, audioPath: "voice", project: project)
        withAnimation(.snappy) {
            context.insert(task)
        }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Kanban Section (Vertical Column)

struct KanbanSection: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    @Binding var draggedTask: TaskItem?
    let onDrop: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onMove: (TaskItem, TaskStatus) -> Void

    @State private var isTargeted = false

    var body: some View {
        Section {
            if tasks.isEmpty {
                emptySection
            } else {
                ForEach(tasks) { task in
                    TaskCard(task: task)
                        .draggable(task.id.uuidString) {
                            TaskCard(task: task)
                                .frame(width: 300)
                                .onAppear { draggedTask = task }
                        }
                        .contextMenu {
                            // Move to other columns
                            ForEach(TaskStatus.allCases.filter { $0 != status }) { targetStatus in
                                Button {
                                    onMove(task, targetStatus)
                                } label: {
                                    Label("Mover a \(targetStatus.displayName)", systemImage: targetStatus.iconName)
                                }
                            }

                            Divider()

                            Button {
                                onEdit(task)
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                onDelete(task)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.5).combined(with: .opacity)
                        ))
                }
            }
        } header: {
            sectionHeader
        }
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let task = draggedTask,
                  task.id.uuidString == idString else {
                return false
            }
            onDrop(task)
            draggedTask = nil
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTargeted = targeted
            }
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: status.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(sectionColor)

            Text(status.sectionHeader)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Text("\(tasks.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .bottom) {
                    if isTargeted {
                        Rectangle()
                            .fill(sectionColor)
                            .frame(height: 2)
                    }
                }
        }
    }

    private var emptySection: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("Arrastra tareas aqui")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    private var sectionColor: Color {
        switch status {
        case .brainstorming: .purple
        case .todo: .blue
        case .done: .green
        }
    }
}

// MARK: - Task Card

struct TaskCard: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)

            HStack {
                if task.audioPath != nil {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(task.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
    }
}

// MARK: - Voice FAB

struct VoiceFAB: View {
    @Bindable var voiceManager: VoiceManager
    let onComplete: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var buttonScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 12) {
            // Transcription preview
            if voiceManager.isRecording && !voiceManager.transcribedText.isEmpty {
                Text(voiceManager.transcribedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // FAB button
            Button {
                // Immediate haptic on press
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()

                // Immediate scale animation
                withAnimation(.spring(duration: 0.15)) {
                    buttonScale = 0.85
                }
                withAnimation(.spring(duration: 0.2).delay(0.1)) {
                    buttonScale = 1.0
                }

                Task {
                    if voiceManager.isRecording {
                        voiceManager.stopRecording()
                        onComplete()
                    } else {
                        await voiceManager.toggleRecording()
                    }
                }
            } label: {
                ZStack {
                    // Pulse ring
                    if voiceManager.isRecording {
                        Circle()
                            .fill(Color.red.opacity(0.2))
                            .scaleEffect(pulseScale)
                            .frame(width: 64, height: 64)
                    }

                    // Audio level ring
                    if voiceManager.isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 3)
                            .scaleEffect(1.0 + CGFloat(voiceManager.audioLevel) * 0.4)
                            .frame(width: 56, height: 56)
                    }

                    // Main button
                    Circle()
                        .fill(voiceManager.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 56, height: 56)
                        .shadow(color: (voiceManager.isRecording ? Color.red : Color.accentColor).opacity(0.35), radius: 10, y: 4)

                    Image(systemName: voiceManager.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .scaleEffect(buttonScale)
            }
            .buttonStyle(.plain)
        }
        .animation(.spring(duration: 0.4), value: voiceManager.isRecording)
        .animation(.spring(duration: 0.3), value: voiceManager.transcribedText)
        .onChange(of: voiceManager.isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.4
                }
            } else {
                pulseScale = 1.0
            }
        }
        .alert(
            "Permiso Requerido",
            isPresented: .init(
                get: { voiceManager.errorMessage != nil },
                set: { if !$0 { voiceManager.errorMessage = nil } }
            )
        ) {
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(voiceManager.errorMessage ?? "")
        }
    }
}

// MARK: - Task Edit Sheet

struct TaskEditSheet: View {
    @Bindable var task: TaskItem
    @Environment(\.dismiss) private var dismiss

    @State private var editedContent: String = ""
    @State private var editedStatus: TaskStatus = .todo

    var body: some View {
        NavigationStack {
            Form {
                Section("Contenido") {
                    TextField("Descripcion de la tarea", text: $editedContent, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Estado") {
                    Picker("Estado", selection: $editedStatus) {
                        ForEach(TaskStatus.allCases) { status in
                            Label(status.displayName, systemImage: status.iconName)
                                .tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if task.audioPath != nil {
                    Section("Origen") {
                        Label("Creado desde nota de voz", systemImage: "waveform")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Editar Tarea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        task.content = editedContent
                        task.status = editedStatus
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                editedContent = task.content
                editedStatus = task.status
            }
        }
    }
}

// MARK: - Add Task Sheet

struct AddTaskSheet: View {
    @Binding var content: String
    @Binding var status: TaskStatus
    let onSave: (String, TaskStatus) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Contenido") {
                    TextField("Que hay que hacer?", text: $content, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Columna") {
                    Picker("Estado", selection: $status) {
                        ForEach(TaskStatus.allCases) { status in
                            Label(status.displayName, systemImage: status.iconName)
                                .tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Nueva Tarea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        onSave(content, status)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
