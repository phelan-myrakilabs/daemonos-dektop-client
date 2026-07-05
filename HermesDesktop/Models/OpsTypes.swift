import Foundation

// Ops / logs / actions / backend-update wire types.

/// `GET /api/logs`.
struct LogsResponse: Codable, Equatable, Sendable {
    var file: String
    var lines: [String]

    enum CodingKeys: String, CodingKey {
        case file, lines
    }
}

/// Per-platform gateway state, keyed by platform id in
/// `StatusResponse.gateway_platforms` (the core `StatusResponse` model decodes
/// only the boot-path subset and skips that map).
struct PlatformStatus: Codable, Equatable, Sendable {
    var errorCode: String?
    var errorMessage: String?
    var state: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case state
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case updatedAt = "updated_at"
    }
}

/// A spawned background action (`POST /api/gateway/restart`, `/api/ops/doctor`,
/// skill-hub installs, …); poll `GET /api/actions/{name}/status`.
struct ActionResponse: Codable, Equatable, Sendable {
    var name: String
    var ok: Bool
    var pid: Int

    enum CodingKeys: String, CodingKey {
        case name, ok, pid
    }
}

/// `GET /api/actions/{name}/status?lines=`.
struct ActionStatusResponse: Codable, Equatable, Sendable {
    var exitCode: Int?
    var lines: [String]
    var name: String
    var pid: Int?
    var running: Bool

    enum CodingKeys: String, CodingKey {
        case lines, name, pid, running
        case exitCode = "exit_code"
    }
}

struct BackendUpdateCommit: Codable, Equatable, Sendable {
    var sha: String
    var summary: String
    var author: String
    var at: Double

    enum CodingKeys: String, CodingKey {
        case sha, summary, author, at
    }
}

/// `GET /api/hermes/update/check` — the backend's own update state. Drives the
/// desktop's remote update overlay so the backend version (not the client)
/// decides "what's changed + Install" in remote mode.
struct BackendUpdateCheckResponse: Codable, Equatable, Sendable {
    var installMethod: String
    var currentVersion: String
    var behind: Int?
    var updateAvailable: Bool
    var canApply: Bool
    var updateCommand: String?
    var message: String?
    var commits: [BackendUpdateCommit]?

    enum CodingKeys: String, CodingKey {
        case behind, message, commits
        case installMethod = "install_method"
        case currentVersion = "current_version"
        case updateAvailable = "update_available"
        case canApply = "can_apply"
        case updateCommand = "update_command"
    }
}

/// `POST /api/ops/debug-share` — shareable diagnostics upload result.
struct DebugShareResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var urls: [String: String]
    var failures: [String: String]
    var redacted: Bool
    var autoDeleteSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case ok, urls, failures, redacted
        case autoDeleteSeconds = "auto_delete_seconds"
    }
}
