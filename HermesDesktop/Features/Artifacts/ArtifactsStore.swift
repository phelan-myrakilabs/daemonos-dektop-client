import Foundation
import Observation

/// Artifacts index: scans the most recent sessions' messages and extracts the
/// images / files / links the agent produced (reference `app/artifacts`). REST-backed
/// (sessions + messages), so gateway-mode only.
@MainActor
@Observable
final class ArtifactsStore {
    /// How many recent sessions to index (bounded — each needs a messages fetch).
    static let sessionScanLimit = 15

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let rest: HermesRESTClient

    private(set) var phase: Phase = .idle
    private(set) var artifacts: [ArtifactRecord] = []
    var query = ""
    var filter: ArtifactRecord.Kind?

    var isAvailable = false

    init(rest: HermesRESTClient) {
        self.rest = rest
    }

    func refresh() async {
        guard isAvailable else { return }
        if artifacts.isEmpty { phase = .loading }
        do {
            let sessions = try await rest.request(
                "/api/profiles/sessions?limit=\(Self.sessionScanLimit)&offset=0&min_messages=1&archived=exclude&order=recent&profile=all",
                timeout: HermesRESTClient.startupTimeout,
                as: PaginatedSessions.self
            ).sessions

            var collected: [ArtifactRecord] = []
            // Fetch each session's messages concurrently, then extract.
            await withTaskGroup(of: [ArtifactRecord].self) { group in
                for session in sessions {
                    group.addTask { [rest] in
                        let escaped = session.id.addingPercentEncoding(withAllowedCharacters: .uriComponentAllowed) ?? session.id
                        guard let response = try? await rest.request("/api/sessions/\(escaped)/messages",
                                                                     timeout: HermesRESTClient.startupTimeout,
                                                                     as: SessionMessagesResponse.self) else {
                            return []
                        }
                        return ArtifactExtractor.collect(session: session, messages: response.messages)
                    }
                }
                for await records in group {
                    collected.append(contentsOf: records)
                }
            }

            artifacts = collected.sorted { $0.timestamp > $1.timestamp }
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    var counts: (all: Int, image: Int, file: Int, link: Int) {
        var image = 0, file = 0, link = 0
        for a in artifacts {
            switch a.kind {
            case .image: image += 1
            case .file: file += 1
            case .link: link += 1
            }
        }
        return (artifacts.count, image, file, link)
    }

    var visible: [ArtifactRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return artifacts.filter { artifact in
            if let filter, artifact.kind != filter { return false }
            guard !q.isEmpty else { return true }
            return artifact.label.lowercased().contains(q)
                || artifact.value.lowercased().contains(q)
                || artifact.sessionTitle.lowercased().contains(q)
        }
    }
}
