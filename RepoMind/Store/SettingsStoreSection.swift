import SwiftData
import SwiftUI

/// Settings → App Store: where the developer's `store.json` lives. One URL for the whole account;
/// saving it reads the file at once, so a wrong address or a missing token says so here and not on
/// the start screen an hour later.
struct SettingsStoreSection: View {
    @Query private var accounts: [GitHubAccount]
    @State private var store = StoreStatusStore.shared
    @State private var text = ""
    @State private var invalidAddress = false
    @FocusState private var focused: Bool

    private var storeAccounts: [StoreAccount] {
        accounts.map { StoreAccount(username: $0.username, tokenKey: $0.tokenKey) }
    }

    var body: some View {
        Section {
            TextField("store_url_placeholder", text: $text, axis: .vertical)
                .lineLimit(1...3)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit { Task { await save() } }
            if invalidAddress {
                Label("store_url_invalid", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Label("store_save_button", systemImage: "arrow.triangle.2.circlepath")
                    if store.loading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.loading)
            status
            if store.isConfigured {
                Button(role: .destructive) {
                    store.disconnect()
                    text = ""
                } label: {
                    Label("store_disconnect_button", systemImage: "minus.circle")
                }
            }
        } header: {
            Text("store_section_header")
        } footer: {
            Text("store_footer")
        }
        .onAppear {
            text = store.endpoint?.absoluteString ?? ""
            store.loadCached()
        }
    }

    @ViewBuilder
    private var status: some View {
        if let failure = store.failure {
            Label(failure, systemImage: "xmark.octagon.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        } else if let status = store.status, let fetched = store.fetchedAt {
            Label(
                String(
                    format: String(localized: "store_connected %lld %@"), status.apps.count,
                    fetched.formatted(.relative(presentation: .named))),
                systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }

    private func save() async {
        focused = false
        invalidAddress = !store.configure(text)
        guard !invalidAddress else { return }
        await store.refresh(accounts: storeAccounts, force: true)
    }
}
