import Foundation
import SwiftUI

// MARK: - Digest card

/// The summary at the top of the home: tiles for what needs a hand, a line per secondary
/// signal, a row per app with statistics. Every piece with a number is a button that opens
/// the list behind it, and a zero shows nothing.
struct HomeDigestCard: View {
    let digest: HomeDigest
    var onOpen: (HomeDigestKind) -> Void = { _ in }
    var onOpenStats: (Int) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tiles
            rows
            if !digest.apps.isEmpty {
                apps
            }
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                .fill(HomeTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("home_digest_title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeTheme.textPrimary)
            Spacer()
            Text("home_digest_captured \(digest.capturedThisWeek)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(HomeTheme.textSecondary)
        }
    }

    // MARK: Tiles

    @ViewBuilder
    private var tiles: some View {
        let items = tileItems
        if !items.isEmpty {
            HomeFlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(items, id: \.kind) { item in
                    tile(item)
                }
            }
        }
    }

    private struct Tile {
        let kind: HomeDigestKind
        let count: Int
        let label: LocalizedStringKey
        let symbol: String
        let tint: Color
    }

    private var tileItems: [Tile] {
        var items: [Tile] = []
        if digest.abandoned > 0 {
            items.append(Tile(
                kind: .abandoned, count: digest.abandoned, label: "home_digest_tile_abandoned",
                symbol: "hourglass", tint: HomeTheme.warning))
        }
        if digest.unpublished > 0 {
            items.append(Tile(
                kind: .unpublished, count: digest.unpublished, label: "home_digest_tile_unpublished",
                symbol: "arrow.up.doc", tint: HomeTheme.danger))
        }
        if digest.failingBuilds > 0 {
            items.append(Tile(
                kind: .failingBuilds, count: digest.failingBuilds, label: "home_digest_tile_builds",
                symbol: "xmark.octagon.fill", tint: HomeTheme.danger))
        }
        if digest.unreadFeedback > 0 {
            items.append(Tile(
                kind: .feedback, count: digest.unreadFeedback, label: "home_digest_tile_feedback",
                symbol: "bell.badge.fill", tint: HomeTheme.info))
        }
        return items
    }

    private func tile(_ item: Tile) -> some View {
        Button {
            onOpen(item.kind)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(item.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.count.formatted())
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(HomeTheme.textPrimary)
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(HomeTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.tint.opacity(0.12))
            )
        }
        .buttonStyle(HomeCardButtonStyle())
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        if digest.pullRequests > 0 {
            row(
                .pullRequests, symbol: "arrow.triangle.pull", tint: HomeTheme.accent,
                text: String(format: String(localized: "home_digest_prs %lld"), digest.pullRequests))
        }
        if digest.dormantRepos > 0 {
            row(
                .dormant, symbol: "moon.zzz.fill", tint: HomeTheme.textSecondary,
                text: String(format: String(localized: "home_digest_dormant %lld"), digest.dormantRepos))
        }
        if digest.syncErrors > 0 {
            row(
                .syncErrors, symbol: "exclamationmark.triangle.fill", tint: HomeTheme.warning,
                text: String(format: String(localized: "home_digest_sync_errors %lld"), digest.syncErrors))
        }
    }

    private func row(_ kind: HomeDigestKind, symbol: String, tint: Color, text: String) -> some View {
        Button {
            onOpen(kind)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(HomeTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeTheme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Apps

    private var apps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("home_digest_apps")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(HomeTheme.textSecondary)
                .padding(.top, 2)
            ForEach(digest.apps) { app in
                appRow(app)
            }
        }
    }

    private func appRow(_ app: HomeDigestApp) -> some View {
        Button {
            onOpenStats(app.repoID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeTheme.info)
                    .frame(width: 16)
                Text(app.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
                    .lineLimit(1)
                Text(app.headline)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(HomeTheme.textSecondary)
                    .lineLimit(1)
                if let change = app.change {
                    BoardStatsDelta(change: change)
                }
                Spacer(minLength: 8)
                if app.crashes > 0 {
                    Text("home_digest_crashes \(app.crashes)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeTheme.danger)
                } else if app.reports > 0 {
                    Text("home_digest_reports \(app.reports)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeTheme.warning)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeTheme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Digest") {
    HomeDigestCard(digest: HomeMockData.digest)
        .padding()
        .background(HomeTheme.background)
        .preferredColorScheme(.dark)
}
