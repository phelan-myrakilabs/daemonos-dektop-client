import SwiftUI

/// ⌃Tab session-switcher HUD (reference `app/session-switcher.tsx`): top-center HUD,
/// no dim backdrop, rows with a status dot + truncated title + a `⌃N` slot hint for
/// the first nine. Rendered whenever `SessionSwitcherPresenter.isPresented`; the shell
/// drives cycling and commit from the ⌃Tab key handling.
struct SessionSwitcherView: View {
    @Environment(AppModel.self) private var model
    @Environment(SessionSwitcherPresenter.self) private var presenter
    @Environment(\.hermesTheme) private var theme

    private var sessions: [SessionInfo] {
        Array(model.sessionList.sessions.prefix(SessionSwitcherPresenter.maxRows))
    }

    var body: some View {
        if presenter.isPresented {
            ZStack(alignment: .top) {
                // Transparent click-catcher (no dim) — click commits nothing, just closes.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { presenter.cancel() }

                hud
                    .padding(.top, HermesTheme.titlebarHeight + 12)
            }
            .transition(.opacity)
        }
    }

    private var hud: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.hairline)
            if sessions.isEmpty {
                Text("No sessions yet")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            row(session, slot: index + 1, isSelected: index == presenter.index)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 352) // min(22rem, 64vh)
            }
        }
        .overlayPanelChrome(width: 304) // min(19rem, …)
        .hermesShadow(HermesShadow.overlay)
    }

    private var header: some View {
        HStack {
            Text("Switch session")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.1 * 11)
                .foregroundStyle(theme.primary)
            Spacer()
            Text("⌃Tab")
                .font(HermesTheme.monoFont(size: 10))
                .foregroundStyle(theme.textDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ session: SessionInfo, slot: Int, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.isActive == true ? theme.accent : theme.textDisabled.opacity(0.5))
                .frame(width: 5, height: 5)
            Text(displayTitle(session))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 8)
            if slot <= 9 {
                Text("⌃\(slot)")
                    .font(HermesTheme.monoFont(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: HermesTheme.sessionRowHeight)
        .background(
            RoundedRectangle(cornerRadius: HermesRadius.sm, style: .continuous)
                .fill(isSelected ? theme.accent.opacity(0.14) : .clear)
        )
    }

    private func displayTitle(_ session: SessionInfo) -> String {
        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let preview = session.preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return preview
        }
        return session.id
    }
}
