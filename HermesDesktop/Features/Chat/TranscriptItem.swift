import Foundation

// The chat transcript render model. A transcript is a flat, ordered list of
// `TranscriptItem`s; streaming mutates the tail in place (see ChatSessionViewModel).

enum ToolRowState: Equatable, Sendable {
    case running
    case success
    case error
}

struct ToolRowModel: Equatable, Sendable {
    var toolID: String
    var name: String
    /// Human subtitle (the shell command, file path, search query, …). May be empty.
    var context: String
    var state: ToolRowState
    /// Expandable body text (tool result / result_text / summary).
    var detail: String?
    /// Rendered unified-diff text for file-edit tools.
    var inlineDiff: String?
    var durationSeconds: Double?
    var summary: String?

    var hasExpandableContent: Bool {
        (detail?.isEmpty == false) || (inlineDiff?.isEmpty == false)
    }
}

struct ThinkingGroupModel: Equatable, Sendable {
    var text: String
    var streaming: Bool
}

enum TranscriptItemKind: Equatable, Sendable {
    case user(text: String)
    case assistant(text: String, streaming: Bool)
    case tool(ToolRowModel)
    case thinking(ThinkingGroupModel)
    /// Centered meta note (system messages, transient hydrated notes).
    case status(text: String)
    case error(message: String)
}

struct TranscriptItem: Identifiable, Equatable, Sendable {
    let id: String
    var kind: TranscriptItemKind
}

// MARK: - Gateway text coercion

