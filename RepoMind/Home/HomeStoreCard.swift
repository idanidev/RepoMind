import Charts
import Foundation
import SwiftUI

// MARK: - Data

/// One app of the App Store as the start screen draws it: what is out, what is on its way, what sits
/// in TestFlight unsent, and the downloads. Value-typed, built from `StoreStatus.StoreApp`.
struct HomeStoreApp: Hashable, Identifiable {
    let id: String
    /// The repo's name when the app is built from one of the user's repos, else the store's name.
    let name: String
    /// The `homeCardID` of that repo, to open its board.
    let repoCardID: String?
    let releases: [StoreRelease]
    let build: StoreStatus.Build?
    /// A build newer than the published version that nobody sent to review.
    let unsubmitted: StoreStatus.Build?
    let downloads: StoreDownloads?
}

extension HomeStoreApp {
    init(app: StoreStatus.StoreApp, repos: [ProjectRepo]) {
        let best = app.bestRepoName(in: repos.map(\.name))
        let repo = best.flatMap { name in repos.first { $0.name == name } }
        self.init(
            id: app.id, name: repo?.name ?? app.name, repoCardID: repo?.homeCardID, releases: app.releases,
            build: app.latestBuild, unsubmitted: app.unsubmittedBuild, downloads: app.downloads)
    }
}

// MARK: - Card

/// Which version of each app is on the App Store, which is waiting, and how many people downloaded it.
struct HomeStoreCard: View {
    let apps: [HomeStoreApp]
    let updatedAt: Date?
    var onOpenRepo: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeDashboardSectionTitle(
                title: "home_store_title",
                trailing: updatedAt.map { $0.formatted(.relative(presentation: .named)) })
            if let updatedAt, Date.now.timeIntervalSince(updatedAt) > StoreStatus.staleAfter {
                HomeChip(
                    symbol: "clock.badge.exclamationmark", text: String(localized: "home_store_stale"),
                    tint: HomeTheme.warning)
            }
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 {
                    Divider().overlay(HomeTheme.hairline)
                }
                row(app)
            }
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
    }

    @ViewBuilder
    private func row(_ app: HomeStoreApp) -> some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            Text(app.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeTheme.textPrimary)
            HomeFlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(app.releases) { release in
                    releaseChips(release, showPlatform: app.releases.count > 1)
                }
                if let build = app.build {
                    HomeChip(symbol: "airplane", text: buildText(build))
                }
                if let unsent = app.unsubmitted {
                    HomeChip(
                        symbol: "exclamationmark.triangle.fill",
                        text: String(format: String(localized: "home_store_unsent %@"), unsent.version ?? ""),
                        tint: HomeTheme.warning)
                }
            }
            if let downloads = app.downloads {
                downloadsRow(downloads)
            }
        }
        if let id = app.repoCardID {
            Button { onOpenRepo(id) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private func releaseChips(_ release: StoreRelease, showPlatform: Bool) -> some View {
        let prefix = showPlatform ? release.platformName + " " : ""
        if let live = release.live {
            HomeChip(symbol: "checkmark.seal.fill", text: prefix + live.version, tint: HomeTheme.success)
        } else if release.pending == nil {
            HomeChip(symbol: "minus.circle", text: prefix + String(localized: "home_store_not_published"))
        }
        if let pending = release.pending {
            let style = Self.style(for: pending.kind)
            HomeChip(
                symbol: style.symbol,
                text: prefix + pending.version + " · " + style.title,
                tint: style.tint)
        }
    }

    private func buildText(_ build: StoreStatus.Build) -> String {
        let number = String(build.build.suffix(4))
        guard let version = build.version else { return "TestFlight " + number }
        return "TestFlight \(version) (\(number))"
    }

    private func downloadsRow(_ downloads: StoreDownloads) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                figure(downloads.last7, label: "home_store_downloads_7")
                figure(downloads.last30, label: "home_store_downloads_30")
                if downloads.purchases(lastDays: 30) > 0 {
                    figure(downloads.purchases(lastDays: 30), label: "home_store_purchases_30")
                }
                Spacer(minLength: 0)
            }
            if downloads.hasActivity, downloads.sparkline.count > 1 {
                Chart(Array(downloads.sparkline.enumerated()), id: \.offset) { point in
                    BarMark(x: .value("chart_axis_day", point.offset), y: .value("chart_axis_downloads", point.element))
                        .foregroundStyle(HomeTheme.accent.opacity(0.8))
                        .cornerRadius(1.5)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 30)
            }
        }
    }

    private func figure(_ value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.formatted())
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(HomeTheme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(HomeTheme.textSecondary)
        }
    }

    /// How a pending version reads, and in what color: red for a rejection, amber for what waits on
    /// the developer, blue for what waits on Apple.
    static func style(for state: StoreVersionState) -> (title: String, symbol: String, tint: Color) {
        switch state {
        case .waitingForReview: (String(localized: "home_store_state_waiting"), "hourglass", HomeTheme.info)
        case .inReview: (String(localized: "home_store_state_in_review"), "eye.fill", HomeTheme.info)
        case .approved: (String(localized: "home_store_state_approved"), "checkmark.circle", HomeTheme.warning)
        case .rejected: (String(localized: "home_store_state_rejected"), "xmark.octagon.fill", HomeTheme.danger)
        case .draft: (String(localized: "home_store_state_draft"), "pencil", HomeTheme.warning)
        case .processing: (String(localized: "home_store_state_processing"), "gearshape.2.fill", HomeTheme.info)
        case .live, .removed, .replaced, .other: ("", "circle", HomeTheme.textSecondary)
        }
    }
}
