import Foundation

// Star map wire types (`GET /api/learning/graph`).
// NOTE: unlike the rest of the protocol, Starmap wire keys are camelCase
// (`memorySource`, `useCount`, `createdBy`) — do not snake_case these.

/// Origin of a memory node/card: the memory store or the profile soul.
enum StarmapMemorySource: String, Codable, Sendable {
    case memory
    case profile
    case unknown

    init(from decoder: Decoder) throws {
        self = StarmapMemorySource(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// One graph node in the star map (learned skill or memory chunk).
struct StarmapNode: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var kind: Kind
    var memorySource: StarmapMemorySource?
    var timestamp: Double?
    var category: String
    var useCount: Int
    var state: String
    var createdBy: String?
    var pinned: Bool

    enum Kind: String, Codable, Sendable {
        case memory
        case skill
        case unknown

        init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, label, kind, memorySource, timestamp, category, useCount, state, createdBy, pinned
    }
}

/// A declared `related_skills` link; both endpoints are guaranteed to be nodes.
struct StarmapEdge: Codable, Equatable, Sendable {
    var source: String
    var target: String

    enum CodingKeys: String, CodingKey {
        case source, target
    }
}

struct StarmapCluster: Codable, Equatable, Sendable {
    var category: String
    var count: Int

    enum CodingKeys: String, CodingKey {
        case category, count
    }
}

/// Freeform memory rendered as a card — never a graph node.
struct StarmapMemoryCard: Codable, Equatable, Sendable {
    var source: StarmapMemorySource
    var timestamp: Double?
    var title: String
    var body: String

    enum CodingKeys: String, CodingKey {
        case source, timestamp, title, body
    }
}

/// `GET /api/learning/graph` (path is legacy-named `/api/learning`).
struct StarmapGraph: Codable, Equatable, Sendable {
    var nodes: [StarmapNode]
    var edges: [StarmapEdge]
    var clusters: [StarmapCluster]
    var memory: [StarmapMemoryCard]
    var stats: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case nodes, edges, clusters, memory, stats
    }
}

/// `GET /api/learning/node?id=` — node body for the detail panel.
/// (Documented in the REST spec's endpoint catalog, not in the TS type file.)
struct LearningNodeDetail: Codable, Equatable, Sendable {
    var content: String
    var kind: StarmapNode.Kind
    var label: String
    var ok: Bool

    enum CodingKeys: String, CodingKey {
        case content, kind, label, ok
    }
}
