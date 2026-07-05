import Foundation

// Session lifecycle / runtime wire types beyond the core list/messages models.

/// Session-creation RPC/REST result.
struct SessionCreateResponse: Codable, Equatable, Sendable {
    var info: SessionRuntimeInfo?
    var messageCount: Int?
    var messages: [SessionMessage]?
    var sessionID: String
    var storedSessionID: String?

    enum CodingKeys: String, CodingKey {
        case info, messages
        case messageCount = "message_count"
        case sessionID = "session_id"
        case storedSessionID = "stored_session_id"
    }
}

/// Session-resume result; `resumed` is the id that was resumed.
struct SessionResumeResponse: Codable, Equatable, Sendable {
    var info: SessionRuntimeInfo?
    var messageCount: Int
    var messages: [SessionMessage]
    var resumed: String
    var sessionID: String

    enum CodingKeys: String, CodingKey {
        case info, messages, resumed
        case messageCount = "message_count"
        case sessionID = "session_id"
    }
}

/// Live runtime info for a session. Appears in REST responses
/// (`SessionCreateResponse.info`, `SessionResumeResponse.info`) and in gateway
/// event payloads.
struct SessionRuntimeInfo: Codable, Equatable, Sendable {
    var branch: String?
    var configWarning: String?
    var credentialWarning: String?
    var cwd: String?
    var desktopContract: Int?
    var fast: Bool?
    var model: String?
    var personality: String?
    var provider: String?
    var reasoningEffort: String?
    var running: Bool?
    var serviceTier: String?
    var skills: Skills?
    var tools: [String: [String]]?
    var usage: PartialUsageStats?
    var version: String?
    var yolo: Bool?

    /// `Record<string, string[]> | string[]` on the wire — either skills grouped
    /// by category or a flat name list.
    enum Skills: Codable, Equatable, Sendable {
        case grouped([String: [String]])
        case flat([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let grouped = try? container.decode([String: [String]].self) {
                self = .grouped(grouped)
            } else {
                self = .flat(try container.decode([String].self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .grouped(let value): try container.encode(value)
            case .flat(let value): try container.encode(value)
            }
        }

        /// Skill names normalized across both wire shapes.
        var names: [String] {
            switch self {
            case .grouped(let groups): return groups.values.flatMap { $0 }.sorted()
            case .flat(let names): return names
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case branch, cwd, fast, model, personality, provider, running, skills, tools, usage, version, yolo
        case configWarning = "config_warning"
        case credentialWarning = "credential_warning"
        case desktopContract = "desktop_contract"
        case reasoningEffort = "reasoning_effort"
        case serviceTier = "service_tier"
    }
}

/// Token usage totals as reported by the backend (REST and gateway payloads).
struct UsageStats: Codable, Equatable, Sendable {
    var calls: Int
    var contextMax: Int?
    var contextPercent: Double?
    var contextUsed: Int?
    var costUSD: Double?
    var input: Int
    var output: Int
    var total: Int

    enum CodingKeys: String, CodingKey {
        case calls, input, output, total
        case contextMax = "context_max"
        case contextPercent = "context_percent"
        case contextUsed = "context_used"
        case costUSD = "cost_usd"
    }
}

/// All-optional mirror of `UsageStats` (TS `Partial<UsageStats>`), used by
/// `SessionRuntimeInfo.usage`.
struct PartialUsageStats: Codable, Equatable, Sendable {
    var calls: Int?
    var contextMax: Int?
    var contextPercent: Double?
    var contextUsed: Int?
    var costUSD: Double?
    var input: Int?
    var output: Int?
    var total: Int?

    enum CodingKeys: String, CodingKey {
        case calls, input, output, total
        case contextMax = "context_max"
        case contextPercent = "context_percent"
        case contextUsed = "context_used"
        case costUSD = "cost_usd"
    }
}

/// One hit from `GET /api/sessions/search?q=`.
struct SessionSearchResult: Codable, Equatable, Sendable {
    /// Lineage root of the matched conversation — the durable pin id; falls
    /// back to `sessionID` when absent. Key is `lineage_root` here, unlike
    /// `SessionInfo`'s `_lineage_root_id`.
    var lineageRoot: String?
    var model: String?
    var role: String?
    /// Live compression tip of the matched conversation — resume by this id.
    var sessionID: String
    var sessionStarted: Double?
    var snippet: String
    var source: String?

    enum CodingKeys: String, CodingKey {
        case model, role, snippet, source
        case lineageRoot = "lineage_root"
        case sessionID = "session_id"
        case sessionStarted = "session_started"
    }
}

/// `GET /api/sessions/search` envelope.
struct SessionSearchResponse: Codable, Equatable, Sendable {
    var results: [SessionSearchResult]

    enum CodingKeys: String, CodingKey {
        case results
    }
}

struct ContextUsageCategory: Codable, Equatable, Identifiable, Sendable {
    /// Server-supplied color string (format unspecified in the TS source).
    var color: String
    var id: String
    var label: String
    var tokens: Int

    enum CodingKeys: String, CodingKey {
        case color, id, label, tokens
    }
}

/// Per-category context window usage breakdown.
struct ContextBreakdown: Codable, Equatable, Sendable {
    var categories: [ContextUsageCategory]
    var contextMax: Int
    var contextPercent: Double
    var contextUsed: Int
    var estimatedTotal: Int
    var model: String?

    enum CodingKeys: String, CodingKey {
        case categories, model
        case contextMax = "context_max"
        case contextPercent = "context_percent"
        case contextUsed = "context_used"
        case estimatedTotal = "estimated_total"
    }
}
