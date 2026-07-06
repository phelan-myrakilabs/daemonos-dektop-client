import Foundation
import Observation

/// Composition root. Owns the connection store, gateway client, REST client, and
/// the boot/reconnect controller; feature view models hang off this.
@MainActor
@Observable
final class AppModel {
    let connectionStore: ConnectionStore
    let gateway: GatewayClient
    let rest: HermesRESTClient
    let v1: V1ChatClient
    let sessionList: SessionListStore
    let boot: GatewayBootController

    /// Default model id for the v1 transport (the deployment exposes `hermes-agent`).
    static let defaultV1Model = "hermes-agent"

    init() {
        let connectionStore = ConnectionStore()
        self.connectionStore = connectionStore

        // The REST providers read persisted state directly (UserDefaults/Keychain are
        // thread-safe) so the client stays usable off the main actor.
        let tokenCache = connectionStore.tokenCache
        let rest = HermesRESTClient(
            baseURLProvider: {
                let raw = UserDefaults.standard.string(forKey: ConnectionStore.Keys.restBaseURL)
                    ?? ConnectionSettings.defaultRESTBaseURL
                return try ConnectionSettings.normalizeRESTBaseURL(raw)
            },
            tokenProvider: { tokenCache.current() }
        )
        self.rest = rest

        // Streaming-friendly session for the v1 transport: a long inactivity timeout
        // so a running agent turn (kept alive by tool-progress events) is not dropped.
        let streamConfig = URLSessionConfiguration.default
        streamConfig.timeoutIntervalForRequest = V1ChatClient.streamTimeout
        streamConfig.waitsForConnectivity = false
        self.v1 = V1ChatClient(
            baseURLProvider: {
                let raw = UserDefaults.standard.string(forKey: ConnectionStore.Keys.restBaseURL)
                    ?? ConnectionSettings.defaultRESTBaseURL
                return try ConnectionSettings.normalizeRESTBaseURL(raw)
            },
            tokenProvider: { tokenCache.current() },
            session: URLSession(configuration: streamConfig)
        )

        let gateway = GatewayClient()
        self.gateway = gateway

        let sessionList = SessionListStore(rest: rest)
        self.sessionList = sessionList

        self.boot = GatewayBootController(
            connectionStore: connectionStore,
            gateway: gateway,
            rest: rest,
            v1: v1,
            sessionList: sessionList
        )
    }
}
