import Foundation

// Profile and project wire types (`/api/profiles…`).

/// Request body for `POST /api/profiles`. Unset fields are omitted on the wire.
/// Semantics: explicit `cloneFrom` wins; `cloneAll` without a source clones from
/// `"default"`; otherwise `cloneFromDefault` controls cloning.
struct ProfileCreatePayload: Codable, Equatable, Sendable {
    var cloneAll: Bool?
    var cloneFrom: String?
    var cloneFromDefault: Bool?
    var name: String
    var noSkills: Bool?

    init(name: String, cloneAll: Bool? = nil, cloneFrom: String? = nil,
         cloneFromDefault: Bool? = nil, noSkills: Bool? = nil) {
        self.name = name
        self.cloneAll = cloneAll
        self.cloneFrom = cloneFrom
        self.cloneFromDefault = cloneFromDefault
        self.noSkills = noSkills
    }

    enum CodingKeys: String, CodingKey {
        case name
        case cloneAll = "clone_all"
        case cloneFrom = "clone_from"
        case cloneFromDefault = "clone_from_default"
        case noSkills = "no_skills"
    }
}

/// One profile row from `GET /api/profiles`. The backend sends extra fields
/// (`gateway_running`, `description`, `distribution_*`, …) beyond this consumed
/// subset; they are intentionally ignored.
struct ProfileInfo: Codable, Equatable, Sendable {
    var hasEnv: Bool
    var isDefault: Bool
    var model: String?
    var name: String
    var path: String
    var provider: String?
    var skillCount: Int

    enum CodingKeys: String, CodingKey {
        case model, name, path, provider
        case hasEnv = "has_env"
        case isDefault = "is_default"
        case skillCount = "skill_count"
    }
}

/// `GET /api/profiles/{name}/setup-command`.
struct ProfileSetupCommand: Codable, Equatable, Sendable {
    var command: String

    enum CodingKeys: String, CodingKey {
        case command
    }
}

/// `GET /api/profiles/{name}/soul`.
struct ProfileSoul: Codable, Equatable, Sendable {
    var content: String
    var exists: Bool

    enum CodingKeys: String, CodingKey {
        case content, exists
    }
}

/// `GET /api/profiles` envelope.
struct ProfilesResponse: Codable, Equatable, Sendable {
    var profiles: [ProfileInfo]

    enum CodingKeys: String, CodingKey {
        case profiles
    }
}

// Projects: a first-class, per-profile, human-named workspace spanning one or
// more folders. Mirrors `hermes_cli/projects_db.Project.to_dict()`.

struct ProjectFolder: Codable, Equatable, Sendable {
    var path: String
    var label: String?
    var isPrimary: Bool
    var addedAt: Double

    enum CodingKeys: String, CodingKey {
        case path, label
        case isPrimary = "is_primary"
        case addedAt = "added_at"
    }
}

struct ProjectInfo: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var slug: String
    var name: String
    var description: String?
    var icon: String?
    var color: String?
    var boardSlug: String?
    var primaryPath: String?
    var archived: Bool
    var createdAt: Double
    var folders: [ProjectFolder]

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description, icon, color, archived, folders
        case boardSlug = "board_slug"
        case primaryPath = "primary_path"
        case createdAt = "created_at"
    }
}

struct ProjectsPayload: Codable, Equatable, Sendable {
    var projects: [ProjectInfo]
    var activeID: String?

    enum CodingKeys: String, CodingKey {
        case projects
        case activeID = "active_id"
    }
}
