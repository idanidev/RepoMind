import SwiftData
import SwiftUI

// MARK: - Content View (Root Navigation)

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @Query private var accounts: [GitHubAccount]

    private var shouldShowMain: Bool {
        isAuthenticated || !accounts.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if shouldShowMain {
                    if horizontalSizeClass == .regular {
                        AdaptiveRepoListView()
                    } else {
                        RepoListView()
                    }
                } else {
                    LoginView(isAuthenticated: $isAuthenticated)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: shouldShowMain)

            ToastOverlay()
        }
        .onChange(of: accounts.isEmpty) { _, isEmpty in
            // Si llegan cuentas via CloudKit, marcar como autenticado
            if !isEmpty {
                isAuthenticated = true
            }
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(item: $repoToConfigureIcon) { repo in
                RepoIconConfigSheet(repo: repo)
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

        var sorted = result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        // Free-tier: show only the most recent repos up to the limit.
        // Favorites always pass through so the user never loses starred repos.
        if !subscription.isPro && activeFilter == .all {
            let limit = subscription.maxFreeRepos
            if sorted.count > limit {
                let favorites = sorted.filter { $0.isFavorite }
                let nonFavorites = sorted.filter { !$0.isFavorite }
                let slotsForNonFav = max(0, limit - favorites.count)
                sorted = favorites + Array(nonFavorites.prefix(slotsForNonFav))
            }
        }

        filteredRepos = sorted
    }

    // MARK: - Toolbar

    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var subscription = SubscriptionManager.shared

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            accountMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    showSettings = true
                } label: {
                    Label("settings_label", systemImage: "gearshape")
                }
                .accessibilityLabel("settings_label")

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

            if !subscription.isPro {
                Button {
                    showPaywall = true
                } label: {
                    Label("upgrade_to_pro_button", systemImage: "crown")
                }
            }

            Button(role: .destructive, action: logout) {
                Label("sign_out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Group {
                if subscription.isPro {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.purple)
                } else if selectedAccount != nil {
                    Image(systemName: "person.crop.circle")
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
                    iconButton(for: repo)
                }
                .swipeActions(edge: .trailing) {
                    deleteButton(for: repo)
                    archiveButton(for: repo)
                }
            }

            // Limit banner for free users — show when there are hidden repos
            if !subscription.isPro && repos.count > subscription.maxFreeRepos {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.purple)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("repo_limit_banner_title")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(
                                    String(
                                        format: String(localized: "repo_limit_banner_subtitle"),
                                        repos.count - subscription.maxFreeRepos
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.purple.opacity(0.08))
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
            Task {
                await toggleFavorite(for: repo)
            }
        } label: {
            Label(
                repo.isFavorite ? "unfavorite" : "favorite",
                systemImage: repo.isFavorite ? "star.slash" : "star.fill"
            )
        }
        .tint(.yellow)
    }

    private func toggleFavorite(for repo: ProjectRepo) async {
        let wasStarred = repo.isFavorite

        // Actualizar localmente primero (optimistic update)
        withAnimation {
            repo.isFavorite.toggle()
            updateFilteredRepos()
        }

        // Sincronizar con GitHub
        guard let account = repo.account else { return }

        do {
            if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                if repo.isFavorite {
                    try await GitHubService.shared.starRepo(
                        owner: account.username, repo: repo.name, token: token)
                } else {
                    try await GitHubService.shared.unstarRepo(
                        owner: account.username, repo: repo.name, token: token)
                }
            }
        } catch {
            // Revertir si falla
            withAnimation {
                repo.isFavorite = wasStarred
                updateFilteredRepos()
            }
            ToastManager.shared.show(
                String(localized: "github_sync_error"), style: .error)
        }
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
            withAnimation {
                repo.isArchived.toggle()
                updateFilteredRepos()
            }
        } label: {
            Label(
                repo.isArchived ? "unarchive" : "archive",
                systemImage: repo.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        .tint(.indigo)
    }

    @State private var repoToConfigureIcon: ProjectRepo?

    private func iconButton(for repo: ProjectRepo) -> some View {
        Button {
            repoToConfigureIcon = repo
        } label: {
            Label("icon_configure_button", systemImage: "photo.badge.plus")
        }
        .tint(.blue)
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
            Text("connect_account_prompt")
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

            // Reset mock Pro state on logout
            SubscriptionManager.shared.isMockPro = false

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

    private var taskCount: Int {
        repo.tasks?.count ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar del owner (de GitHub)
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                // Nombre + favorito
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
                }

                // Descripción
                if !repo.repoDescription.isEmpty {
                    Text(repo.repoDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Badges: lenguaje + tareas
                HStack(spacing: 8) {
                    if let language = repo.language {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(languageColor(for: language))
                                .frame(width: 8, height: 8)
                            Text(language)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Badge de tareas destacado
                    if taskCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.caption2)
                            Text("\(taskCount)")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.purple, in: Capsule())
                    }

                    if repo.stargazersCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text("\(repo.stargazersCount)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("view_details_hint")
    }

    // Logo del repo o avatar del owner como fallback
    @ViewBuilder
    private var avatarView: some View {
        // Prioridad: 1. Logo del repo, 2. Avatar del owner, 3. Placeholder
        if let logoURL = repo.logoURL, let url = URL(string: logoURL) {
            // Logo del repositorio
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    ownerAvatarOrPlaceholder
                @unknown default:
                    ownerAvatarOrPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ownerAvatarOrPlaceholder
        }
    }

    @ViewBuilder
    private var ownerAvatarOrPlaceholder: some View {
        if let avatarURL = repo.account?.avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    avatarPlaceholder
                @unknown default:
                    avatarPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.tertiarySystemFill))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }

    // Colores de lenguaje estilo GitHub
    private func languageColor(for language: String) -> Color {
        switch language.lowercased() {
        case "swift": return Color(hex: "#F05138")
        case "javascript", "js": return Color(hex: "#F7DF1E")
        case "typescript", "ts": return Color(hex: "#3178C6")
        case "python": return Color(hex: "#3776AB")
        case "java": return Color(hex: "#B07219")
        case "kotlin": return Color(hex: "#A97BFF")
        case "go": return Color(hex: "#00ADD8")
        case "rust": return Color(hex: "#DEA584")
        case "ruby": return Color(hex: "#CC342D")
        case "c++", "cpp": return Color(hex: "#F34B7D")
        case "c#", "csharp": return Color(hex: "#239120")
        case "php": return Color(hex: "#777BB4")
        case "html": return Color(hex: "#E34C26")
        case "css": return Color(hex: "#1572B6")
        case "shell", "bash": return Color(hex: "#89E051")
        default: return .gray
        }
    }

    private var accessibilityDescription: String {
        var parts = [repo.name]
        if repo.isFavorite {
            parts.append(String(localized: "favorite"))
        }
        parts.append(String(format: String(localized: "tasks_count"), taskCount))
        if repo.stargazersCount > 0 {
            parts.append(String(format: String(localized: "stars_count"), repo.stargazersCount))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Repo Icon Config Sheet

struct RepoIconConfigSheet: View {
    @Bindable var repo: ProjectRepo
    @Environment(\.dismiss) private var dismiss

    @State private var iconPath: String = ""
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // Vista previa del icono actual
                Section {
                    HStack {
                        Spacer()
                        currentIconPreview
                        Spacer()
                    }
                } header: {
                    Text("icon_current_header")
                }

                // Ruta personalizada
                Section {
                    TextField("icon_path_placeholder", text: $iconPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: iconPath) { _, _ in
                            errorMessage = nil
                        }

                    Text("icon_path_example")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Mostrar error dentro del formulario
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("icon_path_header")
                } footer: {
                    Text("icon_path_footer")
                }

                // Buscar automáticamente
                Section {
                    Button {
                        Task {
                            await searchForIcon()
                        }
                    } label: {
                        HStack {
                            if isSearching {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isSearching ? "icon_searching" : "icon_search_button")
                        }
                    }
                    .disabled(isSearching)
                } footer: {
                    Text("icon_search_footer")
                }

                // Quitar icono
                if repo.logoURL != nil {
                    Section {
                        Button(role: .destructive) {
                            repo.logoURL = nil
                            dismiss()
                        } label: {
                            Text("icon_remove_button")
                        }
                    }
                }
            }
            .navigationTitle("icon_configure_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_button") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("save_button") {
                            saveIconPath()
                        }
                        .disabled(iconPath.isEmpty)
                    }
                }
            }
            .onAppear {
                // Extraer path del URL actual si existe
                if let url = repo.logoURL, url.contains("raw.githubusercontent.com") {
                    // Extraer la parte del path
                    let parts = url.components(separatedBy: "/")
                    if let mainIndex = parts.firstIndex(of: "main") ?? parts.firstIndex(of: "master")
                    {
                        iconPath = parts.dropFirst(mainIndex + 1).joined(separator: "/")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var currentIconPreview: some View {
        if let logoURL = repo.logoURL, let url = URL(string: logoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    iconPlaceholder(text: "Error")
                case .empty:
                    ProgressView()
                @unknown default:
                    iconPlaceholder(text: "?")
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            iconPlaceholder(text: String(localized: "icon_no_icon"))
        }
    }

    private func iconPlaceholder(text: String) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.tertiarySystemFill))
            .frame(width: 80, height: 80)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.title2)
                    Text(text)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
    }

    private func saveIconPath() {
        guard !iconPath.isEmpty else {
            dismiss()
            return
        }

        // Extraer owner del htmlURL del repo (más preciso que account.username)
        let owner: String
        if let htmlURL = URL(string: repo.htmlURL),
           htmlURL.pathComponents.count >= 2
        {
            owner = htmlURL.pathComponents[1]
        } else if let account = repo.account {
            owner = account.username
        } else {
            errorMessage = String(localized: "icon_owner_error")
            return
        }

        // Limpiar el path (solo quitar espacios y slashes al inicio/final)
        let cleanPath = iconPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        #if DEBUG
        print("🔍 Configurando icono: owner=\(owner) repo=\(repo.name) path=\(cleanPath)")
        #endif

        // Intentar construir la URL y verificarla
        isSaving = true
        errorMessage = nil

        Task {
            let branches = ["main", "master", "develop"]
            var foundURL: String?

            for branch in branches {
                let testURL =
                    "https://raw.githubusercontent.com/\(owner)/\(repo.name)/\(branch)/\(cleanPath)"

                if let url = URL(string: testURL) {
                    var request = URLRequest(url: url)
                    request.httpMethod = "HEAD"

                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let httpResponse = response as? HTTPURLResponse,
                           httpResponse.statusCode == 200 {
                            foundURL = testURL
                            break
                        }
                    } catch { }
                }
            }

            await MainActor.run {
                isSaving = false

                if let url = foundURL {
                    repo.logoURL = url
                    ToastManager.shared.show(String(localized: "icon_configured_toast"), style: .success)
                    dismiss()
                } else {
                    errorMessage = String(localized: "icon_not_found_error")
                }
            }
        }
    }

    private func searchForIcon() async {
        guard let account = repo.account else {
            errorMessage = String(localized: "icon_no_account_error")
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                let owner: String
                if let htmlURL = URL(string: repo.htmlURL),
                   htmlURL.pathComponents.count >= 2 {
                    owner = htmlURL.pathComponents[1]
                } else {
                    owner = account.username
                }

                if let foundURL = await GitHubService.shared.fetchRepoLogoURL(
                    owner: owner, repo: repo.name, token: token)
                {
                    repo.logoURL = foundURL
                    isSearching = false
                    ToastManager.shared.show(String(localized: "icon_found_toast"), style: .success)
                    dismiss()
                } else {
                    isSearching = false
                    errorMessage = String(localized: "icon_not_found_search_error")
                }
            } else {
                isSearching = false
                errorMessage = String(localized: "icon_token_error")
            }
        } catch {
            isSearching = false
            errorMessage = String(format: String(localized: "icon_search_error"), error.localizedDescription)
        }
    }
}

