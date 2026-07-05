import Foundation

// Env-var (Keys page) and audio wire types.

/// One entry of the `GET /api/env` map, keyed by env-var name.
struct EnvVarInfo: Codable, Equatable, Sendable {
    var advanced: Bool
    var category: String
    /// True when this var is a messaging-platform credential owned by a card on
    /// the dedicated Messaging page (the Keys page hides these).
    var channelManaged: Bool?
    var description: String
    var isPassword: Bool
    var isSet: Bool
    /// Backend-derived provider grouping hints from the unified provider
    /// catalog — the same identity `hermes model` uses. Empty for
    /// non-provider env vars.
    var provider: String?
    var providerLabel: String?
    var redactedValue: String?
    var tools: [String]
    var url: String?

    enum CodingKeys: String, CodingKey {
        case advanced, category, description, provider, tools, url
        case channelManaged = "channel_managed"
        case isPassword = "is_password"
        case isSet = "is_set"
        case providerLabel = "provider_label"
        case redactedValue = "redacted_value"
    }
}

/// `POST /api/audio/transcribe`.
struct AudioTranscriptionResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var provider: String?
    var transcript: String

    enum CodingKeys: String, CodingKey {
        case ok, provider, transcript
    }
}

/// `POST /api/audio/speak`. `dataURL` is a `data:` URL containing the
/// synthesized audio; `mimeType` its MIME type.
struct AudioSpeakResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var dataURL: String
    var mimeType: String
    var provider: String?

    enum CodingKeys: String, CodingKey {
        case ok, provider
        case dataURL = "data_url"
        case mimeType = "mime_type"
    }
}

struct ElevenLabsVoice: Codable, Equatable, Sendable {
    var label: String
    var name: String
    var voiceID: String

    enum CodingKeys: String, CodingKey {
        case label, name
        case voiceID = "voice_id"
    }
}

/// `GET /api/audio/elevenlabs/voices`.
struct ElevenLabsVoicesResponse: Codable, Equatable, Sendable {
    var available: Bool
    var voices: [ElevenLabsVoice]

    enum CodingKeys: String, CodingKey {
        case available, voices
    }
}
