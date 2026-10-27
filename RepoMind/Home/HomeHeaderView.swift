import SwiftUI

// MARK: - Filter

/// What a row of filter chips can show: every case, each with a label.
protocol HomeChipOption: CaseIterable, Identifiable, Hashable where AllCases: RandomAccessCollection {
    var label: LocalizedStringKey { get }
}

enum HomeFilter: String, CaseIterable, Identifiable, HomeChipOption {
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

/// Everything above the first card: the account menu and the two actions on the first row, the
/// title on its own line below, then the stats strip and the filter chips. Search is not here:
/// it sits at the bottom, next to the tab bar, where iOS puts it now.
struct HomeHeaderView: View {
    var account = HomeAccountMenuData()
    let stats: HomeStats
    @Binding var filter: HomeFilter
    var onSelectAccount: (String?) -> Void = { _ in }
    var onUpgrade: () -> Void = {}
    var onSignOut: () -> Void = {}
    var onAdd: () -> Void = {}
    var onNotifications: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !account.names.isEmpty {
                    HomeAccountMenu(
                        account: account, onSelectAccount: onSelectAccount,
                        onUpgrade: onUpgrade, onSignOut: onSignOut)
                }
                if account.isDemo {
                    Text("demo_mode_badge")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeTheme.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HomeTheme.warning, in: Capsule())
                }
                Spacer(minLength: 4)
                HomeIconButton(symbol: "plus", label: "home_add_label", action: onAdd)
                HomeIconButton(symbol: "bell", label: "home_notifications_label", action: onNotifications)
            }
            Text("home_title")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(HomeTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HomeStatsStrip(stats: stats)
            HomeFilterChips(selection: $filter)
        }
    }
}

// MARK: - Account menu

/// Filter by account, upgrade, sign out: the same menu the classic list keeps behind the person
/// icon, hung from the account name instead. Shared by the start screen and the repo list.
struct HomeAccountMenu: View {
    let account: HomeAccountMenuData
    var onSelectAccount: (String?) -> Void = { _ in }
    var onUpgrade: () -> Void = {}
    var onSignOut: () -> Void = {}

    var body: some View {
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
            HStack(spacing: 5) {
                Image(systemName: "person.crop.circle")
                    .font(.subheadline)
                accountTitle
                if account.isPro {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(HomeTheme.accent)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(HomeTheme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Capsule().fill(HomeTheme.surfaceElevated))
            .overlay(Capsule().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
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
}

/// A small square action, hairline on an elevated surface: the header's plus and bell.
struct HomeIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
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
                .homeHitArea(extending: 6)
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
struct HomeFilterChips<Option: HomeChipOption>: View {
    @Binding var selection: Option
    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(Option.allCases) { filter in
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
