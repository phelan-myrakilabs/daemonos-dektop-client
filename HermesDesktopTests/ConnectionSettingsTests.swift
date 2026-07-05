import Foundation
import Testing
@testable import HermesDesktop

struct ConnectionSettingsTests {

    // MARK: - normalizeRESTBaseURL

    @Test func normalizeTrimsSurroundingWhitespace() throws {
        let url = try ConnectionSettings.normalizeRESTBaseURL("  https://host.example \n")
        #expect(url.absoluteString == "https://host.example")
    }

    @Test func normalizeStripsQueryFragmentAndTrailingSlashes() throws {
        let prefixed = try ConnectionSettings.normalizeRESTBaseURL("https://host.example/hermes/?q=1#frag")
        #expect(prefixed.absoluteString == "https://host.example/hermes")

        let bare = try ConnectionSettings.normalizeRESTBaseURL("https://host.example///")
        #expect(bare.absoluteString == "https://host.example")
    }

    @Test func normalizeRejectsHTTP() {
        do {
            _ = try ConnectionSettings.normalizeRESTBaseURL("http://host.example")
            Issue.record("expected https enforcement")
        } catch let error as HermesAPIError {
            #expect(error.message == "Remote gateway URL must be https://, got http:")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func normalizeRejectsEmptyInput() {
        do {
            _ = try ConnectionSettings.normalizeRESTBaseURL("   ")
            Issue.record("expected empty-input rejection")
        } catch let error as HermesAPIError {
            #expect(error.message == "Remote gateway URL is required.")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func normalizeRejectsGarbage() {
        do {
            _ = try ConnectionSettings.normalizeRESTBaseURL("not-a-url")
            Issue.record("expected invalid-URL rejection")
        } catch let error as HermesAPIError {
            #expect(error.message == "Remote gateway URL is not valid: not-a-url")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    // MARK: - webSocketURL

    @Test func derivedWSURLPreservesPathPrefixAndAppendsAPIWS() throws {
        let settings = ConnectionSettings(restBaseURLString: "https://host.example/hermes",
                                          wsURLString: "")
        let url = try settings.webSocketURL(token: "abc")
        #expect(url.absoluteString == "wss://host.example/hermes/api/ws?token=abc")
    }

    @Test func explicitWSURLWinsOverDerivation() throws {
        let settings = ConnectionSettings(restBaseURLString: "https://host.example/hermes",
                                          wsURLString: "wss://ws.example/api/ws")
        let url = try settings.webSocketURL(token: "abc")
        #expect(url.absoluteString == "wss://ws.example/api/ws?token=abc")
    }

    @Test func tokenIsEncodedLikeEncodeURIComponent() throws {
        let settings = ConnectionSettings(restBaseURLString: ConnectionSettings.defaultRESTBaseURL,
                                          wsURLString: "wss://ws.example/api/ws")
        let url = try settings.webSocketURL(token: "a/b c+d")
        #expect(url.absoluteString == "wss://ws.example/api/ws?token=a%2Fb%20c%2Bd")
    }

    @Test func explicitWSURLMustBeWSS() {
        let settings = ConnectionSettings(restBaseURLString: ConnectionSettings.defaultRESTBaseURL,
                                          wsURLString: "ws://host.example/api/ws")
        do {
            _ = try settings.webSocketURL(token: "abc")
            Issue.record("expected wss enforcement")
        } catch let error as HermesAPIError {
            #expect(error.message == "WebSocket gateway URL must be wss://, got ws:")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
