import Foundation
import Observation

/// Sidebar session list. Mirrors the reference `refreshSessions`:
/// `GET /api/profiles/sessions` with page size 50, `min_messages=1`,
/// `archived=exclude`, `order=recent`, and the messaging/automation sources excluded.
///
/// The server returns rows in `order=recent` (last_active desc), but the sidebar
/// deliberately re-sorts by creation time (`started_at`) descending so activity on
/// an old session never floats it up (reference sidebar `sortedSessions`).
///
/// Pinning is client-side state keyed by the durable lineage-root id
/// (`_lineage_root_id ?? id`, reference `sessionPinId`) so a pin survives
/// auto-compression tip changes; pin order is preserved.
@MainActor
@Observable
final class SessionListStore {
    static let pageSize = 50
    /// `cron,subagent,tool` plus every messaging source id (reference exclude list).
    static let excludeSources = [
        "cron", "subagent", "tool",
        "telegram", "discord", "slack", "mattermost", "matrix", "signal", "whatsapp",
        "bluebubbles", "homeassistant", "email", "sms", "webhook", "api_server",
        "weixin", "wecom", "qqbot", "yuanbao", "dingtalk", "feishu",
    ]
    private static let pinnedDefaultsKey = "sessions.pinnedIDs"

    private let rest: HermesRESTClient
    private let defaults: UserDefaults

    private(set) var sessions: [SessionInfo] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var lastError: String?
    /// Durable lineage-root pin ids, in user-facing order.
    private(set) var pinnedIDs: [String]

    init(rest: HermesRESTClient, defaults: UserDefaults = .standard) {
        self.rest = rest
        self.defaults = defaults
        self.pinnedIDs = defaults.stringArray(forKey: Self.pinnedDefaultsKey) ?? []
    }

    /// The durable id a pin is stored under (`_lineage_root_id ?? id`).
    static func pinID(for session: SessionInfo) -> String {
        session.lineageRootID ?? session.id
    }

    func isPinned(_ session: SessionInfo) -> Bool {
        pinnedIDs.contains(Self.pinID(for: session))
    }

    /// Pinned rows in pin order; a pinned session whose row isn't currently loaded
    /// is simply absent until it pages in.
    var pinnedSessions: [SessionInfo] {
        pinnedIDs.compactMap { pinID in
            sessions.first { Self.pinID(for: $0) == pinID }
        }
    }

    var unpinnedSessions: [SessionInfo] {
        sessions.filter { !isPinned($0) }
    }

    func refresh(profile: String) async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await fetchPage(profile: profile, offset: 0)
            sessions = Self.sortedByCreation(response.sessions)
            total = response.total
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func loadMore(profile: String) async {
        guard sessions.count < total, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await fetchPage(profile: profile, offset: sessions.count)
            let known = Set(sessions.map(\.id))
            let merged = sessions + response.sessions.filter { !known.contains($0.id) }
            sessions = Self.sortedByCreation(merged)
            total = response.total
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reference sidebar order: creation time (`started_at`) descending.
    private static func sortedByCreation(_ rows: [SessionInfo]) -> [SessionInfo] {
        rows.sorted { ($0.startedAt ?? 0) > ($1.startedAt ?? 0) }
    }

    func togglePin(_ session: SessionInfo) {
        let id = Self.pinID(for: session)
        if let index = pinnedIDs.firstIndex(of: id) {
            pinnedIDs.remove(at: index)
        } else {
            pinnedIDs.append(id)
        }
        defaults.set(pinnedIDs, forKey: Self.pinnedDefaultsKey)
    }

    private func fetchPage(profile: String, offset: Int) async throws -> PaginatedSessions {
        let encodedProfile = profile.addingPercentEncoding(withAllowedCharacters: .uriComponentAllowed) ?? profile
        let excludeList = Self.excludeSources.joined(separator: ",")
            .addingPercentEncoding(withAllowedCharacters: .uriComponentAllowed) ?? ""
        let path = "/api/profiles/sessions"
            + "?limit=\(Self.pageSize)&offset=\(offset)&min_messages=1&archived=exclude&order=recent"
            + "&profile=\(encodedProfile)&exclude_sources=\(excludeList)"
        return try await rest.request(path, timeout: HermesRESTClient.startupTimeout, as: PaginatedSessions.self)
    }
}
