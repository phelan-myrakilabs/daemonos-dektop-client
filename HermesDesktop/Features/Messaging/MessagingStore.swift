import Foundation
import Observation

/// Messaging platforms surface: `GET /api/messaging/platforms` for the platform
/// list/status, and `GET /api/profiles/sessions?source=<platform>` for a selected
/// platform's recent conversations. Gateway-mode only (v1 has no /api/*).
@MainActor
@Observable
final class MessagingStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let rest: HermesRESTClient

    private(set) var phase: Phase = .idle
    private(set) var platforms: [MessagingPlatformInfo] = []
    private(set) var selectedPlatformID: String?
    private(set) var sessions: [SessionInfo] = []
    private(set) var sessionsLoading = false
    private(set) var sessionsError: String?

    /// Skills & Tools availability pattern: the surface needs the agent gateway.
    var isAvailable = false

    init(rest: HermesRESTClient) {
        self.rest = rest
    }

    var selectedPlatform: MessagingPlatformInfo? {
        platforms.first { $0.id == selectedPlatformID }
    }

    func refresh() async {
        guard isAvailable else { return }
        if platforms.isEmpty { phase = .loading }
        do {
            let response = try await rest.request("/api/messaging/platforms",
                                                  timeout: HermesRESTClient.startupTimeout,
                                                  as: MessagingPlatformsResponse.self)
            // Configured/enabled platforms first, then alphabetical by display name.
            platforms = response.platforms.sorted {
                if $0.enabled != $1.enabled { return $0.enabled }
                if $0.configured != $1.configured { return $0.configured }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            phase = .loaded
            if selectedPlatformID == nil, let first = platforms.first(where: { $0.enabled }) ?? platforms.first {
                await select(platformID: first.id)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func select(platformID: String) async {
        selectedPlatformID = platformID
        sessions = []
        sessionsError = nil
        sessionsLoading = true
        defer { sessionsLoading = false }
        let encoded = platformID.addingPercentEncoding(withAllowedCharacters: .uriComponentAllowed) ?? platformID
        do {
            let response = try await rest.request(
                "/api/profiles/sessions?limit=20&offset=0&min_messages=1&archived=exclude&order=recent&profile=all&source=\(encoded)",
                timeout: HermesRESTClient.startupTimeout,
                as: PaginatedSessions.self
            )
            guard selectedPlatformID == platformID else { return } // stale selection
            sessions = response.sessions
        } catch {
            guard selectedPlatformID == platformID else { return }
            sessionsError = error.localizedDescription
        }
    }

    /// Status pill semantics from `gateway_platforms` state strings: `connected` is
    /// healthy; anything with an error message is failing; otherwise neutral.
    static func statusKind(for platform: MessagingPlatformInfo) -> StatusKind {
        if platform.state == "connected" { return .connected }
        if platform.errorMessage?.isEmpty == false || platform.errorCode?.isEmpty == false { return .error }
        if !platform.enabled { return .disabled }
        return .pending
    }

    enum StatusKind {
        case connected
        case pending
        case disabled
        case error
    }
}
