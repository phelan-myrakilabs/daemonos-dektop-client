import Foundation

// Usage-analytics wire types (`GET /api/analytics/usage?days=`).

struct AnalyticsDailyEntry: Codable, Equatable, Sendable {
    var actualCost: Double
    var apiCalls: Int
    var cacheReadTokens: Int
    /// Date key (presumed `YYYY-MM-DD`).
    var day: String
    var estimatedCost: Double
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var sessions: Int

    enum CodingKeys: String, CodingKey {
        case day, sessions
        case actualCost = "actual_cost"
        case apiCalls = "api_calls"
        case cacheReadTokens = "cache_read_tokens"
        case estimatedCost = "estimated_cost"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
    }
}

struct AnalyticsModelEntry: Codable, Equatable, Sendable {
    var apiCalls: Int
    var estimatedCost: Double
    var inputTokens: Int
    var model: String
    var outputTokens: Int
    var sessions: Int

    enum CodingKeys: String, CodingKey {
        case model, sessions
        case apiCalls = "api_calls"
        case estimatedCost = "estimated_cost"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct AnalyticsSkillEntry: Codable, Equatable, Sendable {
    var lastUsedAt: Double?
    var manageCount: Int
    var percentage: Double
    var skill: String
    var totalCount: Int
    var viewCount: Int

    enum CodingKeys: String, CodingKey {
        case percentage, skill
        case lastUsedAt = "last_used_at"
        case manageCount = "manage_count"
        case totalCount = "total_count"
        case viewCount = "view_count"
    }
}

struct AnalyticsSkillsSummary: Codable, Equatable, Sendable {
    var distinctSkillsUsed: Int
    var totalSkillActions: Int
    var totalSkillEdits: Int
    var totalSkillLoads: Int

    enum CodingKeys: String, CodingKey {
        case distinctSkillsUsed = "distinct_skills_used"
        case totalSkillActions = "total_skill_actions"
        case totalSkillEdits = "total_skill_edits"
        case totalSkillLoads = "total_skill_loads"
    }
}

/// Nullable totals are present-but-null on the wire (`null | number`).
struct AnalyticsTotals: Codable, Equatable, Sendable {
    var totalActualCost: Double
    var totalAPICalls: Int?
    var totalCacheRead: Int?
    var totalEstimatedCost: Double
    var totalInput: Int?
    var totalOutput: Int?
    var totalReasoning: Int?
    var totalSessions: Int

    enum CodingKeys: String, CodingKey {
        case totalActualCost = "total_actual_cost"
        case totalAPICalls = "total_api_calls"
        case totalCacheRead = "total_cache_read"
        case totalEstimatedCost = "total_estimated_cost"
        case totalInput = "total_input"
        case totalOutput = "total_output"
        case totalReasoning = "total_reasoning"
        case totalSessions = "total_sessions"
    }
}

/// `GET /api/analytics/usage` envelope.
struct AnalyticsResponse: Codable, Equatable, Sendable {
    var byModel: [AnalyticsModelEntry]
    var daily: [AnalyticsDailyEntry]
    var periodDays: Int
    var skills: Skills
    var totals: AnalyticsTotals

    struct Skills: Codable, Equatable, Sendable {
        var summary: AnalyticsSkillsSummary
        var topSkills: [AnalyticsSkillEntry]

        enum CodingKeys: String, CodingKey {
            case summary
            case topSkills = "top_skills"
        }
    }

    enum CodingKeys: String, CodingKey {
        case daily, skills, totals
        case byModel = "by_model"
        case periodDays = "period_days"
    }
}
