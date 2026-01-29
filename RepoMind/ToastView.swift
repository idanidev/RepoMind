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

    private init() {}

    func show(_ message: String, style: ToastStyle) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(style.hapticType)

        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            currentToast = ToastItem(style: style, message: message)
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.3)) {
                currentToast = nil
            }
        }
    }
}

// MARK: - Toast Overlay View

struct ToastOverlay: View {
    @State private var toastManager = ToastManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            if let toast = toastManager.currentToast {
                toastPill(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: toastManager.currentToast)
    }

    private func toastPill(_ toast: ToastItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(toast.style.tintColor)

            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.label))
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
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                toastManager.currentToast = nil
            }
        }
    }
}
