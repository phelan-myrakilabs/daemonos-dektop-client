import SwiftUI

/// ⌘/ keyboard-shortcuts panel (reference `app/shell/keybind-panel.tsx`): dim
/// backdrop, centered card, grouped rows of label + key-cap chips. Rendered while
/// `KeybindsPanelPresenter.isPresented`. Read-only for now — click-to-rebind is a
/// later phase (TODO(protocol): rebinding + persisted keymap).
struct KeybindsPanelView: View {
    @Environment(KeybindsPanelPresenter.self) private var presenter
    @Environment(\.hermesTheme) private var theme

    private struct Shortcut: Identifiable {
        let id = UUID()
        let label: String
        let combos: [String]
    }
    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let shortcuts: [Shortcut]
    }

    /// Only the shortcuts this app actually implements, plus the read-only composer keys.
    private let groups: [Group] = [
        Group(title: "Session", shortcuts: [
            Shortcut(label: "New chat", combos: ["⌘N"]),
            Shortcut(label: "Switch session", combos: ["⌃Tab", "⌃⇧Tab"]),
            Shortcut(label: "Focus session search", combos: ["⌘⇧F"]),
        ]),
        Group(title: "Navigation", shortcuts: [
            Shortcut(label: "Command palette", combos: ["⌘K", "⌘P"]),
            Shortcut(label: "Settings", combos: ["⌘,"]),
            Shortcut(label: "Keyboard shortcuts", combos: ["⌘/"]),
        ]),
        Group(title: "View", shortcuts: [
            Shortcut(label: "Toggle sidebar", combos: ["⌘B"]),
        ]),
        Group(title: "Appearance", shortcuts: [
            Shortcut(label: "Toggle light / dark", combos: ["⇧X"]),
        ]),
        Group(title: "Composer", shortcuts: [
            Shortcut(label: "Send", combos: ["↵"]),
            Shortcut(label: "New line", combos: ["⇧↵"]),
            Shortcut(label: "Steer live turn", combos: ["⌘↵"]),
            Shortcut(label: "Stop / cancel", combos: ["Esc"]),
        ]),
    ]

    var body: some View {
        if presenter.isPresented {
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { presenter.close() }

                panel
                    .background(
                        Button("") { presenter.close() }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    )
            }
            .transition(.opacity)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.1 * 10)
                                .foregroundStyle(theme.primary)
                                .padding(.bottom, 2)
                            ForEach(group.shortcuts) { shortcut in
                                shortcutRow(shortcut)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 460)
        }
        .overlayPanelChrome(width: 480)
        .hermesShadow(HermesShadow.overlay)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Keyboard shortcuts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("⌘/ reopens this panel.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func shortcutRow(_ shortcut: Shortcut) -> some View {
        HStack(spacing: 8) {
            Text(shortcut.label)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ForEach(Array(shortcut.combos.enumerated()), id: \.offset) { index, combo in
                    if index > 0 {
                        Text("/")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textDisabled)
                    }
                    keyCap(combo)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(HermesTheme.monoFont(size: 10))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.xs)
                    .strokeBorder(theme.strokeSecondary, lineWidth: 0.5)
            )
    }
}
