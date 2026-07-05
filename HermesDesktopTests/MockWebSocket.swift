import Foundation
@testable import HermesDesktop

struct MockSocketError: Error, Equatable {
    let message: String
}

/// Scripted stand-in for `URLSessionWebSocketConnection`. Inbound frames are
/// injected by yielding into the events continuation; outbound frames are
/// recorded thread-safely for inspection.
final class MockWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    /// What the socket does as soon as the client starts listening.
    enum Behavior: Sendable {
        case openImmediately
        case neverOpen
        case openThenClose(code: Int?, reason: String?)
        case failImmediately
    }

    let events: AsyncStream<WebSocketTransportEvent>
    private let continuation: AsyncStream<WebSocketTransportEvent>.Continuation

    private let lock = NSLock()
    private var _sentTexts: [String] = []
    private var _cancelled = false
    private var _sendError: Error?

    init(behavior: Behavior = .openImmediately) {
        var streamContinuation: AsyncStream<WebSocketTransportEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { streamContinuation = $0 }
        continuation = streamContinuation

        switch behavior {
        case .openImmediately:
            continuation.yield(.opened)
        case .neverOpen:
            break
        case .openThenClose(let code, let reason):
            continuation.yield(.opened)
            continuation.yield(.closed(code: code, reason: reason))
            continuation.finish()
        case .failImmediately:
            continuation.yield(.failed(MockSocketError(message: "mock socket failure")))
            continuation.finish()
        }
    }

    // MARK: WebSocketConnection

    func send(text: String) async throws {
        let error = withLock { _sendError }
        if let error { throw error }
        withLock { _sentTexts.append(text) }
    }

    func cancel() {
        withLock { _cancelled = true }
        continuation.finish()
    }

    // MARK: Scripting (server side of the wire)

    func open() {
        continuation.yield(.opened)
    }

    func receive(_ text: String) {
        continuation.yield(.text(text))
    }

    func close(code: Int? = nil, reason: String? = nil) {
        continuation.yield(.closed(code: code, reason: reason))
        continuation.finish()
    }

    func fail(_ error: Error = MockSocketError(message: "mock socket failure")) {
        continuation.yield(.failed(error))
        continuation.finish()
    }

    func setSendError(_ error: Error?) {
        withLock { _sendError = error }
    }

    // MARK: Inspection

    var sentTexts: [String] {
        withLock { _sentTexts }
    }

    var isCancelled: Bool {
        withLock { _cancelled }
    }

    /// Polls (10 ms interval) until at least `count` frames were sent.
    /// Returns false on deadline so the caller's `#expect` fails visibly
    /// instead of hanging the test.
    func waitForSentCount(_ count: Int, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if sentTexts.count >= count { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return sentTexts.count >= count
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Hands out scripted connections in FIFO order; falls back to a fresh
/// connection with `fallbackBehavior` when the queue is empty.
final class MockWebSocketConnector: WebSocketConnector, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [MockWebSocketConnection]
    private let fallbackBehavior: MockWebSocketConnection.Behavior
    private var _openedURLs: [URL] = []
    private var _connections: [MockWebSocketConnection] = []

    init(behavior: MockWebSocketConnection.Behavior = .openImmediately) {
        queued = []
        fallbackBehavior = behavior
    }

    init(connections: [MockWebSocketConnection]) {
        queued = connections
        fallbackBehavior = .openImmediately
    }

    func enqueue(_ connection: MockWebSocketConnection) {
        lock.lock()
        queued.append(connection)
        lock.unlock()
    }

    func open(url: URL) -> any WebSocketConnection {
        lock.lock()
        defer { lock.unlock() }
        _openedURLs.append(url)
        let connection = queued.isEmpty
            ? MockWebSocketConnection(behavior: fallbackBehavior)
            : queued.removeFirst()
        _connections.append(connection)
        return connection
    }

    var openedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _openedURLs
    }

    var connections: [MockWebSocketConnection] {
        lock.lock()
        defer { lock.unlock() }
        return _connections
    }

    var lastConnection: MockWebSocketConnection? {
        connections.last
    }
}

/// Builders for server → client frames, matching the reference wire shapes
/// (`_ok` / `_err` in `tui_gateway/server.py`, event notifications, and the
/// connect-time `gateway.ready` frame).
enum ServerFrame {
    static func response(id: Int, result: JSONValue = .object([:])) -> String {
        encode(.object([
            "jsonrpc": "2.0",
            "id": .int(id),
            "result": result,
        ]))
    }

    static func errorResponse(id: Int, code: Int, message: String) -> String {
        encode(.object([
            "jsonrpc": "2.0",
            "id": .int(id),
            "error": .object(["code": .int(code), "message": .string(message)]),
        ]))
    }

    static func event(type: String, sessionID: String? = nil, payload: JSONValue? = nil) -> String {
        var params: [String: JSONValue] = ["type": .string(type)]
        if let sessionID { params["session_id"] = .string(sessionID) }
        if let payload { params["payload"] = payload }
        return encode(.object([
            "jsonrpc": "2.0",
            "method": "event",
            "params": .object(params),
        ]))
    }

    static func gatewayReady(skin: JSONValue = .object([:])) -> String {
        event(type: GatewayEventName.gatewayReady, payload: .object(["skin": skin]))
    }

    /// The server's reply to an unparseable inbound message — must be invisible
    /// to the client (`id: null`, no `method`).
    static let parseError = #"{"jsonrpc":"2.0","error":{"code":-32700,"message":"parse error"},"id":null}"#

    private static func encode(_ value: JSONValue) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Collects every element of an AsyncStream on a background task so tests can
/// poll deterministically instead of blocking on an iterator that might never
/// yield again.
final class StreamCollector<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []
    private var task: Task<Void, Never>? = nil

    init(_ stream: AsyncStream<Element>) {
        task = Task { [weak self] in
            for await element in stream {
                self?.append(element)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    var values: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Polls (10 ms interval) until at least `count` elements arrived.
    func waitForCount(_ count: Int, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if values.count >= count { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return values.count >= count
    }

    private func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }
}
