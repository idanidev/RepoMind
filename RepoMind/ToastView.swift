import SwiftUI

// MARK: - Toast Style

enum ToastStyle {
    case error
    case success
    case info

    var iconName: String {
        switch self {
        case .error: "xmark.circle.fill"
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .error: .red
        case .success: .green
        case .info: .blue
        }
    }

    var hapticType: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .error: .error
        case .success: .success
        case .info: .warning
        }
    }
}

// MARK: - Toast Item

struct ToastItem: Equatable {
    let id = UUID()
    let style: ToastStyle
    let message: String

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast Manager

@MainActor
@Observable
final class ToastManager {
    static let shared = ToastManager()

    var currentToast: ToastItem?

    // ✅ FIX: Track dismiss task for cancellation
    private var dismissTask: Task<Void, Never>?

    // ✅ FIX: Static feedback generator for performance
    private static let feedbackGenerator = UINotificationFeedbackGenerator()

    private init() {}

    func show(_ message: String, style: ToastStyle, duration: TimeInterval = 3.0) {
        // ✅ FIX: Cancel previous dismiss task to avoid race conditions
        dismissTask?.cancel()

        Self.feedbackGenerator.prepare()
        Self.feedbackGenerator.notificationOccurred(style.hapticType)

        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            currentToast = ToastItem(style: style, message: message)
        }

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.currentToast = nil
                }
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        withAnimation(.easeOut(duration: 0.2)) {
            currentToast = nil
        }
    }
}

// MARK: - Toast Overlay View

struct ToastOverlay: View {
    @State private var toastManager = ToastManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            if let toast = toastManager.currentToast {
                ToastPill(toast: toast) {
                    toastManager.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: toastManager.currentToast)
    }
}

// MARK: - Toast Pill (Extracted Subview)

private struct ToastPill: View {
    let toast: ToastItem
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Image(systemName: toast.style.iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(toast.style.tintColor)

                Text(toast.message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color(.label).opacity(0.08), radius: 12, x: 0, y: 6)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(toast.style == .error ? "Error" : toast.style == .success ? "Éxito" : "Info"): \(toast.message)"
        )
        .accessibilityHint("Toca para cerrar")
        .accessibilityAddTraits(.isButton)
    }
}
