import Foundation
import Observation

/// Sidebar session list. Mirrors the reference `refreshSessions`:
/// `GET /api/profiles/sessions` with page size 50, `min_messages=1`,
/// `archived=exclude`, `order=recent`, and the messaging/automation sources excluded.
/// Sessions are ordered by creation time descending (deliberately not by last
/// activity). Pinning is client-side state.
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
    private(set) var pinnedIDs: Set<String>

    init(rest: HermesRESTClient, defaults: UserDefaults = .standard) {
        self.rest = rest
        self.defaults = defaults
        self.pinnedIDs = Set(defaults.stringArray(forKey: Self.pinnedDefaultsKey) ?? [])
    }

    var pinnedSessions: [SessionInfo] {
        sessions.filter { pinnedIDs.contains($0.id) }
    }

    var unpinnedSessions: [SessionInfo] {
        sessions.filter { !pinnedIDs.contains($0.id) }
    }

    func refresh(profile: String) async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await fetchPage(profile: profile, offset: 0)
            sessions = response.sessions
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
            sessions.append(contentsOf: response.sessions.filter { !known.contains($0.id) })
            total = response.total
        } catch {
            lastError = error.localizedDescription
        }
    }

    func togglePin(_ id: String) {
        if pinnedIDs.contains(id) {
            pinnedIDs.remove(id)
        } else {
            pinnedIDs.insert(id)
        }
        defaults.set(Array(pinnedIDs), forKey: Self.pinnedDefaultsKey)
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
