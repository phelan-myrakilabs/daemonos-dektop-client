import SwiftUI

/// Session picker dialog — the desktop analog of the TUI sessions overlay
/// (reference `components/session-picker.tsx`): searchable list of stored
/// sessions; Enter/click resumes through the same path as the sidebar.
struct SessionPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatCoordinator.self) private var chat
    @Environment(OverlayCoordinator.self) private var overlays
    @Environment(\.hermesTheme) private var theme

    @State private var query = ""
    @State private var selectionIndex = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        let rows = filteredSessions

        VStack(spacing: 0) {
            header
            searchField(rows: rows)
            Divider().overlay(theme.hairline)
            if rows.isEmpty {
                Text(model.sessionList.sessions.isEmpty
                    ? "No sessions yet"
                    : "No sessions match “\(query)”")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, session in
                            row(session, isSelected: index == selectionIndex)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }
        }
        .overlayPanelChrome(width: 560)
        .onAppear { searchFocused = true }
        .onChange(of: query) { selectionIndex = 0 }
    }

    private var header: some View {
        HStack {
            Text("Resume session")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text("\(model.sessionList.sessions.count)/\(model.sessionList.total)")
                .font(.system(size: 11))
                .foregroundStyle(theme.textDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func searchField(rows: [SessionInfo]) -> some View {
        TextField("Search sessions…", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(theme.textPrimary)
            .focused($searchFocused)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .onKeyPress(keys: [.downArrow], phases: .down) { _ in
                selectionIndex = min(selectionIndex + 1, max(0, rows.count - 1))
                return .handled
            }
            .onKeyPress(keys: [.upArrow], phases: .down) { _ in
                selectionIndex = max(selectionIndex - 1, 0)
                return .handled
            }
            .onKeyPress(keys: [.return], phases: .down) { _ in
                guard rows.indices.contains(selectionIndex) else { return .handled }
                open(rows[selectionIndex])
                return .handled
            }
    }

    private func row(_ session: SessionInfo, isSelected: Bool) -> some View {
        Button {
            open(session)
        } label: {
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
                Text(Self.relativeAge(session))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: HermesTheme.sessionRowHeight)
            .background(
                RoundedRectangle(cornerRadius: HermesRadius.sm, style: .continuous)
                    .fill(isSelected ? theme.textPrimary.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ session: SessionInfo) {
        overlays.close()
        chat.openSession(session)
    }

    private var filteredSessions: [SessionInfo] {
        let terms = query.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !terms.isEmpty else { return model.sessionList.sessions }
        return model.sessionList.sessions.filter { session in
            let haystack = [session.title ?? "", session.preview ?? "", session.id]
                .joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
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

    /// d / h / m thresholds, else "now" — matches the sidebar's age chip.
    static func relativeAge(_ session: SessionInfo) -> String {
        guard var stamp = session.lastActive ?? session.startedAt else { return "now" }
        if stamp > 1_000_000_000_000 { stamp /= 1000 } // defensively normalize ms
        let age = Date().timeIntervalSince1970 - stamp
        if age >= 86_400 { return "\(Int(age / 86_400))d" }
        if age >= 3_600 { return "\(Int(age / 3_600))h" }
        if age >= 60 { return "\(Int(age / 60))m" }
        return "now"
    }
}
