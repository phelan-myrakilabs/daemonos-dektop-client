import Foundation
import Testing
@testable import HermesDesktop

struct GatewayClientTests {
    private let wsURL = URL(string: "wss://gateway.test/api/ws?token=stub")!

    private func makeConnectedClient(
        connection: MockWebSocketConnection = MockWebSocketConnection(behavior: .openImmediately)
    ) async throws -> (GatewayClient, MockWebSocketConnection) {
        let connector = MockWebSocketConnector(connections: [connection])
        let client = GatewayClient(connector: connector)
        try await client.connect(url: wsURL)
        return (client, connection)
    }

    private func decodeJSON(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    // MARK: - Connection lifecycle

    @Test func connectResolvesOnOpenAndStatesProgress() async throws {
        let connector = MockWebSocketConnector(behavior: .openImmediately)
        let client = GatewayClient(connector: connector)
        let states = StreamCollector(await client.states())

        try await client.connect(url: wsURL)

        let sawAll = await states.waitForCount(3)
        #expect(sawAll)
        #expect(states.values == [.idle, .connecting, .open])
        let state = await client.state
        #expect(state == .open)
        #expect(connector.openedURLs == [wsURL])
    }

    @Test func connectTimeoutFailsAndNextConnectStartsClean() async throws {
        let connector = MockWebSocketConnector(behavior: .neverOpen)
        let client = GatewayClient(connector: connector)

        await #expect(throws: GatewayError.connectFailed) {
            try await client.connect(url: wsURL, timeout: 0.1)
        }
        var state = await client.state
        #expect(state == .error)
        // The half-open socket is dropped so the next connect starts clean.
        #expect(connector.lastConnection?.isCancelled == true)

        connector.enqueue(MockWebSocketConnection(behavior: .openImmediately))
        try await client.connect(url: wsURL, timeout: 1)
        state = await client.state
        #expect(state == .open)
        #expect(connector.openedURLs.count == 2)
    }

