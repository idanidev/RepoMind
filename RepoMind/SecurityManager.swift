import Foundation
import LocalAuthentication
import Observation
import Security

// MARK: - Keychain Manager (Actor-isolated for thread safety)

actor KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.repomind.github-token"
    private let account = "github-pat"

    private init() {}

    // MARK: - Save Token

    func saveToken(_ token: String, for accountKey: String = "github-pat") throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first (cover both synced and non-synced variants)
        for syncable in [true, false] as [Bool] {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountKey,
                kSecAttrSynchronizable as String: syncable,
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }

        // Add new item — synced via iCloud Keychain for seamless cross-device login.
        //
        // After the first unlock, not only while unlocked: the background refresh that powers the
        // alerts runs with the phone locked, and a `WhenUnlocked` item is unreadable there
        // (errSecInteractionNotAllowed), which every caller read as "no token" and skipped.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Retrieve Token

    func retrieveToken(for accountKey: String = "github-pat") throws -> String? {
        // Try synced (iCloud Keychain) first, fall back to legacy non-synced items
        for syncable in [true, false] as [Bool] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountKey,
                kSecAttrSynchronizable as String: syncable,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            switch status {
            case errSecSuccess:
                guard let data = result as? Data,
                    let token = String(data: data, encoding: .utf8)
                else {
                    throw KeychainError.decodingFailed
                }
                return token
            case errSecItemNotFound:
                continue
            default:
                throw KeychainError.retrieveFailed(status)
            }
        }
        return nil
    }

    // MARK: - Delete Token

    func deleteToken(for accountKey: String = "github-pat") throws {
        // Delete both synced and non-synced items
        for syncable in [true, false] as [Bool] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountKey,
                kSecAttrSynchronizable as String: syncable,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.deleteFailed(status)
            }
        }
    }

    /// Every token this app keeps, synced or not: each account's and the one per connected app.
    /// Signing out has to take them all, or they survive in iCloud Keychain on every device.
    func deleteAllTokens() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Accessibility migration

    /// Moves the tokens saved before the change above to the class a background refresh can read.
    /// One update for the whole service; it needs the items readable, so it runs from the foreground
    /// at launch, and a failure (a launch with the phone locked) just tries again the next time.
    func migrateAccessibility(defaults: UserDefaults = .standard) {
        let doneKey = "keychainAfterFirstUnlock"
        guard !defaults.bool(forKey: doneKey) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let update: [String: Any] = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            defaults.set(true, forKey: doneKey)
        }
    }

    // MARK: - Check if token exists

    func hasToken(for accountKey: String = "github-pat") -> Bool {
        (try? retrieveToken(for: accountKey)) != nil
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Failed to encode token data."
        case .decodingFailed:
            "Failed to decode token data."
        case .saveFailed(let status):
            "Keychain save failed with status: \(status)."
        case .retrieveFailed(let status):
            "Keychain retrieval failed with status: \(status)."
        case .deleteFailed(let status):
            "Keychain deletion failed with status: \(status)."
        }
    }
}

// MARK: - Biometric Authentication

/// Deliberately `nonisolated` instead of `@MainActor`.
///
/// A main-actor isolated class gets a main-actor isolated `deinit`, so Swift emits a hop onto the
/// main executor just to deallocate it. SwiftUI releases `@State`-held objects while tearing down
/// the view graph, and that is not guaranteed to happen on the main thread — the hop crashed the
/// app inside `BiometricAuthManager.__deallocating_deinit` (heap corruption in the task-local
/// teardown). Nothing here needs isolation: `LAContext` is created per call, and the properties
/// are only ever touched from the view.
@Observable
nonisolated final class BiometricAuthManager {
    var isAuthenticated = false
    var biometricType: LABiometryType = .none
    var errorMessage: String?

    init() {
        checkBiometricAvailability()
    }

    func checkBiometricAvailability() {
        // Created locally rather than stored: a long-lived LAContext keeps a connection to the
        // authentication daemon alive and must be invalidated on dealloc, which is what put
        // LocalAuthentication teardown on the crashing path.
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }

    func authenticate() async {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "biometric_use_token")

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        else {
            errorMessage = error?.localizedDescription ?? String(localized: "biometric_unavailable")
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: "biometric_reason")
            )
            isAuthenticated = success
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticated = false
        }
    }
}
