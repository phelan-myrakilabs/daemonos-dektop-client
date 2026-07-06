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
        static let mode = "connection.mode"
    }

    private let defaults: UserDefaults
    /// Shared token cache — the REST/WS clients read from this too, so the Keychain
    /// is touched at most once per launch (not per request).
    let tokenCache: TokenCache

    var settings: ConnectionSettings {
        didSet { persist() }
    }

    /// Bumped by setToken so `tokenPreview`/`needsSetup` re-read the cache; the
    /// Keychain is not read at init (avoids a blocking read / prompt on launch).
    private var tokenRevision = 0

    init(defaults: UserDefaults = .standard, tokenCache: TokenCache = TokenCache()) {
        self.defaults = defaults
        self.tokenCache = tokenCache
        self.settings = ConnectionSettings(
            restBaseURLString: defaults.string(forKey: Keys.restBaseURL) ?? ConnectionSettings.defaultRESTBaseURL,
            wsURLString: defaults.string(forKey: Keys.wsURL) ?? ConnectionSettings.defaultWSURL,
            mode: defaults.string(forKey: Keys.mode).flatMap(ConnectionMode.init) ?? .v1
        )
    }

    /// Whether a token is saved. Reads the cache lazily (first access loads once).
    var tokenPresent: Bool {
        _ = tokenRevision // observation dependency so UI refreshes after setToken
        return tokenCache.isPresent
    }

    private func persist() {
        defaults.set(settings.restBaseURLString, forKey: Keys.restBaseURL)
        defaults.set(settings.mode.rawValue, forKey: Keys.mode)
        // Token-hygiene backstop: never let a query string (which could carry ?token=)
        // reach UserDefaults, even if a raw URL slipped past the settings form.
        defaults.set(Self.strippedOfQuery(settings.wsURLString), forKey: Keys.wsURL)
    }

    private static func strippedOfQuery(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? raw
    }

    /// No token stored yet → show Settings instead of dialing.
    var needsSetup: Bool { !tokenPresent }

    func token() -> String? {
        _ = tokenRevision
        return tokenCache.current()
    }

    func setToken(_ token: String?) throws {
        try tokenCache.set(token)
        tokenRevision &+= 1
    }

    /// Reference `tokenPreview`: empty → nil; length <= 8 → "set"; else "...{last 6}".
    /// The raw token is never echoed to UI.
    var tokenPreview: String? {
        guard let token = token(), !token.isEmpty else { return nil }
        if token.count <= 8 { return "set" }
        return "...\(token.suffix(6))"
    }
}
