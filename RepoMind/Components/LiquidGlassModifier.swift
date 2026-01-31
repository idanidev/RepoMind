import SwiftUI

// MARK: - Liquid Glass Modifier (iOS 26+ Native)

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var isInteractive: Bool = false

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 15, *) {
                content
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius)
                    )
                // If interactive, maybe add a subtle scaling or border change,
                // but Material handles most of it.
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
    func glassBackground(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, isInteractive: interactive))
    }

    func shapeContentHittable() -> some View {
        self.contentShape(Rectangle())
    }
}
