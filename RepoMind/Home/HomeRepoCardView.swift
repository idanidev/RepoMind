import Foundation
import SwiftUI

// MARK: - Repo card

/// One repository on the home screen.
///
/// Every row below the title is optional and driven by the data: a card only grows for what it
/// can say. The hero (`isFeatured`) and the user's own app (`isOwnApp`) get a glowing border;
/// everything else sits on a hairline.
struct HomeRepoCardView: View {
    let repo: HomeRepoCardData

    private var isHighlighted: Bool { repo.isFeatured || repo.isOwnApp }
    private var glow: Color { repo.isOwnApp ? HomeTheme.accent : HomeTheme.success }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if repo.isOwnApp {
                ownAppTag
            }
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
            if let history = repo.commitsLast7Days {
                sparklineRow(history)
            }
            if !repo.taskPreview.isEmpty {
                taskList
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
                .strokeBorder(border, lineWidth: isHighlighted ? 1 : 0.5)
        )
        .shadow(color: glow.opacity(isHighlighted ? 0.22 : 0), radius: 18, y: 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    private var ownAppTag: some View {
        Text("home_badge_your_app")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(HomeTheme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(HomeTheme.surfaceElevated))
            .overlay(Capsule().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
    }

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
            if let branch = repo.branch {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(branch)
                }
                .font(.caption.monospaced())
                .foregroundStyle(HomeTheme.textSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let status = repo.status {
                HomeStatusBadge(status: status, version: repo.isFeatured ? repo.version : nil)
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

    private func sparklineRow(_ history: [Int]) -> some View {
        HStack(alignment: .bottom) {
            Text("home_commits_7d")
                .font(.caption2)
                .foregroundStyle(HomeTheme.textSecondary)
            Spacer()
            HomeCommitSparkline(values: history)
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = repo.progress {
                HomeProgressBar(progress: progress)
            }
            HomeFlowLayout(spacing: 14, rowSpacing: 6) {
                ForEach(repo.taskPreview) { task in
                    HStack(spacing: 5) {
                        Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(task.isDone ? HomeTheme.success : HomeTheme.textSecondary)
                        Text(task.title)
                            .foregroundStyle(task.isDone ? HomeTheme.textSecondary : HomeTheme.textPrimary)
                            .strikethrough(task.isDone, color: HomeTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var metaRow: some View {
        HomeFlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(repo.languages) { HomeLanguageChip(share: $0) }
            if repo.stars > 0 {
                HomeChip(symbol: "star.fill", text: repo.stars.formatted(), symbolTint: HomeTheme.star)
            }
            if let issues = repo.openIssues, issues > 0 {
                HomeChip(symbol: "smallcircle.filled.circle", text: format("home_open_issues %lld", issues))
            }
            if repo.tasksTotal > 0 {
                HomeChip(symbol: "checklist", text: tasksText)
            }
            if let build = repo.build {
                HomeChip(symbol: build.symbol, text: build.title, tint: build.tint)
            }
            if let prs = repo.pullRequests {
                HomeChip(
                    symbol: "arrow.triangle.pull",
                    text: format("home_prs_count %lld", prs),
                    tint: prs > 0 ? HomeTheme.accent : nil
                )
            }
            if let alerts = repo.alerts, alerts > 0 {
                HomeChip(symbol: "exclamationmark.triangle.fill", text: alerts.formatted(), tint: HomeTheme.warning)
            }
            if let version = repo.version, !repo.isFeatured {
                HomeChip(symbol: "tag.fill", text: version)
            }
            if let collaborators = repo.collaborators {
                HomeChip(symbol: "person.2.fill", text: format("home_collaborators_count %lld", collaborators))
            }
        }
    }

    // MARK: Text

    private var border: AnyShapeStyle {
        guard isHighlighted else { return AnyShapeStyle(HomeTheme.hairline) }
        return AnyShapeStyle(
            LinearGradient(
                colors: [glow.opacity(0.8), glow.opacity(0.25), HomeTheme.hairline],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var activityText: String {
        guard let commit = repo.lastCommit else {
            return String(format: String(localized: "home_last_activity %@"), relative(repo.lastActivity))
        }
        return String(
            format: String(localized: "home_last_commit_detail"),
            relative(commit.date), commit.message, commit.author
        )
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
