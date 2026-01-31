import SwiftUI

struct GlassEffectContainer<Content: View>: View {
    var cornerRadius: CGFloat
    var isInteractive: Bool
    var content: Content

    init(
        cornerRadius: CGFloat = 12, isInteractive: Bool = false, @ViewBuilder content: () -> Content
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
