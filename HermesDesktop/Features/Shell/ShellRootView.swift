import SwiftUI
import Observation

/// Shared shell chrome state: sidebar visibility (⌘B / titlebar toggle) and
/// cross-view focus requests (⌘⇧F → sidebar search).
@MainActor
@Observable
final class ShellLayoutState {
    var sidebarVisible = true
    var pendingSearchFocus = false

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisible.toggle()
        }
    }

    /// Reference `session.focusSearch` opens the sidebar first, then focuses.
    func focusSessionSearch() {
        if !sidebarVisible {
            withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible = true }
        }
        pendingSearchFocus = true
    }
}

/// Top-level shell: 34pt titlebar band floating over the panes, collapsible
/// 237pt sessions sidebar, center content column, 20pt status bar, and the
/// full-window boot overlay (reference z-1200/1400 layers).
struct ShellRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatCoordinator.self) private var chat
    @Environment(ThemeStore.self) private var themeStore

    @State private var shell = ShellLayoutState()

    var body: some View {
        let theme = themeStore.theme
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    if shell.sidebarVisible {
                        SidebarView()
                            .frame(width: HermesTheme.sidebarWidth)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(theme.hairline).frame(width: 1)
                            }
                            .transition(.move(edge: .leading))
                    }
                    centerContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.appBackground)
                }
                TitlebarView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBarView()
        }
        .background(theme.appBackground)
        .overlay {
            if model.boot.bootProgress.visible {
                BootOverlayView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.boot.bootProgress.visible)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 960, minHeight: 600)
        .environment(shell)
        .environment(\.hermesTheme, themeStore.theme)
        .focusedSceneValue(\.shellActions, ShellActions(
            sidebarVisible: shell.sidebarVisible,
            newSession: { chat.startNewSession() },
            toggleSidebar: { shell.toggleSidebar() },
            toggleAppearance: { themeStore.toggleMode() }
        ))
        .background(searchFocusShortcut)
    }

    @ViewBuilder
    private var centerContent: some View {
        // Intro shows only for a fresh draft with an empty transcript; once a draft's
        // first send paints an optimistic bubble (items non-empty) or an existing
        // session is open, render the transcript so streaming is visible even before
        // the backend assigns a stored session id.
        let showIntro = chat.activeViewModel.map { $0.isDraft && $0.items.isEmpty } ?? true
        if showIntro {
            ZStack(alignment: .bottom) {
                EmptyStateView()
                // ComposerView applies its own 780pt column + padding.
                ComposerView()
            }
        } else {
            ChatSurfaceView()
        }
    }

    /// Hidden ⌘⇧F trigger — focuses (and if needed reveals) the sidebar search.
    private var searchFocusShortcut: some View {
        Button("") { shell.focusSessionSearch() }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
