import Foundation

/// One artifact extracted from a session's messages — an image, file, or link the
/// agent produced. Port of the reference `ArtifactRecord` + `collectArtifactsForSession`.
struct ArtifactRecord: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case image, file, link
    }

    let id: String
    let kind: Kind
    let value: String
    let label: String
    let sessionID: String
    let sessionTitle: String
    let timestamp: Double
}

/// Extracts artifacts (images / files / links) from message content, mirroring the
/// reference `artifact-utils.ts` regex pipeline.
enum ArtifactExtractor {
    private static let markdownImage = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#)
    private static let markdownLink = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#)
    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"')]+"#)
    private static let pathPattern = try! NSRegularExpression(
        pattern: #"(?:^|[\s("'`])((?:/|~/|\.\.?/)[^\s"'`<>]+(?:\.[a-z0-9]{1,8})?)"#,
        options: [.caseInsensitive]
    )
    private static let imageExt = try! NSRegularExpression(pattern: #"\.(?:png|jpe?g|gif|webp|svg|bmp)(?:\?.*)?$"#, options: [.caseInsensitive])
    private static let fileExt = try! NSRegularExpression(pattern: #"\.(?:png|jpe?g|gif|webp|svg|bmp|pdf|txt|json|md|csv|zip|tar|gz|mp3|wav|mp4|mov)(?:\?.*)?$"#, options: [.caseInsensitive])

    static func collect(session: SessionInfo, messages: [SessionMessage]) -> [ArtifactRecord] {
        var found: [String: ArtifactRecord] = [:]
        var order: [String] = []
        let title = session.title?.trimmed.nonEmpty
            ?? session.preview?.trimmed.nonEmpty
            ?? "Untitled session"

        for message in messages where message.role == "assistant" || message.role == "tool" {
            let text = messageText(message)
            guard !text.isEmpty else { continue }
            for candidate in candidates(in: text) {
                let value = normalize(candidate)
                guard !value.isEmpty, looksLikeArtifact(value) else { continue }
                let key = "\(session.id):\(value)"
                guard found[key] == nil else { continue }
                let record = ArtifactRecord(
                    id: key,
                    kind: kind(of: value),
                    value: value,
                    label: label(of: value),
                    sessionID: session.id,
                    sessionTitle: title,
                    timestamp: message.timestamp ?? session.lastActive ?? session.startedAt ?? 0
                )
                found[key] = record
                order.append(key)
            }
        }
        return order.compactMap { found[$0] }
    }

    // MARK: - Text extraction

    /// Message content is a string or an array of multimodal parts; pull all text.
    private static func messageText(_ message: SessionMessage) -> String {
        guard let content = message.content else { return "" }
        switch content {
        case .string(let s):
            return s
        case .array(let parts):
            return parts.compactMap { part -> String? in
                if case .string(let s) = part { return s }
                if let type = part["type"]?.stringValue {
                    if type == "text" { return part["text"]?.stringValue }
                    if type == "image_url" {
                        return part["image_url"]?["url"]?.stringValue ?? part["image_url"]?.stringValue
                    }
                }
                return part["text"]?.stringValue
            }.joined(separator: "\n")
        default:
            return ""
        }
    }

    private static func candidates(in text: String) -> [String] {
        var out: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        for regex in [markdownImage, markdownLink] {
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                if let match, match.numberOfRanges > 2, let r = Range(match.range(at: 2), in: text) {
                    out.append(String(text[r]))
                }
            }
        }
        urlPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            if let match, let r = Range(match.range, in: text) { out.append(String(text[r])) }
        }
        pathPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            if let match, match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
                out.append(String(text[r]))
            }
        }
        // data:image payloads are captured by the markdown-image group above.
        return out
    }

    // MARK: - Classification

    private static func normalize(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = v.last, ")".contains(last) || ",.;".contains(last) { v.removeLast() }
        return v
    }

    private static func looksLikeArtifact(_ value: String) -> Bool {
        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("data:image/") {
            return true
        }
        let isPathLike = value.hasPrefix("file://") || value.hasPrefix("/")
            || value.hasPrefix("./") || value.hasPrefix("../") || value.hasPrefix("~/")
        return isPathLike && (matches(imageExt, value) || matches(fileExt, value))
    }

    private static func kind(of value: String) -> ArtifactRecord.Kind {
        if value.hasPrefix("data:image/") || matches(imageExt, value) { return .image }
        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../")
            || value.hasPrefix("~/") || value.hasPrefix("file://") { return .file }
        return .link
    }

    private static func label(of value: String) -> String {
        if let url = URL(string: value), let host = url.host {
            let last = url.pathComponents.filter { $0 != "/" }.last
            return last ?? host
        }
        let parts = value.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return parts.last.map(String.init) ?? value
    }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
