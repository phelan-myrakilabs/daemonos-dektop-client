import Foundation

/// Signed-in identity from `GET /api/auth/me`.
struct DashboardSession: Codable, Sendable {
    var userID: String?
    var email: String?
    var provider: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email, provider
    }

    var displayName: String {
        if let email, !email.isEmpty { return email }
        if let userID, !userID.isEmpty { return userID }
        return "signed in"
    }
}

/// Client for the gated gateway's dashboard-auth routes (basic username/password
/// provider). Session state lives in HttpOnly cookies (`__Host-hermes_session_at`/`_rt`)
/// managed by the shared URLSession cookie store — the credentials themselves are
/// never persisted by the app. WS upgrades can't carry cookies' auth, so a
/// single-use 30 s ticket is minted immediately before every connect.
struct DashboardAuthClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// `POST /auth/password-login` — on success the session cookies are set on the
    /// shared cookie store. Failure modes are deliberately generic server-side:
    /// 401 invalid credentials, 404 unknown provider, 429 rate-limited, 503 store down.
    func login(baseURL: URL, provider: String, username: String, password: String) async throws {
        struct Body: Encodable {
            let provider: String
            let username: String
            let password: String
            var next = ""
        }
        var request = URLRequest(url: try endpoint(baseURL, "/auth/password-login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Body(provider: provider, username: username, password: password)
        )
        let (data, response) = try await session.data(for: request)
        try Self.throwOnError(response, data: data)
    }

    /// `GET /api/auth/me` — the current session, or nil when not signed in (401).
    func me(baseURL: URL) async throws -> DashboardSession? {
        var request = URLRequest(url: try endpoint(baseURL, "/api/auth/me"))
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            return nil
        }
        try Self.throwOnError(response, data: data)
        return try? JSONDecoder().decode(DashboardSession.self, from: data)
    }

    /// `POST /api/auth/ws-ticket` — single-use, 30 s TTL; mint immediately before
    /// EVERY WebSocket connect (a cached ticket URL always fails on reconnect).
    func mintWSTicket(baseURL: URL) async throws -> String {
        var request = URLRequest(url: try endpoint(baseURL, "/api/auth/ws-ticket"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        try Self.throwOnError(response, data: data)
        struct Ticket: Decodable { let ticket: String? }
        guard let ticket = (try? JSONDecoder().decode(Ticket.self, from: data))?.ticket,
              !ticket.isEmpty else {
            throw HermesAPIError(message: "Gateway did not return a WS ticket.")
        }
        return ticket
    }

    /// `POST /auth/logout` — clears the session cookies (best-effort revoke server-side).
    func logout(baseURL: URL) async {
        var request = URLRequest(url: (try? endpoint(baseURL, "/auth/logout")) ?? baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        _ = try? await session.data(for: request)
    }

    private func endpoint(_ base: URL, _ path: String) throws -> URL {
        guard let url = URL(string: base.absoluteString + path) else {
            throw HermesAPIError(message: "Invalid URL: \(base.absoluteString + path)")
        }
        return url
    }

    private static func throwOnError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }
        struct Detail: Decodable { let detail: String? }
        let detail = (try? JSONDecoder().decode(Detail.self, from: data))?.detail
        let message = detail ?? String(data: data, encoding: .utf8) ?? ""
        throw HermesAPIError(
            message: message.isEmpty ? "\(http.statusCode): request failed" : message,
            statusCode: http.statusCode
        )
    }
}
