import Foundation
import Security

/// Thread-safe in-memory cache over `KeychainTokenStore`, so the token is read from
/// the Keychain at most once per launch instead of on every authenticated request.
/// The first read is memoized even on failure (a locked/denied Keychain returns nil
/// once rather than re-prompting per request). Safe to read from any thread — the
/// REST/WS clients call `current()` from background executors.
final class TokenCache: @unchecked Sendable {
    private let lock = NSLock()
    private let keychain: KeychainTokenStore
    private var cached: String?
    private var loaded = false

    init(keychain: KeychainTokenStore = KeychainTokenStore()) {
        self.keychain = keychain
    }

    /// The cached token, loading it from the Keychain once on first access.
    func current() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if !loaded {
            cached = normalize((try? keychain.read()) ?? nil)
            loaded = true
        }
        return cached
    }

    /// Whether a non-empty token is present (loads on first access).
    var isPresent: Bool { current()?.isEmpty == false }

    /// Persist a new value (or clear when nil/empty) and update the cache.
    func set(_ token: String?) throws {
        let normalized = normalize(token)
        if let normalized {
            try keychain.write(normalized)
        } else {
            try keychain.delete()
        }
        lock.lock()
        cached = normalized
        loaded = true
        lock.unlock()
    }

    private func normalize(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Stores the Hermes session token as a generic password in the user's Keychain.
/// The token must never be written to UserDefaults or logged.
struct KeychainTokenStore {
    let service: String
    let account: String

    init(service: String = "com.myrakilabs.HermesDesktop", account: String = "session-token") {
        self.service = service
        self.account = account
    }

    enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
                return "Keychain error: \(message)"
            }
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Non-interactive: a background token read must never pop a keychain-unlock
        // dialog. If the keychain is locked the read fails (→ nil) instead of
        // blocking the UI; it succeeds normally once the keychain is unlocked.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound, errSecInteractionNotAllowed:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func write(_ token: String) throws {
        let data = Data(token.utf8)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