/// Mirrors the reference `coerceGatewayText`: string / array of strings-or-
/// `{text|output_text}` parts / object with `text`/`output_text` / anything else
/// JSON-stringified.
enum GatewayTextCoercion {
    static func coerce(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .null:
            return ""
        case .string(let text):
            return text
        case .array(let parts):
            return parts.map { part -> String in
                if let text = part.stringValue { return text }
                if let text = part["text"]?.stringValue { return text }
                if let text = part["output_text"]?.stringValue { return text }
                return jsonString(part)
            }.joined()
        case .object:
            if let text = value["text"]?.stringValue { return text }
            if let text = value["output_text"]?.stringValue { return text }
            return jsonString(value)
        case .bool, .int, .double:
            return jsonString(value)
        }
    }

    static func jsonString(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Hydration (stored transcript → render items)

/// Maps hydrated transcripts to render items following rpc-methods.md Part C:
/// rows are either text messages `{role, text/content, reasoning passthrough}` or
/// tool rows `{role: "tool", name, context}`.
enum TranscriptHydration {

    /// Hydrates from REST `GET /api/sessions/{id}/messages` rows.
    static func items(from messages: [SessionMessage]) -> [TranscriptItem] {
        var result: [TranscriptItem] = []
        // Assistant tool_calls remembered so later `role:"tool"` rows resolve name/args.
        var toolCallsByID: [String: (name: String, args: JSONValue?)] = [:]
        var lastToolNames: [String] = []

        for (index, message) in messages.enumerated() {
            let baseID = "h-\(index)-\(message.role)"
            switch message.role {
            case "tool":
                var name = message.toolName ?? "tool"
                var args: JSONValue?
                if let callID = message.toolCallID, let match = toolCallsByID[callID] {
                    name = match.name
                    args = match.args
                } else if name == "tool", let fallback = lastToolNames.last {
                    name = fallback
                }
                let flattened = flattenContent(message.content)
                var row = ToolRowModel(toolID: message.toolCallID ?? baseID,
                                       name: name,
                                       context: toolLabel(name: name, args: args),
                                       state: .success)
                let detail = flattened.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !detail.isEmpty { row.detail = detail }
                result.append(TranscriptItem(id: baseID, kind: .tool(row)))

            case "assistant":
                if let calls = message.toolCalls?.arrayValue {
                    for call in calls {
                        guard let callID = call["id"]?.stringValue
                                ?? call["tool_call_id"]?.stringValue else { continue }
                        let name = call["function"]?["name"]?.stringValue
                            ?? call["name"]?.stringValue ?? "tool"
                        let args = decodeArguments(call["function"]?["arguments"] ?? call["arguments"])
                        toolCallsByID[callID] = (name, args)
                        lastToolNames.append(name)
                    }
                }
                let flattened = flattenContent(message.content)
                let text = flattened.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let reasoning = reasoningText(of: message)
                if let reasoning, !reasoning.isEmpty {
                    result.append(TranscriptItem(
                        id: baseID + "-thinking",
                        kind: .thinking(ThinkingGroupModel(text: reasoning, streaming: false))
                    ))
                }
                // Assistant tool-call stubs with blank text are dropped (the tool rows
                // represent them); thinking-only turns were kept above.
                if !text.isEmpty {
                    result.append(TranscriptItem(id: baseID, kind: .assistant(text: text, streaming: false)))
                }
                appendImageNotes(flattened, baseID: baseID, into: &result)

            case "user":
                let flattened = flattenContent(message.content)
                let text = flattened.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty || !flattened.imageURLs.isEmpty else { continue }
                if !text.isEmpty {
                    result.append(TranscriptItem(id: baseID, kind: .user(text: text)))
                }
                appendImageNotes(flattened, baseID: baseID, into: &result)

            case "system":
                let text = flattenContent(message.content).text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                result.append(TranscriptItem(id: baseID, kind: .status(text: text)))

            default:
                continue
            }
        }
        return result
    }

    /// Hydrates from a gateway `messages` array (session.create/resume results,
    /// Part C display shape: `{role, text, reasoning?…}` or `{role:"tool", name, context}`).
    static func items(fromGatewayMessages messages: [JSONValue]) -> [TranscriptItem] {
        var result: [TranscriptItem] = []
        for (index, message) in messages.enumerated() {
            guard let role = message["role"]?.stringValue else { continue }
            let baseID = "g-\(index)-\(role)"
            switch role {
            case "tool":
                let row = ToolRowModel(toolID: baseID,
                                       name: message["name"]?.stringValue ?? "tool",
                                       context: message["context"]?.stringValue ?? "",
                                       state: .success)
                result.append(TranscriptItem(id: baseID, kind: .tool(row)))
            case "assistant":
                let text = (message["text"]?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let reasoning = gatewayReasoningText(message)
                if let reasoning, !reasoning.isEmpty {
                    result.append(TranscriptItem(
                        id: baseID + "-thinking",
                        kind: .thinking(ThinkingGroupModel(text: reasoning, streaming: false))
                    ))
                }
                if !text.isEmpty {
                    result.append(TranscriptItem(id: baseID, kind: .assistant(text: text, streaming: false)))
                }
            case "user":
                let text = (message["text"]?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                result.append(TranscriptItem(id: baseID, kind: .user(text: text)))
            case "system":
                let text = (message["text"]?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                result.append(TranscriptItem(id: baseID, kind: .status(text: text)))
            default:
                continue
            }
        }
        return result
    }

    // MARK: Content flattening (rpc-methods.md C.2 rules)

    struct FlattenedContent {
        var text: String = ""
        var imageURLs: [String] = []
    }

    /// Flattens a `content` value that is a plain string OR an array of multimodal
    /// parts. Text parts are extracted; image parts are collected separately so the
    /// caller can surface them as rows.
    static func flattenContent(_ value: JSONValue?) -> FlattenedContent {
        var out = FlattenedContent()
        guard let value else { return out }
        switch value {
        case .string(let text):
            out.text = text
        case .int, .double, .bool:
            out.text = GatewayTextCoercion.jsonString(value)
        case .array(let parts):
            for part in parts { flattenPart(part, into: &out, inline: true) }
        case .object:
            flattenPart(value, into: &out, inline: false)
        case .null:
            break
        }
        return out
    }

    private static func flattenPart(_ part: JSONValue, into out: inout FlattenedContent, inline: Bool) {
        if let text = part.stringValue {
            out.text += text
            return
        }
        let type = part["type"]?.stringValue ?? ""
        switch type {
        case "text", "input_text", "output_text":
            out.text += part["text"]?.stringValue ?? part["content"]?.stringValue ?? ""
        case "image_url", "input_image", "image":
            let url = part["image_url"]?["url"]?.stringValue
                ?? part["image_url"]?.stringValue
                ?? part["url"]?.stringValue
            if let url, !url.isEmpty {
                out.imageURLs.append(url)
            } else {
                out.text += inline ? "\n[image]" : "[image]"
            }
        case "input_audio", "audio":
            out.text += inline ? "\n[audio]" : "[audio]"
        default:
            if let text = part["text"]?.stringValue {
                out.text += text
            } else if !type.isEmpty {
                out.text += inline ? "\n[\(type)]" : "[\(type)]"
            } else {
                out.text += "[structured content]"
            }
        }
    }

    private static func appendImageNotes(_ flattened: FlattenedContent,
                                         baseID: String,
                                         into result: inout [TranscriptItem]) {
        // TODO(protocol): render inline image attachments; for now images surface
        // as a placeholder row (the URL/data is available in the stored content).
        for (offset, _) in flattened.imageURLs.enumerated() {
            result.append(TranscriptItem(
                id: baseID + "-image-\(offset)",
                kind: .status(text: "Image attachment (not rendered yet)")
            ))
        }
    }

    // MARK: Tool helpers

    static func decodeArguments(_ value: JSONValue?) -> JSONValue? {
        guard let value else { return nil }
        if value.objectValue != nil { return value }
        if let raw = value.stringValue, let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return decoded
        }
        return nil
    }

    /// Minimum viable port of the reference subtitle: `args.context` / `args.preview`
    /// or the primary string argument, clamped to 80 chars.
    static func toolLabel(name: String, args: JSONValue?) -> String {
        guard let object = args?.objectValue else { return "" }
        let preferredKeys = ["context", "preview", "command", "path", "file_path", "filename",
                             "query", "search_term", "url", "pattern", "text"]
        for key in preferredKeys {
            if let text = object[key]?.stringValue, !text.isEmpty {
                return clamp(text, max: 80)
            }
        }
        for value in object.values {
            if let text = value.stringValue, !text.isEmpty {
                return clamp(text, max: 80)
            }
        }
        return ""
    }

    static func clamp(_ text: String, max: Int) -> String {
        let collapsed = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard collapsed.count > max else { return collapsed }
        return String(collapsed.prefix(max - 1)) + "…"
    }

    private static func reasoningText(of message: SessionMessage) -> String? {
        if let text = message.reasoning, !text.isEmpty { return text }
        if let text = message.reasoningContent, !text.isEmpty { return text }
        if let details = message.reasoningDetails, !details.isNull {
            let text = GatewayTextCoercion.coerce(details)
            if !text.isEmpty { return text }
        }
        if let items = message.codexReasoningItems, !items.isNull {
            let text = GatewayTextCoercion.coerce(items)
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func gatewayReasoningText(_ message: JSONValue) -> String? {
        for key in ["reasoning", "reasoning_content", "reasoning_details", "codex_reasoning_items"] {
            if let value = message[key], !value.isNull {
                let text = GatewayTextCoercion.coerce(value)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }
}
