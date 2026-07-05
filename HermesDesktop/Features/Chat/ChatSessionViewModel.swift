import Foundation
import Observation

/// Per-session streaming state machine. Owns the transcript items, the delta
/// queue (~33 ms flush cadence), the resume/create/submit flows, and the turn
/// lifecycle driven by gateway events (routed here by ChatCoordinator).
@MainActor
@Observable
final class ChatSessionViewModel: Identifiable {
    enum Phase: Equatable {
        /// Fresh draft — no backend session until the first send.
        case draft
        case loading
        case ready
        case resumeFailed(String)
    }

    /// Reference: `STREAM_DELTA_FLUSH_MS = 33`.
    static let deltaFlushInterval: TimeInterval = 0.033
    /// Reference: `MAX_RESUME_RETRIES = 4`, backoff `min(8s, 1s * 2^attempt)`.
    static let maxResumeRetries = 4

    nonisolated let id = UUID()

    private let rest: HermesRESTClient
    private let boot: GatewayBootController

    private(set) var storedSessionID: String?
    /// Runtime (gateway-minted) sid; changes on every resume.
    private(set) var liveSessionID: String?
    private(set) var title: String?
    private(set) var modelName: String?
    private(set) var phase: Phase
    private(set) var items: [TranscriptItem] = []
    /// Bumped on every transcript mutation — cheap `onChange` hook for autoscroll.
    private(set) var revision = 0
    private(set) var isBusy = false
    private(set) var awaitingResponse = false
    /// Transient status line from `status.update` (cleared when the turn settles).
    private(set) var statusText: String?

    /// Composer draft, kept here so per-session drafts survive session switches.
    var draft = ""

    /// Fired once the backend session exists (after `session.create` adopts ids).
    var onEstablished: (() -> Void)?

