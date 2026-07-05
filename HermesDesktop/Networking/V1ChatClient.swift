import Foundation

/// One message in an OpenAI-style chat request.
struct V1Message: Codable, Sendable, Equatable {
    let role: String
    let content: String
}

/// Events surfaced from a streamed `/v1/chat/completions` response. The Hermes
/// deployment interleaves standard OpenAI `chat.completion.chunk` frames with
/// named `hermes.tool.progress` SSE events.
enum V1StreamEvent: Sendable, Equatable {
    case textDelta(String)
    case toolProgress(tool: String, label: String?, status: String, toolCallID: String?)
    case usage(prompt: Int, completion: Int, total: Int)
    case done
}

struct V1HealthResponse: Codable, Sendable {
    let status: String?
    let platform: String?
    let version: String?
}

/// Client for the OpenAI-compatible `/v1` API at the REST base
/// (`api-hermes.myrakilabs.com`). Auth is `Authorization: Bearer <apiKey>`;
/// `/health` is unauthenticated.
struct V1ChatClient: Sendable {
    /// Inactivity timeout for the streamed response (tool-progress events keep the
    /// stream active between text deltas).
    static let streamTimeout: TimeInterval = 600

    let baseURLProvider: @Sendable () throws -> URL
    let tokenProvider: @Sendable () -> String?
    let session: URLSession

    init(baseURLProvider: @escaping @Sendable () throws -> URL,
         tokenProvider: @escaping @Sendable () -> String?,
         session: URLSession = .shared) {
        self.baseURLProvider = baseURLProvider
        self.tokenProvider = tokenProvider
        self.session = session
    }

    private func url(_ path: String) throws -> URL {
        let base = try baseURLProvider()
        guard let url = URL(string: base.absoluteString + path) else {
            throw HermesAPIError(message: "Invalid URL: \(base.absoluteString + path)")
        }
        return url
    }

    // MARK: - Health / models

    /// `GET /health` (unauthenticated).
    func health() async throws -> V1HealthResponse {
        var request = URLRequest(url: try url("/health"))
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        try Self.throwIfError(response, data: data)
        return try JSONDecoder().decode(V1HealthResponse.self, from: data)
    }

    /// `GET /v1/models` (Bearer). Returns the available model ids.
    func models() async throws -> [String] {
        var request = URLRequest(url: try url("/v1/models"))
        request.timeoutInterval = 15
        applyAuth(&request)
        let (data, response) = try await session.data(for: request)
        try Self.throwIfError(response, data: data)
        struct ModelList: Decodable { struct Entry: Decodable { let id: String }; let data: [Entry] }
        return (try? JSONDecoder().decode(ModelList.self, from: data))?.data.map(\.id) ?? []
    }

    // MARK: - Streaming chat

    /// `POST /v1/chat/completions` with `stream: true`. Yields text deltas, tool
    /// progress, and usage until `[DONE]`. Cancelling the consuming task cancels the
    /// underlying request (used for interrupt).
    func streamChat(model: String, messages: [V1Message]) -> AsyncThrowingStream<V1StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeStreamRequest(model: model, messages: messages)
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw HermesAPIError(message: Self.errorMessage(status: http.statusCode, body: body),
                                             statusCode: http.statusCode)
                    }

                    // NOTE: `bytes.lines` drops blank lines, so the classic
                    // blank-separator SSE framing is invisible here. Each `data:`
                    // line on this server is one complete JSON payload, and an
                    // `event:` line names the type of the NEXT data line — so
                    // dispatch per data line.
                    var eventType: String?
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.hasPrefix(":") { continue } // SSE comment
                        if line.hasPrefix("event:") {
                            eventType = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let chunk = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                            Self.dispatch(eventType: eventType, data: chunk, to: continuation)
                            eventType = nil
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    private func makeStreamRequest(model: String, messages: [V1Message]) throws -> URLRequest {
        var request = URLRequest(url: try url("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.streamTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyAuth(&request)
        struct Body: Encodable { let model: String; let messages: [V1Message]; let stream: Bool }
        request.httpBody = try JSONEncoder().encode(Body(model: model, messages: messages, stream: true))
        return request
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let token = tokenProvider(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - SSE dispatch

    private struct ChatCompletionChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        struct Usage: Decodable { let prompt_tokens: Int?; let completion_tokens: Int?; let total_tokens: Int? }
        let choices: [Choice]
        let usage: Usage?
    }

    private struct ToolProgressPayload: Decodable {
        let tool: String?
        let label: String?
        let status: String?
        let toolCallId: String?
    }

    private static func dispatch(eventType: String?,
                                 data: String,
                                 to continuation: AsyncThrowingStream<V1StreamEvent, Error>.Continuation) {
        guard !data.isEmpty else { return }
        if data == "[DONE]" {
            continuation.yield(.done)
            return
        }
        guard let jsonData = data.data(using: .utf8) else { return }

        if eventType == "hermes.tool.progress" {
            if let payload = try? JSONDecoder().decode(ToolProgressPayload.self, from: jsonData) {
                continuation.yield(.toolProgress(
                    tool: payload.tool ?? "tool",
                    label: payload.label,
                    status: payload.status ?? "running",
                    toolCallID: payload.toolCallId
                ))
            }
            return
        }

        guard let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData) else { return }
        if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
            continuation.yield(.textDelta(delta))
        }
        if let usage = chunk.usage {
            continuation.yield(.usage(prompt: usage.prompt_tokens ?? 0,
                                      completion: usage.completion_tokens ?? 0,
                                      total: usage.total_tokens ?? 0))
        }
    }

    // MARK: - Errors

    private static func throwIfError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            throw HermesAPIError(message: errorMessage(status: http.statusCode,
                                                       body: String(data: data, encoding: .utf8) ?? ""),
                                 statusCode: http.statusCode)
        }
    }

    private static func errorMessage(status: Int, body: String) -> String {
        struct ErrorEnvelope: Decodable { struct Inner: Decodable { let message: String? }; let error: Inner? }
        if let data = body.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message, !message.isEmpty {
            return "\(status): \(message)"
        }
        return "\(status): \(body.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : body)"
    }
}
