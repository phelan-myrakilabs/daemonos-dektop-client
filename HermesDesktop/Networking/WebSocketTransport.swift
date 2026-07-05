import Foundation

/// Low-level socket events surfaced to the gateway client.
enum WebSocketTransportEvent: Sendable {
    case opened
    case text(String)
    case closed(code: Int?, reason: String?)
    case failed(Error)
}

/// One live WebSocket connection. `events` yields lifecycle + inbound text frames
/// in order and finishes when the socket dies.
protocol WebSocketConnection: Sendable {
    var events: AsyncStream<WebSocketTransportEvent> { get }
    func send(text: String) async throws
    func cancel()
}

/// Creates connections — injectable so tests can substitute a mock socket.
protocol WebSocketConnector: Sendable {
    func open(url: URL) -> any WebSocketConnection
}

// MARK: - URLSession implementation

struct URLSessionWebSocketConnector: WebSocketConnector {
    func open(url: URL) -> any WebSocketConnection {
        URLSessionWebSocketConnection(url: url)
    }
}

/// Wraps `URLSessionWebSocketTask`. The delegate provides open/close signals;
/// a receive pump yields inbound text frames.
final class URLSessionWebSocketConnection: NSObject, WebSocketConnection, URLSessionWebSocketDelegate, @unchecked Sendable {
    let events: AsyncStream<WebSocketTransportEvent>
    private let continuation: AsyncStream<WebSocketTransportEvent>.Continuation
    private var session: URLSession!
    private var task: URLSessionWebSocketTask!

    init(url: URL) {
        var streamContinuation: AsyncStream<WebSocketTransportEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { streamContinuation = $0 }
        continuation = streamContinuation
        super.init()

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: url)
        task.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                self.continuation.yield(.text(text))
                self.receiveLoop()
            case .success:
                // The server never sends binary on this channel; drop and continue.
                self.receiveLoop()
            case .failure(let error):
                self.continuation.yield(.failed(error))
                self.continuation.finish()
            }
        }
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func cancel() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
        continuation.finish()
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        continuation.yield(.opened)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
        continuation.yield(.closed(code: closeCode.rawValue, reason: reasonText))
        continuation.finish()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation.yield(.failed(error))
        }
        continuation.finish()
    }
}
