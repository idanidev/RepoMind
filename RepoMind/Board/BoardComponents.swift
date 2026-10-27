import SwiftData
import SwiftUI
import UIKit

// MARK: - Circle button

/// The round header buttons: back, feedback, the menu.
struct BoardCircleButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var badge = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Self.face(symbol: symbol)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge.formatted())
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(HomeTheme.danger, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(badge > 0 ? badge.formatted() : "")
    }

    /// The disc alone, for a `Menu` label.
    static func face(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeTheme.textPrimary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(HomeTheme.surfaceElevated))
            .overlay(Circle().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
            .contentShape(Circle())
    }
}

// MARK: - Progress ring

struct BoardProgressRing: View {
    let progress: Double

    private var clamped: Double { min(max(progress, 0), 1) }
    private var percent: Int { Int((clamped * 100).rounded()) }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(HomeTheme.surfaceElevated, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(colors: [HomeTheme.info, HomeTheme.accent], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
            Text(verbatim: "\(percent)%")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(HomeTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(HomeTheme.surfaceElevated))
        .overlay(Capsule().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
        .accessibilityElement()
        .accessibilityLabel(String(format: String(localized: "board_progress %lld"), percent))
    }
}

// MARK: - Column pills

/// The column names as a scrollable row of pills; the active one is filled with the accent.
/// Long-press renames or deletes a column, the trailing "+" adds one.
struct BoardColumnPills: View {
    let columns: [KanbanColumn]
    @Binding var selection: Int
    let onAddColumn: () -> Void
    let onRename: (KanbanColumn) -> Void
    let onDelete: (KanbanColumn) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                        pill(column, index: index)
                            .id(index)
                    }
                    Button(action: onAddColumn) {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(HomeTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(HomeTheme.surface))
                            .overlay(Circle().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("add_new_column_button")
                }
                .padding(.horizontal, HomeTheme.gutter)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, index in
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func pill(_ column: KanbanColumn, index: Int) -> some View {
        let isSelected = index == selection
        let count = (column.tasks ?? []).count
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = index }
        } label: {
            HStack(spacing: 5) {
                Text(column.name)
                Text(verbatim: "(\(count))")
                    .monospacedDigit()
                    .opacity(0.8)
            }
            .font(.footnote.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.white : HomeTheme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isSelected ? HomeTheme.accent : HomeTheme.surface))
            .overlay(Capsule().strokeBorder(isSelected ? HomeTheme.accent : HomeTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onRename(column)
            } label: {
                Label("rename_column", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete(column)
            } label: {
                Label("delete_column", systemImage: "trash")
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Page dots

struct BoardPageDots: View {
    let count: Int
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Capsule()
                    .fill(index == selection ? HomeTheme.textPrimary : HomeTheme.textSecondary.opacity(0.35))
                    .frame(width: index == selection ? 16 : 6, height: 6)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.25)) { selection = index }
                    }
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Column page

/// The cards of one column, or an empty state that says what the microphone is for.
struct BoardColumnPage: View {
    let column: KanbanColumn
    let isDoneColumn: Bool
    let viewModel: KanbanViewModel

    private var tasks: [TaskItem] {
        (column.tasks ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if tasks.isEmpty {
                    emptyState
                } else {
                    ForEach(tasks) { task in
                        BoardTaskCard(
                            task: task,
                            isDone: isDoneColumn,
                            onTap: { viewModel.editingTask = task },
                            onCheck: { viewModel.moveTaskToDoneColumn(task) },
                            onMove: { viewModel.showMoveTaskSheet(task) },
                            onDelete: { viewModel.deleteTask(task) }
                        )
                    }
                }
            }
            .padding(.horizontal, HomeTheme.gutter)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: isDoneColumn ? "checkmark.circle" : "tray")
                .font(.title)
                .foregroundStyle(HomeTheme.textSecondary)
            Text("board_empty_column")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeTheme.textPrimary)
            Text("board_empty_column_hint")
                .font(.caption)
                .foregroundStyle(HomeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.horizontal, 24)
    }
}

// MARK: - Task card

/// One task: the checkbox that sends it to the done column, an accent bar, the text, and a row
/// of facts — issue number, not-published warning, when it was captured — plus the photo if
/// one was attached. Tap edits; long-press offers done, move and delete.
struct BoardTaskCard: View {
    let task: TaskItem
    let isDone: Bool
    let onTap: () -> Void
    let onCheck: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    private var hasPhoto: Bool { task.imageData != nil || task.imagePath != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: isDone ? {} : onCheck) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? HomeTheme.success : HomeTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDone)
            .accessibilityLabel("mark_done")

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isDone ? HomeTheme.success : HomeTheme.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.content)
                    .font(.subheadline)
                    .foregroundStyle(isDone ? HomeTheme.textSecondary : HomeTheme.textPrimary)
                    .strikethrough(isDone, color: HomeTheme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let number = task.issueNumber {
                        Text(verbatim: "#\(number)")
                            .font(.caption.monospaced())
                            .foregroundStyle(HomeTheme.textSecondary)
                    }
                    if task.needsIssueSync {
                        HomeChip(
                            symbol: "arrow.up.circle",
                            text: String(localized: "board_unpublished"),
                            tint: HomeTheme.danger
                        )
                    }
                    Spacer(minLength: 0)
                    Text(task.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(HomeTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("photo_badge")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(HomeTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: onTap) {
                Label("edit_task", systemImage: "pencil")
            }
            if !isDone {
                Button(action: onCheck) {
                    Label("mark_done", systemImage: "checkmark.circle")
                }
            }
            Button(action: onMove) {
                Label("move_task", systemImage: "arrow.right.circle")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("delete_task", systemImage: "trash")
            }
        }
        .task(id: task.id) {
            guard hasPhoto else {
                thumbnail = nil
                return
            }
            thumbnail = await TaskImageHelper.loadThumbnail(from: task, size: CGSize(width: 112, height: 112))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.content)
        .accessibilityHint("task_edit_hint")
    }
}
