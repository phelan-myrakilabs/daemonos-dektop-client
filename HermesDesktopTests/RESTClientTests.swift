import Foundation
import Testing
@testable import HermesDesktop

/// Intercepts requests from the injected ephemeral session. Stubs are keyed by
/// URL path so concurrently running tests never collide as long as each test
/// uses a distinct path.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]

    static func register(path: String, handler: @escaping Handler) {
        lock.lock()
        handlers[path] = handler
        lock.unlock()
    }

    private static func handler(forPath path: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[path]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = Self.handler(forPath: url.path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Thread-safe capture of the requests a stub saw, for header assertions.
final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }
}

struct RESTClientTests {
    private static let baseURL = URL(string: "https://api.test.example")!

    private func makeClient(token: String? = "stub-token") -> HermesRESTClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return HermesRESTClient(
            baseURLProvider: { Self.baseURL },
            tokenProvider: { token },
            session: URLSession(configuration: configuration)
        )
    }

    private func stub(_ path: String,
                      status: Int = 200,
                      body: String = "",
                      contentType: String = "application/json",
                      recorder: RequestRecorder? = nil) {
        StubURLProtocol.register(path: path) { request in
            recorder?.record(request)
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": contentType])!
            return (response, Data(body.utf8))
        }
    }

    // MARK: - Headers

    @Test func sessionTokenHeaderPresenceAndContentType() async throws {
        let recorder = RequestRecorder()
        let path = "/stub/auth-header"
        stub(path, body: #"{"ok":true}"#, recorder: recorder)
        let client = makeClient(token: "stub-token")

        _ = try await client.request(path)
        _ = try await client.request(path, authenticated: false)

        let requests = recorder.requests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "X-Hermes-Session-Token") == "stub-token")
        #expect(requests[1].value(forHTTPHeaderField: "X-Hermes-Session-Token") == nil)
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(requests[1].value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // MARK: - Error and body handling

    @Test func errorStatusSurfacesStatusAndBody() async throws {
        let path = "/stub/server-error"
        stub(path, status: 500, body: "backend exploded")
        let client = makeClient()

        do {
            _ = try await client.request(path)
            Issue.record("expected 500 rejection")
        } catch let error as HermesAPIError {
            #expect(error.message == "500: backend exploded")
            #expect(error.statusCode == 500)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func empty2xxBodyReturnsNil() async throws {
        let path = "/stub/empty-body"
        stub(path, status: 204, body: "")
        let client = makeClient()

        let value = try await client.request(path)
        #expect(value == nil)
    }

    @Test func htmlBodyIsRejectedAsMissingEndpoint() async throws {
        let path = "/stub/html-fallthrough"
        stub(path, body: "<!doctype html><html><body>spa</body></html>", contentType: "text/html")
        let client = makeClient()

        do {
            _ = try await client.request(path)
            Issue.record("expected HTML rejection")
        } catch let error as HermesAPIError {
            #expect(error.message.hasPrefix("Expected JSON from"))
            #expect(error.message.contains("got HTML"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func invalidJSONIsRejected() async throws {
        let path = "/stub/invalid-json"
        stub(path, body: #"{"broken": "#)
        let client = makeClient()

        do {
            _ = try await client.request(path)
            Issue.record("expected invalid-JSON rejection")
        } catch let error as HermesAPIError {
            #expect(error.message.hasPrefix("Invalid JSON from"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    // MARK: - Typed decodes

    @Test func decodesSessionMessagesResponse() async throws {
        let path = "/stub/session-messages"
        let body = """
        {
          "session_id": "abc123",
          "messages": [
            {"id": 1, "role": "user", "content": "hello there", "timestamp": 1751600000.5},
            {"id": 2, "role": "tool", "content": "total 0", "tool_call_id": "call_1", "tool_name": "shell", "timestamp": 1751600001.25}
          ]
        }
        """
        stub(path, body: body)
        let client = makeClient()

        let decoded = try await client.request(path, as: SessionMessagesResponse.self)
        #expect(decoded.sessionID == "abc123")
        #expect(decoded.messages.count == 2)
        #expect(decoded.messages[0].id == 1)
        #expect(decoded.messages[0].role == "user")
        #expect(decoded.messages[0].content?.stringValue == "hello there")
        #expect(decoded.messages[0].timestamp == 1751600000.5)
        #expect(decoded.messages[1].role == "tool")
        #expect(decoded.messages[1].toolCallID == "call_1")
        #expect(decoded.messages[1].toolName == "shell")
        #expect(decoded.messages[1].content?.stringValue == "total 0")
    }

    @Test func decodesPaginatedSessions() async throws {
        let path = "/stub/sessions-page"
        let body = """
        {
          "sessions": [
            {
              "id": "s1",
              "title": "First",
              "archived": false,
              "_lineage_root_id": "root-1",
              "message_count": 4,
              "last_active": 1751600000.5,
              "is_active": true,
              "preview": "hello"
            },
            {
              "id": "s2",
              "archived": true,
              "started_at": 1751500000.25
            }
          ],
          "total": 2,
          "limit": 50,
          "offset": 0,
          "profile_totals": {"default": 2}
        }
        """
        stub(path, body: body)
        let client = makeClient()

        let page = try await client.request(path, as: PaginatedSessions.self)
        #expect(page.total == 2)
        #expect(page.limit == 50)
        #expect(page.offset == 0)
        #expect(page.profileTotals?["default"] == 2)
        #expect(page.sessions.count == 2)
        #expect(page.sessions[0].id == "s1")
        #expect(page.sessions[0].archived == false)
        #expect(page.sessions[0].lineageRootID == "root-1")
        #expect(page.sessions[0].messageCount == 4)
        #expect(page.sessions[0].isActive == true)
        #expect(page.sessions[0].preview == "hello")
        #expect(page.sessions[1].archived == true)
        #expect(page.sessions[1].startedAt == 1751500000.25)
    }
}
