import SwiftUI

/// Full-window boot layer shown while `bootProgress.visible` (reference
/// gateway-connecting overlay at z-1200 and boot-failure overlay at z-1400).
struct BootOverlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.hermesTheme) private var theme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            theme.appBackground
                .ignoresSafeArea()
            if let error = model.boot.bootProgress.error {
                errorCard(error)
            } else {
                connecting
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Connecting

    /// Mono, uppercase, wide-tracked "CONNECTING" word in `--theme-primary`
    /// (the reference scrambles the tail; the scramble animation is Phase 2).
    private var connecting: some View {
        let boot = model.boot.bootProgress
        return VStack(spacing: 16) {
            Text("CONNECTING")
                .font(HermesTheme.monoFont(size: 10.5).weight(.semibold))
                .tracking(0.4 * 10.5) // 0.4em
                .foregroundStyle(theme.primary)
            Text(boot.message)
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
            ProgressView(value: Double(boot.progress), total: 100)
                .progressViewStyle(.linear)
                .tint(theme.primary)
                .frame(width: 220)
        }
        .padding(24)
    }

    // MARK: - Failure

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle") // Lucide `AlertCircle`
                    .font(.system(size: 18))
                    .foregroundStyle(theme.statusError)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Desktop boot failed")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Hermes Desktop could not finish connecting to the gateway.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: HermesRadius.xl2, style: .continuous) // rounded-2xl
                        .fill(theme.statusError.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HermesRadius.xl2, style: .continuous)
                        .stroke(theme.statusError.opacity(0.3), lineWidth: 1)
                )
            HStack(spacing: 8) {
                Button("Retry") { // Lucide `RefreshCw`
                    model.boot.retryBoot()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                Button("Open Settings…") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: 640) // reference max-w-[40rem]
        .background(
            RoundedRectangle(cornerRadius: HermesRadius.xl, style: .continuous) // rounded-xl
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.xl, style: .continuous)
                .stroke(theme.strokeSecondary, lineWidth: 1)
        )
        .padding(24)
    }
}
