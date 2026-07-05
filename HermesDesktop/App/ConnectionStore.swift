import Foundation
import Observation

/// Persists the two endpoints in UserDefaults and the token in the Keychain.
/// The token is never written to UserDefaults or logs.
@MainActor
@Observable
final class ConnectionStore {
    enum Keys {
        static let restBaseURL = "connection.restBaseURL"
        static let wsURL = "connection.wsURL"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainTokenStore

    var settings: ConnectionSettings {
        didSet { persist() }
    }

    private(set) var tokenPresent: Bool

    init(defaults: UserDefaults = .standard, keychain: KeychainTokenStore = KeychainTokenStore()) {
        self.defaults = defaults
        self.keychain = keychain
        self.settings = ConnectionSettings(
            restBaseURLString: defaults.string(forKey: Keys.restBaseURL) ?? ConnectionSettings.defaultRESTBaseURL,
            wsURLString: defaults.string(forKey: Keys.wsURL) ?? ConnectionSettings.defaultWSURL
        )
        self.tokenPresent = ((try? keychain.read()) ?? nil)?.isEmpty == false
    }

    private func persist() {
        defaults.set(settings.restBaseURLString, forKey: Keys.restBaseURL)
        defaults.set(settings.wsURLString, forKey: Keys.wsURL)
    }

    /// No token stored yet → show Settings instead of dialing.
    var needsSetup: Bool { !tokenPresent }

    func token() -> String? {
        (try? keychain.read()) ?? nil
    }

    func setToken(_ token: String?) throws {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            try keychain.delete()
            tokenPresent = false
        } else {
            try keychain.write(trimmed)
            tokenPresent = true
        }
    }

    /// Reference `tokenPreview`: empty → nil; length <= 8 → "set"; else "...{last 6}".
    /// The raw token is never echoed to UI.
    var tokenPreview: String? {
        guard let token = token(), !token.isEmpty else { return nil }
        if token.count <= 8 { return "set" }
        return "...\(token.suffix(6))"
    }
}
