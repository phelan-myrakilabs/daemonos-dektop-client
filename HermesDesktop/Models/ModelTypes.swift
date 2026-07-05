import Foundation

// Model / provider assignment wire types (`/api/model/…`).

/// `GET /api/model/info`. On internal failure the backend returns the empty
/// shape (`""` / `0` / `{}`) with HTTP 200, not an error.
struct ModelInfoResponse: Codable, Equatable, Sendable {
    var autoContextLength: Int?
    var capabilities: [String: JSONValue]?
    var configContextLength: Int?
    var effectiveContextLength: Int?
    var model: String
    var provider: String

    enum CodingKeys: String, CodingKey {
        case model, provider, capabilities
        case autoContextLength = "auto_context_length"
        case configContextLength = "config_context_length"
        case effectiveContextLength = "effective_context_length"
    }
}

/// Pre-formatted $/Mtok display strings (e.g. `"$3.00"`, `"free"`, `""`), not numbers.
struct ModelPricing: Codable, Equatable, Sendable {
    var input: String
    var output: String
    /// Cached-input price, or nil when the model has none.
    var cache: String?
    /// True when the model costs nothing (free tier eligible).
    var free: Bool

    enum CodingKeys: String, CodingKey {
        case input, output, cache, free
    }
}

struct ModelCapabilities: Codable, Equatable, Sendable {
    var fast: Bool
    var reasoning: Bool

    enum CodingKeys: String, CodingKey {
        case fast, reasoning
    }
}

/// One provider row from `GET /api/model/options`.
struct ModelOptionProvider: Codable, Equatable, Sendable {
    var isCurrent: Bool?
    var models: [String]?
    var name: String
    var slug: String
    var totalModels: Int?
    var warning: String?
    /// False for canonical providers surfaced by `include_unconfigured` that the
    /// user hasn't set up yet — render with a setup affordance instead of hiding.
    var authenticated: Bool?
    /// `"api_key"` can be activated inline by pasting `keyEnv`; anything else
    /// (`oauth_*`, `external`, `aws_sdk`, …) needs the CLI / onboarding OAuth flow.
    var authType: String?
    /// Env var to paste an API key into, for unconfigured `api_key` providers.
    var keyEnv: String?
    /// True for providers defined via the user's `providers:` config block.
    var isUserDefined: Bool?
    /// Per-model pricing keyed by model id.
    var pricing: [String: ModelPricing]?
    /// Nous only: whether the current account is on the free tier.
    var freeTier: Bool?
    /// Nous only: paid models a free-tier user cannot select (shown disabled).
    var unavailableModels: [String]?
    /// Per-model option support keyed by model id; gates fast/reasoning controls.
    var capabilities: [String: ModelCapabilities]?

    enum CodingKeys: String, CodingKey {
        case models, name, slug, warning, authenticated, pricing, capabilities
        case isCurrent = "is_current"
        case totalModels = "total_models"
        case authType = "auth_type"
        case keyEnv = "key_env"
        case isUserDefined = "is_user_defined"
        case freeTier = "free_tier"
        case unavailableModels = "unavailable_models"
    }
}

/// `GET /api/model/options` envelope.
struct ModelOptionsResponse: Codable, Equatable, Sendable {
    var model: String?
    var provider: String?
    var providers: [ModelOptionProvider]?

    enum CodingKeys: String, CodingKey {
        case model, provider, providers
    }
}

struct AuxiliaryTaskAssignment: Codable, Equatable, Sendable {
    var baseURL: String
    var model: String
    var provider: String
    var task: String

    enum CodingKeys: String, CodingKey {
        case model, provider, task
        case baseURL = "base_url"
    }
}

/// `GET /api/model/auxiliary`.
struct AuxiliaryModelsResponse: Codable, Equatable, Sendable {
    var main: Main
    var tasks: [AuxiliaryTaskAssignment]

    struct Main: Codable, Equatable, Sendable {
        var model: String
        var provider: String

