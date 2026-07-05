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
    private let v1: V1ChatClient
    private let auth = DashboardAuthClient()
    private let sessionList: SessionListStore

    private(set) var bootProgress: BootProgress = .initial
    private(set) var gatewayState: GatewayConnectionState = .idle
    private(set) var bootCompleted = false
    private(set) var activeProfile = "default"
    /// Skin payload from the most recent `gateway.ready` / `skin.changed` event.
    private(set) var serverSkin: JSONValue?

    /// v1 transport: true once `/health` succeeds.
    private(set) var v1Ready = false
    /// Backend version reported by `/health` (v1) — surfaced in the status bar.
    private(set) var serverVersion: String?

    /// Gateway mode: whether the deployment is auth-gated (`auth_required` in
    /// /api/status). nil until probed; reset when settings change.
    private(set) var gatewayGated: Bool?
    /// Signed-in identity (gated gateway) — shown in Settings.
    private(set) var authIdentity: String?
    private var reauthNotified = false

    static let signInRequiredMessage = "The gateway requires sign-in. Open Settings → Gateway and sign in with your username and password."

    var mode: ConnectionMode { connectionStore.settings.mode }

    /// Unified readiness across both transports — drives composer enablement and the
    /// gateway status pill.
    var isReady: Bool { mode == .v1 ? v1Ready : gatewayState == .open }

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
         v1: V1ChatClient,
         sessionList: SessionListStore) {
        self.connectionStore = connectionStore
        self.gateway = gateway
        self.rest = rest
        self.v1 = v1
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
        v1Ready = false
        gatewayGated = nil // re-probe: mode/endpoint may have changed
        reauthNotified = false
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

        if mode == .v1 {
            if connectionStore.needsSetup {
                failBoot("No API key saved. Open Settings → Gateway and save your API key.")
                return
            }
            await bootV1()
            return
        }

        do {
            setBootStep(phase: "renderer.gateway.connect", message: "Connecting live desktop gateway", progress: 95)
            let wsURL = try await mintGatewayWSURL()
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

    /// Resolves the WS URL for gateway mode, minting fresh auth every call
    /// (the analog of the reference's resolveGatewayWsUrl, called before EVERY
    /// connect). Ungated → long-lived `?token=` from the Keychain. Gated →
    /// cookie-session check + single-use `?ticket=`; a missing session throws the
    /// sign-in-required message (never falls back to a stale URL — reference
    /// oauth-branch semantics).
    private func mintGatewayWSURL() async throws -> URL {
        let base = try ConnectionSettings.normalizeRESTBaseURL(connectionStore.settings.restBaseURLString)

        if gatewayGated == nil {
            let status = try? await rest.request("/api/status", authenticated: false, as: StatusResponse.self)
            if let status {
                gatewayGated = status.authRequired == true
            } else if (try? await auth.me(baseURL: base)) != nil {
                // The probe failed transiently, but a live cookie session means the
                // gateway is gated — don't fall through to the token branch and
                // surface a misleading "no token saved" error while signed in.
                gatewayGated = true
            }
            // Otherwise leave gatewayGated nil (undetermined): re-probe next attempt
            // rather than committing to the ungated branch on a transient failure.
        }

        if gatewayGated == true {
            guard let session = try await auth.me(baseURL: base) else {
                authIdentity = nil
                throw HermesAPIError(message: Self.signInRequiredMessage, statusCode: 401)
            }
            authIdentity = session.displayName
            let ticket = try await auth.mintWSTicket(baseURL: base)
            return try connectionStore.settings.webSocketURL(ticket: ticket)
        }

        guard let token = connectionStore.token(), !token.isEmpty else {
            // gatewayGated still nil (probe failed, no cookie session) OR genuinely
            // ungated with no token: point the user at sign-in, which is the likely fix.
            throw HermesAPIError(message: Self.signInRequiredMessage, statusCode: 401)
        }
        return try connectionStore.settings.webSocketURL(token: token)
    }

    /// Sign in against the gated gateway's password provider. Credentials are used
    /// once and never persisted — the session lives in HttpOnly cookies.
    func signIn(username: String, password: String) async throws {
        let base = try ConnectionSettings.normalizeRESTBaseURL(connectionStore.settings.restBaseURLString)
        let provider = await passwordProviderName(baseURL: base)
        try await auth.login(baseURL: base, provider: provider, username: username, password: password)
        authIdentity = (try? await auth.me(baseURL: base))?.displayName ?? "signed in"
        reauthNotified = false
        retryBoot()
    }

    func signOut() async {
        if let base = try? ConnectionSettings.normalizeRESTBaseURL(connectionStore.settings.restBaseURLString) {
            await auth.logout(baseURL: base)
        }
        authIdentity = nil
        retryBoot()
    }

    /// First registered password-capable provider (public endpoint); "basic" fallback.
    private func passwordProviderName(baseURL: URL) async -> String {
        struct Providers: Decodable {
            struct Provider: Decodable {
                let name: String?
                let supports_password: Bool?
            }
            let providers: [Provider]
        }
        var request = URLRequest(url: URL(string: baseURL.absoluteString + "/api/auth/providers") ?? baseURL)
        request.timeoutInterval = 8
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let list = try? JSONDecoder().decode(Providers.self, from: data),
           let match = list.providers.first(where: { $0.supports_password == true })?.name {
            return match
        }
        return "basic"
    }

    /// v1 boot: probe `/health` (no persistent socket). Sessions are client-side, so
    /// there is no session-list fetch. Ready as soon as health responds.
    private func bootV1() async {
        v1Ready = false
        setBootStep(phase: "renderer.gateway.connect", message: "Checking Hermes API", progress: 95)
        do {
            let health = try await v1.health()
            if Task.isCancelled { return }
            serverVersion = health.version
            activeProfile = "default"
            v1Ready = true
            completeBoot()
            bootCompleted = true
        } catch {
            if Task.isCancelled { return }
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
            reauthNotified = false
            reconnectTimer?.cancel()
            reconnectTimer = nil
            if bootCompleted {
                // Dismiss a boot overlay a reconnect may have re-driven.
                completeBoot()
            }
        case .closed, .error:
            if bootCompleted, mode == .gateway {
                scheduleReconnect()
            }
        case .connecting, .idle:
            break
        }
    }

    private func scheduleReconnect() {
        guard mode == .gateway else { return }
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
            // Re-derive the endpoint + re-mint auth from current settings every
            // attempt (the analog of revalidate + getConnection + re-mint in the
            // reference; single-use tickets make caching the URL always wrong).
            let wsURL = try await mintGatewayWSURL()
            try await gateway.connect(url: wsURL)
            reconnectAttempt = 0
            // Best-effort resync of state that moved while disconnected.
            await refreshConfig()
            try? await sessionList.refresh(profile: activeProfile)
        } catch {
            // Reauth surfaces once per disconnect episode; transport errors are
            // swallowed and the backoff loop continues (reference behavior).
            if (error as? HermesAPIError)?.statusCode == 401, !reauthNotified {
                reauthNotified = true
                failBoot(Self.signInRequiredMessage)
            }
        }
        reconnecting = false
        if gatewayState != .open {
            // Don't overwrite the actionable "sign in" overlay with a generic
            // connectivity message — a gated session that expired needs the user
            // in Settings → Account, not a "lost connection" dead end.
            if reconnectAttempt >= Self.reconnectEscalateAfter && !escalated && !reauthNotified {
                escalated = true
                failBoot("Lost connection to the gateway")
            }
            scheduleReconnect()
        }
    }

    /// Immediate reconnect on wake signals: clears the timer, resets backoff,
    /// reconnects now if the socket is not open. No-op before boot completes.
    func reconnectNow() {
        guard bootCompleted, mode == .gateway else { return }
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
            let wsURL = try await self.mintGatewayWSURL()
            try await self.gateway.connect(url: wsURL)
        }
        inFlightReconnect = task
        defer { inFlightReconnect = nil }
        try await task.value
    }
}
