import Foundation

// MCP server wire types (`/api/mcp/…`).

/// One configured MCP server row from `GET /api/mcp/servers`.
struct McpServerSummary: Codable, Equatable, Sendable {
    var name: String
    var transport: String
    var command: String?
    var args: [String]
    var url: String?
    var enabled: Bool
    /// Tool names, or nil when unknown (unlike `McpServerTestResponse.tools`,
    /// which is an always-present array of `{name, description}` objects).
    var tools: [String]?

    enum CodingKeys: String, CodingKey {
        case name, transport, command, args, url, enabled, tools
    }
}

/// `GET /api/mcp/servers` envelope (documented in the REST spec's endpoint
/// catalog, not in the TS type file).
struct McpServersResponse: Codable, Equatable, Sendable {
    var servers: [McpServerSummary]

    enum CodingKeys: String, CodingKey {
        case servers
    }
}

/// `POST /api/mcp/servers/{name}/test`.
struct McpServerTestResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var error: String?
    var tools: [Tool]

    struct Tool: Codable, Equatable, Sendable {
        var name: String
        var description: String

        enum CodingKeys: String, CodingKey {
            case name, description
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok, error, tools
    }
}

/// One Nous-approved MCP catalog entry from `GET /api/mcp/catalog`.
struct McpCatalogEntry: Codable, Equatable, Sendable {
    var name: String
    var description: String
    var source: String
    var transport: String
    var authType: String
    var requiredEnv: [RequiredEnv]
    var command: String?
    var args: [String]
    var url: String?
    var installURL: String?
    var installRef: String?
    var bootstrap: [String]
    var defaultEnabled: [String]?
    var postInstall: String
    var needsInstall: Bool
    var installed: Bool
    var enabled: Bool

    struct RequiredEnv: Codable, Equatable, Sendable {
        var name: String
        var prompt: String
        var required: Bool

        enum CodingKeys: String, CodingKey {
            case name, prompt, required
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, description, source, transport, command, args, url, bootstrap, installed, enabled
        case authType = "auth_type"
        case requiredEnv = "required_env"
        case installURL = "install_url"
        case installRef = "install_ref"
        case defaultEnabled = "default_enabled"
        case postInstall = "post_install"
        case needsInstall = "needs_install"
    }
}

/// `GET /api/mcp/catalog` envelope.
struct McpCatalogResponse: Codable, Equatable, Sendable {
    var entries: [McpCatalogEntry]
    var diagnostics: [Diagnostic]

    struct Diagnostic: Codable, Equatable, Sendable {
        var name: String
        var kind: String
        var message: String

        enum CodingKeys: String, CodingKey {
            case name, kind, message
        }
    }

    enum CodingKeys: String, CodingKey {
        case entries, diagnostics
    }
}
