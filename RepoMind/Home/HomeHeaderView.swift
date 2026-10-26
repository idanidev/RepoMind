import SwiftUI

// MARK: - Filter

enum HomeFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case tasks

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .all: "home_filter_all"
        case .favorites: "home_filter_favorites"
        case .tasks: "home_filter_tasks"
        }
    }

    func apply(to repos: [HomeRepoCardData]) -> [HomeRepoCardData] {
        switch self {
        case .all: repos
        case .favorites: repos.filter(\.isFavorite)
        case .tasks: repos.filter { $0.tasksPending > 0 }
        }
    }
}

// MARK: - Header

/// Title, account, the three actions, the stats strip and the filter chips — everything above
/// the first card. Search is inline: tapping the glass opens a field under the title instead of
/// pushing the whole screen into a navigation bar it does not otherwise have. Filtering lives
/// in the chips, so there is no separate filter button.
struct HomeHeaderView: View {
    var accountName: String?
    let stats: HomeStats
    @Binding var filter: HomeFilter
    @Binding var isSearching: Bool
    @Binding var searchText: String
    var onAdd: () -> Void = {}
    var onNotifications: () -> Void = {}

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            if isSearching {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HomeStatsStrip(stats: stats)
            HomeFilterChips(selection: $filter)
        }
        .onChange(of: isSearching) { _, searching in
            searchFocused = searching
            if !searching {
                searchText = ""
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("home_title")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeTheme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let accountName {
                    Text(verbatim: "•")
                        .foregroundStyle(HomeTheme.textSecondary)
                    HStack(spacing: 3) {
                        Text(accountName)
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(HomeTheme.textSecondary)
                    .lineLimit(1)
                    .accessibilityLabel("account_menu_label")
                    .accessibilityValue(accountName)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                iconButton("magnifyingglass", label: "home_search_label") {
                    withAnimation(.snappy(duration: 0.25)) { isSearching.toggle() }
                }
                iconButton("plus", label: "home_add_label", action: onAdd)
                iconButton("bell", label: "home_notifications_label", action: onNotifications)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HomeTheme.textSecondary)
            TextField("search_placeholder", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(HomeTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HomeTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("home_clear_search_label")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
        )
    }

    private func iconButton(
        _ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeTheme.textPrimary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HomeTheme.surfaceElevated))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Stats strip

/// "6 repos • 8 pending • 4 alerts • 2 unpublished". Alerts and unpublished only appear when
/// non-zero. Scrolls sideways rather than shrinking when a large Dynamic Type size or a long
/// translation does not fit.
struct HomeStatsStrip: View {
    let stats: HomeStats

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                Text("home_stat_total \(stats.totalRepos)")
                    .foregroundStyle(HomeTheme.success)
                separator
                Text("home_stat_pending \(stats.pendingTasks)")
                    .foregroundStyle(stats.pendingTasks > 0 ? HomeTheme.accent : HomeTheme.textSecondary)
                if stats.alerts > 0 {
                    separator
                    Text("home_stat_alerts \(stats.alerts)")
                        .foregroundStyle(HomeTheme.warning)
                }
                if stats.unpublished > 0 {
                    separator
                    Text("home_stat_unpublished \(stats.unpublished)")
                        .foregroundStyle(HomeTheme.danger)
                }
            }
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var separator: some View {
        Text(verbatim: "•")
            .foregroundStyle(HomeTheme.textSecondary)
    }
}

// MARK: - Filter chips

/// Segmented chips with a pill that slides to the selection.
struct HomeFilterChips: View {
    @Binding var selection: HomeFilter
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HomeFilter.allCases) { filter in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = filter }
                } label: {
                    Text(filter.label)
                        .font(.footnote.weight(selection == filter ? .semibold : .medium))
                        .foregroundStyle(selection == filter ? HomeTheme.textPrimary : HomeTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selection == filter {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(HomeTheme.surfaceElevated)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HomeTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
        )
    }
}