        enum CodingKeys: String, CodingKey {
            case model, provider
        }
    }

    enum CodingKeys: String, CodingKey {
        case main, tasks
    }
}

struct MoaModelSlot: Codable, Equatable, Sendable {
    var provider: String
    var model: String

    enum CodingKeys: String, CodingKey {
        case provider, model
    }
}

/// One MoA preset body. The same shape repeats at the `MoaConfigResponse` top
/// level as the active/effective config (named struct for the TS inline object).
struct MoaPreset: Codable, Equatable, Sendable {
    var aggregator: MoaModelSlot
    var aggregatorTemperature: Double
    var enabled: Bool
    var maxTokens: Int
    var referenceModels: [MoaModelSlot]
    var referenceTemperature: Double

    enum CodingKeys: String, CodingKey {
        case aggregator, enabled
        case aggregatorTemperature = "aggregator_temperature"
        case maxTokens = "max_tokens"
        case referenceModels = "reference_models"
        case referenceTemperature = "reference_temperature"
    }
}

/// `GET /api/model/moa` (and the `PUT /api/model/moa` body echo).
struct MoaConfigResponse: Codable, Equatable, Sendable {
    var defaultPreset: String
    var activePreset: String
    var presets: [String: MoaPreset]
    var aggregator: MoaModelSlot
    var aggregatorTemperature: Double
    var enabled: Bool
    var maxTokens: Int
    var referenceModels: [MoaModelSlot]
    var referenceTemperature: Double

    enum CodingKeys: String, CodingKey {
        case presets, aggregator, enabled
        case defaultPreset = "default_preset"
        case activePreset = "active_preset"
        case aggregatorTemperature = "aggregator_temperature"
        case maxTokens = "max_tokens"
        case referenceModels = "reference_models"
        case referenceTemperature = "reference_temperature"
    }
}

/// Request body for `POST /api/model/set`. Unset fields are omitted on the wire.
struct ModelAssignmentRequest: Codable, Equatable, Sendable {
    /// Optional API key for a custom/local endpoint. Only honored for
    /// custom/local providers on the main slot.
    var apiKey: String?
    /// OpenAI-compatible endpoint URL. Only honored for custom/local providers
    /// on the main slot.
    var baseURL: String?
    var model: String
    var provider: String
    var scope: Scope
    var task: String?

    enum Scope: String, Codable, Sendable {
        case main
        case auxiliary
    }

    init(model: String, provider: String, scope: Scope, task: String? = nil,
         apiKey: String? = nil, baseURL: String? = nil) {
        self.model = model
        self.provider = provider
        self.scope = scope
        self.task = task
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    enum CodingKeys: String, CodingKey {
        case model, provider, scope, task
        case apiKey = "api_key"
        case baseURL = "base_url"
    }
}

/// An auxiliary task still pinned to a provider that differs from the
/// newly-selected main provider after a main-model switch.
struct StaleAuxAssignment: Codable, Equatable, Sendable {
    var task: String
    var provider: String
    var model: String

    enum CodingKeys: String, CodingKey {
        case task, provider, model
    }
}

/// `POST /api/model/set` response.
struct ModelAssignmentResponse: Codable, Equatable, Sendable {
    /// Persisted endpoint URL for custom/local providers (echoed back).
    var baseURL: String?
    /// Toolset keys auto-routed through the Nous Tool Gateway when switching
    /// the main provider to Nous.
    var gatewayTools: [String]?
    var model: String?
    var ok: Bool
    var provider: String?
    var reset: Bool?
    var scope: String?
    /// Auxiliary slots still pinned to a different provider than the new main.
    /// Only set on scope "main".
    var staleAux: [StaleAuxAssignment]?
    var tasks: [String]?

    enum CodingKeys: String, CodingKey {
        case model, ok, provider, reset, scope, tasks
        case baseURL = "base_url"
        case gatewayTools = "gateway_tools"
        case staleAux = "stale_aux"
    }
}
