import SwiftUI

/// ⌘K / ⌘P command palette: top-center HUD, grouped rows with uppercase
/// headings in `--theme-primary`, exact multi-term substring filtering
/// (the reference uses cmdk with substring matching — no fuzzy).
struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatCoordinator.self) private var chat
    @Environment(ThemeStore.self) private var themeStore
    @Environment(ShellLayoutState.self) private var shell
    @Environment(OverlayCoordinator.self) private var overlays
    @Environment(\.hermesTheme) private var theme
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var selectionIndex = 0
    @FocusState private var searchFocused: Bool

    private struct PaletteItem: Identifiable {
        let id: String
        let group: String
        let title: String
        let keycap: String?
        let systemImage: String
        let run: () -> Void
    }

    var body: some View {
        let sections = filteredSections
        let flat = sections.flatMap(\.items)

        VStack(spacing: 0) {
            searchField(flat: flat)
            Divider().overlay(theme.hairline)
            if flat.isEmpty {
                Text("No matching commands")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(sections, id: \.title) { section in
                                sectionHeader(section.title)
                                ForEach(section.items) { item in
                                    row(item, isSelected: flat.firstIndex(where: { $0.id == item.id }) == selectionIndex)
                                        .id(item.id)
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectionIndex) {
                        // Keep the highlighted row visible under arrow-key navigation.
                        if flat.indices.contains(selectionIndex) {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(flat[selectionIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .overlayPanelChrome(width: 520)
        // Defer focus to the next runloop tick — a synchronous set in onAppear lands
        // before the field is in the responder chain and silently no-ops.
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: query) { selectionIndex = 0 }
    }

    // MARK: - Pieces

    private func searchField(flat: [PaletteItem]) -> some View {
        TextField("Type a command or search…", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(theme.textPrimary)
            .focused($searchFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .onKeyPress(keys: [.downArrow], phases: .down) { _ in
                selectionIndex = min(selectionIndex + 1, max(0, flat.count - 1))
                return .handled
            }
            .onKeyPress(keys: [.upArrow], phases: .down) { _ in
                selectionIndex = max(selectionIndex - 1, 0)
                return .handled
            }
            .onKeyPress(keys: [.return], phases: .down) { _ in
                guard flat.indices.contains(selectionIndex) else { return .handled }
                execute(flat[selectionIndex])
                return .handled
            }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.1 * 10)
            .foregroundStyle(theme.primary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        Button {
            execute(item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 14)
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                if let keycap = item.keycap {
                    Text(keycap)
                        .font(HermesTheme.monoFont(size: 10))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.codeBackground)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.xs))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: HermesRadius.sm, style: .continuous)
                    .fill(isSelected ? theme.textPrimary.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func execute(_ item: PaletteItem) {
        overlays.close()
        item.run()
    }

    // MARK: - Command catalog

    private var commands: [PaletteItem] {
        [
            PaletteItem(id: "new-session", group: "Go to", title: "New chat", keycap: "⌘N",
                        systemImage: "plus.bubble") { chat.startNewSession() },
            PaletteItem(id: "open-settings", group: "Go to", title: "Settings", keycap: "⌘,",
                        systemImage: "gearshape") { openSettings() },
            PaletteItem(id: "resume-session", group: "Go to", title: "Resume session…", keycap: nil,
                        systemImage: "clock.arrow.circlepath") { overlays.open(.sessionPicker) },
            PaletteItem(id: "model-picker", group: "Go to", title: "Models…", keycap: nil,
                        systemImage: "cpu") { overlays.open(.modelPicker) },
            PaletteItem(id: "toggle-sidebar", group: "View", title: "Toggle sidebar", keycap: "⌘B",
                        systemImage: "sidebar.left") { shell.toggleSidebar() },
            PaletteItem(id: "toggle-appearance", group: "Appearance", title: "Toggle color mode", keycap: "⇧X",
                        systemImage: "circle.lefthalf.filled") { themeStore.toggleMode() },
        ]
    }

    private struct PaletteSection {
        let title: String
        let items: [PaletteItem]
    }

    /// Exact multi-term substring filter: every whitespace-separated term must
    /// appear (case-insensitive) in the row's search text. No fuzzy matching.
    private static func matches(_ haystack: String, terms: [String]) -> Bool {
        let lowered = haystack.lowercased()
        return terms.allSatisfy { lowered.contains($0) }
    }

    private var filteredSections: [PaletteSection] {
        let terms = query.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        var sections: [PaletteSection] = []
        let groupOrder = ["Go to", "View", "Appearance"]
        for group in groupOrder {
            let items = commands.filter { $0.group == group }
                .filter { terms.isEmpty || Self.matches($0.title, terms: terms) }
            if !items.isEmpty {
                sections.append(PaletteSection(title: group, items: items))
            }
        }

        // Sessions group: shown while typing (the reference surfaces sessions
        // for typed queries).
        if !terms.isEmpty {
            let sessionItems = model.sessionList.sessions
                .filter { session in
                    let haystack = [session.title ?? "", session.preview ?? "", session.id]
                        .joined(separator: " ")
                    return Self.matches(haystack, terms: terms)
                }
                .prefix(8)
                .map { session in
                    PaletteItem(id: "session-\(session.id)", group: "Sessions",
                                title: sessionDisplayTitle(session), keycap: nil,
                                systemImage: "bubble.left") { chat.openSession(session) }
                }
            if !sessionItems.isEmpty {
                sections.append(PaletteSection(title: "Sessions", items: Array(sessionItems)))
            }
        }
        return sections
    }

    private func sessionDisplayTitle(_ session: SessionInfo) -> String {
        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let preview = session.preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return preview
        }
        return session.id
    }
}
