import SwiftUI
import AppKit

/// Sessions sidebar: top nav group, borderless search field, Pinned + Sessions
/// sections with 26pt rows, load-more footer. 10pt horizontal content padding;
/// nav starts at titlebar height + 6 (the sidebar has no titlebar of its own).
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatCoordinator.self) private var chat
    @Environment(ShellLayoutState.self) private var shell
    @Environment(\.hermesTheme) private var theme

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            navGroup
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    sections
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, HermesTheme.titlebarHeight + 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.chromeBackground)
        .onChange(of: shell.pendingSearchFocus, initial: true) { _, pending in
            if pending {
                shell.pendingSearchFocus = false
                Task { @MainActor in searchFocused = true }
            }
        }
    }

    // MARK: - Nav group

    private var navGroup: some View {
        VStack(spacing: 1) {
            // codicon `robot` — no SF equivalent, `plus.bubble` per mapping table
            SidebarNavRow(icon: "plus.bubble", label: "New session", showsNewSessionKeycaps: true) {
                chat.startNewSession()
            }
            // codicon `symbol-misc` — Phase 2 route /skills
            SidebarNavRow(icon: "wand.and.stars", label: "Skills & Tools", disabled: true) {}
            // codicon `comment` — Phase 2 route /messaging
            SidebarNavRow(icon: "bubble.left", label: "Messaging", disabled: true) {}
            // codicon `files` — Phase 2 route /artifacts
            SidebarNavRow(icon: "doc.on.doc", label: "Artifacts", disabled: true) {}
        }
        .padding(.bottom, 8)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass") // Lucide `Search`
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary.opacity(0.7))
            TextField("Search sessions…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .focused($searchFocused)
                .accessibilityLabel("Search sessions")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark") // codicon `close`
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            // Borderless; underline appears on focus.
            Rectangle()
                .fill(searchFocused ? theme.strokeSecondary : Color.clear)
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Phase 1: client-side filter over the loaded list only (the reference also
    /// merges a debounced server full-text search).
    private var searchResults: [SessionInfo] {
        let q = trimmedQuery
        return model.sessionList.sessions.filter {
            ($0.title?.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.preview?.localizedCaseInsensitiveContains(q) ?? false)
                || $0.id.localizedCaseInsensitiveContains(q)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        let list = model.sessionList
        if !trimmedQuery.isEmpty {
            SidebarSectionHeader(label: "Results", count: "\(searchResults.count)")
            if searchResults.isEmpty {
                emptyMessage("No sessions match “\(trimmedQuery)”.")
            } else {
                ForEach(searchResults) { SessionRowView(session: $0) }
            }
        } else {
            // Pinned section is always present; an empty pin set shows the hint row.
            SidebarSectionHeader(label: "Pinned",
                                 count: list.pinnedSessions.isEmpty ? "" : countLabel(loaded: list.pinnedSessions.count, total: list.pinnedSessions.count))
            if list.pinnedSessions.isEmpty {
                emptyMessage("Shift-click a chat to pin")
            } else {
                ForEach(list.pinnedSessions) { SessionRowView(session: $0) }
            }
            SidebarSectionHeader(label: "Sessions", count: countLabel(loaded: list.sessions.count, total: list.total))
            if list.sessions.isEmpty && list.isLoading {
                sessionSkeletons
            } else if list.unpinnedSessions.isEmpty {
                emptyMessage(list.sessions.isEmpty
                    ? "No sessions yet"
                    : "Everything here is pinned. Unpin a chat to show it in recents.")
            } else {
                ForEach(list.unpinnedSessions) { SessionRowView(session: $0) }
            }
            if list.sessions.count < list.total {
                LoadMoreRow()
            }
        }
    }

    /// Reference `countLabel(loaded, total)`: "{loaded}/{total}" when total > loaded, else "{loaded}".
    private func countLabel(loaded: Int, total: Int) -> String {
        total > loaded ? "\(loaded)/\(total)" : "\(loaded)"
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 96)
    }

    /// 5 skeleton rows, bar widths per the reference (w-32/40/28/36/24).
    private var sessionSkeletons: some View {
        ForEach(Array([128, 160, 112, 144, 96].enumerated()), id: \.offset) { _, width in
            HStack {
                RoundedRectangle(cornerRadius: HermesTheme.radius(4))
                    .fill(theme.textPrimary.opacity(0.06))
                    .frame(width: CGFloat(width), height: 12)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .frame(minHeight: HermesTheme.sessionRowHeight)
        }
    }
}

// MARK: - Nav row

private struct SidebarNavRow: View {
    let icon: String
    let label: String
    var disabled = false
    var showsNewSessionKeycaps = false
    let action: () -> Void

    @Environment(\.hermesTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 16, height: 16)
                    // Reference: icon = 72% of currentColor.
                    .foregroundStyle((hovering && !disabled ? theme.textPrimary : theme.textSecondary).opacity(0.72))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hovering && !disabled ? theme.textPrimary : theme.textSecondary)
                Spacer(minLength: 0)
                if showsNewSessionKeycaps {
                    HStack(spacing: 2) {
                        KeyCap(text: "⌘")
                        KeyCap(text: "N")
                    }
                    .opacity(0.55)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.radius(6), style: .continuous)
                    .fill(hovering && !disabled ? theme.textPrimary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hovering = $0 }
    }
}

