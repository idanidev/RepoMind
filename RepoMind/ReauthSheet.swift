import SwiftUI

/// Lets the user replace an expired GitHub token without signing out.
///
/// GitHub personal access tokens cannot be refreshed — there is no refresh token to exchange, so
/// "renew it automatically" is not something the app can do. What it *can* do is notice the moment
/// a token stops working and offer a way back in.
///
/// Before this, an expired token left the app in a dead end: the account still existed so the main
/// screen kept showing, every sync failed with a generic error, and the only route to entering a
/// new token was signing out — which deletes the local repos and their tasks.
struct ReauthSheet: View {
    let account: GitHubAccount
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    private let tokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,user")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("reauth_explanation \(account.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Link(destination: tokenURL) {
                        Label("reauth_create_token", systemImage: "safari")
                    }
                }

                Section("access_token_section") {
                    SecureField("ghp_xxxxxxxxxxxx", text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .onSubmit { Task { await validateAndSave() } }

                    Button {
                        if let clipboard = UIPasteboard.general.string {
                            token = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("paste_from_clipboard", systemImage: "doc.on.clipboard")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("reauth_title")
            #if !targetEnvironment(macCatalyst)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") { Task { await validateAndSave() } }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
                }
            }
            .overlay {
                if isValidating {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .frame(idealWidth: 460)
    }

    private func validateAndSave() async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isValidating else { return }

        isValidating = true
        defer { isValidating = false }
        errorMessage = nil

        do {
            // Confirm the token works *and* belongs to the same account before storing it —
            // silently accepting another user's token would attach their repos to this account.
            let user = try await GitHubService.shared.validateToken(trimmed)
            guard user.login.lowercased() == account.username.lowercased() else {
                errorMessage = String(
                    format: String(localized: "reauth_wrong_account %@ %@"), user.login, account.username)
                return
            }
            try KeychainManager.shared.saveToken(trimmed, for: account.tokenKey)
            ToastManager.shared.show(String(localized: "reauth_success"), style: .success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
