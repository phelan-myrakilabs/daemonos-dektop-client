import Foundation

// Toolset and computer-use wire types (`/api/tools/…`).

/// One row of the bare array returned by `GET /api/tools/toolsets`.
struct ToolsetInfo: Codable, Equatable, Sendable {
    var configured: Bool
    var description: String
    var enabled: Bool
    var label: String
    var name: String
    var tools: [String]
    /// Sent by the backend but absent from the desktop TS type (REST spec §7).
    var available: Bool?

    enum CodingKeys: String, CodingKey {
        case configured, description, enabled, label, name, tools, available
    }
}

struct ToolEnvVar: Codable, Equatable, Sendable {
    var key: String
    var prompt: String
    var url: String?
    /// Wire key is literally `"default"`.
    var defaultValue: String?
    var isSet: Bool

    enum CodingKeys: String, CodingKey {
        case key, prompt, url
        case defaultValue = "default"
        case isSet = "is_set"
    }
}

struct ToolProvider: Codable, Equatable, Sendable {
    var name: String
    var badge: String
    var tag: String
    var envVars: [ToolEnvVar]
    var postSetup: String?
    var requiresNousAuth: Bool
    /// True when this is the provider currently written to config (mirrors the
    /// CLI `hermes tools` active-provider detection).
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case name, badge, tag
        case envVars = "env_vars"
        case postSetup = "post_setup"
        case requiresNousAuth = "requires_nous_auth"
        case isActive = "is_active"
    }
}

/// `GET /api/tools/toolsets/{name}/config`.
struct ToolsetConfig: Codable, Equatable, Sendable {
    var name: String
    var hasCategory: Bool
    var providers: [ToolProvider]
    /// Name of the currently active provider, or nil if none is configured.
    var activeProvider: String?

    enum CodingKeys: String, CodingKey {
        case name, providers
        case hasCategory = "has_category"
        case activeProvider = "active_provider"
    }
}

/// One model row from a toolset backend's catalog (image/video gen).
struct ToolsetModel: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var display: String
    var speed: String
    var strengths: String
    var price: String

    enum CodingKeys: String, CodingKey {
        case id, display, speed, strengths, price
    }
}

/// `GET /api/tools/toolsets/{name}/models`.
struct ToolsetModelsResponse: Codable, Equatable, Sendable {
    var name: String
    var hasModels: Bool
    var provider: String?
    var plugin: String?
    var models: [ToolsetModel]
    var current: String?
    /// Wire key is literally `"default"`.
    var defaultModel: String?

    enum CodingKeys: String, CodingKey {
        case name, provider, plugin, models, current
        case hasModels = "has_models"
        case defaultModel = "default"
    }
}

/// Process that holds the macOS TCC grants for computer use.
struct ComputerUsePermissionSource: Codable, Equatable, Sendable {
    var attribution: String?
    var executable: String?
    var note: String?
    var pid: Int?
    var responsiblePPID: Int?

    enum CodingKeys: String, CodingKey {
        case attribution, executable, note, pid
        case responsiblePPID = "responsible_ppid"
    }
}

/// One cross-platform `cua-driver doctor` probe result.
struct ComputerUseCheck: Codable, Equatable, Sendable {
    var label: String
    var status: String
    var message: String

    enum CodingKeys: String, CodingKey {
        case label, status, message
    }
}

/// `GET /api/tools/computer-use/status`. Tri-state booleans (`ready`,
/// `accessibility`, `screen_recording`, `screen_recording_capturable`) use
/// nil for "unknown", distinct from false.
struct ComputerUseStatus: Codable, Equatable, Sendable {
    /// Python `sys.platform`: "darwin" | "win32" | "linux" | …
    var platform: String
    /// cua-driver has a runtime backend for this platform.
    var platformSupported: Bool
    /// cua-driver binary resolved on PATH.
    var installed: Bool
    /// e.g. "cua-driver 0.5.1", or nil when unknown.
    var version: String?
    /// Unified readiness — both TCC grants (macOS) or driver health (else).
    var ready: Bool?
    /// Whether a permission grant flow exists (macOS-only TCC).
    var canGrant: Bool
    var checks: [ComputerUseCheck]
    var accessibility: Bool?
    var screenRecording: Bool?
    var screenRecordingCapturable: Bool?
    var source: ComputerUsePermissionSource?
    /// Populated when the status probe itself failed.
    var error: String?

    enum CodingKeys: String, CodingKey {
        case platform, installed, version, ready, checks, accessibility, source, error
        case platformSupported = "platform_supported"
        case canGrant = "can_grant"
        case screenRecording = "screen_recording"
        case screenRecordingCapturable = "screen_recording_capturable"
    }
}
