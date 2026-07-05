import Foundation

// OAuth provider credential wire types (`/api/providers/oauth/…`).

/// Credential state for one OAuth provider row.
struct OAuthProviderStatus: Codable, Equatable, Sendable {
    var error: String?
    var expiresAt: String?
    var hasRefreshToken: Bool?
    var lastRefresh: String?
    var loggedIn: Bool
    var source: String?
    var sourceLabel: String?
    var tokenPreview: String?

    enum CodingKeys: String, CodingKey {
        case error, source
        case expiresAt = "expires_at"
        case hasRefreshToken = "has_refresh_token"
        case lastRefresh = "last_refresh"
        case loggedIn = "logged_in"
        case sourceLabel = "source_label"
        case tokenPreview = "token_preview"
    }
}

/// One provider row from `GET /api/providers/oauth`.
struct OAuthProvider: Codable, Equatable, Identifiable, Sendable {
    var cliCommand: String
    /// Shell command that clears an external provider's credentials, run in the
    /// embedded terminal. Nil when Hermes doesn't know how to remove it.
    var disconnectCommand: String?
    var disconnectHint: String?
    var disconnectable: Bool?
    var docsURL: String
    var flow: Flow
    var id: String
    var name: String
    var status: OAuthProviderStatus

    enum Flow: String, Codable, Sendable {
        case deviceCode = "device_code"
        case external
        case pkce
        case unknown

        init(from decoder: Decoder) throws {
            self = Flow(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case disconnectable, flow, id, name, status
        case cliCommand = "cli_command"
        case disconnectCommand = "disconnect_command"
        case disconnectHint = "disconnect_hint"
        case docsURL = "docs_url"
    }
}

/// `GET /api/providers/oauth` envelope.
struct OAuthProvidersResponse: Codable, Equatable, Sendable {
    var providers: [OAuthProvider]

    enum CodingKeys: String, CodingKey {
        case providers
    }
}

/// `POST /api/providers/oauth/{id}/start` — discriminated union on `flow`.
enum OAuthStartResponse: Codable, Equatable, Sendable {
    case pkce(authURL: String, expiresIn: Int, sessionID: String)
    case deviceCode(expiresIn: Int, pollInterval: Int, sessionID: String, userCode: String, verificationURL: String)

    private enum CodingKeys: String, CodingKey {
        case flow
        case authURL = "auth_url"
        case expiresIn = "expires_in"
        case sessionID = "session_id"
        case pollInterval = "poll_interval"
        case userCode = "user_code"
        case verificationURL = "verification_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let flow = try container.decode(String.self, forKey: .flow)
        switch flow {
        case "pkce":
            self = .pkce(
                authURL: try container.decode(String.self, forKey: .authURL),
                expiresIn: try container.decode(Int.self, forKey: .expiresIn),
                sessionID: try container.decode(String.self, forKey: .sessionID))
        case "device_code":
            self = .deviceCode(
                expiresIn: try container.decode(Int.self, forKey: .expiresIn),
                pollInterval: try container.decode(Int.self, forKey: .pollInterval),
                sessionID: try container.decode(String.self, forKey: .sessionID),
                userCode: try container.decode(String.self, forKey: .userCode),
                verificationURL: try container.decode(String.self, forKey: .verificationURL))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .flow, in: container, debugDescription: "Unknown OAuth flow \"\(flow)\"")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pkce(authURL, expiresIn, sessionID):
            try container.encode("pkce", forKey: .flow)
            try container.encode(authURL, forKey: .authURL)
            try container.encode(expiresIn, forKey: .expiresIn)
            try container.encode(sessionID, forKey: .sessionID)
        case let .deviceCode(expiresIn, pollInterval, sessionID, userCode, verificationURL):
            try container.encode("device_code", forKey: .flow)
            try container.encode(expiresIn, forKey: .expiresIn)
            try container.encode(pollInterval, forKey: .pollInterval)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(userCode, forKey: .userCode)
            try container.encode(verificationURL, forKey: .verificationURL)
        }
    }
}

/// `POST /api/providers/oauth/{id}/submit`.
struct OAuthSubmitResponse: Codable, Equatable, Sendable {
    var message: String?
    var ok: Bool
    var status: Status

    enum Status: String, Codable, Sendable {
        case approved
        case error
        case unknown

        init(from decoder: Decoder) throws {
            self = Status(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case message, ok, status
    }
}

/// `GET /api/providers/oauth/{id}/poll/{session_id}`.
/// Note: `expires_at` is numeric here, unlike the string form in `OAuthProviderStatus`.
struct OAuthPollResponse: Codable, Equatable, Sendable {
    var errorMessage: String?
    var expiresAt: Double?
    var sessionID: String
    var status: Status

    enum Status: String, Codable, Sendable {
        case approved
        case denied
        case error
        case expired
        case pending
        case unknown

        init(from decoder: Decoder) throws {
            self = Status(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case status
        case errorMessage = "error_message"
        case expiresAt = "expires_at"
        case sessionID = "session_id"
    }
}
