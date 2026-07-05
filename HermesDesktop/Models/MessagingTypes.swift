import Foundation

// Messaging-platform wire types (`/api/messaging/platforms…`).

struct MessagingEnvVarInfo: Codable, Equatable, Sendable {
    var advanced: Bool
    var description: String
    var isPassword: Bool
    var isSet: Bool
    var key: String
    var prompt: String
    var redactedValue: String?
    var required: Bool
    var url: String?

    enum CodingKeys: String, CodingKey {
        case advanced, description, key, prompt, required, url
        case isPassword = "is_password"
        case isSet = "is_set"
        case redactedValue = "redacted_value"
    }
}

struct MessagingHomeChannel: Codable, Equatable, Sendable {
    var chatID: String
    var name: String
    var platform: String
    var threadID: String?

    init(chatID: String, name: String, platform: String, threadID: String? = nil) {
        self.chatID = chatID
        self.name = name
        self.platform = platform
        self.threadID = threadID
    }

    enum CodingKeys: String, CodingKey {
        case name, platform
        case chatID = "chat_id"
        case threadID = "thread_id"
    }
}

/// One platform card from `GET /api/messaging/platforms`.
struct MessagingPlatformInfo: Codable, Equatable, Identifiable, Sendable {
    var configured: Bool
    var description: String
    var docsURL: String
    var enabled: Bool
    var envVars: [MessagingEnvVarInfo]
    var errorCode: String?
    var errorMessage: String?
    var gatewayRunning: Bool
    var homeChannel: MessagingHomeChannel?
    var id: String
    var name: String
    var state: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case configured, description, enabled, id, name, state
        case docsURL = "docs_url"
        case envVars = "env_vars"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case gatewayRunning = "gateway_running"
        case homeChannel = "home_channel"
        case updatedAt = "updated_at"
    }
}

/// `GET /api/messaging/platforms` envelope.
struct MessagingPlatformsResponse: Codable, Equatable, Sendable {
    var platforms: [MessagingPlatformInfo]

    enum CodingKeys: String, CodingKey {
        case platforms
    }
}

/// Request body for `PUT /api/messaging/platforms/{id}`. Unset fields are
/// omitted on the wire (synthesized encoding uses `encodeIfPresent`).
struct MessagingPlatformUpdate: Codable, Equatable, Sendable {
    /// Env var keys to unset.
    var clearEnv: [String]?
    var enabled: Bool?
    /// Env vars to set.
    var env: [String: String]?

    init(clearEnv: [String]? = nil, enabled: Bool? = nil, env: [String: String]? = nil) {
        self.clearEnv = clearEnv
        self.enabled = enabled
        self.env = env
    }

    enum CodingKeys: String, CodingKey {
        case enabled, env
        case clearEnv = "clear_env"
    }
}

/// `POST /api/messaging/platforms/{id}/test`.
struct MessagingPlatformTestResponse: Codable, Equatable, Sendable {
    var message: String
    var ok: Bool
    var state: String?

    enum CodingKeys: String, CodingKey {
        case message, ok, state
    }
}
