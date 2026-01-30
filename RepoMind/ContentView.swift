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

            // Toast overlay — sits on top of all navigation
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

    var displayName: String {
        switch self {
        case .all: "Todos"
        case .favorites: "Favoritos"
        case .archived: "Archivados"
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
    @State private var selectedAccount: GitHubAccount?  // nil = All Accounts

    private var filteredRepos: [ProjectRepo] {
        var result = repos

        // Apply filter
        switch activeFilter {
        case .all:
            result = result.filter { !$0.isArchived }
        case .favorites:
            result = result.filter { $0.isFavorite && !$0.isArchived }
        case .archived:
            result = result.filter { $0.isArchived }
        }

        // Apply Account Filter
        if let account = selectedAccount {
            result = result.filter { $0.account?.id == account.id }
        }

        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.repoDescription.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort: favorites first, then by date
        return result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

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
            .navigationTitle("Repositorios")
            .searchable(text: $searchText, prompt: "Buscar repos...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        // Account Section
                        Picker("Cuentas", selection: $selectedAccount) {
                            Text("Todas las Cuentas").tag(nil as GitHubAccount?)
                            ForEach(accounts) { account in
                                Text(account.username).tag(account as GitHubAccount?)
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            logout()
                        } label: {
                            Label(
                                "Cerrar Sesion", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        // Dynamic Icon based on selection
                        if let account = selectedAccount {
                            // Using system images for now, could be AsyncImage if avatarURL exists
                            Image(
                                systemName: account.isPro
                                    ? "person.crop.circle.badge.checkmark" : "person.crop.circle"
                            )
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                            .foregroundStyle(account.isPro ? .purple : .primary)
                        } else {
                            Image(systemName: "person.2.circle")  // Icon for "All"
                                .font(.title3)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Filter menu
                        Menu {
                            ForEach(RepoFilter.allCases) { filter in
                                Button {
                                    withAnimation { activeFilter = filter }
                                } label: {
                                    Label(filter.displayName, systemImage: filter.iconName)
                                }
                            }
                        } label: {
                            Image(
                                systemName: activeFilter == .all
                                    ? "line.3.horizontal.decrease.circle"
                                    : "line.3.horizontal.decrease.circle.fill")
                        }

                        // Sync button
                        Button {
                            Task { await syncRepos() }
                        } label: {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.trianglehead.2.clockwise")
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .refreshable {
                await syncRepos()
            }
            .task {
                if repos.isEmpty {
                    await syncRepos()
                }
            }
        }
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
                    Button {
                        withAnimation {
                            repo.isFavorite.toggle()
                        }
                    } label: {
                        Label(
                            repo.isFavorite ? "Quitar Favorito" : "Favorito",
                            systemImage: repo.isFavorite ? "star.slash" : "star.fill"
                        )
                    }
                    .tint(.yellow)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        withAnimation {
                            context.delete(repo)
                        }
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }

                    Button {
                        withAnimation {
                            repo.isArchived.toggle()
                        }
                    } label: {
                        Label(
                            repo.isArchived ? "Desarchivar" : "Archivar",
                            systemImage: repo.isArchived ? "tray.and.arrow.up" : "archivebox"
                        )
                    }
                    .tint(.indigo)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: ProjectRepo.self) { repo in
            KanbanView(project: repo)
        }
        .overlay {
            if filteredRepos.isEmpty && !repos.isEmpty {
                ContentUnavailableView {
                    Label(
                        activeFilter == .archived ? "Sin Archivados" : "Sin Resultados",
                        systemImage: activeFilter == .archived ? "archivebox" : "magnifyingglass"
                    )
                } description: {
                    if activeFilter == .archived {
                        Text("No tienes repositorios archivados.")
                    } else if activeFilter == .favorites {
                        Text("No tienes repos favoritos. Desliza a la derecha para marcar uno.")
                    } else {
                        Text("No se encontraron repos con ese nombre.")
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No hay repositorios", systemImage: "tray")
        } description: {
            Text("Añade tu token o revisa tu conexion. Arrastra hacia abajo para sincronizar.")
        } actions: {
            Button("Sincronizar") {
                Task { await syncRepos() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func syncRepos() async {
        isLoading = true

        do {
            if accounts.isEmpty {
                // No accounts logic?
                // For now just return or throw if strictly needed, but let's just do nothing if empty
                return
            }

            for account in accounts {
                if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey)
                {
                    try await GitHubService.shared.syncRepos(
                        account: account, token: token, into: context)
                }
            }

            if !repos.isEmpty {
                ToastManager.shared.show("Repos sincronizados", style: .success)
            }
        } catch {
            ToastManager.shared.show(error.localizedDescription, style: .error)
        }

        isLoading = false
    }

    private func logout() {
        Task {
            // Wipe all data to prevent duplicates issues
            try? context.delete(model: GitHubAccount.self)
            try? context.delete(model: ProjectRepo.self)
            try? await KeychainManager.shared.deleteToken()  // Legacy cleanup

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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ProjectRepo.self, TaskItem.self], inMemory: true)
}
