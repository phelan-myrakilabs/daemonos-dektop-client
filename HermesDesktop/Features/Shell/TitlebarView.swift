import SwiftUI

/// 34pt chrome band floating over the panes (the reference paints no opaque bar).
/// Ghost 20×22 buttons with 4pt gaps; left cluster inset 98pt (traffic lights at
/// x=24 + 74pt control offset), right system cluster pinned 12pt from the trailing
/// edge. The band itself stays transparent and non-hit-testable outside the
/// buttons, so the hiddenTitleBar window keeps native background dragging
/// (no WindowDragGesture needed — macOS 15 only anyway).
struct TitlebarView: View {
    @Environment(ShellLayoutState.self) private var shell
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 0) {
            // Left cluster (reference nudges it down 2pt: translate-y-0.5).
            // TODO: in fullscreen the inset drops to 14pt (traffic lights hidden).
            HStack(spacing: 4) {
                // codicon `layout-sidebar-left`
                TitlebarIconButton(
                    systemImage: "sidebar.left",
                    help: shell.sidebarVisible ? "Hide sidebar" : "Show sidebar"
                ) {
                    shell.toggleSidebar()
                }
                // codicon `arrow-swap` — Phase 2 (pane flipping)
                TitlebarIconButton(
                    systemImage: "arrow.left.arrow.right",
                    help: "Swap sidebar sides",
                    disabled: true
                ) {}
            }
            .padding(.leading, 98)
            .offset(y: 2)

            Spacer(minLength: 8)

            // Right (system) cluster, spec order: haptics, keybinds, settings, right sidebar.
            HStack(spacing: 4) {
                // codicon `unmute` (`mute` when muted) — Phase 2 (haptics)
                TitlebarIconButton(systemImage: "speaker.wave.2", help: "Mute haptics", disabled: true) {}
                // codicon `keyboard` — Phase 2 (keybind panel, ⌘/)
                TitlebarIconButton(systemImage: "keyboard", help: "Keyboard shortcuts", disabled: true) {}
                // codicon `settings-gear`
                TitlebarIconButton(systemImage: "gearshape", help: "Open settings") {
                    openSettings()
                }
                // codicon `layout-sidebar-right` — Phase 2 (file browser rail)
                TitlebarIconButton(systemImage: "sidebar.right", help: "Show right sidebar", disabled: true) {}
            }
            .padding(.trailing, 12)
        }
        .frame(height: HermesTheme.titlebarHeight)
        .frame(maxWidth: .infinity)
    }
}

/// Ghost titlebar button: transparent at rest, hover wash only (the reference
/// deliberately has no pressed background — state reads from the glyph).
private struct TitlebarIconButton: View {
    let systemImage: String
    let help: String
    var disabled = false
    let action: () -> Void

    @Environment(\.hermesTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium)) // codicons render at 14px; SF glyphs read equal at 12
                .foregroundStyle(hovering && !disabled ? theme.textPrimary : theme.textSecondary.opacity(0.85))
                .frame(width: 20, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: HermesTheme.radius(4), style: .continuous)
                        // No control-hover token in HermesTheme yet — derived wash.
                        .fill(hovering && !disabled ? theme.textPrimary.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
        .help(help)
    }
}