// MARK: - Adaptive Repo List View (iPad/Mac - NavigationSplitView)

struct AdaptiveRepoListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]

    @State private var isLoading = false
    @State private var searchText = ""
    @State private var activeFilter: RepoFilter = .all
    @State private var selectedAccount: GitHubAccount?
    @State private var selectedRepo: ProjectRepo?
    @State private var filteredRepos: [ProjectRepo] = []
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var subscription = SubscriptionManager.shared
    @State private var repoToConfigureIcon: ProjectRepo?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .searchable(text: $searchText, prompt: "search_placeholder")
        .refreshable {
            await syncRepos()
        }
        .task {
            updateFilteredRepos()
            if repos.isEmpty {
                await syncRepos()
            }
        }
        .onChange(of: repos) { _, _ in updateFilteredRepos() }
        .onChange(of: activeFilter) { _, _ in updateFilteredRepos() }
        .onChange(of: searchText) { _, _ in updateFilteredRepos() }
        .onChange(of: selectedAccount) { _, _ in updateFilteredRepos() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $repoToConfigureIcon) { repo in
            RepoIconConfigSheet(repo: repo)
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncReposShortcut)) { _ in
            Task { await syncRepos() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsShortcut)) { _ in
            showSettings = true
        }
    }

    // MARK: - Sidebar

    private var sidebarAccountSection: some View {
        Section {
            Picker("accounts_filter", selection: $selectedAccount) {
                Text("all_accounts").tag(nil as GitHubAccount?)
                ForEach(accounts) { account in
                    Text(account.username).tag(account as GitHubAccount?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var sidebarFilterSection: some View {
        Section {
            ForEach(RepoFilter.allCases) { filter in
                Button {
                    withAnimation { activeFilter = filter }
                } label: {
                    Label(filter.displayName, systemImage: filter.iconName)
                        .foregroundStyle(activeFilter == filter ? Color.accentColor : Color.primary)
                }
            }
        }
    }

    private func sidebarRepoRow(_ repo: ProjectRepo) -> some View {
        NavigationLink(value: repo) {
            RepoRow(repo: repo)
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await toggleFavorite(for: repo) }
            } label: {
                Label(
                    repo.isFavorite ? "unfavorite" : "favorite",
                    systemImage: repo.isFavorite ? "star.slash" : "star.fill"
                )
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation { context.delete(repo) }
            } label: {
                Label("delete_task", systemImage: "trash")
            }
            Button {
                withAnimation {
                    repo.isArchived.toggle()
                    updateFilteredRepos()
                }
            } label: {
                Label(
                    repo.isArchived ? "unarchive" : "archive",
                    systemImage: repo.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            .tint(.indigo)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedRepo) {
            sidebarAccountSection
            sidebarFilterSection
            Section("repositories_title") {
                ForEach(filteredRepos) { repo in
                    sidebarRepoRow(repo)
                }
                if !subscription.isPro && repos.count > subscription.maxFreeRepos {
                    Button { showPaywall = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill").foregroundStyle(.purple)
                            Text("repo_limit_banner_title").font(.subheadline.weight(.semibold))
                        }
                    }
                    .listRowBackground(Color.purple.opacity(0.08))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("repositories_title")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { accountMenuButton }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { showSettings = true } label: {
                        Label("settings_label", systemImage: "gearshape")
                    }
                    syncButton
                }
            }
        }
        .overlay {
            if repos.isEmpty && isLoading {
                ProgressView()
            } else if repos.isEmpty {
                ContentUnavailableView {
                    Label("no_repos_title", systemImage: "tray")
                } actions: {
                    Button("sync_button") { Task { await syncRepos() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if filteredRepos.isEmpty {
                ContentUnavailableView {
                    Label("no_results_title", systemImage: "magnifyingglass")
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selectedRepo {
            KanbanView(project: selectedRepo)
        } else {
            ContentUnavailableView {
                Label("select_repo_prompt", systemImage: "sidebar.left")
            } description: {
                Text("select_repo_description")
            }
        }
    }

    // MARK: - Components

    private var accountMenuButton: some View {
        Menu {
            if !subscription.isPro {
                Button {
                    showPaywall = true
                } label: {
                    Label("upgrade_to_pro_button", systemImage: "crown")
                }
            }
            Button(role: .destructive, action: logout) {
                Label("sign_out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Group {
                if subscription.isPro {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.purple)
                } else {
                    Image(systemName: "person.2.circle")
                }
            }
            .font(.title3)
        }
    }

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
    }

    // MARK: - Logic (shared with RepoListView)

    private func updateFilteredRepos() {
        var result = repos
        switch activeFilter {
        case .all: result = result.filter { !$0.isArchived }
        case .favorites: result = result.filter { $0.isFavorite && !$0.isArchived }
        case .archived: result = result.filter { $0.isArchived }
        }
        if let account = selectedAccount {
            result = result.filter { $0.account?.id == account.id }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedStandardContains(searchText)
                    || $0.repoDescription.localizedStandardContains(searchText)
            }
        }
        var sorted = result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.updatedAt > rhs.updatedAt
        }
        if !subscription.isPro && activeFilter == .all {
            let limit = subscription.maxFreeRepos
            if sorted.count > limit {
                let favorites = sorted.filter { $0.isFavorite }
                let nonFavorites = sorted.filter { !$0.isFavorite }
                let slotsForNonFav = max(0, limit - favorites.count)
                sorted = favorites + Array(nonFavorites.prefix(slotsForNonFav))
            }
        }
        filteredRepos = sorted
    }

    private func toggleFavorite(for repo: ProjectRepo) async {
        let wasStarred = repo.isFavorite
        withAnimation { repo.isFavorite.toggle(); updateFilteredRepos() }
        guard let account = repo.account else { return }
        do {
            if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                if repo.isFavorite {
                    try await GitHubService.shared.starRepo(owner: account.username, repo: repo.name, token: token)
                } else {
                    try await GitHubService.shared.unstarRepo(owner: account.username, repo: repo.name, token: token)
                }
            }
        } catch {
            withAnimation { repo.isFavorite = wasStarred; updateFilteredRepos() }
            ToastManager.shared.show(String(localized: "github_sync_error"), style: .error)
        }
    }

    private func syncRepos() async {
        isLoading = true
        defer { isLoading = false }
        guard !accounts.isEmpty else { return }
        do {
            for account in accounts {
                if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                    try await GitHubService.shared.syncRepos(account: account, token: token, into: context)
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
            SubscriptionManager.shared.isMockPro = false
            withAnimation { isAuthenticated = false }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ProjectRepo.self, TaskItem.self], inMemory: true)
}
