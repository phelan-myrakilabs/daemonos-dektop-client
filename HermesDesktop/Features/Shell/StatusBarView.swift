import SwiftUI

/// 20pt status bar with a hairline top border. Left: Gateway pill + Agents +
/// Cron chips. Right: session timer, context-usage placeholder, version chip.
struct StatusBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatCoordinator.self) private var chat
    @Environment(\.hermesTheme) private var theme

    @State private var sessionOpenedAt: Date?
    @State private var turnStartedAt: Date?

    private var turnRunning: Bool { chat.activeViewModel?.isBusy ?? false }

    private static let appVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"

    var body: some View {
        HStack(spacing: 2) {
            gatewayChip
            // codicon `hubot` — subagent counts arrive with chat events (Phase 2), placeholder 0.
            StatusChip(icon: "cpu", label: "Agents", detail: "0 subagents",
                       disabled: true, help: "Open agents")
            // Lucide `Clock` — cron overlay is Phase 2.
            StatusChip(icon: "clock", label: "Cron",
                       disabled: true, help: "Open cron jobs")

            Spacer(minLength: 8)

            // Reference right-cluster order: running-turn timer, context usage,
            // session timer, version.
            runningTurnChip
            // Context usage is fed by chat usage events — Phase 2. Detail uses the
            // reference `contextBarLabel` format.
            StatusChip(detail: "[░░░░░░░░░░] 0%", monoDetail: true,
                       disabled: true, help: "Open context usage breakdown")
            sessionTimerChip
            // Lucide `Hash` — Updates overlay is Phase 2.
            StatusChip(icon: "number", label: "v\(Self.appVersion)",
                       disabled: true, help: "Hermes Desktop v\(Self.appVersion)")
        }
        .padding(.horizontal, 4)
        .frame(height: HermesTheme.statusBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.chromeBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
        .onChange(of: chat.activeSessionID, initial: true) { old, new in
            if new == nil {
                sessionOpenedAt = nil
            } else if old != new || sessionOpenedAt == nil {
                sessionOpenedAt = Date()
            }
        }
        .onChange(of: turnRunning) { _, running in
            turnStartedAt = running ? Date() : nil
        }
    }

    // MARK: - Running turn timer

    @ViewBuilder
    private var runningTurnChip: some View {
        if let start = turnStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatusChip(icon: "circle.fill", label: "Running",
                           detail: Self.formatDuration(context.date.timeIntervalSince(start)),
                           tint: theme.statusWarning, monoDetail: true,
                           help: "Current turn elapsed")
            }
        }
    }

    // MARK: - Gateway pill

    /// Reference detail words: ready / connecting / offline. The `needs setup` /
    /// `checking` / `restarting…` states need the inference-readiness probe —
    /// Phase 2. TODO(protocol): the runtime-readiness probe endpoint is not
    /// specified in the shell spec.
    private var gatewayChip: some View {
        let status = gatewayStatus
        return StatusChip(icon: status.icon, label: "Gateway", detail: status.detail,
                          tint: status.tint, help: "Hermes inference gateway status")
    }

    private var gatewayStatus: (detail: String, tint: Color?, icon: String) {
        // Mode-agnostic: v1 readiness (health OK) or gateway open both read as "ready".
        if model.boot.isReady {
            return ("ready", nil, "waveform.path.ecg") // Lucide `Activity`
        }
        if model.boot.bootProgress.running {
            return ("connecting", theme.statusWarning, "exclamationmark.circle") // Lucide `AlertCircle`
        }
        return ("offline", theme.statusError, "exclamationmark.circle")
    }

    // MARK: - Session timer

    @ViewBuilder
    private var sessionTimerChip: some View {
        if let start = sessionOpenedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatusChip(label: "Session",
                           detail: Self.formatDuration(context.date.timeIntervalSince(start)),
                           monoDetail: true,
                           help: "Runtime session elapsed")
            }
        }
    }

    /// Reference `formatDuration`: `H:MM:SS` when hours > 0, else `M:SS`.
    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Chip

/// Statusbar chip: full-height, 6pt horizontal padding, 11pt text in the
/// tertiary color (or a status tint); interactive chips get a hover wash,
/// disabled chips drop to 45% opacity (reference `disabled:opacity-45`).
private struct StatusChip: View {
    var icon: String? = nil
    var label: String? = nil
    var detail: String? = nil
    var tint: Color? = nil
    var monoDetail = false
    var disabled = false
    var help: String = ""
    var action: (() -> Void)? = nil

    @Environment(\.hermesTheme) private var theme
    @State private var hovering = false

    var body: some View {
        if let action, !disabled {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help(help)
        } else {
            content
                .opacity(disabled ? 0.45 : 1)
                .help(help)
        }
    }

    private var content: some View {
        let base = tint ?? (hovering && action != nil ? theme.textPrimary : theme.textTertiary)
        return HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }
            if let label {
                Text(label)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            if let detail {
                Text(detail)
                    .font(monoDetail ? HermesTheme.monoFont(size: 11) : .system(size: 11))
                    .foregroundStyle(base.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(base)
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .background(hovering && action != nil && !disabled ? theme.textPrimary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
    }
}
