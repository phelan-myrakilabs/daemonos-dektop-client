import Foundation

/// Auth mode. Only `.token` is implemented in v1; `.oauth` exists so the connection
/// layer keeps the seam the reference defines (`normAuthMode`: unknown → token).
enum AuthMode: String, Codable, Sendable {
    case token
    case oauth

    init(coercing raw: String?) {
        self = raw == "oauth" ? .oauth : .token
    }
}

/// The two independently configurable endpoints. This deliberately breaks the
/// original's assumption that the WS URL derives from the REST base — the
/// Cloudflare tunnel setup runs them on separate hostnames.
struct ConnectionSettings: Equatable, Sendable {
    /// REST API base, e.g. `https://api-hermes.myrakilabs.com`. All `/api/*` calls.
    var restBaseURLString: String
    /// WebSocket gateway URL including the `/api/ws` path,
    /// e.g. `wss://hermes.myrakilabs.com/api/ws`. Empty = derive from the REST base.
    var wsURLString: String
    var authMode: AuthMode = .token

    static let defaultRESTBaseURL = "https://api-hermes.myrakilabs.com"
    static let defaultWSURL = "wss://hermes.myrakilabs.com/api/ws"

    static let `default` = ConnectionSettings(
        restBaseURLString: defaultRESTBaseURL,
        wsURLString: defaultWSURL
    )

    /// Replicates `normalizeRemoteBaseUrl`: trim; require http(s); strip query,
    /// fragment, and trailing slashes. Cloudflare terminates TLS, so this client
    /// additionally requires `https`.
    static func normalizeRESTBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HermesAPIError(message: "Remote gateway URL is required.")
        }
        guard var components = URLComponents(string: trimmed), components.host != nil else {
            throw HermesAPIError(message: "Remote gateway URL is not valid: \(trimmed)")
        }
        guard components.scheme == "https" else {
            throw HermesAPIError(message: "Remote gateway URL must be https://, got \(components.scheme.map { "\($0):" } ?? "none")")
        }
        components.query = nil
        components.fragment = nil
        while components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        guard let url = components.url else {
            throw HermesAPIError(message: "Remote gateway URL is not valid: \(trimmed)")
        }
        return url
    }

    /// The WebSocket URL with the token attached as `?token=` (percent-encoded to
    /// `encodeURIComponent` semantics). Uses the explicit WS URL when set, else
    /// derives from the REST base per the reference `buildGatewayWsUrl`
    /// (`https → wss`, path prefix preserved, `/api/ws` appended).
    /// Normalizes an explicit WS URL: trims, requires `wss://`, and strips any query
    /// string, fragment, and trailing slashes. Stripping the query is a token-hygiene
    /// guard — a pasted `…/api/ws?token=SECRET` must never be persisted to UserDefaults,
    /// and the live token is appended fresh at connect time. Empty input returns "".
    static func normalizedWSURLString(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard var components = URLComponents(string: trimmed), components.host != nil else {
            throw HermesAPIError(message: "WebSocket gateway URL is not valid: \(trimmed)")
        }
        guard components.scheme == "wss" else {
            throw HermesAPIError(message: "WebSocket gateway URL must be wss://, got \(components.scheme.map { "\($0):" } ?? "none")")
        }
        components.query = nil
        components.fragment = nil
        while components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        guard let cleaned = components.url?.absoluteString else {
            throw HermesAPIError(message: "WebSocket gateway URL is not valid: \(trimmed)")
        }
        return cleaned
    }

    func webSocketURL(token: String) throws -> URL {
        let cleanedWS = try Self.normalizedWSURLString(wsURLString)
        let base: String
        if !cleanedWS.isEmpty {
            // The explicit WS URL is the complete endpoint (default already ends /api/ws).
            base = cleanedWS
        } else {
            let rest = try Self.normalizeRESTBaseURL(restBaseURLString)
            var components = URLComponents(url: rest, resolvingAgainstBaseURL: false)!
            components.scheme = "wss"
            base = components.url!.absoluteString + "/api/ws"
        }

        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .uriComponentAllowed) else {
            throw HermesAPIError(message: "Session token could not be encoded.")
        }
        guard let url = URL(string: base + "?token=" + encodedToken) else {
            throw HermesAPIError(message: "WebSocket gateway URL is not valid: \(base)")
        }
        return url
    }
}

extension CharacterSet {
    /// Characters `encodeURIComponent` leaves unescaped: A–Z a–z 0–9 - _ . ! ~ * ' ( )
    static let uriComponentAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.!~*'()")
        return set
    }()
}
