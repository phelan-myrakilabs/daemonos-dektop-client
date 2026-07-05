import Foundation

/// Connection lifecycle states — exact spellings from the reference client
/// (`json-rpc-gateway.ts` `ConnectionState`).
enum GatewayConnectionState: String, Sendable, Equatable {
    case idle
    case connecting
    case open
    case closed
    case error
}

/// A gateway event: JSON-RPC notification with `method:"event"` and
/// `params:{type, session_id?, payload?}`.
struct GatewayEvent: Sendable, Equatable {
    let type: String
    let sessionID: String?
    let payload: JSONValue?
}

/// Known event type strings. The set is open-ended — unknown strings must be tolerated.
enum GatewayEventName {
    static let gatewayReady = "gateway.ready"
    static let sessionInfo = "session.info"
    static let sessionTitle = "session.title"
    static let messageStart = "message.start"
    static let messageDelta = "message.delta"
    static let messageComplete = "message.complete"
    static let thinkingDelta = "thinking.delta"
    static let reasoningDelta = "reasoning.delta"
    static let reasoningAvailable = "reasoning.available"
    static let statusUpdate = "status.update"
    static let toolStart = "tool.start"
    static let toolComplete = "tool.complete"
    static let toolGenerating = "tool.generating"
    static let clarifyRequest = "clarify.request"
    static let approvalRequest = "approval.request"
    static let sudoRequest = "sudo.request"
    static let secretRequest = "secret.request"
    static let backgroundComplete = "background.complete"
    static let error = "error"
    static let skinChanged = "skin.changed"
}

/// Errors thrown by the gateway client. Message strings match the desktop reference
/// (`HermesGateway` option overrides) because higher layers classify errors by
/// regex on the message text.
enum GatewayError: Error, LocalizedError, Equatable {
    /// `request()` while the socket is not open. No offline queueing exists.
    case notConnected
    /// The socket closed with requests in flight, or `close()` was called.
    case connectionClosed
    /// WS connect failed or timed out (15 s).
    case connectFailed
    /// Per-request ack timer fired.
    case requestTimedOut(method: String)
    /// Server error frame. Classification must use `message`, not `code`.
    case rpc(code: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Hermes gateway is not connected"
        case .connectionClosed: return "Hermes gateway connection closed"
        case .connectFailed: return "Could not connect to Hermes gateway"
        case .requestTimedOut(let method): return "request timed out: \(method)"
        case .rpc(_, let message): return message.isEmpty ? "Hermes RPC failed" : message
        }
    }

    /// True when the message indicates a dead transport — triggers the one-shot
    /// reconnect-and-retry at the request-dispatch layer
    /// (reference regex: `/not connected|connection closed/i`).
    static func isTransportDead(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let lowered = message.lowercased()
        return lowered.contains("not connected") || lowered.contains("connection closed")
    }

    /// Reference regex `/session busy/i` — retried every 150 ms for up to 6 s.
    static func isSessionBusy(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return message.lowercased().contains("session busy")
    }

    /// Reference regex `/session not found/i` — resume-and-retry once in prompt submit.
    static func isSessionNotFound(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return message.lowercased().contains("session not found")
    }
}

/// Timeout constants (ms in the reference; seconds here).
enum GatewayTimeouts {
    /// `DEFAULT_CONNECT_TIMEOUT_MS = 15_000`
    static let connect: TimeInterval = 15
    /// Desktop `DEFAULT_GATEWAY_REQUEST_TIMEOUT_MS = 30_000`
    static let request: TimeInterval = 30
    /// `PROMPT_SUBMIT_REQUEST_TIMEOUT_MS = 1_800_000` (30 min) — the ack is
    /// fire-and-forget; completion arrives via streamed events.
    static let promptSubmit: TimeInterval = 1_800
    /// `SESSION_BUSY_RETRY_INTERVAL_MS = 150`
    static let sessionBusyRetryInterval: TimeInterval = 0.150
    /// `SESSION_BUSY_RETRY_TIMEOUT_MS = 6_000`
    static let sessionBusyRetryWindow: TimeInterval = 6
}
