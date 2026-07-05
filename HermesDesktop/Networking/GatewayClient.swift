import Foundation

/// JSON-RPC 2.0 client over a WebSocket, reimplementing the reference
/// `JsonRpcGatewayClient` + desktop `HermesGateway` semantics:
///
/// - exactly one JSON object per WS text message, both directions
/// - plain integer request ids starting at 1 (desktop `createRequestId` override)
/// - demux: id-bearing frames resolve pending calls (unknown ids dropped silently);
///   `method == "event"` with a truthy `params.type` fans out as an event; all else dropped
/// - errors carry the server's `error.message` verbatim (classification is by message text)
/// - no offline send queue: requests while not open fail fast
/// - connect timeout 15 s drops the half-open socket so the next connect starts clean
/// - socket close rejects every pending call with the closed-connection message
actor GatewayClient {
    private let connector: any WebSocketConnector
    private let defaultRequestTimeout: TimeInterval

    private var socket: (any WebSocketConnection)?
    private var socketGeneration = 0
    private var readTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var connectWaiters: [CheckedContinuation<Void, Error>] = []

    private(set) var state: GatewayConnectionState = .idle

    private var nextID = 0
    private var pending: [Int: PendingCall] = [:]

    private var eventContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private var stateContinuations: [UUID: AsyncStream<GatewayConnectionState>.Continuation] = [:]

    private struct PendingCall {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeoutTask: Task<Void, Never>?
    }

    init(connector: any WebSocketConnector = URLSessionWebSocketConnector(),
         defaultRequestTimeout: TimeInterval = GatewayTimeouts.request) {
        self.connector = connector
        self.defaultRequestTimeout = defaultRequestTimeout
    }

    // MARK: - Connection lifecycle

    /// Opens the socket. No-op if already open; joins the in-flight attempt if connecting.
    /// Resolves when the WS `open` event fires; rejects on error or after the 15 s
    /// connect timeout. The client instance is reusable across connects (the id
    /// counter and subscriptions persist).
    func connect(url: URL, timeout: TimeInterval = GatewayTimeouts.connect) async throws {
        if state == .open, socket != nil { return }
        if state == .connecting {
            try await withCheckedThrowingContinuation { continuation in
                connectWaiters.append(continuation)
            }
            return
        }

        socketGeneration += 1
        let generation = socketGeneration
        setState(.connecting)
        let connection = connector.open(url: url)
        socket = connection

        readTask?.cancel()
        readTask = Task { [weak self] in
            for await event in connection.events {
                guard let self else { return }
                await self.handleSocketEvent(event, generation: generation)
            }
        }

        if timeout > 0 {
            connectTimeoutTask?.cancel()
            connectTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.handleConnectTimeout(generation: generation)
            }
        }

        try await withCheckedThrowingContinuation { continuation in
            connectWaiters.append(continuation)
        }
    }

    /// Closes the socket and rejects all pending calls with the closed message.
    func close() {
        guard socket != nil else { return }
        socketGeneration += 1
        connectTimeoutTask?.cancel()
        socket?.cancel()
        socket = nil
        setState(.closed)
        rejectAllPending(with: GatewayError.connectionClosed)
        resumeConnectWaiters(throwing: GatewayError.connectFailed)
    }

    private func handleSocketEvent(_ event: WebSocketTransportEvent, generation: Int) {
        // Stale-socket guard: ignore events from a superseded socket.
        guard generation == socketGeneration else { return }
        switch event {
        case .opened:
            connectTimeoutTask?.cancel()
            setState(.open)
            resumeConnectWaiters(throwing: nil)
        case .text(let text):
            handleInbound(text)
        case .closed:
            // Invalidate the URLSession (which strongly retains its delegate) — a bare
            // `socket = nil` would leak the session + connection on every server close.
            socket?.cancel()
            socket = nil
            connectTimeoutTask?.cancel()
            let wasConnecting = state == .connecting
            setState(.closed)
            rejectAllPending(with: GatewayError.connectionClosed)
            resumeConnectWaiters(throwing: wasConnecting ? GatewayError.connectFailed : nil)
        case .failed:
            socket?.cancel()
            socket = nil
            connectTimeoutTask?.cancel()
            let wasConnecting = state == .connecting
            setState(wasConnecting ? .error : .closed)
            rejectAllPending(with: GatewayError.connectionClosed)
            resumeConnectWaiters(throwing: wasConnecting ? GatewayError.connectFailed : nil)
        }
    }

    private func handleConnectTimeout(generation: Int) {
        guard generation == socketGeneration, state == .connecting else { return }
        // Drop the half-open socket so the next connect() starts clean.
        socketGeneration += 1
        socket?.cancel()
        socket = nil
        setState(.error)
        resumeConnectWaiters(throwing: GatewayError.connectFailed)
    }

    private func resumeConnectWaiters(throwing error: Error?) {
        let waiters = connectWaiters
        connectWaiters = []
        for waiter in waiters {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume()
            }
        }
    }

    // MARK: - Requests

    /// Sends a JSON-RPC request and awaits the correlated response.
    /// `timeout <= 0` disables the ack timer (reference semantics).
    func call(_ method: String,
              params: [String: JSONValue] = [:],
              timeout: TimeInterval? = nil) async throws -> JSONValue {
        guard state == .open, let socket else {
            throw GatewayError.notConnected
        }

        nextID += 1
        let id = nextID
        let effectiveTimeout = timeout ?? defaultRequestTimeout

        let frame = OutboundFrame(id: id, method: method, params: .object(params))
        let data: Data
        do {
            data = try JSONEncoder().encode(frame)
        } catch {
            throw error
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayError.rpc(code: nil, message: "Hermes RPC failed")
        }

        return try await withCheckedThrowingContinuation { continuation in
            var timeoutTask: Task<Void, Never>?
            if effectiveTimeout > 0 {
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await self?.timeOutRequest(id: id, method: method)
                }
            }
            pending[id] = PendingCall(continuation: continuation, timeoutTask: timeoutTask)

            Task {
                do {
                    try await socket.send(text: text)
                } catch {
                    self.failRequest(id: id, error: error)
                }
            }
        }
    }

    private func timeOutRequest(id: Int, method: String) {
        guard let call = pending.removeValue(forKey: id) else { return }
        call.continuation.resume(throwing: GatewayError.requestTimedOut(method: method))
    }

    private func failRequest(id: Int, error: Error) {
        guard let call = pending.removeValue(forKey: id) else { return }
        call.timeoutTask?.cancel()
        call.continuation.resume(throwing: error)
    }

    private func rejectAllPending(with error: Error) {
        let calls = pending
        pending = [:]
        for call in calls.values {
            call.timeoutTask?.cancel()
            call.continuation.resume(throwing: error)
        }
    }

    // MARK: - Inbound demux

    private struct OutboundFrame: Encodable {
        var jsonrpc = "2.0"
        let id: Int
        let method: String
        let params: JSONValue
    }

    private struct InboundFrame: Decodable {
        let id: JSONValue?
        let method: String?
        let params: InboundParams?
        let result: JSONValue?
        let error: InboundError?
    }

    private struct InboundParams: Decodable {
        let type: String?
        let session_id: String?
        let payload: JSONValue?
    }

    private struct InboundError: Decodable {
        let code: Int?
        let message: String?
    }

    private func handleInbound(_ text: String) {
        // Parse failures are dropped silently (reference behavior).
        guard let data = text.data(using: .utf8),
              let frame = try? JSONDecoder().decode(InboundFrame.self, from: data) else { return }

        // Branch 1: id-bearing frame → response. A frame with an id is never an event.
        if let idValue = frame.id, !idValue.isNull {
            guard let id = idValue.intValue, let call = pending.removeValue(forKey: id) else {
                return // late/unknown id — drop silently
            }
            call.timeoutTask?.cancel()
            if let error = frame.error {
                let message = error.message ?? ""
                call.continuation.resume(throwing: GatewayError.rpc(
                    code: error.code,
                    message: message.isEmpty ? "Hermes RPC failed" : message
                ))
            } else {
                call.continuation.resume(returning: frame.result ?? .null)
            }
            return
        }

        // Branch 2: event notification.
        if frame.method == "event", let type = frame.params?.type, !type.isEmpty {
            let event = GatewayEvent(type: type,
                                     sessionID: frame.params?.session_id,
                                     payload: frame.params?.payload)
            for continuation in eventContinuations.values {
                continuation.yield(event)
            }
            return
        }

        // Branch 3: anything else (including the server's id:null parse-error reply) is dropped.
    }

    // MARK: - Subscriptions

    /// A stream of all gateway events, in wire order. Each caller gets its own stream;
    /// filtering by type/session is the consumer's concern (matches the reference,
    /// where the server pushes everything and filtering is client-side).
    func events() -> AsyncStream<GatewayEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventContinuation(id) }
            }
        }
    }

    /// A stream of connection states. Immediately yields the current state on
    /// subscription (reference `onState` semantics), then on every change.
    func states() -> AsyncStream<GatewayConnectionState> {
        let id = UUID()
        let current = state
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(current)
            stateContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStateContinuation(id) }
            }
        }
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private func removeStateContinuation(_ id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }

    private func setState(_ newState: GatewayConnectionState) {
        guard newState != state else { return }
        state = newState
        for continuation in stateContinuations.values {
            continuation.yield(newState)
        }
    }
}
