import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kanban View (Vertical Mobile-Friendly)

// MARK: - Kanban View (Vertical Mobile-Friendly)

struct KanbanView: View {
    @Bindable var project: ProjectRepo
    @State private var viewModel: KanbanViewModel?
    @State private var viewMode: ViewMode = .board

    enum ViewMode: String, CaseIterable {
        case board = "Tablero"
        case list = "Lista"
    }

    @Environment(\.modelContext) private var context
    // Removed @Query tasks - using relationships instead for performance

    init(project: ProjectRepo) {
        self.project = project
        // Tasks query removed
    }

    var body: some View {
        Group {
            if let viewModel {
                switch viewMode {
                case .board:
                    boardContent(viewModel: viewModel)
                case .list:
                    listContent(viewModel: viewModel)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    // View Toggle Button
                    Button(action: {
                        withAnimation {
                            viewMode = (viewMode == .board) ? .list : .board
                        }
                    }) {
                        Label(
                            "Cambiar Vista",
                            systemImage: viewMode == .board ? "list.bullet" : "rectangle.grid.1x2")
                    }

                    Button(action: { viewModel?.showAddColumnSheet = true }) {
                        Label("Añadir Columna", systemImage: "rectangle.stack.badge.plus")
                    }
                }
            }
        }
        .sheet(
            item: Binding(
                get: { viewModel?.editingTask },
                set: { viewModel?.editingTask = $0 }
            )
        ) { task in
            TaskEditSheet(task: task, columns: project.columns ?? [])
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel?.showAddTaskSheet ?? false },
                set: { viewModel?.showAddTaskSheet = $0 }
            )
        ) {
            if let viewModel {
                @Bindable var vm = viewModel
                AddTaskSheet(
                    content: $vm.newTaskContent,
                    columns: project.columns ?? [],
                    preselectedColumn: viewModel.targetColumnForNewTask,
                    onSave: { content, column in
                        viewModel.createTask(content: content, column: column)
                    }
                )
            }
        }
        .alert(
            "Nueva Columna",
            isPresented: Binding(
                get: { viewModel?.showAddColumnSheet ?? false },
                set: { viewModel?.showAddColumnSheet = $0 }
            )
        ) {
            TextField(
                "Nombre de columna",
                text: Binding(
                    get: { viewModel?.newColumnName ?? "" },
                    set: { viewModel?.newColumnName = $0 }
                ))
            Button("Cancelar", role: .cancel) { viewModel?.newColumnName = "" }
            Button("Crear") {
                viewModel?.createColumn()
            }
        }
        .alert(
            "Renombrar Columna",
            isPresented: Binding(
                get: { viewModel?.showRenameColumnAlert ?? false },
                set: { viewModel?.showRenameColumnAlert = $0 }
            )
        ) {
            TextField(
                "Nombre de columna",
                text: Binding(
                    get: { viewModel?.renameColumnText ?? "" },
                    set: { viewModel?.renameColumnText = $0 }
                ))
            Button("Cancelar", role: .cancel) {
                viewModel?.renameColumnText = ""
                viewModel?.columnToRename = nil
            }
            Button("Guardar") {
                viewModel?.renameColumn()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = KanbanViewModel(project: project, modelContext: context)
            }
            await viewModel?.checkVoicePermissions()
            viewModel?.initializeDefaultColumnsIfNeeded()
        }
    }

    private func boardContent(viewModel: KanbanViewModel) -> some View {
        @Bindable var viewModel = viewModel
        // Horizontal scroll for columns
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(
                    (project.columns ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
                ) { column in
                    KanbanColumnView(
                        column: column,
                        draggedTask: $viewModel.draggingTask,
                        onDropTask: { task in
                            viewModel.moveTask(task, to: column)
                        },
                        onAdd: {
                            viewModel.prepareAddTask(for: column)
                        },
                        onEditTask: { task in
                            viewModel.editingTask = task
                        },
                        onDeleteTask: { task in
                            viewModel.deleteTask(task)
                        },
                        onDeleteColumn: {
                            viewModel.deleteColumn(column)
                        },
                        onRenameColumn: {
                            viewModel.startRenaming(column)
                        }
                    )
                    .frame(width: 320)
                }

                // Add Column Button
                addColumnButton(viewModel: viewModel)
            }
            .padding()
            .padding(.bottom, 100)
        }
        .overlay(alignment: .bottomTrailing) {
            VoiceFAB(voiceManager: viewModel.voiceManager) {
                viewModel.createTaskFromVoice()
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
    }

    private func addColumnButton(viewModel: KanbanViewModel) -> some View {
        Button(action: { viewModel.showAddColumnSheet = true }) {
            VStack {
                Image(systemName: "plus")
                    .font(.largeTitle)
                Text("Añadir Columna")
                    .font(.headline)
            }
            .frame(width: 320, height: 200)
            .glassBackground(cornerRadius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundStyle(.secondary)
            )
        }
        .buttonStyle(.plain)
    }

    private func listContent(viewModel: KanbanViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach((project.columns ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })) {
                    column in
                    Section {
                        if let tasks = column.tasks, !tasks.isEmpty {
                            ForEach(tasks.sorted(by: { $0.createdAt > $1.createdAt })) { task in
                                TaskCard(task: task)
                                    .contextMenu {
                                        Button {
                                            viewModel.editingTask = task
                                        } label: {
                                            Label("Editar", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            viewModel.deleteTask(task)
                                        } label: {
                                            Label("Eliminar", systemImage: "trash")
                                        }
                                    }
                            }
                        } else {
                            Text("Sin tareas")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading)
                        }
                    } header: {
                        HStack {
                            Text(column.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("\(column.tasks?.count ?? 0)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())

                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)  // Sticky header look
                    }
                }
            }
            .padding()
            .padding(.bottom, 100)
        }
        .overlay(alignment: .bottomTrailing) {
            VoiceFAB(voiceManager: viewModel.voiceManager) {
                viewModel.createTaskFromVoice()
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Kanban Column View

struct KanbanColumnView: View {
    @Bindable var column: KanbanColumn
    @Binding var draggedTask: TaskItem?

    let onDropTask: (TaskItem) -> Void
    let onAdd: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteColumn: () -> Void
    let onRenameColumn: () -> Void

    @State private var isTargeted = false

    // Sort tasks locally to ensure consistency
    var sortedTasks: [TaskItem] {
        (column.tasks ?? []).sorted { $0.createdAt > $1.createdAt }
    }

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
                    Text("\(column.tasks?.count ?? 0)")
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

                    Button(action: onRenameColumn) {
                        Label("Renombrar", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(8)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
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
                        if column.tasks?.isEmpty ?? true {
                            ContentUnavailableView {
                                Label("Vacio", systemImage: "tray")
                            } description: {
                                Text("Arrastra tareas aqui")
                            }
                            .frame(height: 150)
                            .opacity(0.5)
                        } else {
                            ForEach(sortedTasks) { task in
                                TaskCard(task: task)
                                    .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 14))
                                    .onDrag {
                                        draggedTask = task
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
                .shapeContentHittable()
                .dropDestination(for: String.self) { items, _ in
                    guard let idString = items.first,
                        let task = draggedTask,
                        task.id.uuidString == idString
                    else { return false }

                    withAnimation(.snappy) {
                        onDropTask(task)
                    }
                    return true
                } isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTargeted = targeted
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                )
            }

            if !column.isCollapsed {
                Button(action: onAdd) {
                    Label("Añadir tarea", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                }
            }
        }
        .glassBackground(cornerRadius: 12)  // Liquid Glass
        .shadow(color: Color.black.opacity(isTargeted ? 0.15 : 0.05), radius: 8, x: 0, y: 4)
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
        .glassBackground(cornerRadius: 14)  // Liquid Glass
    }
}

extension View {
    func shapeContentHittable() -> some View {
        self.contentShape(Rectangle())
    }
}

// MARK: - Liquid Glass Modifier (iOS 26+ Style)

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, *) {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.regularMaterial)
                    )
                    .clipShape(.rect(cornerRadius: cornerRadius))
            } else {
                content
                    .background(
                        .ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            }
        }
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
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
