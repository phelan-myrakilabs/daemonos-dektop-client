import AppKit
import Foundation
import Network
import Observation

/// Boot overlay state. Mirrors the reference `DesktopBootProgress`: a struct with a
/// free-form phase string, not an enum. Progress is monotonic while running.
struct BootProgress: Equatable, Sendable {
    var error: String?
    var message: String
    var phase: String
    var progress: Int
    var running: Bool

    var visible: Bool { running || progress < 100 || error != nil }

    static let initial = BootProgress(
        error: nil, message: "Starting Hermes Desktop…", phase: "renderer.init", progress: 2, running: true
    )
}

/// Boot sequence + reconnect state machine, mirroring `use-gateway-boot.ts`:
///
/// - boot: resolve connection → mint WS URL → connect (15 s) → load config
///   (non-fatal) → load sessions (fatal) → ready. A failed initial boot never
///   auto-retries; the user retries from the error overlay.
/// - reconnect (armed only after boot completes): backoff
///   `min(15s, 1s * 2^min(attempt, 4))`, no jitter, retries forever; after 6
///   consecutive failures surface "Lost connection to the gateway" (recoverable —
///   the loop keeps running underneath). The WS URL is re-derived from current
///   settings before every attempt.
/// - wake triggers (reset backoff, reconnect immediately): OS power resume,
///   network path restored, app became active.
@MainActor
@Observable
final class GatewayBootController {
    static let reconnectEscalateAfter = 6

    private let connectionStore: ConnectionStore
    private let gateway: GatewayClient
    private let rest: HermesRESTClient
    private let sessionList: SessionListStore

    private(set) var bootProgress: BootProgress = .initial
    private(set) var gatewayState: GatewayConnectionState = .idle
    private(set) var bootCompleted = false
    private(set) var activeProfile = "default"
    /// Skin payload from the most recent `gateway.ready` / `skin.changed` event.
    private(set) var serverSkin: JSONValue?

    private var reconnectAttempt = 0
    private var reconnecting = false
    private var escalated = false
    private var reconnectTimer: Task<Void, Never>?
    private var inFlightReconnect: Task<Void, Error>?

    private var stateWatcher: Task<Void, Never>?
    private var eventWatcher: Task<Void, Never>?
    private var bootTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var observers: [NSObjectProtocol] = []

    init(connectionStore: ConnectionStore,
         gateway: GatewayClient,
         rest: HermesRESTClient,
         sessionList: SessionListStore) {
        self.connectionStore = connectionStore
        self.gateway = gateway
        self.rest = rest
        self.sessionList = sessionList
    }

    // MARK: - Lifecycle

    func start() {
        guard stateWatcher == nil else { return }

        stateWatcher = Task { [weak self] in
            guard let self else { return }
            for await state in await self.gateway.states() {
                self.handleGatewayState(state)
            }
        }
        eventWatcher = Task { [weak self] in
            guard let self else { return }
            for await event in await self.gateway.events() {
                if event.type == GatewayEventName.gatewayReady || event.type == GatewayEventName.skinChanged {
                    self.serverSkin = event.payload?["skin"] ?? event.payload
                }
            }
        }
        installWakeTriggers()

        bootTask = Task { await boot() }
    }

    func stop() {
        stateWatcher?.cancel()
        eventWatcher?.cancel()
        reconnectTimer?.cancel()
        pathMonitor?.cancel()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        Task { await gateway.close() }
    }

    /// Retry from the error overlay (also used by Settings after saving credentials).
    /// Tears the existing socket down first so a rotated token / changed endpoint is
    /// actually re-dialed — `GatewayClient.connect()` no-ops on an already-open socket,
    /// so without the close the new URL would be silently ignored.
    func retryBoot() {
        bootCompleted = false
        escalated = false
        reconnectAttempt = 0
        reconnectTimer?.cancel()
        reconnectTimer = nil
        bootTask?.cancel()
        bootProgress = .initial
        bootTask = Task {
            await gateway.close()
            await boot()
        }
    }

    // MARK: - Boot

    private func setBootStep(phase: String, message: String, progress: Int) {
        let clamped = min(100, max(0, progress))
        // Monotonic while running.
        let merged = bootProgress.running ? max(bootProgress.progress, clamped) : clamped
        bootProgress = BootProgress(error: nil, message: message, phase: phase, progress: merged, running: true)
    }

    private func completeBoot() {
        bootProgress = BootProgress(error: nil, message: "Hermes Desktop is ready",
                                    phase: "renderer.ready", progress: 100, running: false)
    }

    private func failBoot(_ message: String) {
        bootProgress = BootProgress(error: message, message: "Desktop boot failed: \(message)",
                                    phase: "renderer.error", progress: bootProgress.progress, running: false)
    }