private struct KeyCap: View {
    let text: String
    @Environment(\.hermesTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 3)
            .frame(minWidth: 14, minHeight: 14)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.radius(3))
                    .fill(theme.textPrimary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HermesTheme.radius(3))
                    .stroke(theme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Section header

/// Uppercase tracked label in the accent color, preceded by a 2pt-checkerboard
/// dither dot; trailing count chip.
private struct SidebarSectionHeader: View {
    let label: String
    let count: String

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                DitherDot(color: theme.primary)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.16 * 10)
                    .foregroundStyle(theme.primary)
            }
            .padding(.leading, 8)
            Spacer(minLength: 0)
            Text(count)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textDisabled)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

/// 8×8 square filled with a 2pt checkerboard (repeating-conic-gradient analog).
private struct DitherDot: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 2
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var col = 0
                var x: CGFloat = 0
                while x < size.width {
                    if (row + col) % 2 == 0 {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: cell, height: cell)),
                            with: .color(color)
                        )
                    }
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
        .frame(width: 8, height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 1))
    }
}

// MARK: - Session row

/// 26pt row: status dot lead, single-line title (title ?? preview ?? id),
/// hover-revealed relative age, right-click actions menu.
private struct SessionRowView: View {
    let session: SessionInfo

    @Environment(AppModel.self) private var model
    @Environment(ChatCoordinator.self) private var chat
    @Environment(\.hermesTheme) private var theme
    @State private var hovering = false

    private var isSelected: Bool { chat.activeSessionID == session.id }
    /// Phase 1: dot state from `SessionInfo.isActive` only. The amber
    /// needs-input state requires the chat module's pending clarify/approval
    /// signal — Phase 2.
    private var isWorking: Bool { session.isActive == true }
    private var isPinned: Bool { model.sessionList.isPinned(session) }

    private var displayTitle: String {
        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let preview = session.preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return preview
        }
        return session.id
    }

    var body: some View {
        Button {
            // Shift-click toggles the pin; a plain click opens the session.
            if NSEvent.modifierFlags.contains(.shift) {
                model.sessionList.togglePin(session)
            } else {
                chat.openSession(session)
            }
        } label: {
            HStack(spacing: 6) {
                SessionStatusDot(working: isWorking)
                    .frame(width: 14, height: 14)
                Text(displayTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(hovering || isSelected ? theme.textPrimary : theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hovering && !isWorking {
                    Text(Self.formatAge(session))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(minHeight: HermesTheme.sessionRowHeight)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.radius(6), style: .continuous)
                    .fill(isSelected
                        ? theme.textPrimary.opacity(0.08)
                        : hovering ? theme.textPrimary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(isPinned ? "Unpin" : "Pin") { // codicon `pin`
                model.sessionList.togglePin(session)
            }
            Button("Copy ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            Divider()
            Button("Archive") {}.disabled(true) // codicon `archive` — Phase 2
            Button("Delete", role: .destructive) {}.disabled(true) // codicon `trash` — Phase 2
        }
    }

    /// Reference `formatAge`: d / h / m thresholds, else "now", from
    /// `last_active || started_at`.
    static func formatAge(_ session: SessionInfo) -> String {
        guard var stamp = session.lastActive ?? session.startedAt else { return "now" }
        // TODO(protocol): timestamp unit (epoch seconds vs ms) is unspecified;
        // normalize defensively.
        if stamp > 1_000_000_000_000 { stamp /= 1000 }
        let age = Date().timeIntervalSince1970 - stamp
        if age >= 86_400 { return "\(Int(age / 86_400))d" }
        if age >= 3_600 { return "\(Int(age / 3_600))h" }
        if age >= 60 { return "\(Int(age / 60))m" }
        return "now"
    }
}

/// Idle: 4pt dot at 80% quaternary. Working: 6pt accent dot with glow + ping.
private struct SessionStatusDot: View {
    let working: Bool

    @Environment(\.hermesTheme) private var theme
    @State private var pinging = false

    var body: some View {
        ZStack {
            if working {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: theme.accent.opacity(0.55), radius: 5)
                Circle()
                    .stroke(theme.accent.opacity(0.7), lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pinging ? 2.2 : 1)
                    .opacity(pinging ? 0 : 0.7)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                            pinging = true
                        }
                    }
                    .accessibilityLabel("Session running")
            } else {
                Circle()
                    .fill(theme.textDisabled)
                    .opacity(0.8)
                    .frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - Load more

/// Right-aligned ellipsis button shown while `sessions.count < total`.
private struct LoadMoreRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.hermesTheme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                Task { await model.sessionList.loadMore(profile: model.boot.activeProfile) }
            } label: {
                Group {
                    if model.sessionList.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "ellipsis") // codicon `ellipsis`
                            .font(.system(size: 10))
                    }
                }
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: HermesTheme.radius(4))
                        .fill(hovering ? theme.textPrimary.opacity(0.06) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(hovering ? theme.textPrimary : theme.textTertiary)
            .disabled(model.sessionList.isLoading)
            .onHover { hovering = $0 }
            .help("Load more")
        }
    }
}
