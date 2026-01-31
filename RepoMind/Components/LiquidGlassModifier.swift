import SwiftUI

// MARK: - Liquid Glass Modifier (iOS 26+ Native)

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var isInteractive: Bool

    func body(content: Content) -> some View {
        // ✅ FIX: Use native iOS 26 glassEffect with proper fallback
        if #available(iOS 26, *) {
            if isInteractive {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            // Fallback for iOS 15-25
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
        }
    }
}

// MARK: - Convenience Extensions

extension View {
    func glassBackground(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, isInteractive: interactive))
    }

    func shapeContentHittable() -> some View {
        contentShape(Rectangle())
    }
}

// MARK: - Glass Effect Container

struct GlassEffectContainer<Content: View>: View {
    var cornerRadius: CGFloat
    var isInteractive: Bool
    @ViewBuilder var content: Content

    init(
        cornerRadius: CGFloat = 12,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        content
            .glassBackground(cornerRadius: cornerRadius, interactive: isInteractive)
    }
}

// MARK: - Glass Button Style (iOS 26+)

struct GlassButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassBackground(cornerRadius: cornerRadius, interactive: true)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }

    static func glass(cornerRadius: CGFloat) -> GlassButtonStyle {
        GlassButtonStyle(cornerRadius: cornerRadius)
    }
}
