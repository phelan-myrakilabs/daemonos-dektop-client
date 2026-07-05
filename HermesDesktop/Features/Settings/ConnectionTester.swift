import Foundation
import Observation

private let statusProbeTimeout: TimeInterval = 8
private let wsOpenTimeout: TimeInterval = 10
private let wsGraceWindow: TimeInterval = 0.75

/// Two-stage connection test mirroring the reference `testConnectionConfig`:
/// (1) credential-free `GET /api/status` against the draft REST base, then
/// (2) a raw WebSocket probe of the draft WS URL. HTTP-only success is a
/// documented false positive, so the overall result is only "ok" when the WS
/// stage passed or was explicitly skipped (token mode with no token —
/// `resolveTestWsUrl` returns null: nothing to authenticate with).
@MainActor
@Observable
final class ConnectionTester {
    enum Phase: Equatable {
        case idle
        case running
        case success(version: String?)
        case failure(String)
    }

    private(set) var phase: Phase = .idle
    /// Per-stage summary on success, e.g. "REST ok (v1.2.3) · WebSocket ok".
    private(set) var detail: String?

    private let connector: any WebSocketConnector

    init(connector: any WebSocketConnector = URLSessionWebSocketConnector()) {
        self.connector = connector
    }

    func reset() {
        guard phase != .running else { return }
        phase = .idle
        detail = nil
    }

    func run(settings: ConnectionSettings, draftToken: String, storedToken: String?) async {
        guard phase != .running else { return }
        phase = .running
        detail = nil

        // Stage 1 — REST: credential-free status probe against the draft base URL.
        let restBase: URL
        do {
            restBase = try ConnectionSettings.normalizeRESTBaseURL(settings.restBaseURLString)
        } catch {
            phase = .failure("REST failed: \(error.localizedDescription)")
            return
        }

        let rest = HermesRESTClient(baseURLProvider: { restBase }, tokenProvider: { nil })
        let status: StatusResponse
        do {
            status = try await rest.request("/api/status",
                                            timeout: statusProbeTimeout,
                                            authenticated: false,
                                            as: StatusResponse.self)
        } catch {
            phase = .failure("REST failed: \(error.localizedDescription)")
            return
        }

        if status.authRequired == true {
            phase = .failure("The gateway requires OAuth sign-in; this client supports token auth only.")
            return
        }

        let restLabel = Self.restStageLabel(version: status.version)

        // Stage 2 — WS: draft token wins, else the stored token; neither → skip.
        let trimmedDraft = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = trimmedDraft.isEmpty ? (storedToken ?? "") : trimmedDraft
        guard !token.isEmpty else {
            detail = "\(restLabel) · WebSocket skipped (no token to authenticate with)"
            phase = .success(version: status.version)
            return
        }

        let wsURL: URL
        do {
            wsURL = try settings.webSocketURL(token: token)
        } catch {
            phase = .failure("\(restLabel) · WebSocket failed: \(error.localizedDescription)")
            return
        }

        if let failure = await Self.probeWebSocket(url: wsURL, connector: connector) {
            phase = .failure("\(restLabel) · WebSocket failed: \(failure)")
        } else {
            detail = "\(restLabel) · WebSocket ok"
            phase = .success(version: status.version)
        }
    }

    private static func restStageLabel(version: String?) -> String {
        guard let version, !version.isEmpty else { return "REST ok" }
        let display = version.lowercased().hasPrefix("v") ? version : "v\(version)"
        return "REST ok (\(display))"
    }

    /// Probes the real `/api/ws` transport. Success = `.opened` within 10 s and no
    /// close/failure within a 750 ms grace window after open; any inbound frame
    /// inside the window (the server pushes `gateway.ready`) is immediate success.
    /// Returns nil on success, else a failure reason. The URL embeds the token and
    /// must never be logged.
    private nonisolated static func probeWebSocket(url: URL, connector: any WebSocketConnector) async -> String? {
        enum Signal {
            case transport(WebSocketTransportEvent)
            case openDeadline
            case graceDeadline
        }

        let connection = connector.open(url: url)
        let (signals, continuation) = AsyncStream.makeStream(of: Signal.self)

        let pump = Task {
            for await event in connection.events {
                continuation.yield(.transport(event))
            }
            continuation.finish()
        }
        let openTimer = Task {
            try? await Task.sleep(for: .seconds(wsOpenTimeout))
            guard !Task.isCancelled else { return }
            continuation.yield(.openDeadline)
        }
        var graceTimer: Task<Void, Never>?

        defer {
            pump.cancel()
            openTimer.cancel()
            graceTimer?.cancel()
            connection.cancel()
        }

        var opened = false
        for await signal in signals {
            switch signal {
            case .transport(.opened):
                guard !opened else { break }
                opened = true
                openTimer.cancel()
                graceTimer = Task {
                    try? await Task.sleep(for: .seconds(wsGraceWindow))
                    guard !Task.isCancelled else { return }
                    continuation.yield(.graceDeadline)
                }
            case .transport(.text):
                if opened { return nil }
            case .transport(.closed(let code, let reason)):
                if opened {
                    return "credential rejected — the gateway closed the socket right after opening\(closeSuffix(code: code, reason: reason))"
                }
                return "socket closed before the handshake completed\(closeSuffix(code: code, reason: reason))"
            case .transport(.failed(let error)):
                if opened {
                    return "credential rejected (\(error.localizedDescription))"
                }
                return error.localizedDescription
            case .openDeadline:
                if !opened {
                    return "timed out opening the socket after \(Int(wsOpenTimeout))s"
                }
            case .graceDeadline:
                if opened { return nil }
            }
        }
        return "socket closed unexpectedly"
    }

    private nonisolated static func closeSuffix(code: Int?, reason: String?) -> String {
        var parts: [String] = []
        if let code { parts.append("code \(code)") }
        if let reason, !reason.isEmpty { parts.append(reason) }
        return parts.isEmpty ? "" : " (" + parts.joined(separator: ", ") + ")"
    }
}
