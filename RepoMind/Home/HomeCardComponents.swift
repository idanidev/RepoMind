import Foundation
import SwiftUI

// MARK: - Chip

/// The small metadata pill: neutral by default, tinted when it carries a verdict.
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
    let language: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.gitHubLanguage(language))
                .frame(width: 7, height: 7)
            Text(language)
        }
        .homeChip()
    }
}

// MARK: - Inactive badge

struct HomeInactiveBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(HomeTheme.textSecondary)
                .frame(width: 6, height: 6)
            Text("home_status_inactive")
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(HomeTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(HomeTheme.textSecondary.opacity(0.14)))
        .overlay(Capsule().strokeBorder(HomeTheme.textSecondary.opacity(0.35), lineWidth: 0.5))
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
