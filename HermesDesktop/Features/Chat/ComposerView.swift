import SwiftUI

/// The docked composer. Environment-driven; shares the transcript's 780pt column.
///
/// Key handling (this port): Enter sends; Shift+Enter and Cmd+Enter insert a
/// newline. The reference's full Enter decision tree, for later phases:
///   1. queue-edit active → save the edit back to the queue
///   2. busy + slash command (no attachments) → execute immediately (never queued)
///   3. busy + payload → queue the draft (per-session prompt queue)
///   4. busy + empty → Stop (interrupt)
///   5. idle + empty + queue non-empty → drain next queued prompt
///   6. idle + payload → send (restore draft + attachments on rejection)
/// (Cmd+Enter is Steer in the reference — steering is out of scope here, so it
/// falls back to newline; Shift+Enter is always newline.)
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
        let disabled = coordinator.gatewayState != .open
        return HStack(alignment: .bottom, spacing: 4) {
            attachMenu
                .padding(.bottom, 3)

            TextField(placeholder(for: viewModel), text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1...8)
                .focused($inputFocused)
                .padding(.vertical, 5)
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.command) {
                        text.wrappedValue += "\n"
                        return .handled
                    }
                    guard !disabled else { return .handled }
                    handlePrimaryAction(viewModel)
                    return .handled
                }

            HStack(spacing: 4) {
                modelPill(viewModel)
                micButton
                primaryButton(viewModel)
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 8)   // --composer-surface-pad-x
        .padding(.vertical, 5)     // --composer-surface-pad-y
        .background(theme.composerBackground)
        .clipShape(RoundedRectangle(cornerRadius: HermesTheme.radius(16)))
        .overlay(
            RoundedRectangle(cornerRadius: HermesTheme.radius(16))
                .strokeBorder(theme.strokeSecondary, lineWidth: 1)
        )
        .frame(maxWidth: HermesTheme.contentColumnMaxWidth)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .disabled(disabled)
        .opacity(disabled ? 0.75 : 1)
    }

    // MARK: - Actions

    private func handlePrimaryAction(_ viewModel: ChatSessionViewModel) {
        let hasText = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if viewModel.isBusy && !hasText {
            viewModel.interrupt()
        } else if hasText {
            viewModel.submitDraft()
        }
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
        switch coordinator.gatewayState {
        case .connecting:
            return "Starting Hermes..."
        case .closed, .error:
            return "Reconnecting to Hermes…"
        case .idle, .open:
            break
        }
        let pool = viewModel.isDraft ? Self.newSessionPlaceholders : Self.existingSessionPlaceholders
        // Stable pick per conversation (re-rolled only on genuine session change).
        let index = abs(viewModel.id.hashValue) % pool.count
        return pool[index]
    }
}
