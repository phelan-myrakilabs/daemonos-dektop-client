import Foundation

// Core wire types used by the boot/session-list path. The wire format is snake_case;
// explicit CodingKeys are used because a handful of keys break the convention
// (e.g. `_lineage_root_id`).

/// `GET /api/status` — every field optional beyond the basics: gated backends omit
/// the filesystem fields, and the backend sends fields the desktop TS type lacks.
struct StatusResponse: Codable, Sendable {
    var version: String?
    var releaseDate: String?
    var gatewayRunning: Bool?
    var gatewayState: String?
    var activeSessions: Int?
    var activeAgents: Int?
    var authRequired: Bool?
    var authProviders: [String]?
    var canUpdateHermes: Bool?

    enum CodingKeys: String, CodingKey {
        case version
        case releaseDate = "release_date"
        case gatewayRunning = "gateway_running"
        case gatewayState = "gateway_state"
        case activeSessions = "active_sessions"
        case activeAgents = "active_agents"
        case authRequired = "auth_required"
        case authProviders = "auth_providers"
        case canUpdateHermes = "can_update_hermes"
    }
}

/// `GET /api/profiles/active` → `{ active, current }`. The desktop uses `current`.
struct ActiveProfileResponse: Codable, Sendable {
    var active: String
    var current: String
}

/// A session row. List endpoints return enriched rows (`preview`, `last_active`,
/// `is_active`, boolean `archived`); `GET /api/sessions/{id}` returns the raw table
/// row without those and with integer `archived` — so everything computed is optional
/// and `archived` decodes from bool or int.
struct SessionInfo: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var source: String?
    var title: String?
    var model: String?
    var startedAt: Double?
    var endedAt: Double?
    var endReason: String?
    var messageCount: Int?
    var toolCallCount: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var cwd: String?
    var gitBranch: String?
    var parentSessionID: String?

    // Computed by list endpoints only.
    var preview: String?
    var lastActive: Double?
    var isActive: Bool?
    var archived: Bool?
    var lineageRootID: String?
    var profile: String?
    var isDefaultProfile: Bool?

    enum CodingKeys: String, CodingKey {
        case id, source, title, model, cwd, preview, profile, archived
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case endReason = "end_reason"
        case messageCount = "message_count"
        case toolCallCount = "tool_call_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case gitBranch = "git_branch"
        case parentSessionID = "parent_session_id"
        case lastActive = "last_active"
        case isActive = "is_active"
        case lineageRootID = "_lineage_root_id"
        case isDefaultProfile = "is_default_profile"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Double.self, forKey: .endedAt)
        endReason = try container.decodeIfPresent(String.self, forKey: .endReason)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)
        toolCallCount = try container.decodeIfPresent(Int.self, forKey: .toolCallCount)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        parentSessionID = try container.decodeIfPresent(String.self, forKey: .parentSessionID)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        lastActive = try container.decodeIfPresent(Double.self, forKey: .lastActive)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
        lineageRootID = try container.decodeIfPresent(String.self, forKey: .lineageRootID)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        isDefaultProfile = try container.decodeIfPresent(Bool.self, forKey: .isDefaultProfile)
        // Raw table rows carry `archived` as SQLite 0/1; list rows as a real boolean.
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .archived) {
            archived = flag
        } else if let raw = try? container.decodeIfPresent(Int.self, forKey: .archived) {
            archived = raw != 0
        } else {
            archived = nil
        }
    }
}

/// `GET /api/sessions` / `GET /api/profiles/sessions` envelope.
struct PaginatedSessions: Codable, Sendable {
    var sessions: [SessionInfo]
    var total: Int
    var limit: Int?
    var offset: Int?
    var profileTotals: [String: Int]?
    var errors: [ProfileListError]?

    struct ProfileListError: Codable, Sendable {
        var profile: String
        var error: String
    }

    enum CodingKeys: String, CodingKey {
        case sessions, total, limit, offset, errors
        case profileTotals = "profile_totals"
    }
}

/// A hydrated transcript row from `GET /api/sessions/{id}/messages`.
/// `content` is a plain string, a structured array of multimodal parts, or null.
struct SessionMessage: Codable, Equatable, Sendable {
    var id: Int?
    var role: String
    var content: JSONValue?
    var toolCallID: String?
    var toolCalls: JSONValue?
    var toolName: String?
    var timestamp: Double?
    var finishReason: String?
    var reasoning: String?
    var reasoningContent: String?
    var reasoningDetails: JSONValue?
    var codexReasoningItems: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, reasoning
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
        case finishReason = "finish_reason"
        case reasoningContent = "reasoning_content"
        case reasoningDetails = "reasoning_details"
        case codexReasoningItems = "codex_reasoning_items"
    }
}

/// `GET /api/sessions/{id}/messages` envelope. The returned `session_id` can differ
/// from the requested id (compression/resume chain resolution).
struct SessionMessagesResponse: Codable, Equatable, Sendable {
    var sessionID: String
    var messages: [SessionMessage]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case messages
    }
}
