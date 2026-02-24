import StoreKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]

    @State private var isSearchingIcons = false
    @State private var iconsFound = 0
    @State private var showPaywall = false
    @State private var showManageSubscription = false

    private let subscription = SubscriptionManager.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Iconos de repos

                Section {
                    Button {
                        Task {
                            await searchAllIcons()
                        }
                    } label: {
                        HStack {
                            Label("search_app_icons_button", systemImage: "photo.badge.arrow.down")
                            Spacer()
                            if isSearchingIcons {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isSearchingIcons)
                } header: {
                    Text("repositories_title")
                } footer: {
                    Text("search_icons_footer")
                }

                // MARK: - Subscription

                Section("subscription_header") {
                    HStack {
                        Label(
                            "current_plan_label",
                            systemImage: subscription.isPro ? "crown.fill" : "person.fill"
                        )
                        Spacer()
                        Text(subscription.currentPlanName)
                            .foregroundStyle(subscription.isPro ? .purple : .secondary)
                            .font(.subheadline.weight(.semibold))
                    }

                    if subscription.isPro && !subscription.isMockPro {
                        Button("manage_subscription_button") {
                            showManageSubscription = true
                        }
                    } else if !subscription.isPro {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("upgrade_to_pro_button", systemImage: "crown")
                                .foregroundStyle(.purple)
                        }
                    }

                    Button {
                        Task {
                            let restored = await subscription.restorePurchases()
                            if restored {
                                ToastManager.shared.show(
                                    String(localized: "restore_success_toast"),
                                    style: .success
                                )
                            } else {
                                ToastManager.shared.show(
                                    String(localized: "restore_no_purchases_toast"),
                                    style: .info
                                )
                            }
                        }
                    } label: {
                        if subscription.isLoading {
                            HStack {
                                Text("restore_purchases_button")
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        } else {
                            Text("restore_purchases_button")
                        }
                    }
                    .disabled(subscription.isLoading)
                }

                // MARK: - Debug (solo en desarrollo)

                #if DEBUG
                Section {
                    Toggle(isOn: Binding(
                        get: { subscription.isMockPro },
                        set: { subscription.isMockPro = $0 }
                    )) {
                        Label("Simular Pro", systemImage: "crown.fill")
                            .foregroundStyle(.purple)
                    }
                    .tint(.purple)

                    if subscription.isMockPro {
                        Text("La app se comporta como usuario Pro.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Solo visible en builds de desarrollo. No tiene efecto en producción.")
                }
                #endif

                // MARK: - About

                Section("about_header") {
                    HStack {
                        Text("version_label")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Link("privacy_policy", destination: URL(string: "https://idanidev.github.io/repomind/privacy")!)
                    Link("terms_of_use", destination: URL(string: "https://idanidev.github.io/repomind/terms")!)
                }
            }
            .navigationTitle("settings_title")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("done_button") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
        }
        .presentationDetents([.large])
        .frame(idealWidth: 500)
    }

    // MARK: - Search Icons

    private func searchAllIcons() async {
        isSearchingIcons = true
        iconsFound = 0

        // Filtrar repos iOS sin logo
        let iosRepos = repos.filter {
            ($0.language == "Swift" || $0.language == "Objective-C") && $0.logoURL == nil
        }

        guard !iosRepos.isEmpty else {
            isSearchingIcons = false
            ToastManager.shared.show(String(localized: "no_ios_repos_icon_toast"), style: .info)
            return
        }

        ToastManager.shared.show(String(format: String(localized: "searching_icons_progress"), iosRepos.count), style: .info)

        for repo in iosRepos {
            guard let account = repo.account else { continue }

            do {
                if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey)
                {
                    // Extraer owner del htmlURL
                    let owner: String
                    if let url = URL(string: repo.htmlURL), url.pathComponents.count >= 2 {
                        owner = url.pathComponents[1]
                    } else {
                        owner = account.username
                    }

                    if let logoURL = await GitHubService.shared.fetchRepoLogoURL(
                        owner: owner, repo: repo.name, token: token)
                    {
                        await MainActor.run {
                            repo.logoURL = logoURL
                            iconsFound += 1
                        }
                    }
                }
            } catch { }
        }

        isSearchingIcons = false

        if iconsFound > 0 {
            ToastManager.shared.show(String(format: String(localized: "icons_found_toast"), iconsFound), style: .success)
        } else {
            ToastManager.shared.show(String(localized: "no_icons_found_toast"), style: .info)
        }
    }
}

#Preview {
    SettingsView()
}
