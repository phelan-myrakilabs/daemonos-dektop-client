import Foundation

// Memory-provider and curator wire types (`/api/memory/…`, `/api/curator`).

/// `GET /api/memory/providers/{provider}/oauth/status` (also returned by
/// `POST /api/memory/providers/{provider}/oauth/start`).
struct MemoryProviderOAuthStatus: Codable, Equatable, Sendable {
    /// Present-but-nullable on the wire (`'apikey' | 'oauth' | null`).
    var auth: Auth?
    var connected: Bool
    var detail: String
    var state: State

    enum Auth: String, Codable, Sendable {
        case apiKey = "apikey"
        case oauth
        case unknown

        init(from decoder: Decoder) throws {
            self = Auth(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum State: String, Codable, Sendable {
        case connected
        case error
        case idle
        case pending
        case unknown

        init(from decoder: Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case auth, connected, detail, state
    }
}

enum MemoryProviderFieldKind: String, Codable, Sendable {
    case secret
    case select
    case text
    case unknown

    init(from decoder: Decoder) throws {
        self = MemoryProviderFieldKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

struct MemoryProviderFieldOption: Codable, Equatable, Sendable {
    var description: String
    var label: String
    var value: String

    enum CodingKeys: String, CodingKey {
        case description, label, value
    }
}

struct MemoryProviderField: Codable, Equatable, Sendable {
    var description: String
    var isSet: Bool
    var key: String
    var kind: MemoryProviderFieldKind
    var label: String
    var options: [MemoryProviderFieldOption]
    var placeholder: String
    /// Always `""` for secrets — they are write-only over the API.
    var value: String

    enum CodingKeys: String, CodingKey {
        case description, key, kind, label, options, placeholder, value
        case isSet = "is_set"
    }
}

/// `GET /api/memory/providers/{provider}/config`.
struct MemoryProviderConfig: Codable, Equatable, Sendable {
    var fields: [MemoryProviderField]
    var label: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case fields, label, name
    }
}

/// `GET /api/memory` — active provider + built-in memory file sizes.
struct MemoryStatusResponse: Codable, Equatable, Sendable {
    var active: String
    var providers: [Provider]
    var builtinFiles: BuiltinFiles

    struct Provider: Codable, Equatable, Sendable {
        var name: String
        var description: String
        var configured: Bool

        enum CodingKeys: String, CodingKey {
            case name, description, configured
        }
    }

    /// Sizes (presumed bytes) of the built-in memory files.
    struct BuiltinFiles: Codable, Equatable, Sendable {
        var memory: Int
        var user: Int

        enum CodingKeys: String, CodingKey {
            case memory, user
        }
    }

    enum CodingKeys: String, CodingKey {
        case active, providers
        case builtinFiles = "builtin_files"
    }
}

/// `GET /api/curator` — background skill-curator status.
struct CuratorStatusResponse: Codable, Equatable, Sendable {
    var enabled: Bool
    var paused: Bool
    var intervalHours: Double?
    var lastRunAt: String?
    var minIdleHours: Double?
    var staleAfterDays: Int?
    var archiveAfterDays: Int?

    enum CodingKeys: String, CodingKey {
        case enabled, paused
        case intervalHours = "interval_hours"
        case lastRunAt = "last_run_at"
        case minIdleHours = "min_idle_hours"
        case staleAfterDays = "stale_after_days"
        case archiveAfterDays = "archive_after_days"
    }
}
