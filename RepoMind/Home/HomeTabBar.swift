import SwiftUI

// MARK: - Tabs

enum HomeTab: String, CaseIterable, Identifiable {
    case start
    case repos
    case tasks
    case settings

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .start: "home_tab_start"
        case .repos: "home_tab_repos"
        case .tasks: "home_tab_tasks"
        case .settings: "home_tab_settings"
        }
    }

    var symbol: String {
        switch self {
        case .start: "house"
        case .repos: "shippingbox"
        case .tasks: "checklist"
        case .settings: "gearshape"
        }
    }
}

// MARK: - Tab bar

/// A floating bar rather than the system one: the system bar cannot sit on pure black with a
/// hairline, and its tint would paint every glyph. Only the selected item carries the accent.
struct HomeTabBar: View {
    @Binding var selection: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.title3)
                            .symbolVariant(isSelected ? .fill : .none)
                        Text(tab.label)
                            .font(.caption2.weight(isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(isSelected ? HomeTheme.accent : HomeTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(HomeTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}