    var isDraft: Bool { storedSessionID == nil && liveSessionID == nil }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "Untitled session"
    }

    // MARK: Private state

    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var openGeneration = 0
    @ObservationIgnored private var prefetchPainted = false
    @ObservationIgnored private var submitInFlight = false
    @ObservationIgnored private var queuedPrompts: [String] = []
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var sawAssistantPayload = false
    @ObservationIgnored private var turnCounter = 0
    @ObservationIgnored private var currentTurnItemIDs: Set<String> = []
    @ObservationIgnored private var itemSequence = 0
    @ObservationIgnored private var toolSyntheticCounter = 0

    // Delta queue
    @ObservationIgnored private var pendingAssistantDelta = ""
    @ObservationIgnored private var pendingReasoningDelta = ""
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var lastFlushAt = Date.distantPast

    // MARK: Init

    /// Draft session — no RPC until the first send.
    init(rest: HermesRESTClient, boot: GatewayBootController) {
        self.rest = rest
        self.boot = boot
        self.phase = .draft
    }

    /// Existing stored session — call `open()` to hydrate.
    init(session: SessionInfo, rest: HermesRESTClient, boot: GatewayBootController) {
        self.rest = rest
        self.boot = boot
        self.storedSessionID = session.id
        self.title = session.title
        self.modelName = session.model
        self.phase = .loading
    }

    // MARK: - Open / resume

    /// Runs the REST transcript prefetch and `session.resume` concurrently.
    /// The prefetch wins the paint; the resume payload's messages are skipped
    /// when the prefetch already landed.
    func open() {
        guard let storedID = storedSessionID, openTask == nil else { return }
        openGeneration += 1
        let generation = openGeneration
        if items.isEmpty { phase = .loading }
        prefetchPainted = false
        openTask = Task { [weak self] in
            guard let self else { return }
            async let prefetch: Void = self.runPrefetch(storedID: storedID, generation: generation)
            async let resume: Void = self.runResumeWithRetry(storedID: storedID, generation: generation)
            _ = await (prefetch, resume)
            self.openTask = nil
        }
    }

    func retryOpen() {
        openTask?.cancel()
        openTask = nil
        phase = .loading
        open()
    }

    private func runPrefetch(storedID: String, generation: Int) async {
        let escaped = storedID.addingPercentEncoding(withAllowedCharacters: .uriComponentAllowed) ?? storedID
        do {
            let response = try await rest.request("/api/sessions/\(escaped)/messages",
                                                  timeout: HermesRESTClient.startupTimeout,
                                                  as: SessionMessagesResponse.self)
            guard generation == openGeneration else { return }
            items = TranscriptHydration.items(from: response.messages)
            prefetchPainted = true
            if phase == .loading { phase = .ready }
            bumpRevision()
        } catch {
            // Non-fatal: the resume path is the authority on failure handling.
        }
    }

    private func runResumeWithRetry(storedID: String, generation: Int) async {
        var attempt = 0
        var lastMessage = "Resume failed"
        while true {
            do {
                let result = try await boot.requestGateway(
                    "session.resume",
                    params: ["session_id": .string(storedID), "cols": 96]
                )
                guard generation == openGeneration else { return }
                apply(resume: result)
                return
            } catch {
                guard generation == openGeneration, !Task.isCancelled else { return }
                lastMessage = error.localizedDescription
                attempt += 1
                guard attempt <= Self.maxResumeRetries else { break }
                let delay = min(8.0, pow(2.0, Double(attempt - 1)))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard generation == openGeneration, !Task.isCancelled else { return }
            }
        }
        // Exhausted: if the REST prefetch painted a transcript, stay readable;
        // otherwise surface the explicit retry-able error state.
        if items.isEmpty {
            phase = .resumeFailed(lastMessage)
        } else if phase == .loading {
            phase = .ready
        }
    }

    private func apply(resume result: JSONValue) {
        if let sid = result["session_id"]?.stringValue, !sid.isEmpty {
            liveSessionID = sid
        }
        if let resolved = result["resumed"]?.stringValue ?? result["session_key"]?.stringValue,
           !resolved.isEmpty {
            storedSessionID = resolved
        }
        if !prefetchPainted, let messages = result["messages"]?.arrayValue {
            items = TranscriptHydration.items(fromGatewayMessages: messages)
        }
        if let model = result["info"]?["model"]?.stringValue, !model.isEmpty {
            modelName = model
        }
        if let sessionTitle = result["info"]?["title"]?.stringValue, !sessionTitle.isEmpty {
            title = sessionTitle
        }
        let running = result["running"]?.boolValue ?? (result["status"]?.stringValue == "streaming")
        isBusy = running
        awaitingResponse = running
        phase = .ready
        bumpRevision()
    }

    // MARK: - Send

    /// Sends the current composer draft; restores it on failure so nothing is lost.
    func submitDraft() {
        let text = draft
        draft = ""
        Task { [weak self] in
            guard let self else { return }
            let accepted = await self.send(text)
            if !accepted, self.draft.isEmpty {
                self.draft = text
            }
        }
    }

    @discardableResult
    func send(_ raw: String) async -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if isBusy || submitInFlight {
            queuedPrompts.append(text)
            return true
        }
        return await performSend(text)
    }

    private func performSend(_ text: String) async -> Bool {
        submitInFlight = true
        defer { submitInFlight = false }

        let bubbleID = nextItemID(prefix: "user")
        items.append(TranscriptItem(id: bubbleID, kind: .user(text: text)))
        isBusy = true
        awaitingResponse = true
        interrupted = false
        bumpRevision()

        do {
            if liveSessionID == nil {
                if let storedID = storedSessionID {
                    try await resumeOnce(storedID: storedID)
                } else {
                    try await createSession()
                }
            }
            guard let sid = liveSessionID else {
                throw GatewayError.rpc(code: nil, message: "session not found")
            }
            try await submitPrompt(sessionID: sid, text: text)
            return true
        } catch {
            isBusy = false
            awaitingResponse = false
            if isDraft {
                // session.create failed: drop the optimistic bubble entirely.
                items.removeAll { $0.id == bubbleID }
            }
            let message = error.localizedDescription
            appendErrorItem(message.isEmpty ? "Prompt failed" : message)
            return false
        }
    }

    /// First send on a draft: lazily create the backend session.
    /// The reference includes `cwd`/`model`/`profile` overrides here; the desktop
    /// rewrite has no workspace/model picker state yet, so only `cols` is sent.
    private func createSession() async throws {
        let result = try await boot.requestGateway("session.create", params: ["cols": 96])
        guard let sid = result["session_id"]?.stringValue, !sid.isEmpty else {
            throw GatewayError.rpc(code: nil, message: "session.create returned no session_id")
        }
        liveSessionID = sid
        if let stored = result["stored_session_id"]?.stringValue, !stored.isEmpty {
            storedSessionID = stored
        }
        if let model = result["info"]?["model"]?.stringValue, !model.isEmpty {
            modelName = model
        }
        phase = .ready
        onEstablished?()
    }

    private func resumeOnce(storedID: String) async throws {
        let result = try await boot.requestGateway(
            "session.resume",
            params: ["session_id": .string(storedID), "cols": 96]
        )
        apply(resume: result)
        // Do not let the resume snapshot clobber the send-in-progress flags.
        isBusy = true
        awaitingResponse = true
    }

    private func submitPrompt(sessionID: String, text: String) async throws {
        do {
            try await submitWithBusyRetry(sessionID: sessionID, text: text)
        } catch where GatewayError.isSessionNotFound(error) {
            // Sleep/wake reaped the runtime sid: resume once, then retry once.
            guard let storedID = storedSessionID else { throw error }
            try await resumeOnce(storedID: storedID)
            guard let freshSID = liveSessionID else { throw error }
            try await submitWithBusyRetry(sessionID: freshSID, text: text)
        }
    }

    /// Retries `prompt.submit` on "session busy" every 150 ms for up to 6 s.
    private func submitWithBusyRetry(sessionID: String, text: String) async throws {
        let deadline = Date().addingTimeInterval(GatewayTimeouts.sessionBusyRetryWindow)
        while true {
            do {
                _ = try await boot.requestGateway(
                    "prompt.submit",
                    params: ["session_id": .string(sessionID), "text": .string(text)],
                    timeout: GatewayTimeouts.promptSubmit
                )
                return
            } catch where GatewayError.isSessionBusy(error) && Date() < deadline {
                try await Task.sleep(nanoseconds: UInt64(GatewayTimeouts.sessionBusyRetryInterval * 1_000_000_000))
            }
        }
    }

    // MARK: - Interrupt

    func interrupt() {
        guard let sid = liveSessionID else { return }
        interrupted = true
        flushDeltas()
        // Finalize locally: drop empty streaming items, keep partial text.
        items.removeAll { item in
            guard currentTurnItemIDs.contains(item.id) else { return false }
            if case .assistant(let text, true) = item.kind {
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }
        settleTurn()
        let boot = self.boot
        Task {
            try? await boot.requestGateway("session.interrupt", params: ["session_id": .string(sid)])
        }
    }

    // MARK: - Gateway events

    func handle(_ event: GatewayEvent) {
        switch event.type {
        case GatewayEventName.messageStart:
            beginTurn()
        case GatewayEventName.messageDelta:
            guard !interrupted else { return }
            pendingAssistantDelta += GatewayTextCoercion.coerce(event.payload?["text"])
            scheduleFlush()
        case GatewayEventName.thinkingDelta:
            // Deliberately ignored: carries decorative spinner status text, not reasoning.
            break
        case GatewayEventName.reasoningDelta:
            guard !interrupted else { return }
            pendingReasoningDelta += GatewayTextCoercion.coerce(event.payload?["text"])
            scheduleFlush()
        case GatewayEventName.reasoningAvailable:
            guard !interrupted else { return }
            replaceReasoning(with: GatewayTextCoercion.coerce(event.payload?["text"]))
        case GatewayEventName.toolStart, GatewayEventName.toolGenerating:
            guard !interrupted else { return }
            flushDeltas()
            upsertTool(event.payload, completed: false)
        case GatewayEventName.toolComplete:
            guard !interrupted else { return }
            flushDeltas()
            upsertTool(event.payload, completed: true)
        case GatewayEventName.statusUpdate:
            let kind = event.payload?["kind"]?.stringValue ?? "status"
            let text = event.payload?["text"]?.stringValue ?? ""
            statusText = kind == "compacting" ? "Summarizing thread" : (text.isEmpty ? nil : text)
        case GatewayEventName.sessionTitle:
            if let newTitle = event.payload?["title"]?.stringValue, !newTitle.isEmpty {
                title = newTitle
            }
        case GatewayEventName.sessionInfo:
            applySessionInfo(event.payload)
        case GatewayEventName.messageComplete:
            completeTurn(event.payload)
        case GatewayEventName.error:
            failTurn(event.payload?["message"]?.stringValue ?? "Hermes reported an error")
        default:
            break
        }
    }

    private func beginTurn() {
        flushDeltas()
        interrupted = false
        isBusy = true
        awaitingResponse = true
        sawAssistantPayload = false
        statusText = nil
        turnCounter += 1
        currentTurnItemIDs = []
        bumpRevision()
    }

    private func applySessionInfo(_ payload: JSONValue?) {
        if let model = payload?["model"]?.stringValue, !model.isEmpty { modelName = model }
        if let newTitle = payload?["title"]?.stringValue, !newTitle.isEmpty { title = newTitle }
        if let running = payload?["running"]?.boolValue, !running, sawAssistantPayload {
            isBusy = false
            awaitingResponse = false
        }
    }

    // MARK: Delta queue (33 ms coalescing)

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let elapsed = Date().timeIntervalSince(lastFlushAt)
        let remaining = max(0, Self.deltaFlushInterval - elapsed)
        flushTask = Task { [weak self] in
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.flushTask = nil
            self?.flushDeltas()
        }
    }

    private func flushDeltas() {
        flushTask?.cancel()
        flushTask = nil
        lastFlushAt = Date()
        guard !interrupted else {
            pendingAssistantDelta = ""
            pendingReasoningDelta = ""
            return
        }
        if !pendingAssistantDelta.isEmpty {
            let chunk = pendingAssistantDelta
            pendingAssistantDelta = ""
            appendStreamText(chunk, isReasoning: false)
        }
        if !pendingReasoningDelta.isEmpty {
            let chunk = pendingReasoningDelta
            pendingReasoningDelta = ""
            appendStreamText(chunk, isReasoning: true)
        }
    }

    /// Part coalescing: append to the most recent part of the same type within the
    /// current segment, treating the opposite streaming type as transparent; any
    /// other item (tool row) ends the segment and forces a fresh part.
    private func appendStreamText(_ text: String, isReasoning: Bool) {
        sawAssistantPayload = true
        awaitingResponse = false

        var index = items.count - 1
        scan: while index >= 0, currentTurnItemIDs.contains(items[index].id) {
            switch items[index].kind {
            case .assistant(let existing, let streaming):
                if !isReasoning, streaming {
                    items[index].kind = .assistant(text: existing + text, streaming: true)
                    bumpRevision()
                    return
                }
                if isReasoning, streaming {
                    index -= 1
                    continue scan
                }
                break scan
            case .thinking(var group):
                if isReasoning, group.streaming {
                    group.text += text
                    items[index].kind = .thinking(group)
                    bumpRevision()
                    return
                }
                if !isReasoning, group.streaming {
                    index -= 1
                    continue scan
                }
                break scan
            default:
                break scan
            }
        }

        let itemID = nextItemID(prefix: isReasoning ? "thinking" : "assistant")
        let kind: TranscriptItemKind = isReasoning
            ? .thinking(ThinkingGroupModel(text: text, streaming: true))
            : .assistant(text: text, streaming: true)
        items.append(TranscriptItem(id: itemID, kind: kind))
        currentTurnItemIDs.insert(itemID)
        bumpRevision()
    }

    /// `reasoning.available`: immediate flush, then REPLACE all accumulated reasoning
    /// with one part holding the full text — skipped if the turn already streamed
    /// visible assistant text.
    private func replaceReasoning(with text: String) {
        flushDeltas()
        guard !turnHasVisibleText else { return }
        items.removeAll { item in
            guard currentTurnItemIDs.contains(item.id) else { return false }
            if case .thinking = item.kind { return true }
            return false
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            bumpRevision()
            return
        }
        sawAssistantPayload = true
        awaitingResponse = false
        let itemID = nextItemID(prefix: "thinking")
        items.append(TranscriptItem(id: itemID,
                                    kind: .thinking(ThinkingGroupModel(text: text, streaming: true))))
        currentTurnItemIDs.insert(itemID)
        bumpRevision()
    }

    private var turnHasVisibleText: Bool {
        items.contains { item in
            guard currentTurnItemIDs.contains(item.id) else { return false }
            if case .assistant(let text, _) = item.kind {
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }
    }

    // MARK: Tool upsert

    private func upsertTool(_ payload: JSONValue?, completed: Bool) {
        sawAssistantPayload = true
        awaitingResponse = false
        let name = payload?["name"]?.stringValue ?? "tool"
        let toolID = payload?["tool_id"]?.stringValue

        var targetIndex: Int?
        if let toolID {
            targetIndex = items.firstIndex { item in
                if case .tool(let row) = item.kind { return row.toolID == toolID }
                return false
            }
        }
        if targetIndex == nil {
            // No stable id match: completions resolve the oldest pending same-name
            // row; running/progress updates the newest.
            let candidates = items.indices.filter { index in
                guard currentTurnItemIDs.contains(items[index].id),
                      case .tool(let row) = items[index].kind else { return false }
                return row.state == .running && row.name == name
            }
            targetIndex = completed ? candidates.first : candidates.last
        }

        let args = TranscriptHydration.decodeArguments(payload?["args"])
        let context = payload?["context"]?.stringValue
            ?? TranscriptHydration.toolLabel(name: name, args: args)

        if let index = targetIndex, case .tool(var row) = items[index].kind {
            row.name = name
            if !context.isEmpty { row.context = context }
            if let toolID { row.toolID = toolID }
            if completed { applyCompletion(payload, to: &row) }
            items[index].kind = .tool(row)
            bumpRevision()
            return
        }

        toolSyntheticCounter += 1
        var row = ToolRowModel(
            toolID: toolID ?? "live-tool:\(name):\(toolSyntheticCounter)",
            name: name,
            context: context,
            state: .running
        )
        if completed { applyCompletion(payload, to: &row) }
        let itemID = nextItemID(prefix: "tool")
        items.append(TranscriptItem(id: itemID, kind: .tool(row)))
        currentTurnItemIDs.insert(itemID)
        bumpRevision()
    }

    private func applyCompletion(_ payload: JSONValue?, to row: inout ToolRowModel) {
        let hasError: Bool
        if let errorValue = payload?["error"], !errorValue.isNull {
            hasError = errorValue.boolValue ?? true
        } else {
            hasError = false
        }
        row.state = hasError ? .error : .success
        row.durationSeconds = payload?["duration_s"]?.doubleValue
        if let summary = payload?["summary"]?.stringValue, !summary.isEmpty {
            row.summary = summary
        }
        if let diff = payload?["inline_diff"]?.stringValue, !diff.isEmpty {
            row.inlineDiff = diff
        }
        if let resultText = payload?["result_text"]?.stringValue, !resultText.isEmpty {
            row.detail = resultText
        } else if let result = payload?["result"], !result.isNull {
            let text = GatewayTextCoercion.coerce(result)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                row.detail = text
            }
        }
    }

    // MARK: Turn completion / failure

    /// Final texts matching these patterns are treated as inline errors, not content.
    private static let completionErrorPatterns = [
        "^API call failed after \\d+ retries:",
        "^HTTP\\s+\\d{3}\\b",
        "^(Provider|Gateway)\\s+error:",
    ]

    private func completeTurn(_ payload: JSONValue?) {
        flushDeltas()
        if interrupted {
            settleTurn()
            return
        }
        var finalText = GatewayTextCoercion.coerce(payload?["text"])
        if finalText.isEmpty {
            finalText = GatewayTextCoercion.coerce(payload?["rendered"])
        }
        finalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)

        let isCompletionError = Self.completionErrorPatterns.contains { pattern in
            finalText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if isCompletionError {
            removeTurnAssistantText()
            appendErrorItem(finalText)
            settleTurn()
            return
        }

        dedupeReasoning(against: finalText)
        if !finalText.isEmpty {
            removeTurnAssistantText()
            let itemID = nextItemID(prefix: "assistant")
            items.append(TranscriptItem(id: itemID, kind: .assistant(text: finalText, streaming: false)))
        }
        let hadVisiblePayload = sawAssistantPayload && !finalText.isEmpty
        settleTurn()

        // Post-turn hydrate: when the turn streamed nothing visible, re-fetch the
        // stored transcript to pick up whatever was persisted (reference §7.5.6).
        if !hadVisiblePayload, let storedID = storedSessionID {
            let generation = openGeneration
            Task { [weak self] in
                await self?.hydrateAfterTurn(storedID: storedID, generation: generation)
            }
        }
    }

    private func failTurn(_ message: String) {
        flushDeltas()
        statusText = nil
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        appendErrorItem(trimmed.isEmpty ? "Hermes reported an error" : trimmed)
        settleTurn()
    }

    /// Drops reasoning groups whose normalized text is a prefix of (or prefixed by)
    /// the final visible text — dedupes models that stream the answer as reasoning.
    private func dedupeReasoning(against finalText: String) {
        let normalizedFinal = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        items.removeAll { item in
            guard currentTurnItemIDs.contains(item.id),
                  case .thinking(let group) = item.kind else { return false }
            let normalized = group.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty { return true }
            guard !normalizedFinal.isEmpty else { return false }
            return normalizedFinal.hasPrefix(normalized) || normalized.hasPrefix(normalizedFinal)
        }
    }

    private func removeTurnAssistantText() {
        items.removeAll { item in
            guard currentTurnItemIDs.contains(item.id) else { return false }
            if case .assistant = item.kind { return true }
            return false
        }
    }

    private func settleTurn() {
        isBusy = false
        awaitingResponse = false
        statusText = nil
        pendingAssistantDelta = ""
        pendingReasoningDelta = ""
        // Settle streaming flags on remaining turn items.
        for index in items.indices where currentTurnItemIDs.contains(items[index].id) {
            switch items[index].kind {
            case .assistant(let text, true):
                items[index].kind = .assistant(text: text, streaming: false)
            case .thinking(var group) where group.streaming:
                group.streaming = false
                items[index].kind = .thinking(group)
            default:
                break
            }
        }
        currentTurnItemIDs = []
        bumpRevision()

        if !queuedPrompts.isEmpty {
            let next = queuedPrompts.removeFirst()
            Task { [weak self] in
                _ = await self?.performSend(next)
            }
        }
    }

    private func hydrateAfterTurn(storedID: String, generation: Int) async {
        let escaped = storedID.addingPercentEncoding(withAllowedCharacters: .uriComponentAllowed) ?? storedID
        guard let response = try? await rest.request("/api/sessions/\(escaped)/messages",
                                                     as: SessionMessagesResponse.self) else { return }
        guard generation == openGeneration, !isBusy else { return }
        let hydrated = TranscriptHydration.items(from: response.messages)
        guard !hydrated.isEmpty else { return }
        items = hydrated
        bumpRevision()
    }

    // MARK: Item helpers

    private func appendErrorItem(_ message: String) {
        items.append(TranscriptItem(id: nextItemID(prefix: "error"), kind: .error(message: message)))
        bumpRevision()
    }

    private func nextItemID(prefix: String) -> String {
        itemSequence += 1
        return "\(prefix)-\(turnCounter)-\(itemSequence)"
    }

    private func bumpRevision() {
        revision &+= 1
    }
}
