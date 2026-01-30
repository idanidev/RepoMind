import Foundation
import SwiftData
import SwiftUI

@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    // Limits
    let maxFreeRepos = 3
    let maxFreeAccounts = 1

    // Logic
    func canAddAccount(currentCount: Int) -> Bool {
        // Here we could check "isPro" from UserDefaults or CloudKit
        // For now, simple logic:
        return currentCount < maxFreeAccounts
    }

    func canAddRepo(currentCount: Int, accountIsPro: Bool) -> Bool {
        if accountIsPro { return true }
        return currentCount < maxFreeRepos
    }

    private init() {}
}