    private func boot() async {
        setBootStep(phase: "renderer.boot", message: "Starting desktop connection", progress: 6)

        if connectionStore.needsSetup {
            // Rewrite decision (the reference has no needs-setup state): without a
            // token there is nothing to dial — surface the settings prompt.
            failBoot("Remote Hermes gateway is selected, but no session token is saved. Open Settings → Gateway and save a token, or switch back to Local.")
            return
        }

        do {
            setBootStep(phase: "renderer.gateway.connect", message: "Connecting live desktop gateway", progress: 95)
            guard let token = connectionStore.token(), !token.isEmpty else {
                throw HermesAPIError(message: "Remote Hermes gateway is selected, but no session token is saved. Open Settings → Gateway and save a token, or switch back to Local.")
            }
            let wsURL = try connectionStore.settings.webSocketURL(token: token)
            try await gateway.connect(url: wsURL)
            if Task.isCancelled { return } // superseded by a newer retryBoot

            // Record active profile (best-effort; defaults to "default").
            // 60 s startup timeout: this fetch can be slow against a tunneled backend,
            // and a timeout here silently strands the sidebar on profile=default.
            if let profile = try? await rest.request("/api/profiles/active",
                                                     timeout: HermesRESTClient.startupTimeout,
                                                     as: ActiveProfileResponse.self) {
                let current = profile.current.trimmingCharacters(in: .whitespacesAndNewlines)
                activeProfile = current.isEmpty ? "default" : current
            } else {
                activeProfile = "default"
            }

            setBootStep(phase: "renderer.config", message: "Loading Hermes settings", progress: 97)
            await refreshConfig() // non-fatal: "Config is nice-to-have; chat still works without it"

            setBootStep(phase: "renderer.sessions", message: "Loading recent sessions", progress: 99)
            try await sessionList.refresh(profile: activeProfile)

            completeBoot()
            bootCompleted = true
        } catch {
            if Task.isCancelled { return } // superseded boot: don't clobber the new attempt
            failBoot(error.localizedDescription)
        }
    }

    private(set) var hermesConfig: JSONValue?
    private(set) var hermesConfigDefaults: JSONValue?

    private func refreshConfig() async {
        async let config = try? rest.request("/api/config", timeout: HermesRESTClient.startupTimeout)
        async let defaults = try? rest.request("/api/config/defaults", timeout: HermesRESTClient.startupTimeout)
        hermesConfig = await config ?? nil
        hermesConfigDefaults = await defaults ?? nil
    }

    // MARK: - Reconnect

    private func handleGatewayState(_ state: GatewayConnectionState) {
        gatewayState = state
        switch state {
        case .open:
            reconnectAttempt = 0
            escalated = false
            reconnectTimer?.cancel()
            reconnectTimer = nil
            if bootCompleted {
                // Dismiss a boot overlay a reconnect may have re-driven.
                completeBoot()
            }
        case .closed, .error:
            if bootCompleted {
                scheduleReconnect()
            }
        case .connecting, .idle:
            break
        }
    }

    private func scheduleReconnect() {
        guard reconnectTimer == nil, !reconnecting, gatewayState != .open else { return }
        let delay = min(15.0, 1.0 * pow(2.0, Double(min(reconnectAttempt, 4))))
        reconnectAttempt += 1
        reconnectTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.attemptReconnect()
        }
    }

    private func attemptReconnect() async {
        reconnectTimer = nil
        guard !reconnecting, gatewayState != .open else { return }
        reconnecting = true
        do {
            // Re-derive the endpoint from current settings every attempt (the analog
            // of revalidate + getConnection + re-mint in the reference).
            guard let token = connectionStore.token(), !token.isEmpty else {
                throw HermesAPIError(message: "Remote Hermes gateway is selected, but no session token is saved. Open Settings → Gateway and save a token, or switch back to Local.")
            }
            let wsURL = try connectionStore.settings.webSocketURL(token: token)
            try await gateway.connect(url: wsURL)
            reconnectAttempt = 0
            // Best-effort resync of state that moved while disconnected.
            await refreshConfig()
            try? await sessionList.refresh(profile: activeProfile)
        } catch {
            // Transport errors are swallowed here; the backoff loop continues.
        }
        reconnecting = false
        if gatewayState != .open {
            if reconnectAttempt >= Self.reconnectEscalateAfter && !escalated {
                escalated = true
                failBoot("Lost connection to the gateway")
            }
            scheduleReconnect()
        }
    }

    /// Immediate reconnect on wake signals: clears the timer, resets backoff,
    /// reconnects now if the socket is not open. No-op before boot completes.
    func reconnectNow() {
        guard bootCompleted else { return }
        reconnectTimer?.cancel()
        reconnectTimer = nil
        reconnectAttempt = 0
        escalated = false
        if gatewayState != .open {
            Task { await attemptReconnect() }
        }
    }

    private func installWakeTriggers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconnectNow() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconnectNow() }
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.reconnectNow() }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    // MARK: - Request-path recovery

    /// Gateway RPC with the reference request-path recovery: if the call fails with
    /// a dead-transport message (`/not connected|connection closed/i`), reconnect
    /// once (concurrent callers share the in-flight reconnect) and retry exactly
    /// once. Any other error propagates unchanged.
    func requestGateway(_ method: String,
                        params: [String: JSONValue] = [:],
                        timeout: TimeInterval? = nil) async throws -> JSONValue {
        do {
            return try await gateway.call(method, params: params, timeout: timeout)
        } catch where GatewayError.isTransportDead(error) {
            try await sharedReconnect()
            return try await gateway.call(method, params: params, timeout: timeout)
        }
    }

    private func sharedReconnect() async throws {
        if let inFlight = inFlightReconnect {
            try await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { throw GatewayError.notConnected }
            guard let token = self.connectionStore.token(), !token.isEmpty else {
                throw HermesAPIError(message: "Remote Hermes gateway is selected, but no session token is saved. Open Settings → Gateway and save a token, or switch back to Local.")
            }
            let wsURL = try self.connectionStore.settings.webSocketURL(token: token)
            try await self.gateway.connect(url: wsURL)
        }
        inFlightReconnect = task
        defer { inFlightReconnect = nil }
        try await task.value
    }
}
