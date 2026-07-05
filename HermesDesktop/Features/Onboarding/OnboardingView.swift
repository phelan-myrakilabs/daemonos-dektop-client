import SwiftUI

/// First-run welcome card over a dim backdrop. Shown while `OnboardingState.shouldShow`
/// is true; "Get started" completes it, "Open Settings…" jumps to the connection form
/// (first run needs a credential before the app can connect).
struct OnboardingView: View {
    @Environment(OnboardingState.self) private var onboarding
    @Environment(\.hermesTheme) private var theme
    @Environment(\.openSettings) private var openSettings

    private struct Point: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
    }

    private let points: [Point] = [
        Point(icon: "bolt.horizontal.circle",
              text: "Chat with the Hermes agent — it streams answers, runs tools, and shows its work."),
        Point(icon: "wand.and.stars",
              text: "Browse Skills & Tools, resume past sessions, and jump anywhere with ⌘K."),
        Point(icon: "lock.shield",
              text: "Connect over your Cloudflare endpoints. Your credential stays in the macOS Keychain."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("HERMES AGENT")
                        .font(HermesTheme.wordmarkFont(size: 40))
                        .tracking(0.08 * 40)
                        .foregroundStyle(theme.isDark ? theme.textPrimary.opacity(0.9) : theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Welcome — a native, remote client for your Hermes gateway.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(points) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: point.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(theme.primary)
                                .frame(width: 18)
                                .padding(.top, 1)
                            Text(point.text)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button("Open Settings…") {
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Get started") {
                        onboarding.complete()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 440)
            .background(theme.userBubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.xl, style: .continuous)
                    .strokeBorder(theme.strokePrimary, lineWidth: 1)
            )
            .hermesShadow(HermesShadow.overlay)
        }
        .transition(.opacity)
    }
}
