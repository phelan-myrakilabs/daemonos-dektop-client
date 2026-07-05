import SwiftUI

/// New-session intro: fit-to-width "HERMES AGENT" wordmark over a faint radial
/// accent wash, with one randomly chosen body line per appearance (the reference
/// picks per mount from intro-copy.jsonl; these are its five `none` entries).
/// The docked composer slot is owned by ShellRootView.
struct EmptyStateView: View {
    @Environment(\.hermesTheme) private var theme

    @State private var introLine = EmptyStateView.introBodies.randomElement() ?? ""

    static let introBodies: [String] = [
        "Ask a question, paste an error, or point me at a repo. I can read code, run tools, and help you ship.",
        "Describe the task in your own words. I'll pick the right tools, explain my plan, and check in before risky steps.",
        "Drop a file path, a traceback, or a rough idea. I'll investigate, suggest next steps, and keep things reversible.",
        "Search the repo, edit files, run tests, open PRs. Tell me the goal and I'll handle the mechanical parts.",
        "Type a task, question, or snippet. I remember the session, cite my sources, and stop to ask when I'm unsure.",
    ]

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [theme.accent.opacity(0.03), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 420
            )
            VStack(spacing: 4) {
                WordmarkText()
                Text(introLine)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6) // line-height 1.45 at 14pt
                    .frame(maxWidth: 544) // 34rem readable cap
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// Fit-to-width wordmark with a 44pt floor: descending fixed-size candidates,
/// ViewThatFits picks the largest that fits (last one may clip — the floor).
private struct WordmarkText: View {
    @Environment(\.hermesTheme) private var theme

    private static let candidateSizes: [CGFloat] = [
        220, 190, 165, 145, 128, 112, 98, 86, 76, 66, 58, 50, 44,
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.candidateSizes, id: \.self) { size in
                line(size: size)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8) // reference w-[calc(100%-1rem)]
        .accessibilityLabel("HERMES AGENT")
    }

    private func line(size: CGFloat) -> some View {
        Text("HERMES AGENT")
            .font(HermesTheme.wordmarkFont(size: size))
            .tracking(0.08 * size) // 0.08em
            .lineLimit(1)
            .fixedSize()
            // Light: accent (reference text-midground); dark: foreground at 90%.
            .foregroundStyle(theme.isDark ? theme.textPrimary.opacity(0.9) : theme.accent)
    }
}
