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
    let sessionList: SessionListStore
    let boot: GatewayBootController

    init() {
        let connectionStore = ConnectionStore()
        self.connectionStore = connectionStore

        // The REST providers read persisted state directly (UserDefaults/Keychain are
        // thread-safe) so the client stays usable off the main actor.
        let rest = HermesRESTClient(
            baseURLProvider: {
                let raw = UserDefaults.standard.string(forKey: ConnectionStore.Keys.restBaseURL)
                    ?? ConnectionSettings.defaultRESTBaseURL
                return try ConnectionSettings.normalizeRESTBaseURL(raw)
            },
            tokenProvider: {
                (try? KeychainTokenStore().read()) ?? nil
            }
        )
        self.rest = rest

        let gateway = GatewayClient()
        self.gateway = gateway

        let sessionList = SessionListStore(rest: rest)
        self.sessionList = sessionList

        self.boot = GatewayBootController(
            connectionStore: connectionStore,
            gateway: gateway,
            rest: rest,
            sessionList: sessionList
        )
    }
}
