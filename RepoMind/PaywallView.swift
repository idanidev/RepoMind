import StoreKit
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var subscription = SubscriptionManager.shared
    @State private var purchaseError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if horizontalSizeClass == .regular {
                    // iPad/Mac: Two-column layout
                    VStack(spacing: 28) {
                        headerSection
                        HStack(alignment: .top, spacing: 24) {
                            featuresSection
                                .frame(maxWidth: .infinity)
                            VStack(spacing: 20) {
                                pricingSection
                                purchaseButton
                            }
                            .frame(maxWidth: .infinity)
                        }
                        footerSection
                    }
                    .padding()
                    .frame(maxWidth: 800)
                    .frame(maxWidth: .infinity)
                } else {
                    // iPhone: Single column
                    VStack(spacing: 28) {
                        headerSection
                        featuresSection
                        pricingSection
                        purchaseButton
                        footerSection
                    }
                    .padding()
                }
            }
            #if canImport(UIKit)
                .background(Color(.systemGroupedBackground))
            #else
                .background(Color(NSColor.windowBackgroundColor))
            #endif
            .navigationTitle("paywall_title")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close_button") { dismiss() }
                }
            }
            .task {
                await subscription.loadProducts()
            }
            .alert(
                "purchase_error_title",
                isPresented: .init(
                    get: { purchaseError != nil },
                    set: { if !$0 { purchaseError = nil } }
                )
            ) {
                Button("OK") { purchaseError = nil }
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("paywall_header_title")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("paywall_header_subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Spacer()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("free_tier_label")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 60)
                Text("pro_tier_label")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                    .frame(width: 60)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                featureRow(icon: "person.2.fill", name: "feature_accounts", free: "1", pro: nil)
                Divider().padding(.leading, 44)
                featureRow(icon: "folder.fill", name: "feature_repos", free: "3", pro: nil)
                Divider().padding(.leading, 44)
                featureRow(
                    icon: "rectangle.3.group.fill", name: "feature_kanban_columns", free: "3",
                    pro: nil)
                Divider().padding(.leading, 44)
                featureRow(
                    icon: "mic.fill", name: "feature_voice", free: "feature_limited", pro: nil)
                Divider().padding(.leading, 44)
                featureRow(
                    icon: "icloud.fill", name: "feature_sync", free: nil,
                    pro: "feature_coming_soon", showComingSoon: true)
            }
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func featureRow(
        icon: String,
        name: LocalizedStringKey,
        free: LocalizedStringKey?,
        pro: LocalizedStringKey?,
        showComingSoon: Bool = false
    ) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.purple)
                    .frame(width: 24)
                Text(name)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Free column
            Group {
                if let free {
                    Text(free)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.6))
                }
            }
            .frame(width: 60)

            // Pro column
            Group {
                if showComingSoon {
                    Text(pro ?? "")
                        .font(.caption2)
                        .foregroundStyle(.purple.opacity(0.7))
                } else {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                }
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Pricing

    // MARK: - Already Pro

    private var alreadyProView: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.title2)
                .foregroundStyle(.purple)
            Text("paywall_already_pro_title")
                .font(.subheadline.weight(.semibold))
            Text("paywall_already_pro_subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        Group {
            if subscription.isPro {
                alreadyProView
            } else if subscription.isLoadingProducts && subscription.products.isEmpty {
                // Still loading
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if subscription.products.isEmpty {
                // Products not available — show info + retry + debug option
                productsUnavailableView
            } else if let product = subscription.lifetimeProduct {
                VStack(spacing: 8) {
                    Text(product.displayPrice)
                        .font(.system(size: 42, weight: .bold))
                    Text("one_time_payment_label")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        #if canImport(UIKit)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                        #else
                            .fill(Color(NSColor.controlBackgroundColor))
                        #endif
                }
            }
        }
    }

    private var productsUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bag.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("products_unavailable_title")
                .font(.subheadline.weight(.semibold))

            Text("products_unavailable_body")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await subscription.reloadProducts()
                }
            } label: {
                if subscription.isLoadingProducts {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("retry_button", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                }
            }
            .disabled(subscription.isLoadingProducts)

            #if DEBUG
                Divider()
                    .padding(.horizontal, 32)

                Button {
                    subscription.isMockPro = true
                    ToastManager.shared.show(
                        String(localized: "purchase_success_toast"),
                        style: .success
                    )
                    dismiss()
                } label: {
                    Label("debug_activate_pro", systemImage: "ladybug.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.orange, in: RoundedRectangle(cornerRadius: 12))
                }

                Text("debug_activate_pro_hint")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            #endif
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Purchase Button

    @ViewBuilder
    private var purchaseButton: some View {
        if !subscription.products.isEmpty && !subscription.isPro {
            Button {
                guard let product = subscription.lifetimeProduct else { return }
                Task {
                    do {
                        let outcome = try await subscription.purchase(product)
                        switch outcome {
                        case .success:
                            ToastManager.shared.show(
                                String(localized: "purchase_success_toast"),
                                style: .success
                            )
                            dismiss()
                        case .pending:
                            ToastManager.shared.show(
                                String(localized: "purchase_pending_toast"),
                                style: .info
                            )
                        case .cancelled:
                            break
                        }
                    } catch {
                        purchaseError = error.localizedDescription
                    }
                }
            } label: {
                Group {
                    if subscription.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("buy_once_button")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(.purple, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(subscription.lifetimeProduct == nil || subscription.isPurchasing)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    do {
                        let restored = try await subscription.restorePurchases()
                        if restored {
                            ToastManager.shared.show(
                                String(localized: "restore_success_toast"),
                                style: .success
                            )
                            dismiss()
                        } else {
                            ToastManager.shared.show(
                                String(localized: "restore_no_purchases_toast"),
                                style: .info
                            )
                        }
                    } catch {
                        ToastManager.shared.show(error.localizedDescription, style: .error)
                    }
                }
            } label: {
                if subscription.isRestoring {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("restore_purchases_button")
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                }
            }
            .disabled(subscription.isRestoring)

            HStack(spacing: 16) {
                Link(
                    "privacy_policy",
                    destination: URL(string: "https://idanidev.github.io/repomind/privacy")!
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Link(
                    "terms_of_use",
                    destination: URL(string: "https://idanidev.github.io/repomind/terms")!
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("paywall_legal_disclaimer")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    PaywallView()
}
