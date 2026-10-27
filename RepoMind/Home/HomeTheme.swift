import SwiftUI

// MARK: - Home theme

/// Palette and metrics of the redesigned home screen.
///
/// Colors live in the asset catalog as `Home*` colorsets, each with a light and a dark
/// appearance. Dark is the primary design: the background is pure black so OLED panels switch
/// those pixels off, and depth comes from hairlines and faint surface gradients, not shadows.
enum HomeTheme {
    static let background = Color("HomeBackground")
    static let surface = Color("HomeSurface")
    static let surfaceElevated = Color("HomeSurfaceElevated")
    static let hairline = Color("HomeHairline")
    static let textPrimary = Color("HomeTextPrimary")
    static let textSecondary = Color("HomeTextSecondary")
    static let accent = Color("HomeAccent")
    /// Text and glyphs on a filled accent, danger or warning shape. White in light; near-black in dark,
    /// where those fills are pastel and white on them reads 2.5–3.4:1 against the 4.5:1 text needs.
    static let onAccent = Color("HomeOnAccent")
    static let success = Color("HomeSuccess")
    static let warning = Color("HomeWarning")
    static let danger = Color("HomeDanger")
    static let info = Color("HomeInfo")
    /// GitHub's star yellow. Reads the same on both appearances, so it is not a colorset.
    static let star = Color(hex: "#E3B341")

    static let cardRadius: CGFloat = 18
    static let chipRadius: CGFloat = 7
    static let cardPadding: CGFloat = 14
    static let gutter: CGFloat = 16

    /// Faint top-left light on every card — the Raycast-style elevation gradient that replaces
    /// drop shadows.
    static var cardFill: LinearGradient {
        LinearGradient(
            colors: [surfaceElevated.opacity(0.55), surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - GitHub language colors

extension Color {
    /// The color GitHub paints next to a language name.
    static func gitHubLanguage(_ language: String) -> Color {
        switch language.lowercased() {
        case "swift": return Color(hex: "#F05138")
        case "objective-c", "objc": return Color(hex: "#438EFF")
        case "javascript", "js": return Color(hex: "#F7DF1E")
        case "typescript", "ts": return Color(hex: "#3178C6")
        case "python": return Color(hex: "#3776AB")
        case "java": return Color(hex: "#B07219")
        case "kotlin": return Color(hex: "#A97BFF")
        case "go": return Color(hex: "#00ADD8")
        case "rust": return Color(hex: "#DEA584")
        case "ruby": return Color(hex: "#CC342D")
        case "c++", "cpp": return Color(hex: "#F34B7D")
        case "c#", "csharp": return Color(hex: "#239120")
        case "php": return Color(hex: "#777BB4")
        case "html": return Color(hex: "#E34C26")
        case "css": return Color(hex: "#1572B6")
        case "svelte": return Color(hex: "#FF3E00")
        case "vue": return Color(hex: "#41B883")
        case "dart": return Color(hex: "#00B4AB")
        case "shell", "bash": return Color(hex: "#89E051")
        default: return Color.gray
        }
    }
}

// MARK: - Tap targets

extension View {
    /// Lets a small control be hit up to `inset` points beyond its edges, so a 32 pt button still has
    /// the 44 pt target Apple asks for. Nothing is laid out or drawn differently.
    func homeHitArea(extending inset: CGFloat) -> some View {
        contentShape(Rectangle().inset(by: -inset))
    }
}

// MARK: - Card press feedback

/// A tap on a card: a slight sink and dim, nothing bouncy.
struct HomeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Flow layout

/// Lays children out left to right and wraps to a new row when the width runs out.
///
/// SwiftUI has no built-in wrapping stack, and the metadata row of a card (language, stars,
/// tasks, build, PRs…) is exactly the case where a horizontal stack either truncates or
/// overflows. Children keep their ideal size; one wider than the row is proposed the row width.
struct HomeFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = fittedSize(of: subview, maxWidth: maxWidth)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = fittedSize(of: subview, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func fittedSize(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, ideal.width > maxWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}
