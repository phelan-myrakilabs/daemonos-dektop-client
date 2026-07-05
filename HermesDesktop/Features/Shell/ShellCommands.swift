import SwiftUI

/// Actions the focused shell publishes for the menu bar.
/// ShellRootView installs these with `.focusedSceneValue(\.shellActions, …)`.
struct ShellActions {
    var sidebarVisible: Bool
    var newSession: () -> Void
    var toggleSidebar: () -> Void
    var toggleAppearance: () -> Void
}

extension FocusedValues {
    @Entry var shellActions: ShellActions?
}

/// Menu-bar commands mirroring the reference defaults:
/// `session.new` ⌘N, `view.toggleSidebar` ⌘B, `appearance.toggleMode` ⇧X.
struct ShellCommands: Commands {
    @FocusedValue(\.shellActions) private var actions

    var body: some Commands {
        // Replaces the default "New Window" item so ⌘N means New Session.
        CommandGroup(replacing: .newItem) {
            Button("New Session") { actions?.newSession() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(after: .sidebar) {
            Button(actions?.sidebarVisible == false ? "Show Sidebar" : "Hide Sidebar") {
                actions?.toggleSidebar()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(actions == nil)

            // ⇧X only fires when no text field is handling the keystroke
            // (menu equivalents without ⌘ are consulted after the responder chain).
            Button("Toggle Appearance") { actions?.toggleAppearance() }
                .keyboardShortcut("x", modifiers: .shift)
                .disabled(actions == nil)
        }
    }
}
