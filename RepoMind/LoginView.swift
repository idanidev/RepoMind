import SwiftData
import SwiftUI
import UIKit

// MARK: - Login View (Guided Onboarding)

struct LoginView: View {
    @Binding var isAuthenticated: Bool

    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var validationSuccess = false
    @State private var userName: String?
    @State private var showTokenInput = false

    @State private var biometricAuth = BiometricAuthManager()

    private let tokenCreationURL = URL(
        string: "https://github.com/settings/tokens/new?scopes=repo,user")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 24) {
                    RepoMindLogo()
                        .frame(height: 120)

                    Text("RepoMind")
                        .font(.largeTitle.weight(.bold))

                    Text("Conecta RepoMind con GitHub\npara ver tus proyectos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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
        .scrollDismissesKeyboard(.interactively)
        .animation(.spring(duration: 0.45), value: showTokenInput)
        .animation(.spring(duration: 0.3), value: validationSuccess)
        .task {
            await attemptBiometricLogin()
        }
    }

    // MARK: - Onboarding Actions (Before Token Input)

    private var onboardingActions: some View {
        Section("Empezar") {
            // Step 1: Create token
            Link(destination: tokenCreationURL) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Crear Token en GitHub")
                            .foregroundStyle(.primary)
                        Text("Se abre github.com con los permisos necesarios")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.blue)
                }
            }

            // Step 2: Paste token
            Button {
                showTokenInput = true
                pasteFromClipboard()
            } label: {
                Label("Pegar Token del Portapapeles", systemImage: "doc.on.clipboard.fill")
            }

            // Manual entry fallback
            Button {
                showTokenInput = true
            } label: {
                Label("Introducir Token Manualmente", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Token Input Section

    private var tokenInputSection: some View {
        Group {
            Section("Tu Token de Acceso") {
                HStack {
                    SecureField("ghp_xxxxxxxxxxxx", text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .onSubmit { Task { await validateAndSave() } }

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

                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Pegar desde Portapapeles", systemImage: "doc.on.clipboard")
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
                    Label("Bienvenido, \(userName)!", systemImage: "checkmark.circle.fill")
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
                            Text("Validar y Conectar")
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
                    Text("Volver")
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

    // MARK: - Validate Token

    @Environment(\.modelContext) private var context

    private func validateAndSave() async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isValidating = true
        errorMessage = nil
        validationSuccess = false
        userName = nil

        do {
            // 1. Validate Token with API
            let user = try await GitHubService.shared.validateToken(trimmed)

            // 2. Check Subscription Limits
            // Fetch existing accounts count
            let descriptor = FetchDescriptor<GitHubAccount>()
            let existingCount = (try? context.fetchCount(descriptor)) ?? 0

            if trimmed != "mock-pro"
                && !SubscriptionManager.shared.canAddAccount(currentCount: existingCount)
            {
                throw NSError(
                    domain: "RepoMind", code: 403,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Límite de cuentas alcanzado (Gratis: 1). Pásate a Pro."
                    ])
            }

            userName = user.name ?? user.login
            validationSuccess = true

            // 3. Save Token to Keychain (Multi-Account Key)
            let accountKey = "github-token-\(user.login)"
            try await KeychainManager.shared.saveToken(trimmed, for: accountKey)

            // 4. Create Account Entity
            // 4. Upsert Account Entity (Prevent Duplicates)
            let targetLogin = user.login  // Local var for Predicate capture
            let existingAccount = try? context.fetch(
                FetchDescriptor<GitHubAccount>(
                    predicate: #Predicate { $0.username == targetLogin }
                )
            ).first

            if let existing = existingAccount {
                existing.avatarURL = user.avatarUrl
                existing.tokenKey = accountKey
                existing.isPro = trimmed == "mock-pro"
            } else {
                let newAccount = GitHubAccount(
                    username: user.login,
                    avatarURL: user.avatarUrl,
                    tokenKey: accountKey,
                    isPro: trimmed == "mock-pro"
                )
                context.insert(newAccount)
            }

            // Mock: Auto-create secondary account for Pro (Upsert)
            if trimmed == "mock-pro" {
                let secondaryToken = "mock-pro-personal"
                let secondaryUser = "ProPersonal"
                let secondaryKey = "github-token-\(secondaryUser)"

                try await KeychainManager.shared.saveToken(secondaryToken, for: secondaryKey)

                let existingSecondary = try? context.fetch(
                    FetchDescriptor<GitHubAccount>(
                        predicate: #Predicate { $0.username == secondaryUser }
                    )
                ).first

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

            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            try? await Task.sleep(for: .milliseconds(700))

            withAnimation {
                isAuthenticated = true
            }
        } catch let error as GitHubError {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }

        isValidating = false
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

            // Main Hexagon (simplified abstract shape)
            Image(systemName: "cube.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(
                    .linearGradient(
                        colors: [.accentColor, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
