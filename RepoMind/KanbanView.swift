import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kanban View (Vertical Mobile-Friendly)

struct KanbanView: View {
    @Bindable var project: ProjectRepo

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TaskItem]

    @State private var voiceManager = VoiceManager()
    @State private var editingTask: TaskItem?

    // Column Management
    @State private var showAddColumnSheet = false
    @State private var newColumnName = ""
    @State private var draggingTask: TaskItem?

    // Task Creation
    @State private var showAddTaskSheet = false
    @State private var newTaskContent = ""
    @State private var targetColumnForNewTask: KanbanColumn?

    init(project: ProjectRepo) {
        self.project = project
        let projectID = project.persistentModelID
        self._tasks = Query(
            filter: #Predicate<TaskItem> { task in
                task.project?.persistentModelID == projectID
            },
            sort: [SortDescriptor(\TaskItem.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Horizontal scroll for columns
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(
                        project.columns.sorted(by: { $0.orderIndex < $1.orderIndex })
                    ) { column in
                        KanbanColumnView(
                            column: column,
                            tasks: tasks.filter { $0.column == column },
                            draggedTask: $draggingTask,
                            onDropTask: { task in
                                moveTask(task, to: column)
                            },
                            onAdd: {
                                targetColumnForNewTask = column
                                newTaskContent = ""
                                showAddTaskSheet = true
                            },
                            onEditTask: { task in
                                editingTask = task
                            },
                            onDeleteTask: { task in
                                deleteTask(task)
                            },
                            onDeleteColumn: {
                                deleteColumn(column)
                            }
                        )
                        .frame(width: 320)  // Fixed width for columns
                    }

                    // Add Column Button
                    addColumnButton
                }
                .padding()
                .padding(.bottom, 100)  // Space for FAB
            }
            // Voice FAB
            VoiceFAB(voiceManager: voiceManager) {
                createTaskFromVoice()
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showAddColumnSheet = true }) {
                    Label(
                        "Añadir Columna", systemImage: "rectangle.stack.badge.plus")
                }
            }
        }
        // Sheets
        .sheet(item: $editingTask) { task in
            TaskEditSheet(task: task, columns: project.columns)
        }
        .sheet(isPresented: $showAddTaskSheet) {
            AddTaskSheet(
                content: $newTaskContent,
                columns: project.columns,
                preselectedColumn: targetColumnForNewTask,
                onSave: { content, column in
                    createTask(content: content, column: column)
                }
            )
        }
        .alert("Nueva Columna", isPresented: $showAddColumnSheet) {
            TextField("Nombre de columna", text: $newColumnName)
            Button("Cancelar", role: .cancel) { newColumnName = "" }
            Button("Crear") {
                createColumn(name: newColumnName)
                newColumnName = ""
            }
        }
        .task {
            await voiceManager.checkAndRequestPermissions()
            initializeDefaultColumnsIfNeeded()
        }
    }

    // MARK: - Actions

    private func initializeDefaultColumnsIfNeeded() {
        guard project.columns.isEmpty else { return }

        let defaults = ["Por hacer", "En progreso", "Hecho"]
        for (index, name) in defaults.enumerated() {
            let col = KanbanColumn(
                name: name, orderIndex: index, project: project)
            context.insert(col)
        }
    }

    private func createColumn(name: String) {
        let index = project.columns.count
        let col = KanbanColumn(name: name, orderIndex: index, project: project)
        withAnimation {
            context.insert(col)
        }
    }

    private func deleteColumn(_ column: KanbanColumn) {
        withAnimation {
            context.delete(column)
        }
    }

    private func moveTask(_ task: TaskItem, to column: KanbanColumn) {
        guard task.column != column else { return }
        withAnimation(.snappy) {
            task.column = column
        }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    private func deleteTask(_ task: TaskItem) {
        withAnimation {
            context.delete(task)
        }
    }

    private func createTask(content: String, column: KanbanColumn) {
        let task = TaskItem(content: content, column: column, project: project)
        withAnimation {
            context.insert(task)
        }
    }

    private func createTaskFromVoice() {
        let text = voiceManager.transcribedText
        guard !text.isEmpty,
            let firstColumn = project.columns.sorted(by: {
                $0.orderIndex < $1.orderIndex
            }).first
        else { return }

        createTask(content: text, column: firstColumn)
    }

    private var addColumnButton: some View {
        Button(action: { showAddColumnSheet = true }) {
            VStack {
                Image(systemName: "plus")
                    .font(.largeTitle)
                Text("Añadir Columna")
                    .font(.headline)
            }
            .frame(width: 320, height: 200)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundColor(.secondary)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kanban Column View

struct KanbanColumnView: View {
    @Bindable var column: KanbanColumn
    let tasks: [TaskItem]
    @Binding var draggedTask: TaskItem?

    let onDropTask: (TaskItem) -> Void
    let onAdd: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteColumn: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    withAnimation {
                        column.isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: column.isCollapsed ? "chevron.right" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Text(column.name)
                    .font(.headline)

                Spacer()

                if !column.isCollapsed {
                    Text("\(tasks.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                Menu {
                    Button(role: .destructive, action: onDeleteColumn) {
                        Label("Eliminar Columna", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(8)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            // Drop target for empty column header
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first,
                    let task = draggedTask,
                    task.id.uuidString == idString
                else { return false }
                onDropTask(task)
                return true
            } isTargeted: { targeted in
                withAnimation { isTargeted = targeted }
            }

            // Tasks List
            if !column.isCollapsed {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if tasks.isEmpty {
                            ContentUnavailableView {
                                Label("Vacio", systemImage: "tray")
                            } description: {
                                Text("Arrastra tareas aqui")
                            }
                            .frame(height: 150)
                            .opacity(0.5)
                        } else {
                            ForEach(tasks) { task in
                                TaskCard(task: task)
                                    .onDrag {
                                        draggedTask = task
                                        // Pass the UUID string as the dragged item
                                        return NSItemProvider(
                                            object: task.id.uuidString as NSString)
                                    }
                                    .contextMenu {
                                        Button {
                                            onEditTask(task)
                                        } label: {
                                            Label("Editar", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            onDeleteTask(task)
                                        } label: {
                                            Label("Eliminar", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)
                .background(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                .dropDestination(for: String.self) { items, _ in
                    guard let idString = items.first,
                        let task = draggedTask,
                        task.id.uuidString == idString
                    else { return false }
                    onDropTask(task)
                    return true
                } isTargeted: { targeted in
                    withAnimation { isTargeted = targeted }
                }
            }

            // Add Button Footer
            if !column.isCollapsed {
                Button(action: onAdd) {
                    Label("Añadir tarea", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Task Card

struct TaskCard: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(task.content))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            if task.audioPath != nil {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color(.label).opacity(0.06), radius: 6, x: 0, y: 3)
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
                        .shadow(
                            color: (voiceManager.isRecording ? Color.red : Color.accentColor)
                                .opacity(0.35), radius: 10, y: 4)

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
    var columns: [KanbanColumn]
    @Environment(\.dismiss) private var dismiss

    @State private var editedContent: String = ""
    @State private var selectedColumn: KanbanColumn?

    var body: some View {
        NavigationStack {
            Form {
                Section("Contenido") {
                    TextField("Descripcion", text: $editedContent, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Columna") {
                    Picker("Columna", selection: $selectedColumn) {
                        ForEach(columns) { column in
                            Text(column.name).tag(column as KanbanColumn?)
                        }
                    }
                }
            }
            .navigationTitle("Editar Tarea")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        task.content = editedContent
                        task.column = selectedColumn
                        dismiss()
                    }
                    .disabled(editedContent.isEmpty)
                }
            }
            .onAppear {
                editedContent = task.content
                selectedColumn = task.column
            }
        }
    }
}

// MARK: - Add Task Sheet

struct AddTaskSheet: View {
    @Binding var content: String
    var columns: [KanbanColumn]
    var preselectedColumn: KanbanColumn?

    let onSave: (String, KanbanColumn) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColumn: KanbanColumn?

    var body: some View {
        NavigationStack {
            Form {
                Section("Tarea") {
                    TextField("Algo por hacer...", text: $content, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Columna") {
                    Picker("Columna", selection: $selectedColumn) {
                        ForEach(columns) { column in
                            Text(column.name).tag(column as KanbanColumn?)
                        }
                    }
                }
            }
            .navigationTitle("Nueva Tarea")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        if let col = selectedColumn {
                            onSave(content, col)
                            dismiss()
                        }
                    }
                    .disabled(content.isEmpty || selectedColumn == nil)
                }
            }
            .onAppear {
                if let preselectedColumn {
                    selectedColumn = preselectedColumn
                } else {
                    selectedColumn = columns.first
                }
            }
        }
    }
}
