import SwiftUI

/// Mounts the overlay layer: one open overlay route (command palette as a
/// top-center HUD, pickers as centered dialogs) plus the notification stack.
/// Must live inside ShellRootView's subtree so ShellLayoutState/ThemeStore/
/// ChatCoordinator are in the environment.
struct OverlayHostView: View {
    @Environment(OverlayCoordinator.self) private var overlays
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.hermesTheme) private var theme

    var body: some View {
        ZStack(alignment: .top) {
            if let route = overlays.route {
                backdrop(for: route)
                panel(for: route)
                    .hermesShadow(HermesShadow.overlay)
                    // Esc closes; scoped to the overlay's lifetime.
                    .background(
                        Button("") { overlays.close() }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    )
            }
            ToastStackView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: overlays.route)
        .animation(.easeOut(duration: 0.2), value: toasts.toasts)
    }

    /// Reference: the palette HUD has no dim backdrop (transparent click-catcher);
    /// dialogs dim at black/25.
    private func backdrop(for route: OverlayRoute) -> some View {
        Color.black
            .opacity(route == .commandPalette ? 0.001 : 0.25)
            .ignoresSafeArea()
            .onTapGesture { overlays.close() }
    }

    @ViewBuilder
    private func panel(for route: OverlayRoute) -> some View {
        switch route {
        case .commandPalette:
            // Top-center HUD just below the titlebar band.
            CommandPaletteView()
                .padding(.top, HermesTheme.titlebarHeight + 12)
        case .sessionPicker:
            SessionPickerView()
                .padding(.top, 120)
        case .modelPicker:
            ModelPickerView()
                .padding(.top, 120)
        }
    }
}

// MARK: - Shared overlay chrome

/// Dialog/HUD surface: rounded-xl, hairline border, chat-bubble background
/// (reference `rounded-xl border-(--stroke-nous) bg-(--ui-chat-bubble-background)`).
struct OverlayPanelChrome: ViewModifier {
    @Environment(\.hermesTheme) private var theme
    var width: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width)
            .background(theme.userBubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.xl, style: .continuous)
                    .strokeBorder(theme.strokePrimary, lineWidth: 1)
            )
    }
}

extension View {
    func overlayPanelChrome(width: CGFloat) -> some View {
        modifier(OverlayPanelChrome(width: width))
    }
}

// MARK: - Toasts

/// Notification stack: top-center under the titlebar, width min(32rem, 100%−2rem)
/// (reference `components/notifications.tsx`).
private struct ToastStackView: View {
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.hermesTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts.toasts) { toast in
                ToastRowView(toast: toast)
            }
        }
        .frame(maxWidth: 512)
        .padding(.horizontal, 16)
        .padding(.top, HermesTheme.titlebarHeight + 12)
        .allowsHitTesting(!toasts.toasts.isEmpty)
    }
}

private struct ToastRowView: View {
    let toast: ToastCenter.Toast

    @Environment(ToastCenter.self) private var toasts
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.hermesTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(toast.isError ? theme.statusError : theme.primary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                if let message = toast.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button {
                toasts.dismiss(id: toast.id)
            } label: {
                Image(systemName: "xmark") // codicon `close`
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HermesSkinLibrary.extras(skinName: themeStore.skinName, isDark: themeStore.isDark)
                .popoverBackground
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.lg, style: .continuous)
                .strokeBorder(toast.isError ? theme.statusError.opacity(0.4) : theme.strokePrimary, lineWidth: 1)
        )
        .hermesShadow(HermesShadow.md)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
