import Charts
import Foundation
import SwiftUI

// MARK: - Rhythm

/// Captures per day over the last two weeks: whether the habit is alive.
struct HomeDashboardRhythmCard: View {
    let history: [HomeDayCount]

    private var total: Int { history.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeDashboardSectionTitle(
                title: "home_dashboard_rhythm",
                trailing: String(format: String(localized: "home_dashboard_rhythm_caption %lld"), total))
            Chart(history) { day in
                BarMark(x: .value("day", day.date, unit: .day), y: .value("count", day.count))
                    .foregroundStyle(day.count > 0 ? HomeTheme.accent : HomeTheme.surfaceElevated)
                    .cornerRadius(2)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 56)
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
    }
}

// MARK: - GitHub

/// What only GitHub knows, summed: pushes, pull requests, builds, visibility, the latest pushes
/// and the releases out. Until the first refresh it says so instead of showing zeros.
struct HomeDashboardGitHubCard: View {
    let github: HomeGitHubSummary
    var onOpenRepo: (String) -> Void = { _ in }
    var onOpenDigest: (HomeDigestKind) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeDashboardSectionTitle(
                title: "home_dashboard_github",
                trailing: github.known == 0 ? nil : String(
                    format: String(localized: "home_dashboard_visibility %lld %lld"),
                    github.privateRepos, github.publicRepos))
            if github.known == 0 {
                Text("home_dashboard_github_unknown")
                    .font(.footnote)
                    .foregroundStyle(HomeTheme.textSecondary)
            } else {
                tiles
                if !github.recentPushes.isEmpty {
                    pushes
                }
                if !github.releases.isEmpty {
                    releases
                }
            }
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: 0) {
            tile(github.pushedToday, label: "home_dashboard_pushes_today", tint: HomeTheme.textPrimary, kind: nil)
            tile(github.pushedWeek, label: "home_dashboard_pushes_week", tint: HomeTheme.textPrimary, kind: nil)
            tile(
                github.openPullRequests, label: "home_dashboard_open_prs", tint: HomeTheme.accent,
                kind: github.openPullRequests > 0 ? .pullRequests : nil)
            tile(
                github.failing.count, label: "home_dashboard_failing",
                tint: github.failing.isEmpty ? HomeTheme.success : HomeTheme.danger,
                kind: github.failing.isEmpty ? nil : .failingBuilds)
        }
    }

    private func tile(_ value: Int, label: LocalizedStringKey, tint: Color, kind: HomeDigestKind?) -> some View {
        Button {
            if let kind { onOpenDigest(kind) }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted())
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(HomeTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(kind == nil)
    }

    private var pushes: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("home_dashboard_recent_pushes")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(HomeTheme.textSecondary)
            ForEach(github.recentPushes) { push in
                Button {
                    onOpenRepo(push.id)
                } label: {
                    HStack {
                        Text(push.name)
                            .font(.footnote)
                            .foregroundStyle(HomeTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(push.pushedAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(HomeTheme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var releases: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("home_dashboard_releases")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(HomeTheme.textSecondary)
            HomeFlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(github.releases) { release in
                    Button {
                        onOpenRepo(release.id)
                    } label: {
                        HomeChip(symbol: "tag.fill", text: release.name + " " + release.tag)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - App

/// One connected app: its primary number with the trend, a sparkline of its first series, the
/// other headlines, and what broke lately.
struct HomeDashboardAppCard: View {
    let summary: HomeAppSummary
    var onOpenStats: (Int) -> Void = { _ in }

    private struct SparkPoint: Identifiable {
        let id: Int
        let value: Int
    }

    private var points: [SparkPoint] {
        summary.sparkline.enumerated().map { SparkPoint(id: $0.offset, value: $0.element) }
    }

    var body: some View {
        Button {
            onOpenStats(summary.app.repoID)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(HomeTheme.info)
                    Text(summary.app.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeTheme.textPrimary)
                    Spacer()
                    Text(String(format: String(localized: "stats_period %lld"), summary.periodDays))
                        .font(.caption)
                        .foregroundStyle(HomeTheme.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.app.headline)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(HomeTheme.textPrimary)
                    if let change = summary.app.change {
                        BoardStatsDelta(change: change)
                    }
                    Spacer()
                    if summary.app.crashes > 0 {
                        Text("home_digest_crashes \(summary.app.crashes)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeTheme.danger)
                    }
                    if summary.app.reports > 0 {
                        Text("home_digest_reports \(summary.app.reports)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeTheme.warning)
                    }
                }
                if points.count > 1 {
                    Chart(points) { point in
                        AreaMark(x: .value("i", point.id), y: .value("v", point.value))
                            .foregroundStyle(HomeTheme.accent.opacity(0.18))
                        LineMark(x: .value("i", point.id), y: .value("v", point.value))
                            .foregroundStyle(HomeTheme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 40)
                }
                if !summary.headlines.isEmpty {
                    HomeFlowLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(summary.headlines) { item in
                            HomeChip(text: item.value.formatted() + " " + item.label)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("home_dashboard_see_stats")
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeTheme.accent)
            }
            .padding(HomeTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeDashboardCardBackground())
        }
        .buttonStyle(HomeCardButtonStyle())
    }
}

// MARK: - Account and sync

/// The account in numbers and the health of the two syncs. Boring when all is well, which is
/// the point: a red line here is the first sign that something is silently broken.
struct HomeDashboardAccountCard: View {
    let data: HomeDashboardData
    var onShowRepos: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeDashboardSectionTitle(
                title: "home_dashboard_account",
                trailing: data.isPro ? "Pro" : String(localized: "home_dashboard_plan_free"))
            line(
                "person.2", tint: HomeTheme.textSecondary,
                text: String(format: String(localized: "home_dashboard_accounts %lld"), data.repos.accounts)
                    + (data.accountNames.isEmpty ? "" : " · " + data.accountNames.joined(separator: ", ")))
            Button(action: onShowRepos) {
                line(
                    "shippingbox", tint: HomeTheme.textSecondary,
                    text: String(format: String(localized: "home_stat_total %lld"), data.repos.total) + " · " + String(
                        format: String(localized: "home_dashboard_repos_detail %lld %lld %lld"),
                        data.repos.favorites, data.repos.archived, data.repos.local),
                    chevron: true)
            }
            .buttonStyle(.plain)
            line(
                "folder", tint: HomeTheme.textSecondary,
                text: String(format: String(localized: "home_dashboard_folders %lld"), data.repos.folders))
            if !data.languages.isEmpty {
                HomeFlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(data.languages) { share in
                        HomeChip(text: share.name + " " + share.count.formatted())
                    }
                }
            }
            Divider().overlay(HomeTheme.hairline)
            iCloudLine
            gitHubLine
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
    }

    @ViewBuilder
    private var iCloudLine: some View {
        if let problem = data.sync.iCloudProblem {
            line(
                "exclamationmark.icloud.fill", tint: HomeTheme.danger,
                text: String(localized: "home_dashboard_icloud_problem"))
            Text(problem)
                .font(.caption2)
                .foregroundStyle(HomeTheme.textSecondary)
                .padding(.leading, 24)
        } else {
            let detail = data.sync.iCloudLastSuccess.map {
                " · " + String(
                    format: String(localized: "home_dashboard_icloud_last %@"),
                    $0.formatted(.relative(presentation: .named)))
            } ?? ""
            line("icloud.fill", tint: HomeTheme.success, text: String(localized: "home_dashboard_icloud_ok") + detail)
        }
    }

    @ViewBuilder
    private var gitHubLine: some View {
        if let synced = data.sync.lastGitHubSync {
            line(
                "arrow.triangle.2.circlepath", tint: HomeTheme.success,
                text: String(
                    format: String(localized: "home_dashboard_github_sync %@"),
                    synced.formatted(.relative(presentation: .named))))
        } else {
            line(
                "arrow.triangle.2.circlepath", tint: HomeTheme.warning,
                text: String(localized: "home_dashboard_github_never"))
        }
        if let refreshed = data.sync.activityRefreshedAt {
            Text(String(
                format: String(localized: "home_dashboard_activity_refreshed %@"),
                refreshed.formatted(.relative(presentation: .named))))
                .font(.caption2)
                .foregroundStyle(HomeTheme.textSecondary)
                .padding(.leading, 24)
        }
    }

    private func line(_ symbol: String, tint: Color, text: String, chevron: Bool = false) -> some View {
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
            Spacer(minLength: 4)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeTheme.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }
}
