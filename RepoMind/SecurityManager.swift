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

    func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Retrieve Token

    func retrieveToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodingFailed
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.retrieveFailed(status)
        }
    }

    // MARK: - Delete Token

    func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Check if token exists

    func hasToken() -> Bool {
        (try? retrieveToken()) != nil
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

@MainActor
@Observable
final class BiometricAuthManager {
    var isAuthenticated = false
    var biometricType: LABiometryType = .none
    var errorMessage: String?

    private let context = LAContext()

    init() {
        checkBiometricAvailability()
    }

    func checkBiometricAvailability() {
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }

    func authenticate() async {
        let context = LAContext()
        context.localizedCancelTitle = "Use Token"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            errorMessage = error?.localizedDescription ?? "Biometric authentication unavailable."
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock GitVoiceManager to access your repositories."
            )
            isAuthenticated = success
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticated = false
        }
    }
}
