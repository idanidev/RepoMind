import SwiftData
import SwiftUI

// MARK: - Content View (Root Navigation)

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("isAuthenticated") private var isAuthenticated = false

    var body: some View {
        Group {
            if isAuthenticated {
                RepoListView()
            } else {
                LoginView(isAuthenticated: $isAuthenticated)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isAuthenticated)
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

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var activeFilter: RepoFilter = .all

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

        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.repoDescription.localizedCaseInsensitiveContains(searchText)
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
                    ProgressView("Sincronizando repositorios...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Button(role: .destructive) {
                            logout()
                        } label: {
                            Label("Cerrar Sesion", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.title3)
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
                            Image(systemName: activeFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
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
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                if repos.isEmpty {
                    await syncRepos()
                }
            }
        }
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
            Label("Sin Repositorios", systemImage: "folder")
        } description: {
            Text("Arrastra hacia abajo o pulsa sincronizar para obtener tus repos de GitHub.")
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
        errorMessage = nil

        do {
            try await GitHubService.shared.syncRepos(into: context)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func logout() {
        Task {
            try? await KeychainManager.shared.deleteToken()
            isAuthenticated = false
        }
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

                Text("\(repo.tasks.count)")
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
