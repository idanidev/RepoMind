import Charts
import Foundation
import SwiftUI

// MARK: - Headline

/// The numbers at the top: two per row, each with its change against the period before.
struct BoardStatsHeadlineGrid: View {
    let items: [RepoStats.Headline]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(HomeTheme.textSecondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.value.map { $0.formatted() } ?? "—")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(HomeTheme.textPrimary)
                        if let value = item.value,
                           let change = RepoStats.change(current: value, previous: item.previous) {
                            BoardStatsDelta(change: change)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(BoardStatsCard())
            }
        }
    }
}

// MARK: - Series

/// One daily series as bars, with the period total on the title.
struct BoardStatsSeriesCard: View {
    let series: RepoStats.Series
    let periodDays: Int

    private var points: [BoardStatsDay] {
        series.points.compactMap { point in
            RepoStats.day(from: point.date).map { BoardStatsDay(day: $0, value: point.value) }
        }
    }

    var body: some View {
        let points = self.points
        // A counter adds up over the period; a gauge (paying subscribers) is a level, and adding the
        // days up said 120 "paying" for four people.
        let total = series.isGauge ? (points.last?.value ?? 0) : points.reduce(0) { $0 + $1.value }
        VStack(alignment: .leading, spacing: 8) {
            BoardStatsSectionTitle(title: series.label, trailing: total.formatted())
            if points.isEmpty {
                Text("stats_no_data")
                    .font(.caption)
                    .foregroundStyle(HomeTheme.textSecondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        BarMark(
                            x: .value("chart_axis_day", point.day, unit: .day),
                            y: .value("chart_axis_value", point.value))
                            .foregroundStyle(HomeTheme.accent)
                            .cornerRadius(2)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .frame(height: 140)
                Text("stats_period \(periodDays)")
                    .font(.caption2)
                    .foregroundStyle(HomeTheme.textSecondary)
            }
        }
        .padding(12)
        .background(BoardStatsCard())
    }
}

/// One bar of the chart: a calendar day and its count.
struct BoardStatsDay: Identifiable {
    let day: Date
    let value: Int

    var id: Date { day }
}

// MARK: - Signals

/// What gets used, grouped by family and ordered from most to least.
struct BoardStatsSignalsCard: View {
    let stats: RepoStats

    @State private var showAll = false

    var body: some View {
        let families = stats.signalFamilies
        let shown = showAll ? families : Array(families.prefix(3))
        VStack(alignment: .leading, spacing: 12) {
            BoardStatsSectionTitle(
                title: String(localized: "stats_section_signals"),
                trailing: String(localized: "stats_period \(stats.periodDays)")
            )
            ForEach(shown) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.family.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(HomeTheme.textSecondary)
                    ForEach(group.signals) { signal in
                        row(signal, family: group.family)
                    }
                }
            }
            if families.count > 3 {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { showAll.toggle() }
                } label: {
                    Text(showAll ? "stats_show_less" : "stats_show_all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(BoardStatsCard())
    }

    private func row(_ signal: RepoStats.Signal, family: String) -> some View {
        let prefix = family + "."
        let name = signal.key.hasPrefix(prefix) ? String(signal.key.dropFirst(prefix.count)) : signal.key
        return HStack(spacing: 8) {
            Text(name)
                .font(.caption.monospaced())
                .foregroundStyle(HomeTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let change = RepoStats.change(current: signal.current, previous: signal.previous) {
                BoardStatsDelta(change: change)
            }
            Text(signal.current.formatted())
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(HomeTheme.textPrimary)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}

// MARK: - Features

/// Adoption per feature: how many of the population use it lately, and ever.
struct BoardStatsFeaturesCard: View {
    let features: [RepoStats.Feature]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BoardStatsSectionTitle(title: String(localized: "stats_section_features"), trailing: nil)
            ForEach(features) { feature in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(feature.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeTheme.textPrimary)
                        Spacer()
                        Text(adoptionText(feature))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(HomeTheme.textSecondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(HomeTheme.surfaceElevated)
                            Capsule().fill(HomeTheme.accent)
                                .frame(width: geometry.size.width * ratio(feature))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(12)
        .background(BoardStatsCard())
    }

    private func adoptionText(_ feature: RepoStats.Feature) -> String {
        String(
            format: String(localized: "stats_adoption_row %lld %lld %lld"),
            feature.activeAdopters, feature.population, feature.adopters
        )
    }

    private func ratio(_ feature: RepoStats.Feature) -> Double {
        guard feature.population > 0 else { return 0 }
        return min(1, Double(feature.activeAdopters) / Double(feature.population))
    }
}

// MARK: - Versions

struct BoardStatsVersionsCard: View {
    let versions: [RepoStats.Version]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BoardStatsSectionTitle(title: String(localized: "stats_section_versions"), trailing: nil)
            HomeFlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(versions) { version in
                    let name = version.version ?? String(localized: "stats_version_unknown")
                    HomeChip(symbol: "tag.fill", text: name + " · " + version.current.formatted())
                }
            }
        }
        .padding(12)
        .background(BoardStatsCard())
    }
}

// MARK: - Issues

/// The latest crashes and reports. A report with a URL opens it.
struct BoardStatsIssuesCard: View {
    let issues: [RepoStats.Issue]

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BoardStatsSectionTitle(title: String(localized: "stats_section_issues"), trailing: nil)
            ForEach(issues) { issue in
                row(issue)
            }
        }
        .padding(12)
        .background(BoardStatsCard())
    }

    private func row(_ issue: RepoStats.Issue) -> some View {
        let link = SafeLink.web(issue.url)
        let face = HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.isCrash ? "exclamationmark.octagon.fill" : "bubble.left.fill")
                .font(.subheadline)
                .foregroundStyle(issue.isCrash ? HomeTheme.danger : HomeTheme.warning)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.subheadline)
                    .foregroundStyle(HomeTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(caption(issue))
                    .font(.caption2)
                    .foregroundStyle(HomeTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if link != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(HomeTheme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        // A button only when the backend gave a link worth opening: a disabled one reads "dimmed".
        return Group {
            if let link {
                Button { openURL(link) } label: { face }
                    .buttonStyle(.plain)
            } else {
                face.accessibilityElement(children: .combine)
            }
        }
    }

    private func caption(_ issue: RepoStats.Issue) -> String {
        var parts = [String(localized: issue.isCrash ? "stats_issue_crash" : "stats_issue_report")]
        parts.append(issue.at.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
        if issue.count > 1 {
            parts.append(String(localized: "stats_times \(issue.count)"))
        }
        if let version = issue.version, !version.isEmpty {
            parts.append(version)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Pieces

struct BoardStatsSectionTitle: View {
    let title: String
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
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

/// An arrow and a percentage, green up, red down.
struct BoardStatsDelta: View {
    let change: Double

    var body: some View {
        let percent = abs(Int((change * 100).rounded()))
        let symbol = change > 0 ? "arrow.up.right" : (change < 0 ? "arrow.down.right" : "arrow.right")
        let tint = change > 0 ? HomeTheme.success : (change < 0 ? HomeTheme.danger : HomeTheme.textSecondary)
        HStack(spacing: 2) {
            Image(systemName: symbol)
            Text(verbatim: "\(percent)%")
        }
        .font(.caption2.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(tint)
    }
}

/// The card every section sits on.
struct BoardStatsCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
            .fill(HomeTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                    .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
            )
    }
}
