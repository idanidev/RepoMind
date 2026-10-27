import SwiftData
import SwiftUI

// MARK: - Profile tab

/// The accounts signed in, the plan, and the way out. What the classic list kept behind the
/// person icon, as a screen.
struct HomeProfileView: View {
    @Query private var accounts: [GitHubAccount]
    @Query private var repos: [ProjectRepo]
    @State private var subscription = SubscriptionManager.shared
    @State private var isRestoring = false

    var onUpgrade: () -> Void = {}
    var onSignOut: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(accounts) { account in
                    accountCard(account)
                }
                planCard
                Button(action: onSignOut) {
                    Label("sign_out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeTheme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(card)
                }
                .buttonStyle(HomeCardButtonStyle())
            }
            .padding(.horizontal, HomeTheme.gutter)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func accountCard(_ account: GitHubAccount) -> some View {
        let count = repos.filter { $0.account?.id == account.id }.count
        return HStack(spacing: 12) {
            avatar(for: account)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.username)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeTheme.textPrimary)
                Text("home_profile_repos \(count)")
                    .font(.caption)
                    .foregroundStyle(HomeTheme.textSecondary)
            }
            Spacer()
        }
        .padding(HomeTheme.cardPadding)
        .background(card)
    }

    @ViewBuilder
    private func avatar(for account: GitHubAccount) -> some View {
        let shape = Circle()
        Group {
            if let avatarURL = account.avatarURL, let url = URL(string: avatarURL) {
                CachedAsyncImage(url: url) { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(shape)
        .overlay(shape.strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            HomeTheme.surfaceElevated
            Image(systemName: "person.fill")
                .foregroundStyle(HomeTheme.textSecondary)
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: subscription.isPro ? "crown.fill" : "person.fill")
                    .font(.title3)
                    .foregroundStyle(subscription.isPro ? HomeTheme.accent : HomeTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("current_plan_label")
                        .font(.caption)
                        .foregroundStyle(HomeTheme.textSecondary)
                    Text(subscription.currentPlanName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeTheme.textPrimary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if !subscription.isPro {
                    Button(action: onUpgrade) {
                        Label("upgrade_to_pro_button", systemImage: "crown")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeTheme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(HomeTheme.accent))
                    }
                    .buttonStyle(HomeCardButtonStyle())
                }
                Button {
                    Task { await restore() }
                } label: {
                    Group {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text("restore_purchases_button")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(HomeTheme.surfaceElevated))
                    .overlay(Capsule().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
                }
                .buttonStyle(HomeCardButtonStyle())
                .disabled(isRestoring)
            }
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
            .fill(HomeTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                    .strokeBorder(HomeTheme.hairline, lineWidth: 0.5)
            )
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let restored = try await subscription.restorePurchases()
            ToastManager.shared.show(
                String(localized: restored ? "restore_success_toast" : "restore_no_purchases_toast"),
                style: restored ? .success : .info
            )
        } catch {
            ToastManager.shared.show(error.localizedDescription, style: .error)
        }
    }
}
