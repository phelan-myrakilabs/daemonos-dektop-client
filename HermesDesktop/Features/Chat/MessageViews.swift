import SwiftUI

// MARK: - User message (bordered pill, right-aligned)

struct UserMessageView: View {
    let text: String

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 12) // px-3
                .padding(.vertical, 8)    // py-2
                .background(theme.userBubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: HermesTheme.radius(12)))
                .overlay(
                    RoundedRectangle(cornerRadius: HermesTheme.radius(12))
                        .strokeBorder(theme.userBubbleBorder, lineWidth: 1)
                )
                .frame(maxWidth: HermesTheme.contentColumnMaxWidth * 0.66, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Assistant message (plain prose, no bubble)

struct AssistantMessageView: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        MarkdownText(text: text)
            .textSelection(.enabled)
            .padding(.leading, 12) // --message-text-indent
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tool row (flat 11pt disclosure row)

struct ToolRowView: View {
    let row: ToolRowModel

    @Environment(\.hermesTheme) private var theme
    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if isExpanded, row.hasExpandableContent {
                expandedBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovering = $0 }
    }

    private var header: some View {
        Button {
            guard row.hasExpandableContent else { return }
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                statusGlyph
                    .frame(width: 14, height: 14)
                Text(ToolRowMeta.title(for: row))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(titleColor)
                if !row.context.isEmpty {
                    Text(row.context)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let duration = row.durationSeconds {
                    Text(ToolRowMeta.durationLabel(duration))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(theme.textTertiary)
                }
                if row.hasExpandableContent, isHovering || isExpanded {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch row.state {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(theme.statusError)
        case .success:
            // Silent success: the tool's own icon, no checkmark.
            Image(systemName: ToolRowMeta.symbol(for: row.name))
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var titleColor: Color {
        switch row.state {
        case .running: return theme.textTertiary
        case .error: return theme.statusError
        case .success: return theme.textSecondary
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let diff = row.inlineDiff, !diff.isEmpty {
                detailBlock(diff)
            }
            if let detail = row.detail, !detail.isEmpty {
                detailBlock(String(detail.prefix(4_000)))
            }
        }
        .padding(6)
        .background(theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: HermesTheme.radius(5)))
        .overlay(
            RoundedRectangle(cornerRadius: HermesTheme.radius(5))
                .strokeBorder(theme.strokeSecondary, lineWidth: 1)
        )
        .padding(.leading, 20)
    }

    private func detailBlock(_ text: String) -> some View {
        ScrollView(.vertical) {
            Text(text)
                .font(HermesTheme.monoFont(size: 11))
                .foregroundStyle(theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
    }
}

/// Tool icon (SF symbol standing in for the reference codicons) + title copy
/// from the reference `TOOL_META` table.
enum ToolRowMeta {
    private static let meta: [String: (symbol: String, done: String, pending: String)] = [
        "browser_click": ("globe", "Clicked page element", "Clicking page element"),
        "browser_fill": ("globe", "Filled form field", "Filling form field"),
        "browser_navigate": ("globe", "Opened page", "Opening page"),
        "browser_snapshot": ("globe", "Captured page snapshot", "Capturing page snapshot"),
        "browser_take_screenshot": ("photo", "Captured screenshot", "Capturing screenshot"),
        "browser_type": ("globe", "Typed on page", "Typing on page"),
        "clarify": ("questionmark.circle", "Asked a question", "Asking a question"),
        "cronjob": ("clock", "Cron job", "Scheduling cron job"),
        "edit_file": ("pencil", "Edited file", "Editing file"),
        "execute_code": ("terminal", "Ran code", "Scripting"),
        "image_generate": ("photo", "Generated image", "Generating image"),
        "list_files": ("folder", "Listed files", "Listing files"),
        "patch": ("pencil", "Patched file", "Patching file"),
        "read_file": ("doc.text", "Read file", "Reading file"),
        "search_files": ("magnifyingglass", "Searched files", "Searching files"),
        "session_search_recall": ("magnifyingglass", "Searched session history", "Searching session history"),
        "terminal": ("terminal", "Ran command", "Running command"),
        "todo": ("checklist", "Updated todos", "Updating todos"),
        "vision_analyze": ("eye", "Analyzed image", "Analyzing image"),
        "web_extract": ("globe", "Read webpage", "Reading webpage"),
        "web_search": ("magnifyingglass", "Searched web", "Searching web"),
        "write_file": ("pencil", "Edited file", "Editing file"),
    ]

    static func symbol(for name: String) -> String {
        if let entry = meta[name] { return entry.symbol }
        if name.hasPrefix("browser_") || name.hasPrefix("web_") { return "globe" }
        return "wrench.and.screwdriver"
    }

    static func title(for row: ToolRowModel) -> String {
        if let entry = meta[row.name] {
            return row.state == .running ? entry.pending : entry.done
        }
        let cleaned = row.name
            .replacingOccurrences(of: "browser_", with: "")
            .replacingOccurrences(of: "web_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return row.state == .running ? "Running \(cleaned)" : cleaned
    }

    static func durationLabel(_ seconds: Double) -> String {
        if seconds < 10 { return String(format: "%.1fs", seconds) }
        if seconds < 60 { return "\(Int(seconds.rounded()))s" }
        let minutes = Int(seconds) / 60
        let rest = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, rest)
    }
}

// MARK: - Thinking disclosure

/// Collapsed by default; auto-opens while its group streams and auto-collapses
/// on completion — the first explicit user toggle wins permanently.
struct ThinkingDisclosureView: View {
    let group: ThinkingGroupModel

    @Environment(\.hermesTheme) private var theme
    @State private var userChoice: Bool?

    private var isExpanded: Bool {
        userChoice ?? group.streaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                userChoice = !isExpanded
            } label: {
                HStack(spacing: 6) {
                    Text("Thinking")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .opacity(group.streaming ? 0.75 : 1)
                    if group.streaming {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                MarkdownText(text: group.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .opacity(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: group.streaming && userChoice == nil ? 160 : nil,
                           alignment: .bottom)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status note / inline error

struct StatusNoteView: View {
    let text: String

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct InlineErrorView: View {
    let message: String

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
        .foregroundStyle(theme.statusError)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }
}