    @Test func connectFailureEventRejectsConnect() async throws {
        let connector = MockWebSocketConnector(behavior: .failImmediately)
        let client = GatewayClient(connector: connector)

        await #expect(throws: GatewayError.connectFailed) {
            try await client.connect(url: wsURL)
        }
        let state = await client.state
        #expect(state == .error)
    }

    @Test func openThenCloseTransitionsToClosed() async throws {
        let connector = MockWebSocketConnector(
            behavior: .openThenClose(code: 4401, reason: "credential rejected"))
        let client = GatewayClient(connector: connector)
        let states = StreamCollector(await client.states())

        try await client.connect(url: wsURL)

        let sawAll = await states.waitForCount(4)
        #expect(sawAll)
        #expect(states.values == [.idle, .connecting, .open, .closed])
    }

    // MARK: - Request / response correlation

    @Test func requestFrameShapeAndCorrelation() async throws {
        let (client, connection) = try await makeConnectedClient()

        let call = Task { try await client.call("session.create") }
        let sent = await connection.waitForSentCount(1)
        #expect(sent)

        let frame = try decodeJSON(connection.sentTexts[0])
        #expect(frame["jsonrpc"]?.stringValue == "2.0")
        #expect(frame["id"]?.intValue == 1)
        #expect(frame["method"]?.stringValue == "session.create")
        #expect(frame["params"] == .object([:]))

        connection.receive(ServerFrame.response(id: 1, result: ["ok": true]))
        let result = try await call.value
        #expect(result["ok"]?.boolValue == true)
    }

    @Test func outOfOrderResponsesResolveTheRightCallers() async throws {
        let (client, connection) = try await makeConnectedClient()

        let first = Task { try await client.call("session.list") }
        var sent = await connection.waitForSentCount(1)
        #expect(sent)
        let second = Task { try await client.call("session.resume") }
        sent = await connection.waitForSentCount(2)
        #expect(sent)

        connection.receive(ServerFrame.response(id: 2, result: ["order": "second"]))
        connection.receive(ServerFrame.response(id: 1, result: ["order": "first"]))

        let firstResult = try await first.value
        let secondResult = try await second.value
        #expect(firstResult["order"]?.stringValue == "first")
        #expect(secondResult["order"]?.stringValue == "second")
    }

    @Test func unknownAndLateResponseIDsAreDroppedSilently() async throws {
        let (client, connection) = try await makeConnectedClient()

        // Responses for ids nobody is waiting on must be ignored without side effects.
        connection.receive(ServerFrame.response(id: 99))
        connection.receive(#"{"jsonrpc":"2.0","id":"r1","result":{}}"#)

        let call = Task { try await client.call("session.list") }
        let sent = await connection.waitForSentCount(1)
        #expect(sent)

        connection.receive(ServerFrame.response(id: 777))
        connection.receive(ServerFrame.response(id: 1, result: ["ok": true]))

        let result = try await call.value
        #expect(result["ok"]?.boolValue == true)
    }

    // MARK: - Error frames

    @Test func errorFramesRejectWithServerMessage() async throws {
        let (client, connection) = try await makeConnectedClient()

        let busy = Task {
            try await client.call("prompt.submit",
                                  params: ["session_id": "abc123", "text": "hi"])
        }
        var sent = await connection.waitForSentCount(1)
        #expect(sent)
        connection.receive(ServerFrame.errorResponse(id: 1, code: 4009, message: "session busy"))
        do {
            _ = try await busy.value
            Issue.record("expected session-busy rejection")
        } catch {
            #expect(error.localizedDescription == "session busy")
            #expect(GatewayError.isSessionBusy(error))
        }

        let empty = Task { try await client.call("session.list") }
        sent = await connection.waitForSentCount(2)
        #expect(sent)
        connection.receive(ServerFrame.errorResponse(id: 2, code: -32603, message: ""))
        do {
            _ = try await empty.value
            Issue.record("expected fallback rejection")
        } catch {
            #expect(error.localizedDescription == "Hermes RPC failed")
        }
    }

    // MARK: - Timeouts

    @Test func requestTimeoutCarriesMethodName() async throws {
        let (client, connection) = try await makeConnectedClient()

        do {
            _ = try await client.call("session.list", timeout: 0.05)
            Issue.record("expected request timeout")
        } catch {
            #expect(error.localizedDescription == "request timed out: session.list")
        }
        let sent = await connection.waitForSentCount(1)
        #expect(sent)
    }

    @Test func nonPositiveTimeoutDisablesTheTimer() async throws {
        let (client, connection) = try await makeConnectedClient()

        let call = Task { try await client.call("session.list", timeout: 0) }
        let sent = await connection.waitForSentCount(1)
        #expect(sent)

        try await Task.sleep(nanoseconds: 150_000_000)
        connection.receive(ServerFrame.response(id: 1, result: ["ok": true]))

        let result = try await call.value
        #expect(result["ok"]?.boolValue == true)
    }

    @Test func promptSubmitAckAfterLongDelayStillResolves() async throws {
        let (client, connection) = try await makeConnectedClient()

        let call = Task {
            try await client.call("prompt.submit",
                                  params: ["session_id": "abc123", "text": "hello"],
                                  timeout: GatewayTimeouts.promptSubmit)
        }
        let sent = await connection.waitForSentCount(1)
        #expect(sent)

        let frame = try decodeJSON(connection.sentTexts[0])
        #expect(frame["method"]?.stringValue == "prompt.submit")
        #expect(frame["params"]?["session_id"]?.stringValue == "abc123")
        #expect(frame["params"]?["text"]?.stringValue == "hello")

        // Simulated delayed ack — the 1800 s timer must never fire.
        try await Task.sleep(nanoseconds: 200_000_000)
        connection.receive(ServerFrame.response(id: 1, result: ["status": "streaming"]))

        let result = try await call.value
        #expect(result["status"]?.stringValue == "streaming")
    }

    // MARK: - Disconnected behavior

    @Test func callWhileNotConnectedFailsFast() async throws {
        let client = GatewayClient(connector: MockWebSocketConnector())

        do {
            _ = try await client.call("session.list")
            Issue.record("expected not-connected failure")
        } catch {
            #expect(error.localizedDescription == "Hermes gateway is not connected")
            #expect(GatewayError.isTransportDead(error))
        }
    }

    @Test func socketCloseRejectsAllPendingAndClosesState() async throws {
        let (client, connection) = try await makeConnectedClient()

        let first = Task { try await client.call("session.list") }
        var sent = await connection.waitForSentCount(1)
        #expect(sent)
        let second = Task { try await client.call("session.resume") }
        sent = await connection.waitForSentCount(2)
        #expect(sent)

        connection.close(code: 1000, reason: nil)

        for task in [first, second] {
            do {
                _ = try await task.value
                Issue.record("expected closed rejection")
            } catch {
                #expect(error.localizedDescription == "Hermes gateway connection closed")
                #expect(GatewayError.isTransportDead(error))
            }
        }
        let state = await client.state
        #expect(state == .closed)

        do {
            _ = try await client.call("session.list")
            Issue.record("expected not-connected failure after close")
        } catch {
            #expect(error.localizedDescription == "Hermes gateway is not connected")
        }
    }

    // MARK: - Event fan-out

    @Test func eventsFanOutInOrderAndNonEventsAreDropped() async throws {
        let (client, connection) = try await makeConnectedClient()
        let a = StreamCollector(await client.events())
        let b = StreamCollector(await client.events())

        connection.receive(ServerFrame.event(type: GatewayEventName.messageStart,
                                             sessionID: "abc123"))
        // Parse-error reply (id: null, no method) must be invisible.
        connection.receive(ServerFrame.parseError)
        // Id-bearing frames are never events, even when no caller is waiting.
        connection.receive(ServerFrame.response(id: 42))
        // Unparseable messages are dropped silently.
        connection.receive("this is not json")
        connection.receive(ServerFrame.event(type: GatewayEventName.messageDelta,
                                             sessionID: "abc123",
                                             payload: ["text": "he"]))
        connection.receive(ServerFrame.event(type: GatewayEventName.messageComplete,
                                             sessionID: "abc123"))

        let aArrived = await a.waitForCount(3)
        let bArrived = await b.waitForCount(3)
        #expect(aArrived)
        #expect(bArrived)

        let expected = [
            GatewayEvent(type: GatewayEventName.messageStart, sessionID: "abc123", payload: nil),
            GatewayEvent(type: GatewayEventName.messageDelta, sessionID: "abc123", payload: ["text": "he"]),
            GatewayEvent(type: GatewayEventName.messageComplete, sessionID: "abc123", payload: nil),
        ]
        #expect(a.values == expected)
        #expect(b.values == expected)
    }

    @Test func gatewayReadyArrivesAsNormalEvent() async throws {
        let (client, connection) = try await makeConnectedClient()
        let events = StreamCollector(await client.events())

        connection.receive(ServerFrame.gatewayReady(skin: ["name": "midnight"]))

        let arrived = await events.waitForCount(1)
        #expect(arrived)
        let event = events.values.first
        #expect(event?.type == GatewayEventName.gatewayReady)
        #expect(event?.sessionID == nil)
        #expect(event?.payload?["skin"]?["name"]?.stringValue == "midnight")
    }
}
