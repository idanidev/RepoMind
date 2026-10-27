import Foundation
import SwiftUI

// MARK: - Repo card

/// One repository on the home screen.
///
/// Every row below the title is optional and driven by the data: a card only grows for what it
/// can say, and the chips that carry a warning (feedback, unpublished tasks, a failing build)
/// exist only while there is something to warn about. The hero (`isFeatured`) gets a glowing
/// border and the task preview; everything else sits on a hairline.
struct HomeRepoCardView: View {
    let repo: HomeRepoCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                HomeRepoLogo(repo: repo, size: repo.isFeatured ? 64 : 48)
                    .shadow(color: HomeTheme.info.opacity(repo.isFeatured ? 0.45 : 0), radius: 10)
                VStack(alignment: .leading, spacing: 5) {
                    titleRow
                    if !repo.description.isEmpty {
                        Text(repo.description)
                            .font(.footnote)
                            .foregroundStyle(HomeTheme.textSecondary)
                            .lineLimit(repo.isFeatured ? 2 : 1)
                    }
                    activityLine
                }
            }
            if repo.isFeatured, !repo.taskPreview.isEmpty {
                taskPreview
            }
            metaRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HomeTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                .fill(HomeTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                .strokeBorder(border, lineWidth: repo.isFeatured ? 1 : 0.5)
        )
        .shadow(color: HomeTheme.success.opacity(repo.isFeatured ? 0.22 : 0), radius: 18, y: 6)
        .opacity(repo.isInactive ? 0.75 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if repo.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(HomeTheme.star)
                    .accessibilityLabel("favorite")
            }
            Text(repo.name)
                .font(repo.isFeatured ? Font.title2.weight(.bold) : Font.headline.weight(.bold))
                .foregroundStyle(HomeTheme.textPrimary)
                .lineLimit(1)
            if repo.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(HomeTheme.textSecondary)
                    .accessibilityLabel("home_private_label")
            }
            Spacer(minLength: 6)
            if repo.isInactive {
                HomeInactiveBadge()
            }
        }
    }

    private var activityLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10))
            Text(activityText)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(HomeTheme.textSecondary)
    }

    private var taskPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(repo.taskPreview) { task in
                HStack(spacing: 6) {
                    Image(systemName: "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(HomeTheme.accent)
                    Text(task.title)
                        .foregroundStyle(HomeTheme.textPrimary)
                        .lineLimit(2)
                }
                .font(.caption)
            }
        }
    }

    private var metaRow: some View {
        HomeFlowLayout(spacing: 6, rowSpacing: 6) {
            if let language = repo.language {
                HomeLanguageChip(language: language)
            }
            if repo.stars > 0 {
                HomeChip(symbol: "star.fill", text: repo.stars.formatted(), symbolTint: HomeTheme.star)
            }
            if repo.tasksTotal > 0 {
                HomeChip(symbol: "checklist", text: tasksText)
            }
            if repo.alerts > 0 {
                HomeChip(symbol: "bell.badge.fill", text: repo.alerts.formatted(), tint: HomeTheme.warning)
            }
            if repo.unpublished > 0 {
                HomeChip(
                    symbol: "arrow.up.circle",
                    text: format("home_unpublished_chip %lld", repo.unpublished),
                    tint: HomeTheme.danger
                )
            }
            if repo.isSyncDisabled {
                HomeChip(
                    symbol: "exclamationmark.triangle.fill",
                    text: String(localized: "home_sync_disabled_chip"),
                    tint: HomeTheme.danger
                )
            }
            if let prs = repo.pullRequests, prs > 0 {
                HomeChip(
                    symbol: "arrow.triangle.pull",
                    text: format("home_prs_count %lld", prs),
                    tint: HomeTheme.accent
                )
            }
            if repo.isBuildFailing {
                HomeChip(
                    symbol: "xmark.circle.fill",
                    text: String(localized: "home_build_failing"),
                    tint: HomeTheme.danger
                )
            }
            if let version = repo.version {
                HomeChip(symbol: "tag.fill", text: version)
            }
        }
    }

    // MARK: Text

    private var border: AnyShapeStyle {
        guard repo.isFeatured else { return AnyShapeStyle(HomeTheme.hairline) }
        return AnyShapeStyle(
            LinearGradient(
                colors: [HomeTheme.success.opacity(0.8), HomeTheme.success.opacity(0.25), HomeTheme.hairline],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var activityText: String {
        if let lastPush = repo.lastPush {
            return String(format: String(localized: "home_last_push %@"), relative(lastPush))
        }
        return String(format: String(localized: "home_last_activity %@"), relative(repo.lastActivity))
    }

    private var tasksText: String {
        var text = String(format: String(localized: "tasks_count"), repo.tasksTotal)
        if repo.tasksPending > 0 {
            text += " " + format("home_tasks_pending %lld", repo.tasksPending)
        }
        return text
    }

    private func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    private func format(_ key: String.LocalizationValue, _ value: Int) -> String {
        String(format: String(localized: key), value)
    }
}

// MARK: - Previews

#Preview("Cards · dark") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(HomeMockData.repos) { HomeRepoCardView(repo: $0) }
        }
        .padding()
    }
    .background(HomeTheme.background)
    .preferredColorScheme(.dark)
}

#Preview("Cards · light") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(HomeMockData.repos) { HomeRepoCardView(repo: $0) }
        }
        .padding()
    }
    .background(HomeTheme.background)
    .preferredColorScheme(.light)
}
