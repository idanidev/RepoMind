import SwiftUI

// MARK: - Filter

enum HomeFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case tasks
    case archived

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .all: "home_filter_all"
        case .favorites: "home_filter_favorites"
        case .tasks: "home_filter_tasks"
        case .archived: "home_filter_archived"
        }
    }

    /// Archived repos only ever show under their own chip, as in the classic list.
    func apply(to repos: [HomeRepoCardData]) -> [HomeRepoCardData] {
        switch self {
        case .all: repos.filter { !$0.isArchived }
        case .favorites: repos.filter { $0.isFavorite && !$0.isArchived }
        case .tasks: repos.filter { $0.tasksPending > 0 && !$0.isArchived }
        case .archived: repos.filter(\.isArchived)
        }
    }
}

// MARK: - Account menu

/// What the account menu shows: the accounts to filter by, the one selected, and the two
/// facts that decide which entries appear.
struct HomeAccountMenuData: Hashable {
    var names: [String] = []
    var selected: String?
    var isPro = false
    var isDemo = false
}

// MARK: - Header

/// Title, account menu, the three actions, the stats strip and the filter chips — everything
/// above the first card. Search is inline: tapping the glass opens a field under the title instead
/// of pushing the whole screen into a navigation bar it does not otherwise have. Filtering lives
/// in the chips, so there is no separate filter button.
struct HomeHeaderView: View {
    var account = HomeAccountMenuData()
    let stats: HomeStats
    @Binding var filter: HomeFilter
    @Binding var isSearching: Bool
    @Binding var searchText: String
    var onSelectAccount: (String?) -> Void = { _ in }
    var onUpgrade: () -> Void = {}
    var onSignOut: () -> Void = {}
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
                if !account.names.isEmpty {
                    Text(verbatim: "•")
                        .foregroundStyle(HomeTheme.textSecondary)
                    accountMenu
                }
                if account.isDemo {
                    Text("demo_mode_badge")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HomeTheme.warning, in: Capsule())
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

    /// Filter by account, upgrade, sign out — the same menu the classic list keeps behind the
    /// person icon, hung from the account name instead.
    private var accountMenu: some View {
        Menu {
            Picker("accounts_filter", selection: accountSelection) {
                Text("all_accounts").tag(nil as String?)
                ForEach(account.names, id: \.self) { name in
                    Text(name).tag(name as String?)
                }
            }
            Divider()
            if !account.isPro {
                Button(action: onUpgrade) {
                    Label("upgrade_to_pro_button", systemImage: "crown")
                }
            }
            Button(role: .destructive, action: onSignOut) {
                Label("sign_out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 3) {
                accountTitle
                if account.isPro {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(HomeTheme.accent)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(HomeTheme.textSecondary)
            .lineLimit(1)
        }
        .accessibilityLabel("account_menu_label")
    }

    @ViewBuilder
    private var accountTitle: some View {
        if let selected = account.selected {
            Text(selected)
        } else if account.names.count == 1, let only = account.names.first {
            Text(only)
        } else {
            Text("all_accounts")
        }
    }

    private var accountSelection: Binding<String?> {
        Binding(get: { account.selected }, set: { onSelectAccount($0) })
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

/// Segmented chips with a pill that slides to the selection. Scrolls sideways if four chips do
/// not fit at a large Dynamic Type size.
struct HomeFilterChips: View {
    @Binding var selection: HomeFilter
    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(HomeFilter.allCases) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { selection = filter }
                    } label: {
                        Text(filter.label)
                            .font(.footnote.weight(selection == filter ? .semibold : .medium))
                            .foregroundStyle(selection == filter ? HomeTheme.textPrimary : HomeTheme.textSecondary)
                            .lineLimit(1)
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
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}
