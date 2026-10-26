import Foundation
import SwiftUI

// MARK: - Chip

/// The small metadata pill: neutral by default, tinted when it carries a verdict (build, PRs).
struct HomeChipModifier: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(tint ?? HomeTheme.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: HomeTheme.chipRadius, style: .continuous)
                    .fill(tint.map { $0.opacity(0.14) } ?? HomeTheme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HomeTheme.chipRadius, style: .continuous)
                    .strokeBorder(tint.map { $0.opacity(0.35) } ?? HomeTheme.hairline, lineWidth: 0.5)
            )
    }
}

extension View {
    func homeChip(tint: Color? = nil) -> some View {
        modifier(HomeChipModifier(tint: tint))
    }
}

struct HomeChip: View {
    var symbol: String?
    let text: String
    var tint: Color?
    /// Colors only the symbol, for glyphs with a color of their own (the star).
    var symbolTint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(symbolTint ?? tint ?? HomeTheme.textSecondary)
            }
            Text(text)
        }
        .homeChip(tint: tint)
    }
}

struct HomeLanguageChip: View {
    let share: HomeLanguageShare

    private var text: String {
        guard share.share < 1 else { return share.name }
        return "\(share.name) \(Int((share.share * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.gitHubLanguage(share.name))
                .frame(width: 7, height: 7)
            Text(text)
        }
        .homeChip()
    }
}

// MARK: - Status badge

struct HomeStatusBadge: View {
    let status: HomeRepoStatus
    var version: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.tint)
                .frame(width: 6, height: 6)
            Text(status.title)
            if let version {
                Text(verbatim: "•")
                    .opacity(0.6)
                Text(version)
                    .font(.caption2.weight(.semibold).monospaced())
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(status.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(status.tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(status.tint.opacity(0.35), lineWidth: 0.5))
        .fixedSize()
    }
}

// MARK: - Logo

/// Repo logo, owner avatar, or a monogram — in that order of preference.
struct HomeRepoLogo: View {
    let repo: HomeRepoCardData
    var size: CGFloat = 48

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    }

    var body: some View {
        Group {
            if let asset = repo.logoAssetName {
                Image(asset)
                    .resizable()
                    .scaledToFill()
            } else if let url = repo.logoURL ?? repo.ownerAvatarURL {
                CachedAsyncImage(url: url) { monogram }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        ZStack {
            LinearGradient(colors: repo.monogramColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(repo.name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Commit sparkline

/// Seven bars, one per day, the latest at full strength. Drawn with shapes rather than Swift
/// Charts: there are no axes to show, and a chart would want to add them.
struct HomeCommitSparkline: View {
    let values: [Int]
    var tint: Color = HomeTheme.success
    var height: CGFloat = 22

    private var peak: CGFloat { CGFloat(max(values.max() ?? 1, 1)) }
    private var total: Int { values.reduce(0, +) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint.opacity(index == values.count - 1 ? 1 : 0.55))
                    .frame(width: 4, height: max(3, height * CGFloat(value) / peak))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel(String(format: String(localized: "home_commits_7d_accessibility %lld"), total))
    }
}

// MARK: - Progress bar

struct HomeProgressBar: View {
    let progress: Double

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(HomeTheme.surfaceElevated)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [HomeTheme.info, HomeTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geometry.size.width * clamped))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(
            String(format: String(localized: "home_progress_label %lld"), Int((clamped * 100).rounded()))
        )
    }
}
