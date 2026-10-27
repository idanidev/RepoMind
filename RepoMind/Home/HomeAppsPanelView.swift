import Foundation
import SwiftUI

// MARK: - Entry

/// One connected app with everything its backend last said.
struct HomeAppPanelEntry: Identifiable {
    let repoID: Int
    let name: String
    let stats: RepoStats
    let fetchedAt: Date?

    var id: Int { repoID }
}

struct HomeAppsPanelActions {
    var openStats: (Int) -> Void = { _ in }
    var upgrade: () -> Void = {}
    var refresh: () async -> Void = {}
}

// MARK: - Panel

/// Every app with statistics connected, on one screen: the headline numbers, the first series
/// and what broke, per app, with the full page one tap away. The admin panel of all your apps,
/// read from each one's backend. Pro.
struct HomeAppsPanelView: View {
    let entries: [HomeAppPanelEntry]
    var isPro = false
    var actions = HomeAppsPanelActions()

    private var crashes: Int {
        entries.reduce(0) { $0 + $1.stats.issues.filter(\.isCrash).count }
    }

    var body: some View {
        ZStack {
            HomeTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !isPro {
                        proCard
                    } else if entries.isEmpty {
                        emptyCard
                    } else {
                        summary
                        ForEach(entries) { entry in
                            appCard(entry)
                        }
                    }
                }
                .padding(.horizontal, HomeTheme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await actions.refresh() }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("apps_panel_title")
        .navigationBarTitleDisplayMode(.large)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            stat(entries.count, label: "apps_panel_count")
            stat(crashes, label: "apps_panel_crashes", tint: crashes > 0 ? HomeTheme.danger : HomeTheme.success)
        }
        .padding(HomeTheme.cardPadding)
        .background(HomeDashboardCardBackground())
    }

    private func stat(_ value: Int, label: LocalizedStringKey, tint: Color = HomeTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.formatted())
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(HomeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func appCard(_ entry: HomeAppPanelEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeTheme.textPrimary)
                Spacer()
                Text(String(format: String(localized: "stats_period %lld"), entry.stats.periodDays))
                    .font(.caption)
                    .foregroundStyle(HomeTheme.textSecondary)
            }
            BoardStatsHeadlineGrid(items: entry.stats.headline)
            if let series = entry.stats.series.first {
                BoardStatsSeriesCard(series: series, periodDays: entry.stats.periodDays)
            }
            if !entry.stats.issues.isEmpty {
                BoardStatsIssuesCard(issues: Array(entry.stats.issues.prefix(3)))
            }
            Button {
                actions.openStats(entry.repoID)
            } label: {
                HStack(spacing: 4) {
                    Text("home_dashboard_see_stats")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeTheme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(HomeTheme.textSecondary)
            Text("apps_panel_empty_title")
                .font(.headline)
                .foregroundStyle(HomeTheme.textPrimary)
            Text("home_dashboard_apps_hint")
                .font(.footnote)
                .foregroundStyle(HomeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(HomeDashboardCardBackground())
    }

    private var proCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.largeTitle)
                .foregroundStyle(HomeTheme.accent)
            Text("apps_panel_pro_title")
                .font(.headline)
                .foregroundStyle(HomeTheme.textPrimary)
            Text("apps_panel_pro_message")
                .font(.footnote)
                .foregroundStyle(HomeTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: actions.upgrade) {
                Text("upgrade_to_pro_button")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(HomeTheme.accent))
            }
            .buttonStyle(HomeCardButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(HomeDashboardCardBackground())
    }
}
