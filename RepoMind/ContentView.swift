import SwiftData
import SwiftUI

// MARK: - Content View (Root Navigation)

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("isAuthenticated") private var isAuthenticated = false

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if isAuthenticated {
                    RepoListView()
                } else {
                    LoginView(isAuthenticated: $isAuthenticated)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isAuthenticated)

            ToastOverlay()
        }
    }
}

// MARK: - Repo Filter

enum RepoFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case archived

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .all: "filter_all"
        case .favorites: "filter_favorites"
        case .archived: "filter_archived"
        }
    }

    var iconName: String {
        switch self {
        case .all: "folder"
        case .favorites: "star.fill"
        case .archived: "archivebox"
        }
    }
}

// MARK: - Repo List View

struct RepoListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]

    @State private var isLoading = false
    @State private var searchText = ""
    @State private var activeFilter: RepoFilter = .all
    @State private var selectedAccount: GitHubAccount?

    // ✅ FIX: Cached filtered repos (Performance)
    @State private var filteredRepos: [ProjectRepo] = []

    var body: some View {
        NavigationStack {
            Group {
                if repos.isEmpty && isLoading {
                    skeletonList
                } else if repos.isEmpty {
                    emptyState
                } else {
                    repoList
                }
            }
            .navigationTitle("repositories_title")
            .searchable(text: $searchText, prompt: "search_placeholder")
            .toolbar { toolbarContent }
            .refreshable {
                await syncRepos()
            }
            .task {
                updateFilteredRepos()
                if repos.isEmpty {
                    await syncRepos()
                }
            }
            // ✅ FIX: Update cache when dependencies change
            .onChange(of: repos) { _, _ in
                updateFilteredRepos()
            }
            .onChange(of: activeFilter) { _, _ in
                updateFilteredRepos()
            }
            .onChange(of: searchText) { _, _ in
                updateFilteredRepos()
            }
            .onChange(of: selectedAccount) { _, _ in
                updateFilteredRepos()
            }
        }
    }

    // MARK: - Cached Filtering (Performance Fix)

    private func updateFilteredRepos() {
        var result = repos

        switch activeFilter {
        case .all:
            result = result.filter { !$0.isArchived }
        case .favorites:
            result = result.filter { $0.isFavorite && !$0.isArchived }
        case .archived:
            result = result.filter { $0.isArchived }
        }

        if let account = selectedAccount {
            result = result.filter { $0.account?.id == account.id }
        }

        // ✅ FIX: Use localizedStandardContains for better search
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedStandardContains(searchText)
                    || $0.repoDescription.localizedStandardContains(searchText)
            }
        }

        filteredRepos = result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            accountMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                filterMenu
                syncButton
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            Picker("accounts_filter", selection: $selectedAccount) {
                Text("all_accounts").tag(nil as GitHubAccount?)
                ForEach(accounts) { account in
                    Text(account.username).tag(account as GitHubAccount?)
                }
            }

            Divider()

            Button(role: .destructive, action: logout) {
                Label("sign_out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Group {
                if let account = selectedAccount {
                    Image(
                        systemName: account.isPro
                            ? "person.crop.circle.badge.checkmark" : "person.crop.circle"
                    )
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(account.isPro ? .purple : .primary)
                } else {
                    Image(systemName: "person.2.circle")
                }
            }
            .font(.title3)
        }
        .accessibilityLabel("account_menu_label")
        .accessibilityHint(selectedAccount?.username ?? String(localized: "all_accounts"))
    }

    // ✅ FIX: Use Label instead of just Image for accessibility
    private var filterMenu: some View {
        Menu {
            ForEach(RepoFilter.allCases) { filter in
                Button {
                    withAnimation { activeFilter = filter }
                } label: {
                    Label(filter.displayName, systemImage: filter.iconName)
                }
            }
        } label: {
            Label(
                "filter_repos_label",
                systemImage: activeFilter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("filter_repos_label")
        .accessibilityValue(Text(activeFilter.displayName))
    }

    // ✅ FIX: Use Label instead of just Image for accessibility
    private var syncButton: some View {
        Button {
            Task { await syncRepos() }
        } label: {
            if isLoading {
                ProgressView()
            } else {
                Label("sync_repos_label", systemImage: "arrow.trianglehead.2.clockwise")
                    .labelStyle(.iconOnly)
            }
        }
        .disabled(isLoading)
        .accessibilityLabel("sync_repos_label")
        .accessibilityHint(isLoading ? "syncing" : "sync_hint")
    }

    // MARK: - Skeleton Loading

    private var skeletonList: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRepoRow()
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Repo List

    private var repoList: some View {
        List {
            ForEach(filteredRepos) { repo in
                NavigationLink(value: repo) {
                    RepoRow(repo: repo)
                }
                .swipeActions(edge: .leading) {
                    favoriteButton(for: repo)
                }
                .swipeActions(edge: .trailing) {
                    deleteButton(for: repo)
                    archiveButton(for: repo)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: ProjectRepo.self) { repo in
            KanbanView(project: repo)
        }
        .overlay {
            if filteredRepos.isEmpty && !repos.isEmpty {
                emptyFilterState
            }
        }
    }

    // MARK: - Swipe Action Buttons (Extracted for clarity)

    private func favoriteButton(for repo: ProjectRepo) -> some View {
        Button {
            withAnimation { repo.isFavorite.toggle() }
        } label: {
            Label(
                repo.isFavorite ? "unfavorite" : "favorite",
                systemImage: repo.isFavorite ? "star.slash" : "star.fill"
            )
        }
        .tint(.yellow)
    }

    private func deleteButton(for repo: ProjectRepo) -> some View {
        Button(role: .destructive) {
            withAnimation { context.delete(repo) }
        } label: {
            Label("delete_task", systemImage: "trash")
        }
    }

    private func archiveButton(for repo: ProjectRepo) -> some View {
        Button {
            withAnimation { repo.isArchived.toggle() }
        } label: {
            Label(
                repo.isArchived ? "unarchive" : "archive",
                systemImage: repo.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        .tint(.indigo)
    }

    // MARK: - Empty States

    private var emptyFilterState: some View {
        ContentUnavailableView {
            Label(
                activeFilter == .archived ? "no_archived_title" : "no_results_title",
                systemImage: activeFilter == .archived ? "archivebox" : "magnifyingglass"
            )
        } description: {
            switch activeFilter {
            case .archived:
                Text("no_archived_message")
            case .favorites:
                Text("no_favorites_message")
            case .all:
                Text("no_results_message")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("no_repos_title", systemImage: "tray")
        } description: {
            Text("Conecta una cuenta para empezar")
        } actions: {
            Button("sync_button") {
                Task { await syncRepos() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func syncRepos() async {
        isLoading = true
        defer { isLoading = false }

        guard !accounts.isEmpty else { return }

        do {
            for account in accounts {
                if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey)
                {
                    try await GitHubService.shared.syncRepos(
                        account: account,
                        token: token,
                        into: context
                    )
                }
            }

            if !repos.isEmpty {
                ToastManager.shared.show(String(localized: "repos_synced_toast"), style: .success)
            }
        } catch {
            ToastManager.shared.show(error.localizedDescription, style: .error)
        }
    }

    private func logout() {
        Task {
            try? context.delete(model: GitHubAccount.self)
            try? context.delete(model: ProjectRepo.self)
            try? await KeychainManager.shared.deleteToken()

            withAnimation {
                isAuthenticated = false
            }
        }
    }
}

// MARK: - Skeleton Repo Row

struct SkeletonRepoRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("nombre-repositorio")
                    .font(.headline)
                Spacer()
                Text("Swift")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Text("Descripcion del repositorio placeholder que ocupa dos lineas como minimo")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text("Hace 2 horas")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "star")
                        .font(.caption2)
                    Text("42")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - Repo Row

struct RepoRow: View {
    let repo: ProjectRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if repo.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }

                Text(repo.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if let language = repo.language {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                Text("\(repo.tasks?.count ?? 0)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if !repo.repoDescription.isEmpty {
                Text(repo.repoDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(repo.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if repo.stargazersCount > 0 {
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "star")
                            .font(.caption2)
                        Text("\(repo.stargazersCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("view_details_hint")
    }

    // ✅ FIX: Better accessibility description
    private var accessibilityDescription: String {
        var parts = [repo.name]
        if repo.isFavorite {
            parts.append(String(localized: "favorite"))
        }
        parts.append("\(repo.tasks?.count ?? 0) tareas")
        if repo.stargazersCount > 0 {
            parts.append("\(repo.stargazersCount) estrellas")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ProjectRepo.self, TaskItem.self], inMemory: true)
}
