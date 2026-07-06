import SwiftUI

/// Messaging surface: platform list (status pill per gateway platform) with the
/// selected platform's recent conversations. Configure/toggle actions are Phase 3 —
/// rows expose the status and error text the gateway reports today.
struct MessagingView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatCoordinator.self) private var chat
    @Environment(\.hermesTheme) private var theme

    @State private var store: MessagingStore?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.appBackground)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Clear the floating titlebar band.
            Color.clear.frame(height: HermesTheme.titlebarHeight)
        }
        .onAppear {
            if store == nil {
                let created = MessagingStore(rest: model.rest)
                store = created
            }
        }
        .task(id: availabilityKey) {
            guard let store else { return }
            store.isAvailable = model.connectionStore.settings.mode == .gateway && model.boot.isReady
            await store.refresh()
        }
    }

    private var availabilityKey: String {
        "\(model.connectionStore.settings.mode.rawValue)-\(model.boot.isReady)"
    }

    @ViewBuilder
    private func content(_ store: MessagingStore) -> some View {
        if !store.isAvailable {
            unavailable
        } else {
            switch store.phase {
            case .idle, .loading:
                ProgressView("Loading platforms…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 10) {
                    Text("Messaging failed to load")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                    Button("Retry") { Task { await store.refresh() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                loadedBody(store)
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 22))
                .foregroundStyle(theme.textDisabled)
            Text("Messaging needs the Hermes gateway")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Switch to the Hermes gateway connection mode in Settings to see your messaging platforms and conversations.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadedBody(_ store: MessagingStore) -> some View {
        HStack(spacing: 0) {
            // Platform master list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(store.platforms) { platform in
                        PlatformRow(platform: platform,
                                    isSelected: platform.id == store.selectedPlatformID) {
                            Task { await store.select(platformID: platform.id) }
                        }
                    }
                }
                .padding(8)
            }
            .frame(width: 250)
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.hairline).frame(width: 1)
            }

            // Selected platform detail + recent conversations
            detail(store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func detail(_ store: MessagingStore) -> some View {
        if let platform = store.selectedPlatform {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(platform.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        StatusPill(platform: platform)
                        Spacer()
                    }
                    if !platform.description.isEmpty {
                        Text(platform.description)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = platform.errorMessage, !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.statusError)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: HermesRadius.lg, style: .continuous)
                                    .fill(theme.statusError.opacity(0.08))
                            )
                    }
                    // Configure (env vars) + enable toggle land with the Phase-3
                    // settings forms; the endpoint is PUT /api/messaging/platforms/{id}.
                    Text("RECENT CONVERSATIONS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(theme.primary)
                        .padding(.top, 8)

                    if store.sessionsLoading {
                        ProgressView().controlSize(.small)
                    } else if let error = store.sessionsError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.statusError)
                    } else if store.sessions.isEmpty {
                        Text("No conversations yet on \(platform.name).")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        VStack(spacing: 1) {
                            ForEach(store.sessions) { session in
                                ConversationRow(session: session) {
                                    chat.openSession(session)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
            }
        } else {
            Text("Select a platform")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Rows

private struct PlatformRow: View {
    let platform: MessagingPlatformInfo
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.hermesTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(platform.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(platform.enabled ? theme.textPrimary : theme.textTertiary)
                Spacer(minLength: 6)
                if !platform.configured {
                    Text("Needs keys")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.statusWarning)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: HermesRadius.sm, style: .continuous)
                    .fill(isSelected
                        ? theme.textPrimary.opacity(0.08)
                        : hovering ? theme.textPrimary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var dotColor: Color {
        switch MessagingStore.statusKind(for: platform) {
        case .connected: return theme.statusSuccess
        case .error: return theme.statusError
        case .pending: return theme.statusWarning
        case .disabled: return theme.textDisabled
        }
    }
}

private struct StatusPill: View {
    let platform: MessagingPlatformInfo

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var label: String {
        switch MessagingStore.statusKind(for: platform) {
        case .connected: return "Connected"
        case .error: return "Error"
        case .disabled: return "Disabled"
        case .pending: return platform.configured ? "Not connected" : "Needs keys"
        }
    }

    private var color: Color {
        switch MessagingStore.statusKind(for: platform) {
        case .connected: return theme.statusSuccess
        case .error: return theme.statusError
        case .disabled: return theme.textTertiary
        case .pending: return theme.statusWarning
        }
    }
}

private struct ConversationRow: View {
    let session: SessionInfo
    let open: () -> Void

    @Environment(\.hermesTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Text(Self.formatAge(session))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: HermesRadius.sm, style: .continuous)
                    .fill(hovering ? theme.textPrimary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var title: String {
        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let preview = session.preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return preview
        }
        return session.id
    }

    /// d / h / m thresholds, else "now" (same rule as the sidebar rows).
    static func formatAge(_ session: SessionInfo) -> String {
        guard var stamp = session.lastActive ?? session.startedAt else { return "now" }
        if stamp > 1_000_000_000_000 { stamp /= 1000 } // defensively normalize ms
        let age = Date().timeIntervalSince1970 - stamp
        if age >= 86_400 { return "\(Int(age / 86_400))d" }
        if age >= 3_600 { return "\(Int(age / 3_600))h" }
        if age >= 60 { return "\(Int(age / 60))m" }
        return "now"
    }
}
