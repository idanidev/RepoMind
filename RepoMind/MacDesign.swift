import SwiftUI

// MARK: - Mac Design Constants

enum MacDesign {
    static let minWindowWidth: CGFloat = 1200
    static let minWindowHeight: CGFloat = 720
    static let cardCornerRadius: CGFloat = 10
    static let columnHorizontalPadding: CGFloat = 24
}

// MARK: - Platform helper

@inline(__always)
var isMacIdiom: Bool {
    #if targetEnvironment(macCatalyst)
        return true
    #else
        return false
    #endif
}

// MARK: - Hover Modifier

/// Subtle hover background highlight + pointer cursor.
struct HoverableModifier: ViewModifier {
    @State private var isHovered = false
    var cornerRadius: CGFloat = 8
    var intensity: Double = 0.06

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? intensity : 0))
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

extension View {
    func hoverable(cornerRadius: CGFloat = 8, intensity: Double = 0.06) -> some View {
        modifier(HoverableModifier(cornerRadius: cornerRadius, intensity: intensity))
    }
}

// MARK: - Mac-aware font helpers

extension Font {
    /// On Mac use a denser size; on iOS keep original.
    static func macAdaptive(_ macFont: Font, _ iOSFont: Font) -> Font {
        isMacIdiom ? macFont : iOSFont
    }
}

// MARK: - Sidebar list style adapter

extension View {
    /// `.sidebar` on Mac for native look, `.insetGrouped` on iOS.
    @ViewBuilder
    func macSidebarListStyle() -> some View {
        #if targetEnvironment(macCatalyst)
            self.listStyle(.sidebar)
        #else
            self.listStyle(.insetGrouped)
        #endif
    }
}

// MARK: - Toolbar placement helper

extension ToolbarItemPlacement {
    /// `.primaryAction` on Mac, `.topBarTrailing` on iOS.
    static var macAware: ToolbarItemPlacement {
        #if targetEnvironment(macCatalyst)
            return .primaryAction
        #else
            return .topBarTrailing
        #endif
    }
}
