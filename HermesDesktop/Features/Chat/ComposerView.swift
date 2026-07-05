import SwiftUI

/// The docked composer. Environment-driven; shares the transcript's 780pt column.
///
/// Key handling (matches the reference Enter tree, index.tsx):
///   - Shift+Enter → newline at the caret (handled natively by the field)
///   - Cmd/Ctrl+Enter → reserved for Steer (out of scope) → swallowed, never sends
///   - plain Enter while disconnected → no-op (draft stays editable, submit blocked)
///   - plain Enter, busy + empty → no-op (interrupting is explicit via Stop, never
///     a stray Enter after sending)
///   - plain Enter with payload → submit (queues while busy)
/// Later phases add: queue-edit save, busy slash-command immediate exec, idle-empty
/// queue drain, Esc-to-interrupt.
struct ComposerView: View {
    @Environment(ChatCoordinator.self) private var coordinator
    @Environment(\.hermesTheme) private var theme
    @FocusState private var inputFocused: Bool

    var body: some View {
        if let viewModel = coordinator.activeViewModel {
            @Bindable var viewModel = viewModel
            composerBody(viewModel: viewModel, text: $viewModel.draft)
        }
    }

    // MARK: - Body

    private func composerBody(viewModel: ChatSessionViewModel, text: Binding<String>) -> some View {
        // Submit is gated on transport readiness, but the field stays EDITABLE while
        // connecting so a draft can be typed (reference: disabled blocks Enter-submit
        // only).
        let submitDisabled = !coordinator.isReady
        return HStack(alignment: .bottom, spacing: 4) {
            attachMenu
                .padding(.bottom, 3)
                .disabled(submitDisabled)

            TextField(placeholder(for: viewModel), text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1...8)
                .focused($inputFocused)
                .padding(.vertical, 5)
                .onAppear { focusSoon() }
                .onChange(of: coordinator.activeSessionID) { focusSoon() }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    // Shift+Enter → let the field insert a newline at the caret.
                    if press.modifiers.contains(.shift) { return .ignored }
                    // Cmd/Ctrl+Enter → Steer (out of scope); swallow so it never sends.
                    if press.modifiers.contains(.command) || press.modifiers.contains(.control) {
                        return .handled
                    }
                    // Plain Enter.
                    guard !submitDisabled else { return .handled } // reconnecting: no submit
                    let hasText = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if viewModel.isBusy && !hasText { return .handled } // empty Enter while busy = no-op
                    if hasText { viewModel.submitDraft() }
                    return .handled
                }

            HStack(spacing: 4) {
                modelPill(viewModel)
                micButton
                primaryButton(viewModel)
                    .disabled(submitDisabled)
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 8)   // --composer-surface-pad-x
        .padding(.vertical, 5)     // --composer-surface-pad-y
        .background(theme.composerBackground)
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.xl2))
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.xl2)
                .strokeBorder(theme.composerRing, lineWidth: 1)
        )
        .frame(maxWidth: HermesTheme.contentColumnMaxWidth)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .opacity(submitDisabled ? 0.85 : 1)
    }

    // MARK: - Actions

    /// Focus the input on the next runloop tick (the field must exist first).
    private func focusSoon() {
        DispatchQueue.main.async { inputFocused = true }
    }

    // MARK: - Controls

    /// Attach menu — Phase 1 stub (attachment pipeline not built yet).
    private var attachMenu: some View {
        Menu {
            Button("Files") {}.disabled(true)
            Button("Folder") {}.disabled(true)
            Button("Images") {}.disabled(true)
            Button("Paste image") {}.disabled(true)
            Button("URL") {}.disabled(true)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24, height: 24)
        .help("Add context")
    }

    /// Model pill — static display in Phase 1.
    private func modelPill(_ viewModel: ChatSessionViewModel) -> some View {
        HStack(spacing: 3) {
            Text(viewModel.modelName ?? "model")
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .opacity(0.5)
        }
        .foregroundStyle(theme.textTertiary)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .frame(maxWidth: 160)
        .help(viewModel.modelName ?? "Switch model")
    }

    /// Dictation — disabled stub (voice is out of scope in Phase 1).
    private var micButton: some View {
        Image(systemName: "mic")
            .font(.system(size: 12))
            .foregroundStyle(theme.textDisabled)
            .frame(width: 24, height: 24)
            .help("Voice dictation")
    }

    /// The primary round button: Send / Stop / Queue / voice stub.
    @ViewBuilder
    private func primaryButton(_ viewModel: ChatSessionViewModel) -> some View {
        let hasText = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let busy = viewModel.isBusy

        if busy && !hasText {
            roundButton(systemImage: "square.fill", size: 10, help: "Stop") {
                viewModel.interrupt()
            }
        } else if busy && hasText {
            roundButton(systemImage: "square.stack.3d.up", size: 12, help: "Queue message") {
                viewModel.submitDraft()
            }
        } else if hasText {
            roundButton(systemImage: "arrow.up", size: 12, help: "Send") {
                viewModel.submitDraft()
            }
        } else {
            // Voice-conversation start in the reference — out of scope; rendered
            // as a disabled mic-wave affordance.
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.appBackground)
                .frame(width: 26, height: 26)
                .background(theme.textPrimary.opacity(0.3))
                .clipShape(Circle())
                .help("Start voice conversation")
        }
    }

    private func roundButton(systemImage: String,
                             size: CGFloat,
                             help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(theme.appBackground)
                .frame(width: 26, height: 26) // --composer-control-primary-size
                .background(theme.textPrimary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Placeholder

    private static let newSessionPlaceholders = [
        "What are we building?", "Give Hermes a task", "What's on your mind?",
        "Describe what you need", "What should we tackle?", "Ask anything",
        "Start with a goal",
    ]

    private static let existingSessionPlaceholders = [
        "Send a follow-up", "Add more context", "Refine the request",
        "What's next?", "Keep it going", "Push it further", "Adjust or continue",
    ]

    private func placeholder(for viewModel: ChatSessionViewModel) -> String {
        guard coordinator.isReady else {
            return "Connecting to Hermes…"
        }
        let pool = viewModel.isDraft ? Self.newSessionPlaceholders : Self.existingSessionPlaceholders
        // Stable pick per conversation (re-rolled only on genuine session change).
        let index = abs(viewModel.id.hashValue) % pool.count
        return pool[index]
    }
}
