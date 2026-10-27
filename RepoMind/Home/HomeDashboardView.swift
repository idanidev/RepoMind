import Foundation
import SwiftUI

// MARK: - Actions

struct HomeDashboardActions {
    /// Opens the board of the repo with this `homeCardID`.
    var openRepo: (String) -> Void = { _ in }
    var selectAccount: (String?) -> Void = { _ in }
    var upgrade: () -> Void = {}
    var signOut: () -> Void = {}
    var openDigest: (HomeDigestKind) -> Void = { _ in }
    var openStats: (Int) -> Void = { _ in }
    var openToday: () -> Void = {}
    var openApps: () -> Void = {}
    var showRepos: () -> Void = {}
    var refresh: () async -> Void = {}
}

// MARK: - Start screen

/// The first tab: the state of everything, dense, on pure black. Pure presentation, like
/// `HomeView`: it draws `HomeDashboardData` and asks for nothing else.
struct HomeDashboardView: View {
    let data: HomeDashboardData
    var account = HomeAccountMenuData()
    var actions = HomeDashboardActions()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                todayCard
                if data.digest.isQuiet {
                    quietCard
                } else {
                    HomeDigestCard(digest: data.digest, onOpen: actions.openDigest, onOpenStats: actions.openStats)
                }
                HomeDashboardRhythmCard(history: data.captureHistory)
                recentCard
                if !data.busiest.isEmpty {
                    busiestCard
                }
                HomeDashboardGitHubCard(
                    github: data.github, onOpenRepo: actions.openRepo, onOpenDigest: actions.openDigest)
                appCards
                HomeDashboardAccountCard(data: data, onShowRepos: actions.showRepos)
            }
            .padding(.horizontal, HomeTheme.gutter)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .refreshable { await actions.refresh() }
        .scrollIndicators(.hidden)
    }

    /// The apps' cards, the App Store card and the link to the apps panel. Apart because a `ViewBuilder`
    /// takes at most ten children and the stack above reached eleven when the store card arrived:
    /// that is a compile error that only shows on the next build.
    @ViewBuilder
    private var appCards: some View {
        if data.apps.isEmpty {
            appsHint
        } else {
            ForEach(data.apps) { app in
                HomeDashboardAppCard(summary: app, onOpenStats: actions.openStats)
            }
        }
        if !data.store.isEmpty {
            HomeStoreCard(apps: data.store, updatedAt: data.storeUpdatedAt, onOpenRepo: actions.openRepo)
        }
        appsPanelLink
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !account.names.isEmpty {
                    HomeAccountMenu(
                        account: account, onSelectAccount: actions.selectAccount,
                        onUpgrade: actions.upgrade, onSignOut: actions.signOut)
                }
                if account.isDemo {
                    Text("demo_mode_badge")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HomeTheme.warning, in: Capsule())
                }
                Spacer(minLength: 4)
                HomeIconButton(symbol: "bell", label: "home_notifications_label", action: actions.openToday)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("home_dashboard_title")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(HomeTheme.textPrimary)
                Text(data.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(HomeTheme.textSecondary)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: Today

    private var todayCard: some View {
        let totals = data.tasks
        return VStack(alignment: .leading, spacing: 10) {
            HomeDashboardSectionTitle(title: "home_dashboard_today", trailing: nil)
            HStack(alignment: .top, spacing: 0) {
                stat(totals.capturedToday, label: "home_dashboard_captured_today", tint: HomeTheme.accent)
                stat(totals.capturedWeek, label: "home_dashboard_captured_week", tint: HomeTheme.textPrimary)
                stat(totals.pending, label: "home_dashboard_pending", tint: HomeTheme.warning)
                stat(totals.done, label: "home_dashboard_done", tint: HomeTheme.success)
            }
            HomeDashboardBar(ratio: totals.doneRatio, tint: HomeTheme.success)
            HStack {
                Text(String(
                    format: String(localized: "home_dashboard_done_ratio %lld %lld"),
                    totals.done, totals.done + totals.pending))
                Spacer()
                if totals.ideas > 0 {
                    Text(String(format: String(localized: "home_dashboard_ideas %lld"), totals.ideas))
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(HomeTheme.textSecondary)
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
    }

    private func stat(_ value: Int, label: LocalizedStringKey, tint: Color) -> some View {
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
    }

    private var quietCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(HomeTheme.success)
            Text("home_dashboard_quiet")
                .font(.footnote)
                .foregroundStyle(HomeTheme.textSecondary)
            Spacer()
        }
        .padding(HomeTheme.cardPadding)
        .background(HomeDashboardCardBackground())
    }

    // MARK: Recent

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeDashboardSectionTitle(title: "home_dashboard_recent", trailing: nil)
            if data.recent.isEmpty {
                Text("home_dashboard_recent_empty")
                    .font(.footnote)
                    .foregroundStyle(HomeTheme.textSecondary)
            } else {
                ForEach(data.recent) { task in
                    Button {
                        actions.openRepo(task.repoCardID)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(task.isDone ? HomeTheme.success : HomeTheme.textSecondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title)
                                    .font(.footnote)
                                    .foregroundStyle(HomeTheme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(task.repoName + " · " + task.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.caption2)
                                    .foregroundStyle(HomeTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
    }

    // MARK: Busiest

    private var busiestCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeDashboardSectionTitle(title: "home_dashboard_busiest", trailing: nil)
            ForEach(data.busiest) { load in
                Button {
                    actions.openRepo(load.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(load.name)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(HomeTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(String(
                                format: String(localized: "home_dashboard_busiest_detail %lld %lld"),
                                load.pending, load.total))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(HomeTheme.textSecondary)
                        }
                        HomeDashboardBar(ratio: load.ratio, tint: HomeTheme.warning)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
    }

    private var appsPanelLink: some View {
        Button(action: actions.openApps) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeTheme.info)
                    .frame(width: 16)
                Text("apps_panel_open")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeTheme.textSecondary)
            }
            .padding(HomeTheme.cardPadding)
            .background(HomeDashboardCardBackground())
        }
        .buttonStyle(HomeCardButtonStyle())
    }

    private var appsHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(HomeTheme.info)
            Text("home_dashboard_apps_hint")
                .font(.footnote)
                .foregroundStyle(HomeTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(HomeTheme.cardPadding)
        .background(HomeDashboardCardBackground())
    }
}

// MARK: - Pieces

struct HomeDashboardCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
            .fill(HomeTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                    .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
            )
    }
}

struct HomeDashboardSectionTitle: View {
    let title: LocalizedStringKey
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeTheme.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(HomeTheme.textSecondary)
            }
        }
    }
}

/// A thin progress bar, 0 to 1.
struct HomeDashboardBar: View {
    let ratio: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(HomeTheme.surfaceElevated)
                Capsule().fill(tint)
                    .frame(width: geometry.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

#Preview("Start") {
    HomeDashboardView(
        data: HomeMockData.dashboard,
        account: HomeAccountMenuData(names: [HomeMockData.accountName], isPro: true))
        .background(HomeTheme.background)
        .preferredColorScheme(.dark)
}
