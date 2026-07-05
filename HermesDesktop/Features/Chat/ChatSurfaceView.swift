import SwiftUI

/// The chat column: transcript scroller + docked composer. Reads the
/// ChatCoordinator from the environment.
struct ChatSurfaceView: View {
    /// Reference `RENDER_BUDGET = 300` rendered parts; "Show earlier" adds another 300.
    static let renderBudget = 300

    @Environment(ChatCoordinator.self) private var coordinator
    @Environment(\.hermesTheme) private var theme

    @State private var budget = ChatSurfaceView.renderBudget
    @State private var isPinnedToBottom = true
    @State private var bottomDistance: CGFloat = 0

    private static let bottomMarkerID = "chat-bottom-marker"

    var body: some View {
        Group {
            if let viewModel = coordinator.activeViewModel {
                content(for: viewModel)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.appBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView()
        }
        .onChange(of: coordinator.activeViewModel?.id) { _, _ in
            budget = Self.renderBudget
            isPinnedToBottom = true
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private func content(for viewModel: ChatSessionViewModel) -> some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .controlSize(.regular)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .resumeFailed:
            resumeFailedCard(viewModel)
        case .draft where viewModel.items.isEmpty:
            emptyState
        default:
            transcript(viewModel)
        }
    }

    private func transcript(_ viewModel: ChatSessionViewModel) -> some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 6) { // --conversation-turn-gap
                        if viewModel.items.count > budget {
                            showEarlierPill
                        }
                        ForEach(visibleItems(viewModel)) { item in
                            itemView(item)
                                .id(item.id)
                        }
                        if let status = viewModel.statusText {
                            StatusNoteView(text: status)
                                .padding(.top, 4)
                        }
                        if viewModel.isBusy && viewModel.awaitingResponse {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Hermes is loading a response")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .padding(.leading, 12)
                            .padding(.top, 4)
                        }
                        bottomMarker
                    }
                    .frame(maxWidth: HermesTheme.contentColumnMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .coordinateSpace(name: "chat-scroll")
                .onPreferenceChange(ScrollBottomDistanceKey.self) { markerMaxY in
                    // Pinned while the bottom marker sits within ~80pt of the viewport.
                    let distance = markerMaxY - viewport.size.height
                    bottomDistance = distance
                    isPinnedToBottom = distance < 80
                }
                .onChange(of: viewModel.revision) { _, _ in
                    if isPinnedToBottom {
                        proxy.scrollTo(Self.bottomMarkerID, anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo(Self.bottomMarkerID, anchor: .bottom)
                }
                .onChange(of: viewModel.id) { _, _ in
                    // Session switch: settle instantly at the bottom.
                    proxy.scrollTo(Self.bottomMarkerID, anchor: .bottom)
                }
                .overlay(alignment: .bottom) {
                    if !isPinnedToBottom {
                        jumpToBottomButton {
                            isPinnedToBottom = true
                            proxy.scrollTo(Self.bottomMarkerID, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func visibleItems(_ viewModel: ChatSessionViewModel) -> [TranscriptItem] {
        let items = viewModel.items
        guard items.count > budget else { return items }
        return Array(items.suffix(budget))
    }

    @ViewBuilder
    private func itemView(_ item: TranscriptItem) -> some View {
        switch item.kind {
        case .user(let text):
            UserMessageView(text: text)
                .padding(.vertical, 4)
        case .assistant(let text, let streaming):
            AssistantMessageView(text: text, isStreaming: streaming)
        case .tool(let row):
            ToolRowView(row: row)
        case .thinking(let group):
            ThinkingDisclosureView(group: group)
        case .status(let text):
            StatusNoteView(text: text)
        case .error(let message):
            InlineErrorView(message: message)
        }
    }

    private var bottomMarker: some View {
        Color.clear
            .frame(height: 1)
            .id(Self.bottomMarkerID)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollBottomDistanceKey.self,
                        value: geo.frame(in: .named("chat-scroll")).maxY
                    )
                }
            )
    }

    private var showEarlierPill: some View {
        HStack {
            Spacer()
            Button("Show earlier messages") {
                budget += Self.renderBudget
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(theme.cardBackground)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(theme.strokeSecondary, lineWidth: 1))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func jumpToBottomButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(theme.cardBackground)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.strokeSecondary, lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("Scroll to bottom")
        .padding(.bottom, 10)
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("What are we moving today?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Send a bug, branch, plan, or rough idea. I'll inspect the repo and turn it into the next concrete step.")
                .font(.system(size: 13))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resumeFailedCard(_ viewModel: ChatSessionViewModel) -> some View {
        VStack(spacing: 10) {
            Text("Couldn't load this session")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("The connection to this session failed and automatic retries gave up. Check that the gateway is running, then try again.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Retry") {
                viewModel.retryOpen()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScrollBottomDistanceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
