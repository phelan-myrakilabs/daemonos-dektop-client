import Foundation

// Skills and skill-hub wire types (`/api/skills…`).

/// One row of the bare array returned by `GET /api/skills`.
struct SkillInfo: Codable, Equatable, Sendable {
    var category: String
    var description: String
    var enabled: Bool
    var name: String

    enum CodingKeys: String, CodingKey {
        case category, description, enabled, name
    }
}

/// One skill-hub source (official index, GitHub, skills.sh, …) as reported by
/// `GET /api/skills/hub/sources`.
struct SkillHubSource: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var available: Bool?
    var rateLimited: Bool?

    enum CodingKeys: String, CodingKey {
        case id, label, available
        case rateLimited = "rate_limited"
    }
}

/// A searchable/installable hub skill from `GET /api/skills/hub/search`.
struct SkillHubResult: Codable, Equatable, Sendable {
    var name: String
    var description: String
    var source: String
    var identifier: String
    var trustLevel: String
    var repo: String?
    var tags: [String]

    enum CodingKeys: String, CodingKey {
        case name, description, source, identifier, repo, tags
        case trustLevel = "trust_level"
    }
}

struct SkillHubInstalledEntry: Codable, Equatable, Sendable {
    var name: String?
    var trustLevel: String?
    var scanVerdict: String?

    enum CodingKeys: String, CodingKey {
        case name
        case trustLevel = "trust_level"
        case scanVerdict = "scan_verdict"
    }
}

/// `GET /api/skills/hub/sources` envelope. `installed` is keyed by skill identifier.
struct SkillHubSourcesResponse: Codable, Equatable, Sendable {
    var sources: [SkillHubSource]
    var indexAvailable: Bool
    var featured: [SkillHubResult]
    var installed: [String: SkillHubInstalledEntry]

    enum CodingKeys: String, CodingKey {
        case sources, featured, installed
        case indexAvailable = "index_available"
    }
}

/// `GET /api/skills/hub/search` envelope.
struct SkillHubSearchResponse: Codable, Equatable, Sendable {
    var results: [SkillHubResult]
    var sourceCounts: [String: Int]
    var timedOut: [String]
    var installed: [String: SkillHubInstalledEntry]

    enum CodingKeys: String, CodingKey {
        case results, installed
        case sourceCounts = "source_counts"
        case timedOut = "timed_out"
    }
}

/// `GET /api/skills/hub/preview` — SKILL.md + manifest without installing.
struct SkillHubPreview: Codable, Equatable, Sendable {
    var name: String
    var description: String
    var source: String
    var identifier: String
    var trustLevel: String
    var repo: String?
    var tags: [String]
    var skillMD: String
    var files: [String]

    enum CodingKeys: String, CodingKey {
        case name, description, source, identifier, repo, tags, files
        case trustLevel = "trust_level"
        case skillMD = "skill_md"
    }
}

struct SkillHubScanFinding: Codable, Equatable, Sendable {
    var severity: String
    var category: String
    var file: String
    var line: Int?
    var description: String

    enum CodingKeys: String, CodingKey {
        case severity, category, file, line, description
    }
}

/// `GET /api/skills/hub/scan` — install-time security scan verdict.
struct SkillHubScanResult: Codable, Equatable, Sendable {
    var name: String
    var identifier: String
    var source: String
    var trustLevel: String
    var verdict: String
    var summary: String
    var policy: Policy
    var policyReason: String?
    var findings: [SkillHubScanFinding]
    var severityCounts: [String: Int]

    enum Policy: String, Codable, Sendable {
        case allow
        case ask
        case block
        case unknown

        init(from decoder: Decoder) throws {
            self = Policy(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, identifier, source, verdict, summary, policy, findings
        case trustLevel = "trust_level"
        case policyReason = "policy_reason"
        case severityCounts = "severity_counts"
    }
}
