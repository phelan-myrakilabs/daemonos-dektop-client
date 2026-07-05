import Foundation

// Config domain wire types. Snake_case keys via explicit CodingKeys.

/// One entry of the backend's `CONFIG_SCHEMA` (`GET /api/config/schema`).
struct ConfigFieldSchema: Codable, Equatable, Sendable {
    var category: String?
    var description: String?
    /// Arbitrary option values, used with `type == .select`.
    var options: [JSONValue]?
    var type: FieldType?

    enum FieldType: String, Codable, Sendable {
        case boolean
        case list
        case number
        case select
        case string
        case text
        /// Fallback so an unrecognized future field type cannot fail the whole schema decode.
        case unknown

        init(from decoder: Decoder) throws {
            self = FieldType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case category, description, options, type
    }
}

/// `GET /api/config/schema` → `{ fields: CONFIG_SCHEMA, category_order: _CATEGORY_ORDER }`.
struct ConfigSchemaResponse: Codable, Equatable, Sendable {
    var categoryOrder: [String]?
    var fields: [String: ConfigFieldSchema]

    enum CodingKeys: String, CodingKey {
        case fields
        case categoryOrder = "category_order"
    }
}

/// Typed subset of the profile config record returned by `GET /api/config`.
/// Every level is optional; the full record is `HermesConfigRecord`.
struct HermesConfig: Codable, Equatable, Sendable {
    var agent: Agent?
    var display: Display?
    var terminal: Terminal?
    var stt: Stt?
    var voice: Voice?

    struct Agent: Codable, Equatable, Sendable {
        var reasoningEffort: String?
        var personalities: [String: JSONValue]?
        var serviceTier: String?

        enum CodingKeys: String, CodingKey {
            case personalities
            case reasoningEffort = "reasoning_effort"
            case serviceTier = "service_tier"
        }
    }

    struct Display: Codable, Equatable, Sendable {
        var personality: String?
        var skin: String?

        enum CodingKeys: String, CodingKey {
            case personality, skin
        }
    }

    struct Terminal: Codable, Equatable, Sendable {
        var cwd: String?

        enum CodingKeys: String, CodingKey {
            case cwd
        }
    }

    struct Stt: Codable, Equatable, Sendable {
        var enabled: Bool?

        enum CodingKeys: String, CodingKey {
            case enabled
        }
    }

    struct Voice: Codable, Equatable, Sendable {
        var maxRecordingSeconds: Int?
        var autoTTS: Bool?

        enum CodingKeys: String, CodingKey {
            case maxRecordingSeconds = "max_recording_seconds"
            case autoTTS = "auto_tts"
        }
    }

    enum CodingKeys: String, CodingKey {
        case agent, display, terminal, stt, voice
    }
}

/// Fully-dynamic config record (`GET /api/config`, `GET /api/config/defaults`,
/// and the `config` field of the `PUT /api/config` body).
typealias HermesConfigRecord = [String: JSONValue]
