import Foundation
import Security
import StoreKit
import SwiftUI

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    // MARK: - Product IDs

    enum ProductID: String, CaseIterable {
        case proLifetime = "com.idanidev.repomind.pro"
    }

    // MARK: - Purchase Outcome

    enum PurchaseOutcome {
        case success
        case cancelled
        /// Awaiting parental / Ask to Buy approval.
        case pending
    }

    // MARK: - Free Tier Limits

    let maxFreeRepos = 3
    let maxFreeAccounts = 1
    let maxFreeKanbanColumns = 3

    // MARK: - Subscription State

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []

    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false

    /// Convenience: `true` when any async operation is in flight.
    var isLoading: Bool { isLoadingProducts || isPurchasing || isRestoring }

    /// Mock testing support — only effective in DEBUG builds.
    /// In RELEASE builds, setting this has no effect and isPro relies solely on StoreKit.
    var isMockPro: Bool {
        get { _isMockPro }
        set {
            #if DEBUG
                _isMockPro = newValue
            #endif
        }
    }

    private var _isMockPro = false

    // MARK: - Computed Properties

    var isPro: Bool {
        isMockPro || !purchasedProductIDs.isEmpty
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == ProductID.proLifetime.rawValue }
    }

    var currentPlanName: String {
        if isMockPro { return "Pro (Test)" }
        if isPro { return String(localized: "plan_pro") }
        return String(localized: "plan_free")
    }

    // MARK: - Transaction Listener

    private var transactionListener: Task<Void, Error>?

    private init() {
        // Restore cached state for offline access (stored in Keychain)
        if Self.keychainRead() {
            purchasedProductIDs.insert("cached")
        }

        transactionListener = listenForTransactions()

        // Kick off initial load — callers can also await loadProducts() to be safe
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    // MARK: - Load Products

    /// Error visible to UI when products fail to load or purchase fails.
    private(set) var lastError: String?

    /// Ongoing load task to coalesce concurrent calls.
    private var loadTask: Task<Void, Never>?

    /// Loads products if not already loaded. Safe to call multiple times —
    /// concurrent callers will await the same underlying task.
    func loadProducts() async {
        // Already loaded? Done.
        if !products.isEmpty { return }

        // If a load is already in flight, wait for it instead of returning early.
        if let existing = loadTask {
            await existing.value
            return
        }

        let task = Task {
            isLoadingProducts = true
            defer { isLoadingProducts = false }
            do {
                let ids = ProductID.allCases.map(\.rawValue)
                let loaded = try await Product.products(for: ids)
                    .sorted { $0.price < $1.price }
                products = loaded
                #if DEBUG
                print("[SubscriptionManager] Loaded \(loaded.count) products: \(loaded.map { "\($0.id) — \($0.displayPrice)" })")
                #endif

                if loaded.isEmpty {
                    lastError = String(localized: "products_not_available")
                    #if DEBUG
                    print("[SubscriptionManager] ⚠️ Products array is empty — StoreKit config not linked or IDs don't match.")
                    #endif
                } else {
                    lastError = nil
                }
            } catch {
                lastError = error.localizedDescription
                #if DEBUG
                print("[SubscriptionManager] ❌ Failed to load products: \(error)")
                #endif
            }
        }

        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Force reload products (e.g. from retry button).
    func reloadProducts() async {
        products = []
        loadTask = nil
        await loadProducts()
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return .success
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    // MARK: - Restore Purchases

    /// Syncs purchases with the App Store and returns `true` if the user is Pro.
    /// Throws if `AppStore.sync()` fails (e.g. no network) so callers can show the real error.
    @discardableResult
    func restorePurchases() async throws -> Bool {
        isRestoring = true
        defer { isRestoring = false }

        try await AppStore.sync()
        await updatePurchasedProducts()
        return isPro
    }

    // MARK: - Gating Logic

    func canAddAccount(currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < maxFreeAccounts
    }

    func canAddRepo(currentCount: Int, accountIsPro: Bool = false) -> Bool {
        if isPro || accountIsPro { return true }
        return currentCount < maxFreeRepos
    }

    func canAddKanbanColumn(currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < maxFreeKanbanColumns
    }

    // MARK: - Private Helpers

    private func updatePurchasedProducts() async {
        var newPurchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                newPurchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = newPurchased
        Self.keychainSave(!newPurchased.isEmpty)
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await self?.updatePurchasedProducts()
                    await transaction.finish()
                case .unverified(let transaction, _):
                    // Don't grant entitlement, but finish so StoreKit stops resending it.
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }

    // MARK: - Keychain Cache (more tamper-resistant than UserDefaults)

    private static let keychainService = "idanidev.RepoMind"
    private static let keychainAccount = "cachedIsPro"

    private static func keychainSave(_ flag: Bool) {
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        guard flag else { return }
        var addQuery = deleteQuery
        addQuery[kSecValueData] = Data([1])
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func keychainRead() -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
}
