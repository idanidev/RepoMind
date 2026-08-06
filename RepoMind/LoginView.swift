import SwiftData
import SwiftUI
import UIKit

// MARK: - Login View (Guided Onboarding)

struct LoginView: View {
    @Binding var isAuthenticated: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var validationSuccess = false
    @State private var userName: String?
    @State private var showTokenInput = false

    @State private var biometricAuth = BiometricAuthManager()
    @State private var showPaywall = false
    @AppStorage("isDemoMode") private var isDemoMode = false

    private let tokenCreationURL = URL(
        string: "https://github.com/settings/tokens/new?scopes=repo,user")!

    var body: some View {
        Group {
            if isMacIdiom {
                macSplitLayout
            } else {
                iOSLayout
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.spring(duration: 0.45), value: showTokenInput)
        .animation(.spring(duration: 0.3), value: validationSuccess)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task {
            await attemptBiometricLogin()
        }
    }

    // MARK: - iOS / iPad Layout

    private var iOSLayout: some View {
        Form {
            Section {
                heroContent(compact: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
            }

            if showTokenInput {
                tokenInputSection
            } else {
                onboardingActions
            }
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 600 : .infinity)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mac Split Layout

    private var macSplitLayout: some View {
        HStack(spacing: 0) {
            macHero
                .frame(minWidth: 360, idealWidth: 460, maxWidth: 520, maxHeight: .infinity)

            Form {
                if showTokenInput {
                    tokenInputSection
                } else {
                    onboardingActions
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var macHero: some View {
        ZStack {
            LinearGradient(
                colors: [.purple, .indigo, Color.blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            heroContent(compact: false, lightOnDark: true)
                .padding(40)
        }
    }

    @ViewBuilder
    private func heroContent(compact: Bool, lightOnDark: Bool = false) -> some View {
        VStack(spacing: 24) {
            RepoMindLogo()
                .frame(height: lightOnDark ? 160 : 120)

            Text("app_name")
                .font(lightOnDark ? .system(size: 42, weight: .bold) : .largeTitle.weight(.bold))
                .foregroundStyle(lightOnDark ? Color.white : Color.accentColor)

            Text("login_subtitle")
                .font(lightOnDark ? .title3 : .subheadline)
                .foregroundStyle(lightOnDark ? .white.opacity(0.85) : .secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Onboarding Actions (Before Token Input)

    private var onboardingActions: some View {
        Section("start_section") {
            // Step 1: Create token
            Link(destination: tokenCreationURL) {
                HStack {
                    Image(systemName: "safari")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("create_token_button")
                            .font(.headline)
                        Text("create_token_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Step 2: Paste token
            Button {
                showTokenInput = true
                pasteFromClipboard()
            } label: {
                Label("paste_token_button", systemImage: "doc.on.clipboard.fill")
            }

            // Manual entry fallback
            Button {
                withAnimation { showTokenInput = true }  // Changed to showTokenInput for consistency
            } label: {
                Label("enter_token_manually", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            }

            // Demo mode for reviewers / onboarding
            Button {
                loadDemoMode()
            } label: {
                Label("demo_mode_button", systemImage: "play.rectangle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Token Input Section

    private var tokenInputSection: some View {
        Group {
            Section("access_token_section") {
                HStack {
                    SecureField("ghp_xxxxxxxxxxxx", text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .onSubmit { Task { await validateAndSave() } }
                        .accessibilityIdentifier("access_token_field")  // Added accessibilityIdentifier

                    if !token.isEmpty {
                        Button {
                            token = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !validationSuccess {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("paste_from_clipboard", systemImage: "doc.on.clipboard")
                    }
                }
            }

            // Feedback messages
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if validationSuccess, let userName {
                Section {
                    Label(
                        String(format: String(localized: "welcome_message"), userName),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
            }

            // Validate button
            Section {
                Button {
                    Task { await validateAndSave() }
                } label: {
                    HStack {
                        Spacer()
                        if isValidating {
                            ProgressView()
                        } else {
                            Text("validate_connect_button")
                                .bold()
                        }
                        Spacer()
                    }
                }
                .disabled(
                    token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)

                Button(role: .cancel) {
                    showTokenInput = false
                    token = ""
                    errorMessage = nil
                    validationSuccess = false
                    userName = nil
                } label: {
                    Text("back_button")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Clipboard Paste

    private func pasteFromClipboard() {
        if let clipboard = UIPasteboard.general.string?.trimmingCharacters(
            in: .whitespacesAndNewlines),
            !clipboard.isEmpty
        {
            token = clipboard
        }
    }

    // MARK: - Biometric Login

    private func attemptBiometricLogin() async {
        let hasToken = await KeychainManager.shared.hasToken()
        guard hasToken else { return }

        await biometricAuth.authenticate()

        if biometricAuth.isAuthenticated {
            withAnimation {
                isAuthenticated = true
            }
        }
    }

    // MARK: - Demo Mode

    @Environment(\.modelContext) private var context

    /// Removes any persisted demo accounts and negative-ID repos (including those
    /// that may have synced back via CloudKit from another device).
    private func purgeDemoData() {
        let accountDesc = FetchDescriptor<GitHubAccount>(
            predicate: #Predicate { $0.username == "demo-user" }
        )
        if let existing = try? context.fetch(accountDesc) {
            existing.forEach { context.delete($0) }
        }
        let repoDesc = FetchDescriptor<ProjectRepo>(
            predicate: #Predicate { $0.repoID < 0 }
        )
        if let existing = try? context.fetch(repoDesc) {
            existing.forEach { context.delete($0) }
        }
    }

    private func loadDemoMode() {
        isDemoMode = true
        SubscriptionManager.shared.isDemoMode = true

        // Remove any stale demo data before inserting fresh records
        purgeDemoData()

        let account = GitHubAccount(username: "demo-user", avatarURL: nil, tokenKey: "demo-token")
        context.insert(account)

        let demoRepos: [(name: String, desc: String, lang: String, stars: Int, fav: Bool)] = [
            ("my-ios-app",     "SwiftUI app with CloudKit sync",      "Swift",      42,  true),
            ("web-dashboard",  "React dashboard for analytics",        "JavaScript", 128, false),
            ("api-backend",    "REST API with Node.js and PostgreSQL", "TypeScript", 84,  false),
        ]

        let columnDefs = [
            ("To-Do", 0), ("In Progress", 1), ("Done", 2)
        ]
        let taskDefs: [[[String]]] = [
            [["Fix login screen bug", "Write unit tests"],
             ["Add dark mode support", "Implement push notifications"],
             ["Setup CI/CD pipeline"]],
            [["Add export feature", "Fix chart rendering"],
             ["Implement authentication"],
             ["Setup project structure"]],
            [["Add rate limiting", "Write API docs"],
             ["Database migration"],
             ["Initial setup"]],
        ]

        for (i, r) in demoRepos.enumerated() {
            let repo = ProjectRepo(
                repoID: -(i + 1),
                name: r.name,
                repoDescription: r.desc,
                updatedAt: Date().addingTimeInterval(Double(-i * 3600)),
                isFavorite: r.fav,
                language: r.lang,
                stargazersCount: r.stars,
                account: account
            )
            context.insert(repo)

            var columns: [KanbanColumn] = []
            for (colName, colIdx) in columnDefs {
                let col = KanbanColumn(name: colName, orderIndex: colIdx, project: repo)
                context.insert(col)
                columns.append(col)
            }

            for (colIdx, tasks) in taskDefs[i].enumerated() {
                for (taskIdx, content) in tasks.enumerated() {
                    let task = TaskItem(
                        content: content,
                        column: columns[colIdx],
                        project: repo,
                        orderIndex: taskIdx
                    )
                    context.insert(task)
                }
            }
        }

        try? context.save()
        withAnimation { isAuthenticated = true }
    }

    // MARK: - Validate Token

    private func validateAndSave() async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Demo token: activates demo mode without calling the GitHub API
        if trimmed.hasPrefix("mock-") || trimmed == "free-mock" {
            loadDemoMode()
            return
        }

        isValidating = true
        errorMessage = nil
        validationSuccess = false
        userName = nil

        do {
            // 1. Validate Token with API
            let user = try await GitHubService.shared.validateToken(trimmed)

            // 2. Check Subscription Limits
            // Purge any leftover demo data so it doesn't inflate the account count
            // and doesn't block the subscription check with a stale isDemoMode flag.
            purgeDemoData()
            if isDemoMode {
                isDemoMode = false
                SubscriptionManager.shared.isDemoMode = false
            }

            let descriptor = FetchDescriptor<GitHubAccount>()
            let existingCount = (try? context.fetchCount(descriptor)) ?? 0

            if !SubscriptionManager.shared.canAddAccount(currentCount: existingCount) {
                showPaywall = true
                isValidating = false
                return
            }

            #if DEBUG
            if trimmed == "mock-pro" {
                SubscriptionManager.shared.isMockPro = true
            }
            #endif

            userName = user.name ?? user.login
            validationSuccess = true

            // 3. Save Token to Keychain (Multi-Account Key)
            let accountKey = "github-token-\(user.login)"
            try await KeychainManager.shared.saveToken(trimmed, for: accountKey)

            // 4. Upsert Account Entity (Prevent Duplicates)
            let targetLogin = user.login  // Local var for Predicate capture
            var accountDescriptor = FetchDescriptor<GitHubAccount>(
                predicate: #Predicate { $0.username == targetLogin }
            )
            accountDescriptor.fetchLimit = 1
            let existingAccount = try? context.fetch(accountDescriptor).first

            #if DEBUG
            let isProAccount = trimmed == "mock-pro"
            #else
            let isProAccount = false
            #endif

            if let existing = existingAccount {
                existing.avatarURL = user.avatarUrl
                existing.tokenKey = accountKey
                existing.isPro = isProAccount
            } else {
                let newAccount = GitHubAccount(
                    username: user.login,
                    avatarURL: user.avatarUrl,
                    tokenKey: accountKey,
                    isPro: isProAccount
                )
                context.insert(newAccount)
            }

            #if DEBUG
            // Mock: Auto-create secondary account for Pro
            if trimmed == "mock-pro" {
                let secondaryToken = "mock-pro-personal"
                let secondaryUser = "ProPersonal"
                let secondaryKey = "github-token-\(secondaryUser)"

                try await KeychainManager.shared.saveToken(secondaryToken, for: secondaryKey)

                var secondaryDescriptor = FetchDescriptor<GitHubAccount>(
                    predicate: #Predicate { $0.username == secondaryUser }
                )
                secondaryDescriptor.fetchLimit = 1
                let existingSecondary = try? context.fetch(secondaryDescriptor).first

                if let existing = existingSecondary {
                    existing.isPro = true
                } else {
                    let secondaryAccount = GitHubAccount(
                        username: secondaryUser,
                        avatarURL: "figure.gaming",
                        tokenKey: secondaryKey,
                        isPro: true
                    )
                    context.insert(secondaryAccount)
                }
            }
            #endif

            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            try? await Task.sleep(for: .milliseconds(700))

            withAnimation {
                isAuthenticated = true
            }
        } catch let error as GitHubError {
            errorMessage = error.localizedDescription
            handleLoginError()
        } catch {
            errorMessage = error.localizedDescription
            handleLoginError()
        }

        isValidating = false
    }

    private static let feedbackGenerator = UINotificationFeedbackGenerator()

    private func handleLoginError() {
        Self.feedbackGenerator.notificationOccurred(.error)
    }
}

// MARK: - RepoMind Logo

struct RepoMindLogo: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Background Glow
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .blur(radius: 20)
                .scaleEffect(isAnimating ? 1.1 : 1.0)

            // Logo personalizado desde Assets
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
