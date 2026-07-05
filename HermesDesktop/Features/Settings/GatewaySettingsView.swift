import SwiftUI

/// Gateway/Connection settings for the two-endpoint remote model: independent
/// REST base URL and WebSocket URL drafts, the Keychain-backed session token,
/// a two-stage connection test, and Save & Reconnect (re-runs boot).
struct GatewaySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.hermesTheme) private var theme

    @State private var restDraft = ""
    @State private var wsDraft = ""
    @State private var tokenDraft = ""
    @State private var modeDraft: ConnectionMode = .v1
    @State private var validationError: String?
    @State private var didSave = false
    @State private var loadedDrafts = false
    @State private var tester = ConnectionTester()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow

            SettingsHairline()
                .padding(.vertical, 14)

            SettingsSectionHeader("Connection mode")
                .padding(.bottom, 6)
            Picker("", selection: $modeDraft) {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            footnote(modeDraft == .v1
                ? "OpenAI-compatible /v1 API with a Bearer API key. Chat streams directly; sessions are kept on this device."
                : "Hermes agent gateway (/api/* + /api/ws JSON-RPC). Full sessions/tools, but the current deployment is OAuth-gated.")

            SettingsSectionHeader(modeDraft == .v1 ? "API base URL" : "REST API URL")
                .padding(.top, 16)
                .padding(.bottom, 6)
            TextField("", text: $restDraft, prompt: Text(ConnectionSettings.defaultRESTBaseURL))
                .settingsFieldChrome(theme)
            footnote(modeDraft == .v1
                ? "Base URL for /v1 and /health. Must be https://."
                : "Base URL for all /api/* calls. Must be https://.")

            if modeDraft == .gateway {
                SettingsSectionHeader("WebSocket URL")
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                TextField("", text: $wsDraft, prompt: Text(ConnectionSettings.defaultWSURL))
                    .settingsFieldChrome(theme)
                footnote("Leave as-is unless the gateway moved — the two endpoints are independent. Must be wss://; leave empty to derive /api/ws from the REST base.")
            }

            SettingsSectionHeader(modeDraft.credentialLabel)
                .padding(.top, 16)
                .padding(.bottom, 6)
            SecureField("", text: $tokenDraft, prompt: Text("Paste a \(modeDraft.credentialLabel.lowercased()) to replace the saved one"))
                .settingsFieldChrome(theme)
            footnote(tokenStatusLabel)

            if validationError != nil || tester.phase != .idle {
                feedback
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                Button("Test connection", action: runTest)
                    .buttonStyle(.bordered)
                    .disabled(tester.phase == .running)
                Spacer()
                Button("Save & Reconnect", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.appBackground)
        .onAppear(perform: loadDrafts)
        .onChange(of: restDraft) { clearFeedback() }
        .onChange(of: wsDraft) { clearFeedback() }
        .onChange(of: tokenDraft) { clearFeedback() }
        .onChange(of: modeDraft) { clearFeedback() }
    }

    // MARK: - Subviews

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text("Connection: \(connectionLabel)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            if didSave {
                Text("Saved — reconnecting")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
        }
    }

    private var connectionLabel: String {
        if model.boot.isReady { return "ready" }
        return model.boot.bootProgress.running ? "connecting" : "offline"
    }

    private var stateColor: Color {
        if model.boot.isReady { return theme.statusSuccess }
        return model.boot.bootProgress.running ? theme.statusWarning : theme.statusError
    }

    private var tokenStatusLabel: String {
        model.connectionStore.tokenPreview.map { "Current: \($0)" } ?? "No token saved"
    }

    @ViewBuilder
    private var feedback: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let validationError {
                Text(validationError)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.statusError)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch tester.phase {
            case .idle:
                EmptyView()
            case .running:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing connection…")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
            case .success:
                Text(tester.detail ?? "Connection ok")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.statusSuccess)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            case .failure(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.statusError)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Actions

    private func loadDrafts() {
        guard !loadedDrafts else { return }
        loadedDrafts = true
        restDraft = model.connectionStore.settings.restBaseURLString
        wsDraft = model.connectionStore.settings.wsURLString
        modeDraft = model.connectionStore.settings.mode
    }

    private func clearFeedback() {
        validationError = nil
        tester.reset()
    }

    private func runTest() {
        let draft = ConnectionSettings(
            restBaseURLString: restDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            wsURLString: wsDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            authMode: .token,
            mode: modeDraft
        )
        let draftToken = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = model.connectionStore.token()
        Task {
            await tester.run(settings: draft, draftToken: draftToken, storedToken: stored)
        }
    }

    private func save() {
        validationError = nil
        didSave = false

        let rest = restDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let ws = wsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newToken = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try ConnectionSettings.normalizeRESTBaseURL(rest)
        } catch {
            validationError = error.localizedDescription
            return
        }

        let draft = ConnectionSettings(restBaseURLString: rest, wsURLString: ws, authMode: .token, mode: modeDraft)

        // Reference save-time coercion: a new non-empty credential replaces the stored
        // secret, otherwise the existing one is inherited; neither → hard error.
        let effectiveToken = newToken.isEmpty ? (model.connectionStore.token() ?? "") : newToken
        guard !effectiveToken.isEmpty else {
            validationError = "\(modeDraft.credentialLabel) is required."
            return
        }

        // The WS URL only matters in gateway mode; validate it there.
        if modeDraft == .gateway {
            do {
                _ = try draft.webSocketURL(token: effectiveToken)
            } catch {
                validationError = error.localizedDescription
                return
            }
        }

        model.connectionStore.settings = draft
        if !newToken.isEmpty {
            do {
                try model.connectionStore.setToken(newToken)
            } catch {
                validationError = "Could not save the session token: \(error.localizedDescription)"
                return
            }
            tokenDraft = ""
        }

        didSave = true
        model.boot.retryBoot()
    }
}

private extension View {
    func settingsFieldChrome(_ theme: HermesTheme) -> some View {
        self
            .textFieldStyle(.plain)
            .font(HermesTheme.monoFont(size: 12))
            .foregroundStyle(theme.textPrimary)
            .autocorrectionDisabled()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.radius(8))
                    .fill(theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HermesTheme.radius(8))
                    .stroke(theme.strokeSecondary, lineWidth: 1)
            )
    }
}
