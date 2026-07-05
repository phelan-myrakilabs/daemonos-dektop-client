import SwiftUI

/// Skills & Tools surface: tabbed sub-nav (Skills | Toolsets), borderless search
/// with a refresh action, filter chips with counts, and flat rows with toggles —
/// the reference `SkillsView` anatomy. Browse Hub and per-toolset config panels
/// are later phases.
struct SkillsToolsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.hermesTheme) private var theme

    @State private var store: SkillsToolsStore?

    var body: some View {
        Group {
            if let store {
                SkillsToolsContent(store: store)
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard store == nil else { return }
            let model = self.model
            store = SkillsToolsStore(rest: model.rest) {
                model.connectionStore.settings.mode == .gateway && model.boot.isReady
            }
        }
    }
}

private struct SkillsToolsContent: View {
    @Bindable var store: SkillsToolsStore
    @Environment(\.hermesTheme) private var theme
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(theme.hairline).frame(height: 1)
            content
        }
        .background(theme.appBackground)
        .task(id: store.isAvailable) {
            if store.isAvailable, !store.hasLoaded {
                await store.refresh()
            }
        }
    }

    // MARK: - Header (tabs + search + filters)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                ForEach(SkillsToolsStore.Tab.allCases, id: \.self) { tab in
                    TextTabButton(
                        title: tab.title,
                        count: tab == .skills ? store.totalSkills : store.totalToolsets,
                        active: store.tab == tab
                    ) {
                        store.tab = tab
                    }
                }
                // Reference third tab — hub browsing is a later phase.
                TextTabButton(title: "Browse Hub", count: nil, active: false, disabled: true) {}
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                TextField(store.tab == .skills ? "Search skills..." : "Search toolsets...",
                          text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                    .focused($searchFocused)
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise") // codicon `refresh`
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(store.isRefreshing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default, value: store.isRefreshing)
                }
                .buttonStyle(.plain)
                .disabled(store.isRefreshing || !store.isAvailable)
                .help(store.isRefreshing ? "Refreshing skills" : "Refresh skills")
            }

            if store.tab == .skills, !store.categories.isEmpty {
                categoryChips
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FilterChip(label: "All", count: store.totalSkills, active: store.activeCategory == nil) {
                    store.activeCategory = nil
                }
                ForEach(store.categories, id: \.key) { category in
                    FilterChip(
                        label: SkillsToolsStore.prettyName(category.key),
                        count: category.count,
                        active: store.activeCategory == category.key
                    ) {
                        store.activeCategory = store.activeCategory == category.key ? nil : category.key
                    }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !store.isAvailable {
            CenteredState(
                title: "Skills & Tools needs the Hermes gateway",
                description: "The /api/skills and /api/tools endpoints live on the agent gateway. Switch the connection mode to Hermes gateway in Settings → Gateway to manage skills and toolsets."
            )
        } else if let error = store.loadError, !store.hasLoaded {
            CenteredState(title: "Skills failed to load", description: error) {
                Button("Retry") { Task { await store.refresh() } }
                    .buttonStyle(.bordered)
            }
        } else if !store.hasLoaded {
            CenteredState(title: "Loading capabilities...", description: "") {
                ProgressView().controlSize(.small)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let toggleError = store.toggleError {
                        Text(toggleError)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.statusError)
                            .padding(.bottom, 8)
                    }
                    if store.tab == .skills {
                        skillsList
                    } else {
                        toolsetsList
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var skillsList: some View {
        if store.visibleSkills.isEmpty {
            CenteredState(title: "No skills found", description: "Try a broader search or different category.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(store.skillGroups, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        // Category headers only in the unfiltered (All) view.
                        if store.activeCategory == nil {
                            Text(SkillsToolsStore.prettyName(group.category).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.12 * 10)
                                .foregroundStyle(theme.textTertiary)
                        }
                        VStack(spacing: 0) {
                            ForEach(group.skills, id: \.name) { skill in
                                SkillRow(skill: skill, store: store)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var toolsetsList: some View {
        if store.visibleToolsets.isEmpty {
            CenteredState(title: "No toolsets found", description: "Try a broader search query.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(store.enabledToolsetCount)/\(store.totalToolsets) toolsets enabled")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                VStack(spacing: 0) {
                    ForEach(store.visibleToolsets, id: \.name) { toolset in
                        ToolsetRow(toolset: toolset, store: store)
                    }
                }
            }
        }
    }
}

// MARK: - Rows

private struct SkillRow: View {
    let skill: SkillInfo
    let store: SkillsToolsStore

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(skill.description.isEmpty ? "No description." : skill.description)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { skill.enabled },
                set: { enabled in Task { await store.toggleSkill(skill, enabled: enabled) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(theme.accent)
            .disabled(store.savingSkills.contains(skill.name))
        }
        .padding(.vertical, 10)
    }
}

private struct ToolsetRow: View {
    let toolset: ToolsetInfo
    let store: SkillsToolsStore

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        let label = SkillsToolsStore.displayLabel(for: toolset)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusPill(active: toolset.configured,
                           text: toolset.configured ? "Configured" : "Needs keys")
                Toggle("", isOn: Binding(
                    get: { toolset.enabled },
                    set: { enabled in Task { await store.toggleToolset(toolset, enabled: enabled) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(theme.accent)
                .disabled(store.savingToolsets.contains(toolset.name))
                .help("Toggle \(label) toolset")
            }
            Text(toolset.description.isEmpty ? "No description." : toolset.description)
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
            if !toolset.tools.isEmpty {
                // Tool-name chips (mono, quinary fill).
                FlowChips(names: toolset.tools)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Small pieces

private struct TextTabButton: View {
    let title: String
    let count: Int?
    let active: Bool
    var disabled = false
    let action: () -> Void

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textDisabled)
                }
            }
            .foregroundStyle(active ? theme.textPrimary : theme.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

private struct FilterChip: View {
    let label: String
    let count: Int
    let active: Bool
    let action: () -> Void

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textDisabled)
            }
            .foregroundStyle(active ? theme.textPrimary : theme.textTertiary)
        }
        .buttonStyle(.plain)
    }
}

private struct StatusPill: View {
    let active: Bool
    let text: String

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(active ? theme.textSecondary : theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(theme.textPrimary.opacity(active ? 0.08 : 0.04))
            )
    }
}

/// Wrapping row of mono tool-name chips.
private struct FlowChips: View {
    let names: [String]

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(HermesTheme.monoFont(size: 9.5))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: HermesRadius.md)
                            .fill(theme.textPrimary.opacity(0.04))
                    )
            }
        }
        .padding(.top, 4)
    }
}

/// Minimal left-aligned wrapping layout for the tool chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        for (subview, position) in zip(subviews, arrangement.positions) {
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), positions)
    }
}

private struct CenteredState<Accessory: View>: View {
    let title: String
    let description: String
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.hermesTheme) private var theme

    init(title: String, description: String,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.description = description
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            accessory()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
