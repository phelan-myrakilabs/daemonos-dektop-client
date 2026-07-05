import Foundation
import Observation

/// Owns the active chat session and the single gateway event subscription.
/// The Shell selects sessions through `openSession`/`startNewSession`; events are
/// routed to per-session view models (warm cache keyed by stored session id, so
/// switching back to a previously opened session is instant).
@MainActor
@Observable
final class ChatCoordinator {
    private let model: AppModel

    /// Stored (durable) session id of the active session; nil for a fresh draft.
    private(set) var activeSessionID: String?
    private(set) var activeViewModel: ChatSessionViewModel?
    /// Bumped on every EXPLICIT navigation (openSession / startNewSession) so the
    /// shell can return to the chat route. Unlike activeSessionID, this does not
    /// fire when a draft's first send flips nil→stored (no navigation intent there).
    private(set) var navigationEpoch = 0

    @ObservationIgnored private var sessionViewModels: [String: ChatSessionViewModel] = [:]
    @ObservationIgnored private var eventPump: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        startNewSession()
        startEventPump()
    }

    var gatewayState: GatewayConnectionState { model.boot.gatewayState }
    /// Unified transport readiness (v1 health or gateway open) — drives composer state.
    var isReady: Bool { model.boot.isReady }

    private var mode: ConnectionMode { model.connectionStore.settings.mode }

    func openSession(_ session: SessionInfo) {
        navigationEpoch &+= 1
        activeSessionID = session.id
        if let cached = sessionViewModels[session.id] {
            activeViewModel = cached
            if case .resumeFailed = cached.phase {
                cached.retryOpen()
            } else if cached.liveSessionID == nil {
                cached.open()
            }
            return
        }
        let viewModel = makeViewModel(session: session)
        configure(viewModel)
        sessionViewModels[session.id] = viewModel
        activeViewModel = viewModel
        viewModel.open()
    }

    /// Clears to a local draft — no RPC until the first send (reference behavior).
    func startNewSession() {
        navigationEpoch &+= 1
        let viewModel = makeViewModel(session: nil)
        configure(viewModel)
        activeViewModel = viewModel
        activeSessionID = nil
    }

    private func makeViewModel(session: SessionInfo?) -> ChatSessionViewModel {
        if let session {
            return ChatSessionViewModel(session: session, rest: model.rest, boot: model.boot,
                                        v1: model.v1, mode: mode, v1ModelID: AppModel.defaultV1Model)
        }
        return ChatSessionViewModel(rest: model.rest, boot: model.boot,
                                    v1: model.v1, mode: mode, v1ModelID: AppModel.defaultV1Model)
    }

    // MARK: - Wiring

    private func configure(_ viewModel: ChatSessionViewModel) {
        viewModel.onEstablished = { [weak self, weak viewModel] in
            guard let self, let viewModel, let storedID = viewModel.storedSessionID else { return }
            self.sessionViewModels[storedID] = viewModel
            if self.activeViewModel === viewModel {
                self.activeSessionID = storedID
            }
            // Surface the freshly created session in the sidebar (best-effort).
            let sessionList = self.model.sessionList
            let profile = self.model.boot.activeProfile
            Task { try? await sessionList.refresh(profile: profile) }
        }
    }

    private func startEventPump() {
        guard eventPump == nil else { return }
        let gateway = model.gateway
        eventPump = Task { [weak self] in
            let events = await gateway.events()
            for await event in events {
                guard let self else { return }
                self.route(event)
            }
        }
    }

    /// Event routing: scoped events go to the view model owning the live sid;
    /// unscoped events belong to the focused session UNLESS the type starts with
    /// "subagent." (those target child mirrors, never the focused transcript).
    private func route(_ event: GatewayEvent) {
        // `session.title` payloads carry the STORED key (the envelope sid is the
        // live sid) — route by either so retitles land after a sid rotation.
        if event.type == GatewayEventName.sessionTitle,
           let storedKey = event.payload?["session_id"]?.stringValue,
           let viewModel = viewModel(forStoredID: storedKey) {
            viewModel.handle(event)
            return
        }
        if let sid = event.sessionID, !sid.isEmpty {
            viewModel(forLiveID: sid)?.handle(event)
            return
        }
        guard !event.type.hasPrefix("subagent.") else { return }
        activeViewModel?.handle(event)
    }

    private func viewModel(forLiveID sid: String) -> ChatSessionViewModel? {
        if let active = activeViewModel, active.liveSessionID == sid { return active }
        return sessionViewModels.values.first { $0.liveSessionID == sid }
    }

    private func viewModel(forStoredID storedID: String) -> ChatSessionViewModel? {
        if let active = activeViewModel, active.storedSessionID == storedID { return active }
        return sessionViewModels[storedID]
    }
}
