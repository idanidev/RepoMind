import SwiftUI

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

    private let tokenCreationURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,user")!

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // Logo & Branding
                headerSection

                if showTokenInput {
                    tokenInputSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    onboardingActions
                        .transition(.opacity)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.spring(duration: 0.45), value: showTokenInput)
        .animation(.spring(duration: 0.3), value: validationSuccess)
        .task {
            await attemptBiometricLogin()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            Text("RepoMind")
                .font(.largeTitle.weight(.bold))

            Text("Conecta RepoMind con GitHub\npara ver tus proyectos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 44)
    }

    // MARK: - Onboarding Actions (Before Token Input)

    private var onboardingActions: some View {
        VStack(spacing: 16) {
            // Step 1: Create token
            Link(destination: tokenCreationURL) {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.title3)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Crear Token en GitHub")
                            .font(.headline)
                        Text("Se abre github.com con los permisos necesarios")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            // Step 2: Paste token
            Button {
                showTokenInput = true
                pasteFromClipboard()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.title3)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pegar Token")
                            .font(.headline)
                        Text("Pega el token desde el portapapeles")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Manual entry fallback
            Button {
                showTokenInput = true
            } label: {
                Text("Introducir token manualmente")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Token Input Section

    private var tokenInputSection: some View {
        VStack(spacing: 20) {
            // Token field
            VStack(alignment: .leading, spacing: 8) {
                Text("GitHub Personal Access Token")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    SecureField("ghp_xxxxxxxxxxxx", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .onSubmit { Task { await validateAndSave() } }

                    // Paste button inline
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.body)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Feedback messages
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if validationSuccess, let userName {
                Label("Bienvenido, \(userName)!", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }

            // Validate button
            Button {
                Task { await validateAndSave() }
            } label: {
                Group {
                    if isValidating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Validar y Conectar", systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)

            // Back
            Button {
                showTokenInput = false
                token = ""
                errorMessage = nil
                validationSuccess = false
                userName = nil
            } label: {
                Text("Volver")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Clipboard Paste

    private func pasteFromClipboard() {
        if let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clipboard.isEmpty {
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

    private func validateAndSave() async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isValidating = true
        errorMessage = nil
        validationSuccess = false
        userName = nil

        do {
            let user = try await GitHubService.shared.validateToken(trimmed)
            userName = user.name ?? user.login
            validationSuccess = true

            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            try await KeychainManager.shared.saveToken(trimmed)

            try? await Task.sleep(for: .milliseconds(700))

            withAnimation {
                isAuthenticated = true
            }
        } catch let error as GitHubError {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        } catch {
            errorMessage = "Error inesperado: \(error.localizedDescription)"
        }

        isValidating = false
    }
}
