import AppKit
import SwiftUI
import Observation

/// Center-pane routes beyond the chat surface.
enum ShellRoute: Equatable {
    case chat
    case skillsTools
    case messaging
    case artifacts
}

/// Shared shell chrome state: sidebar visibility (⌘B / titlebar toggle),
/// cross-view focus requests (⌘⇧F → sidebar search), and the center route.
@MainActor
@Observable
final class ShellLayoutState {
    var sidebarVisible = true
    var pendingSearchFocus = false
    var route: ShellRoute = .chat

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisible.toggle()
        }
    }

    /// Any explicit chat action (open a session, new chat) returns the center pane
    /// to the chat surface. Called from the sidebar rows, palette, and switcher so
    /// route control is deliberate — not a side effect of activeSessionID changing
    /// (a draft's first send flips that nil→stored without a navigation intent).
    func showChat() {
        route = .chat
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
    @Environment(OverlayCoordinator.self) private var overlays
    @Environment(OnboardingState.self) private var onboarding
    @Environment(SessionSwitcherPresenter.self) private var switcher
    @Environment(KeybindsPanelPresenter.self) private var keybinds

    @State private var shell = ShellLayoutState()
    @State private var keyMonitor: Any?

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
        .overlay { OverlayHostView() }
        .overlay { SessionSwitcherView() }
        .overlay { KeybindsPanelView() }
        .overlay {
            if model.boot.bootProgress.visible {
                BootOverlayView()
                    .transition(.opacity)
            }
        }
        .overlay {
            if onboarding.shouldShow {
                OnboardingView()
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
        .onChange(of: chat.navigationEpoch) {
            // Any explicit open/new-chat action returns the center pane to chat.
            shell.route = .chat
        }
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch shell.route {
        case .skillsTools:
            SkillsToolsView()
        case .messaging:
            MessagingView()
        case .artifacts:
            ArtifactsView()
        case .chat:
            chatContent
        }
    }

    @ViewBuilder
    private var chatContent: some View {
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

    /// Hidden shortcut triggers: ⌘⇧F sidebar search, ⌘K/⌘P command palette, ⌘/ keybinds.
    private var searchFocusShortcut: some View {
        Group {
            Button("") { shell.focusSessionSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("") { overlays.toggle(.commandPalette) }
                .keyboardShortcut("k", modifiers: .command)
            Button("") { overlays.toggle(.commandPalette) }
                .keyboardShortcut("p", modifiers: .command)
            Button("") { keybinds.toggle() }
                .keyboardShortcut("/", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// The recent sessions the ⌃Tab switcher cycles (capped to match the HUD).
    private var switcherSessions: [SessionInfo] {
        Array(model.sessionList.sessions.prefix(SessionSwitcherPresenter.maxRows))
    }

    /// ⌃Tab session switcher: SwiftUI shortcuts can't express "hold Ctrl, release
    /// commits," so a local event monitor drives it. ⌃Tab shows/advances (⌃⇧Tab
    /// reverses), ⌃1–9 jumps directly, and releasing Ctrl opens the selection.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .keyDown where event.modifierFlags.contains(.control):
                if event.keyCode == 48 { // Tab
                    let sessions = switcherSessions
                    guard !sessions.isEmpty else { return event }
                    if !switcher.isPresented {
                        switcher.begin(sessionCount: sessions.count)
                    } else if event.modifierFlags.contains(.shift) {
                        switcher.prev()
                    } else {
                        switcher.next()
                    }
                    return nil // swallow so focus doesn't tab away
                }
                if switcher.isPresented,
                   let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit) {
                    let sessions = switcherSessions
                    if let index = switcher.select(slot: digit), sessions.indices.contains(index) {
                        chat.openSession(sessions[index])
                    }
                    return nil
                }
                return event
            case .flagsChanged where switcher.isPresented && !event.modifierFlags.contains(.control):
                let sessions = switcherSessions
                if let index = switcher.confirm(), sessions.indices.contains(index) {
                    chat.openSession(sessions[index])
                }
                return event
            default:
                return event
            }
        }
    }
}
