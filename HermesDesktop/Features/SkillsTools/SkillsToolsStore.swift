import Foundation
import Observation

/// State for the Skills & Tools surface. Mirrors the reference `SkillsView`
/// data flow: `GET /api/skills` and `GET /api/tools/toolsets` (both bare JSON
/// arrays) loaded together; toggles via `PUT /api/skills/toggle` and
/// `PUT /api/tools/toolsets/{name}` with a per-row saving guard.
///
/// These endpoints exist only on the Hermes agent gateway — in v1 mode the
/// surface reports `isAvailable == false` and the view shows an explainer.
@MainActor
@Observable
final class SkillsToolsStore {
    enum Tab: String, CaseIterable {
        case skills
        case toolsets

        var title: String {
            switch self {
            case .skills: return "Skills"
            case .toolsets: return "Toolsets"
            }
        }
    }

    /// Desktop curation (reference `desktop-toolsets.ts`): platform-coupled
    /// toolsets and internal plumbing are hidden from the flat toggle list;
    /// hiding a row leaves its enabled state untouched.
    static let hiddenToolsets: Set<String> = [
        "discord", "discord_admin", "yuanbao",
        "context_engine", "moa",
    ]

    private let rest: HermesRESTClient
    private let availability: () -> Bool

    var tab: Tab = .skills
    var query = ""
    /// Active category filter chip (nil = All). Skills tab only.
    var activeCategory: String?

    private(set) var skills: [SkillInfo]?
    private(set) var toolsets: [ToolsetInfo]?
    private(set) var isRefreshing = false
    private(set) var loadError: String?
    private(set) var savingSkills: Set<String> = []
    private(set) var savingToolsets: Set<String> = []
    /// Row-level toggle failure, cleared on the next toggle/refresh.
    private(set) var toggleError: String?

    init(rest: HermesRESTClient, availability: @escaping () -> Bool) {
        self.rest = rest
        self.availability = availability
    }

    var isAvailable: Bool { availability() }
    var hasLoaded: Bool { skills != nil && toolsets != nil }

    // MARK: - Loading

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        toggleError = nil
        defer { isRefreshing = false }
        do {
            async let skillRows = rest.request("/api/skills", as: [SkillInfo].self)
            async let toolsetRows = rest.request("/api/tools/toolsets", as: [ToolsetInfo].self)
            skills = try await skillRows
            toolsets = try await toolsetRows
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Toggles

    /// Optimistic flip with revert-on-error; the row stays disabled while the
    /// server confirms (reference disables the switch while saving).
    func toggleSkill(_ skill: SkillInfo, enabled: Bool) async {
        guard !savingSkills.contains(skill.name) else { return }
        savingSkills.insert(skill.name)
        toggleError = nil
        setSkillEnabled(skill.name, enabled: enabled)
        do {
            try await rest.request("/api/skills/toggle", method: "PUT",
                                   body: .object(["name": .string(skill.name), "enabled": .bool(enabled)]))
        } catch {
            setSkillEnabled(skill.name, enabled: !enabled)
            toggleError = "Failed to update \(skill.name): \(error.localizedDescription)"
        }
        savingSkills.remove(skill.name)
    }

    func toggleToolset(_ toolset: ToolsetInfo, enabled: Bool) async {
        guard !savingToolsets.contains(toolset.name) else { return }
        savingToolsets.insert(toolset.name)
        toggleError = nil
        setToolsetEnabled(toolset.name, enabled: enabled)
        let escaped = toolset.name.addingPercentEncoding(withAllowedCharacters: .uriComponentAllowed) ?? toolset.name
        do {
            try await rest.request("/api/tools/toolsets/\(escaped)", method: "PUT",
                                   body: .object(["enabled": .bool(enabled)]))
        } catch {
            setToolsetEnabled(toolset.name, enabled: !enabled)
            toggleError = "Failed to update \(Self.displayLabel(for: toolset)): \(error.localizedDescription)"
        }
        savingToolsets.remove(toolset.name)
    }

    private func setSkillEnabled(_ name: String, enabled: Bool) {
        guard var rows = skills, let index = rows.firstIndex(where: { $0.name == name }) else { return }
        rows[index].enabled = enabled
        skills = rows
    }

    private func setToolsetEnabled(_ name: String, enabled: Bool) {
        guard var rows = toolsets, let index = rows.firstIndex(where: { $0.name == name }) else { return }
        rows[index].enabled = enabled
        // Reference also mirrors `enabled` into `available` on toggle.
        rows[index].available = enabled
        toolsets = rows
    }

    // MARK: - Filtering (reference `filteredSkills` / `filteredToolsets`)

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func category(for skill: SkillInfo) -> String {
        skill.category.isEmpty ? "general" : skill.category
    }

    /// `[(key, count)]` over ALL skills, sorted by key.
    var categories: [(key: String, count: Int)] {
        guard let skills else { return [] }
        var counts: [String: Int] = [:]
        for skill in skills {
            counts[Self.category(for: skill), default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { (key: $0.key, count: $0.value) }
    }

    var visibleSkills: [SkillInfo] {
        guard let skills else { return [] }
        let q = trimmedQuery
        return skills
            .filter { skill in
                if let activeCategory, Self.category(for: skill) != activeCategory { return false }
                guard !q.isEmpty else { return true }
                return skill.name.lowercased().contains(q)
                    || skill.description.lowercased().contains(q)
                    || skill.category.lowercased().contains(q)
            }
            .sorted { $0.name < $1.name }
    }

    /// Visible skills grouped by category, groups sorted by category key.
    var skillGroups: [(category: String, skills: [SkillInfo])] {
        var groups: [String: [SkillInfo]] = [:]
        for skill in visibleSkills {
            groups[Self.category(for: skill), default: []].append(skill)
        }
        return groups.sorted { $0.key < $1.key }.map { (category: $0.key, skills: $0.value) }
    }

    var visibleToolsets: [ToolsetInfo] {
        guard let toolsets else { return [] }
        let q = trimmedQuery
        return toolsets
            .filter { toolset in
                guard !Self.hiddenToolsets.contains(toolset.name) else { return false }
                guard !q.isEmpty else { return true }
                let label = Self.displayLabel(for: toolset)
                return toolset.name.lowercased().contains(q)
                    || label.lowercased().contains(q)
                    || toolset.label.lowercased().contains(q)
                    || toolset.description.lowercased().contains(q)
                    || toolset.tools.contains { $0.lowercased().contains(q) }
            }
            .sorted { Self.displayLabel(for: $0) < Self.displayLabel(for: $1) }
    }

    var totalSkills: Int { skills?.count ?? 0 }
    var enabledToolsetCount: Int { toolsets?.filter(\.enabled).count ?? 0 }
    var totalToolsets: Int { toolsets?.count ?? 0 }

    // MARK: - Labels (reference `helpers.ts`)

    /// `prettyName`: underscores → spaces, Title Case.
    static func prettyName(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// `toolsetDisplayLabel`: label (leading emoji stripped) falling back to name.
    static func displayLabel(for toolset: ToolsetInfo) -> String {
        let raw = toolset.label.isEmpty ? toolset.name : toolset.label
        let stripped = raw.drop { char in
            char.unicodeScalars.allSatisfy { scalar in
                scalar.properties.isEmojiPresentation
                    || scalar.properties.isEmoji && scalar.value > 0x238C
                    || scalar.properties.generalCategory == .spaceSeparator
            }
        }
        let cleaned = String(stripped).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? raw : cleaned
    }
}
