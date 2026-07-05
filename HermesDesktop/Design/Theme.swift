import SwiftUI
import Observation

/// Semantic design tokens resolved for the current skin + mode. The reference derives
/// these from ~28 skin seed colors via CSS color-mix formulas; `Skins.swift` owns the
/// exact seed tables and derivation. This file is the stable contract the UI builds
/// against.
struct HermesTheme: Equatable {
    var isDark: Bool

    // Surfaces
    var appBackground: Color
    var chromeBackground: Color      // titlebar / sidebar / statusbar chrome
    var cardBackground: Color
    var composerBackground: Color

    // Text ladder
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var textDisabled: Color

    // Strokes / hairlines
    var strokePrimary: Color
    var strokeSecondary: Color
    var hairline: Color

    // Accent
    var accent: Color                // --theme-midground (#0053FD in nous light)
    var accentForeground: Color
    var primary: Color               // --theme-primary (skin primary seed)
    var primaryForeground: Color
    var composerRing: Color          // composer focus ring (composerRing over input)

    // Chat
    var userBubbleBackground: Color
    var userBubbleBorder: Color
    var codeBackground: Color

    // Status
    var statusSuccess: Color
    var statusWarning: Color
    var statusError: Color

    // MARK: Layout constants (from styles.css / layout-constants.ts)

    static let sidebarWidth: CGFloat = 237
    static let titlebarHeight: CGFloat = 34
    static let statusBarHeight: CGFloat = 20
    /// Shared transcript/composer column: 48.75rem = 780pt.
    static let contentColumnMaxWidth: CGFloat = 780
    static let sessionRowHeight: CGFloat = 26
    /// Every radius in the app is multiplied by --radius-scalar.
    static let radiusScalar: CGFloat = 0.6

    static func radius(_ base: CGFloat) -> CGFloat { base * radiusScalar }

    // MARK: Typography

    /// The reference wordmark face is the bundled "Collapse Bold" (private package,
    /// license unverified) — deliberately substituted with the system serif.
    static func wordmarkFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    static func monoFont(size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

/// Current skin + light/dark mode. Persisted; `toggleMode` mirrors the reference
/// `appearance.toggleMode` keybind (Shift+X); skin cycling mirrors `/skin next`.
@MainActor
@Observable
final class ThemeStore {
    private static let skinKey = "appearance.skin"
    private static let modeKey = "appearance.mode"

    private(set) var skinName: String
    private(set) var isDark: Bool
    private(set) var theme: HermesTheme

    init(defaults: UserDefaults = .standard) {
        let skin = defaults.string(forKey: Self.skinKey) ?? "nous"
        let dark = defaults.object(forKey: Self.modeKey) as? Bool ?? false
        self.skinName = skin
        self.isDark = dark
        self.theme = ThemeStore.resolve(skinName: skin, isDark: dark)
    }

    func toggleMode() {
        isDark.toggle()
        UserDefaults.standard.set(isDark, forKey: Self.modeKey)
        theme = ThemeStore.resolve(skinName: skinName, isDark: isDark)
    }

    func setSkin(_ name: String) {
        skinName = name
        UserDefaults.standard.set(name, forKey: Self.skinKey)
        theme = ThemeStore.resolve(skinName: skinName, isDark: isDark)
    }

    /// Resolution hook — Skins.swift provides the full registry + derivation.
    static func resolve(skinName: String, isDark: Bool) -> HermesTheme {
        HermesSkinLibrary.resolve(skinName: skinName, isDark: isDark)
    }
}

extension EnvironmentValues {
    @Entry var hermesTheme: HermesTheme = HermesSkinLibrary.resolve(skinName: "nous", isDark: false)
}
