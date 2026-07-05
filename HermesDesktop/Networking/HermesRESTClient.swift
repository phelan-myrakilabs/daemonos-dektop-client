import Foundation

/// REST error. The message strings replicate the reference `fetchJson` exactly —
/// they are part of the observable contract (surfaced verbatim in UI/toasts).
struct HermesAPIError: Error, LocalizedError {
    let message: String
    let statusCode: Int?

    init(message: String, statusCode: Int? = nil) {
        self.message = message
        self.statusCode = statusCode
    }

    var errorDescription: String? { message }
}

/// Plain JSON-over-HTTP client for the Hermes REST API.
///
/// Auth is token-mode only: `X-Hermes-Session-Token` header on every authenticated
/// request. `/api/status` (the pre-auth probe) uses the credential-free variant so the
/// token never leaks to endpoints that don't need it.
struct HermesRESTClient: Sendable {
    /// Default REST timeout (`DEFAULT_FETCH_TIMEOUT_MS = 15_000`).
    static let defaultTimeout: TimeInterval = 15
    /// Boot-burst and session-list calls use 60 s.
    static let startupTimeout: TimeInterval = 60

    /// Returns the current normalized REST base URL (no trailing slash).
    let baseURLProvider: @Sendable () throws -> URL
    /// Returns the current session token, or nil when none is stored.
    let tokenProvider: @Sendable () -> String?

    private let session: URLSession

    init(baseURLProvider: @escaping @Sendable () throws -> URL,
         tokenProvider: @escaping @Sendable () -> String?,
         session: URLSession = .shared) {
        self.baseURLProvider = baseURLProvider
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Performs a request against `{base}{path}` and returns the parsed JSON body
    /// (nil for an empty 2xx body).
    @discardableResult
    func request(_ path: String,
                 method: String = "GET",
                 body: JSONValue? = nil,
                 timeout: TimeInterval = HermesRESTClient.defaultTimeout,
                 authenticated: Bool = true) async throws -> JSONValue? {
        let base = try baseURLProvider()
        guard let scheme = base.scheme, scheme == "http" || scheme == "https" else {
            throw HermesAPIError(message: "Unsupported Hermes backend URL protocol: \(base.scheme.map { "\($0):" } ?? "none")")
        }
        // String concatenation preserves any reverse-proxy path prefix in the base URL.
        guard let url = URL(string: base.absoluteString + path) else {
            throw HermesAPIError(message: "Remote gateway URL is not valid: \(base.absoluteString + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token = tokenProvider(), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw HermesAPIError(message: "Timed out connecting to Hermes backend after \(Int(timeout * 1000))ms")
        }

        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIError(message: "Invalid response from \(url.absoluteString)")
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""

        if http.statusCode >= 400 {
            let statusMessage = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            let detail = bodyText.isEmpty ? statusMessage : bodyText
            throw HermesAPIError(message: "\(http.statusCode): \(detail)", statusCode: http.statusCode)
        }

        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        // Guard against SPA index.html fallthrough on unregistered /api paths.
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let looksLikeHTML = contentType.contains("text/html")
            || trimmed.lowercased().hasPrefix("<!doctype")
            || trimmed.lowercased().hasPrefix("<html")
        if looksLikeHTML {
            throw HermesAPIError(
                message: "Expected JSON from \(url.absoluteString) but got HTML (status \(http.statusCode)). The endpoint is likely missing on the Hermes backend.",
                statusCode: http.statusCode
            )
        }

        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw HermesAPIError(
                message: "Invalid JSON from \(url.absoluteString) (status \(http.statusCode)): \(String(bodyText.prefix(200)))",
                statusCode: http.statusCode
            )
        }
    }

    /// Typed variant: decodes the response body into a `Decodable`.
    func request<T: Decodable>(_ path: String,
                               method: String = "GET",
                               body: JSONValue? = nil,
                               timeout: TimeInterval = HermesRESTClient.defaultTimeout,
                               authenticated: Bool = true,
                               as type: T.Type) async throws -> T {
        guard let value = try await request(path, method: method, body: body,
                                            timeout: timeout, authenticated: authenticated) else {
            throw HermesAPIError(message: "Empty response from \(path)")
        }
        return try value.decoded(as: type)
    }
}
