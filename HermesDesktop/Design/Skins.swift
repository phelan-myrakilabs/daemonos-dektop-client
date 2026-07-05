import SwiftUI

/// Skin registry + resolution. Six built-ins carrying the exact reference seed
/// tables (`themes/presets.ts`); semantic tokens are derived by
/// `HermesSkinDerivation` using the styles.css color-mix formulas.
///
/// Only `nous` ships a hand-tuned dark palette alongside its light one. The other
/// five are dark-only seeds whose light mode is synthesized (`synthLightColors`).
enum HermesSkinLibrary {
    /// Registry order — also the `/skin` cycling order.
    static let skinOrder = ["nous", "midnight", "ember", "mono", "cyberpunk", "slate"]

    static let defaultSkinName = "nous"

    /// `/skin` command aliases + retired skin names, mapped to registry names.
    static let skinAliases: [String: String] = [
        "ares": "ember",
        "default": "nous",
        "gold": "nous",
        "hermes": "nous",
        "nous-light": "nous",
    ]

    struct SkinInfo: Identifiable {
        var name: String
        var label: String
        var description: String
        var id: String { name }
    }

    static var availableSkins: [SkinInfo] {
        skinOrder.compactMap { name in
            skins[name].map { SkinInfo(name: name, label: $0.label, description: $0.description) }
        }
    }

    /// Case-insensitive name/alias normalization; nil when unknown.
    static func canonicalName(_ raw: String) -> String? {
        let lowered = raw.lowercased()
        let name = skinAliases[lowered] ?? lowered
        return skins[name] != nil ? name : nil
    }

    static func resolve(skinName: String, isDark: Bool) -> HermesTheme {
        HermesSkinDerivation.theme(from: palette(skinName: skinName, isDark: isDark))
    }

    /// Derived tokens beyond the frozen `HermesTheme` surface (hover/active fills,
    /// elevated/popover surfaces, seed borders, destructive, selection, …).
    static func extras(skinName: String, isDark: Bool) -> HermesSkinDerivation.Extras {
        HermesSkinDerivation.extras(from: palette(skinName: skinName, isDark: isDark))
    }

    private static func palette(skinName: String, isDark: Bool) -> HermesSkinPalette {
        let skin = canonicalName(skinName).flatMap { skins[$0] } ?? nous
        return skin.palette(isDark: isDark)
    }

    // MARK: - Registry

    private struct Skin {
        var label: String
        var description: String
        /// Light palette when `darkColors` exists; otherwise the (dark) seed palette.
        var colors: HermesSkinPalette
        var darkColors: HermesSkinPalette? = nil

        func palette(isDark: Bool) -> HermesSkinPalette {
            if isDark { return darkColors ?? colors }
            return darkColors != nil
                ? colors
                : HermesSkinDerivation.synthesizedLightPalette(from: colors)
        }
    }

    private static let skins: [String: Skin] = [
        "nous": nous,
        "midnight": midnight,
        "ember": ember,
        "mono": mono,
        "cyberpunk": cyberpunk,
        "slate": slate,
    ]

    // MARK: nous

    private static let nousBlue = HermesRGBA(hex: "#0053FD")

    /// `nousTint(p) = color-mix(in srgb, #0053FD p%, #FFFFFF)`
    private static func nousTint(_ p: Double) -> HermesRGBA {
        HermesRGBA.mix(nousBlue, p / 100, .white)
    }

    /// `nousTintTransparent(p) = color-mix(in srgb, #0053FD p%, transparent)`
    private static func nousTintTransparent(_ p: Double) -> HermesRGBA {
        nousBlue.withAlpha(p / 100)
    }

    private static let nous = Skin(
        label: "Nous",
        description: "Glass neutrals with Nous blue accents",
        colors: HermesSkinPalette(
            background: HermesRGBA(hex: "#F8FAFF"),
            foreground: HermesRGBA(hex: "#17171A"),
            card: HermesRGBA(hex: "#FFFFFF"),
            cardForeground: HermesRGBA(hex: "#17171A"),
            muted: nousTint(5),
            mutedForeground: HermesRGBA(hex: "#666678"),
            popover: HermesRGBA(hex: "#FFFFFF"),
            popoverForeground: HermesRGBA(hex: "#17171A"),
            primary: nousBlue,
            primaryForeground: HermesRGBA(hex: "#FCFCFC"),
            secondary: nousTint(7),
            secondaryForeground: HermesRGBA(hex: "#242432"),
            accent: nousTint(10),
            accentForeground: HermesRGBA(hex: "#202030"),
            border: nousTintTransparent(22),
            input: nousTintTransparent(30),
            ring: nousBlue,
            midground: nousBlue,
            composerRing: nousBlue,
            destructive: HermesRGBA(hex: "#C72E4D"),
            destructiveForeground: HermesRGBA(hex: "#FFFFFF"),
            sidebarBackground: HermesRGBA(hex: "#F3F7FF"),
            sidebarBorder: nousTintTransparent(18),
            userBubble: nousTint(6),
            userBubbleBorder: nousTintTransparent(24)),
        darkColors: HermesSkinPalette(
            background: HermesRGBA(hex: "#0D2F86"),
            foreground: HermesRGBA(hex: "#FFE6CB"),
            card: HermesRGBA(hex: "#12378F"),
            cardForeground: HermesRGBA(hex: "#FFE6CB"),
            muted: HermesRGBA(hex: "#183F9A"),
            mutedForeground: HermesRGBA(hex: "#B5C7F3"),
            popover: HermesRGBA(hex: "#123A96"),
            popoverForeground: HermesRGBA(hex: "#FFE6CB"),
            primary: HermesRGBA(hex: "#FFE6CB"),
            primaryForeground: HermesRGBA(hex: "#0D2F86"),
            secondary: HermesRGBA(hex: "#1B45A4"),
            secondaryForeground: HermesRGBA(hex: "#E0E8FF"),
            accent: HermesRGBA(hex: "#1540B1"),
            accentForeground: HermesRGBA(hex: "#F0F4FF"),
            border: HermesRGBA(hex: "#3158AD"),
            input: HermesRGBA(hex: "#0B2566"),
            ring: HermesRGBA(hex: "#FFE6CB"),
            midground: nousBlue,
            composerRing: HermesRGBA(hex: "#FFE6CB"),
            destructive: HermesRGBA(hex: "#C0473A"),
            destructiveForeground: HermesRGBA(hex: "#FEF2F2"),
            sidebarBackground: HermesRGBA(hex: "#09286F"),
            sidebarBorder: HermesRGBA(hex: "#234A9C"),
            userBubble: HermesRGBA(hex: "#143B91"),
            userBubbleBorder: HermesRGBA(hex: "#3A63BD")))

    // MARK: midnight (dark-only)

    private static let midnight = Skin(
        label: "Midnight",
        description: "Deep blue-violet with cool accents",
        colors: HermesSkinPalette(
            background: HermesRGBA(hex: "#08081C"),
            foreground: HermesRGBA(hex: "#DDD6FF"),
            card: HermesRGBA(hex: "#0D0D28"),
            cardForeground: HermesRGBA(hex: "#DDD6FF"),
            muted: HermesRGBA(hex: "#13133A"),
            mutedForeground: HermesRGBA(hex: "#7C7AB0"),
            popover: HermesRGBA(hex: "#0F0F2E"),
            popoverForeground: HermesRGBA(hex: "#DDD6FF"),
            primary: HermesRGBA(hex: "#DDD6FF"),
            primaryForeground: HermesRGBA(hex: "#08081C"),
            secondary: HermesRGBA(hex: "#1A1A4A"),
            secondaryForeground: HermesRGBA(hex: "#C4BFF0"),
            accent: HermesRGBA(hex: "#1A1A44"),
            accentForeground: HermesRGBA(hex: "#D0C8FF"),
            border: HermesRGBA(hex: "#1E1E52"),
            input: HermesRGBA(hex: "#1E1E52"),
            ring: HermesRGBA(hex: "#8B80E8"),
            midground: HermesRGBA(hex: "#8B80E8"),
            destructive: HermesRGBA(hex: "#B03060"),
            destructiveForeground: HermesRGBA(hex: "#FEF2F2"),
            sidebarBackground: HermesRGBA(hex: "#06061A"),
            sidebarBorder: HermesRGBA(hex: "#12123A"),
            userBubble: HermesRGBA(hex: "#14143A"),
            userBubbleBorder: HermesRGBA(hex: "#242466")))

    // MARK: ember (dark-only)

    private static let ember = Skin(
        label: "Ember",
        description: "Warm crimson and bronze — forge vibes",
        colors: HermesSkinPalette(
            background: HermesRGBA(hex: "#160800"),
            foreground: HermesRGBA(hex: "#FFD8B0"),
            card: HermesRGBA(hex: "#1E0E04"),
            cardForeground: HermesRGBA(hex: "#FFD8B0"),
            muted: HermesRGBA(hex: "#2A1408"),
            mutedForeground: HermesRGBA(hex: "#AA7A56"),
            popover: HermesRGBA(hex: "#221008"),
            popoverForeground: HermesRGBA(hex: "#FFD8B0"),
            primary: HermesRGBA(hex: "#FFD8B0"),
            primaryForeground: HermesRGBA(hex: "#160800"),
            secondary: HermesRGBA(hex: "#341800"),
            secondaryForeground: HermesRGBA(hex: "#F0C090"),
            accent: HermesRGBA(hex: "#301600"),
            accentForeground: HermesRGBA(hex: "#E8C080"),
            border: HermesRGBA(hex: "#3A1C08"),
            input: HermesRGBA(hex: "#3A1C08"),
            ring: HermesRGBA(hex: "#D97316"),
            midground: HermesRGBA(hex: "#D97316"),
            destructive: HermesRGBA(hex: "#C43010"),
            destructiveForeground: HermesRGBA(hex: "#FEF2F2"),
            sidebarBackground: HermesRGBA(hex: "#100600"),
            sidebarBorder: HermesRGBA(hex: "#2A1004"),
            userBubble: HermesRGBA(hex: "#2A1000"),
            userBubbleBorder: HermesRGBA(hex: "#4A2010")))

    // MARK: mono (dark-only)

    private static let mono = Skin(
        label: "Mono",
        description: "Clean grayscale — minimal and focused",
        colors: HermesSkinPalette(
            background: HermesRGBA(hex: "#0E0E0E"),
            foreground: HermesRGBA(hex: "#EAEAEA"),
            card: HermesRGBA(hex: "#141414"),
            cardForeground: HermesRGBA(hex: "#EAEAEA"),
            muted: HermesRGBA(hex: "#1E1E1E"),
            mutedForeground: HermesRGBA(hex: "#808080"),
            popover: HermesRGBA(hex: "#181818"),
            popoverForeground: HermesRGBA(hex: "#EAEAEA"),
            primary: HermesRGBA(hex: "#EAEAEA"),
            primaryForeground: HermesRGBA(hex: "#0E0E0E"),
            secondary: HermesRGBA(hex: "#262626"),
            secondaryForeground: HermesRGBA(hex: "#C8C8C8"),
            accent: HermesRGBA(hex: "#222222"),
            accentForeground: HermesRGBA(hex: "#D8D8D8"),
            border: HermesRGBA(hex: "#2A2A2A"),
            input: HermesRGBA(hex: "#2A2A2A"),
            ring: HermesRGBA(hex: "#9A9A9A"),
            midground: HermesRGBA(hex: "#9A9A9A"),
            destructive: HermesRGBA(hex: "#A84040"),
            destructiveForeground: HermesRGBA(hex: "#FEF2F2"),
            sidebarBackground: HermesRGBA(hex: "#0A0A0A"),
            sidebarBorder: HermesRGBA(hex: "#202020"),
            userBubble: HermesRGBA(hex: "#1A1A1A"),
            userBubbleBorder: HermesRGBA(hex: "#363636")))

    // MARK: cyberpunk (dark-only)

    private static let cyberpunk = Skin(
        label: "Cyberpunk",
        description: "Neon green on black — matrix terminal",
        colors: HermesSkinPalette(
            background: HermesRGBA(hex: "#000A00"),
            foreground: HermesRGBA(hex: "#00FF41"),
            card: HermesRGBA(hex: "#001200"),
            cardForeground: HermesRGBA(hex: "#00FF41"),
            muted: HermesRGBA(hex: "#001A00"),
            mutedForeground: HermesRGBA(hex: "#1A8A30"),
            popover: HermesRGBA(hex: "#001000"),
            popoverForeground: HermesRGBA(hex: "#00FF41"),
            primary: HermesRGBA(hex: "#00FF41"),
            primaryForeground: HermesRGBA(hex: "#000A00"),
            secondary: HermesRGBA(hex: "#002800"),
            secondaryForeground: HermesRGBA(hex: "#00CC34"),
            accent: HermesRGBA(hex: "#002000"),
            accentForeground: HermesRGBA(hex: "#00E038"),
            border: HermesRGBA(hex: "#003000"),
            input: HermesRGBA(hex: "#003000"),
            ring: HermesRGBA(hex: "#00FF41"),
            midground: HermesRGBA(hex: "#00FF41"),
            destructive: HermesRGBA(hex: "#FF003C"),
            destructiveForeground: HermesRGBA(hex: "#000A00"),
            sidebarBackground: HermesRGBA(hex: "#000600"),
            sidebarBorder: HermesRGBA(hex: "#001800"),
            userBubble: HermesRGBA(hex: "#001400"),
            userBubbleBorder: HermesRGBA(hex: "#004800")))

    // MARK: slate (dark-only)

    private static let slate = Skin(
        label: "Slate",
        description: "Cool slate blue — focused developer theme",
        colors: HermesSkinPalette(
            background: HermesRGBA(hex: "#0D1117"),
            foreground: HermesRGBA(hex: "#C9D1D9"),
            card: HermesRGBA(hex: "#161B22"),
            cardForeground: HermesRGBA(hex: "#C9D1D9"),
            muted: HermesRGBA(hex: "#21262D"),
            mutedForeground: HermesRGBA(hex: "#8B949E"),
            popover: HermesRGBA(hex: "#1C2128"),
            popoverForeground: HermesRGBA(hex: "#C9D1D9"),
            primary: HermesRGBA(hex: "#C9D1D9"),
            primaryForeground: HermesRGBA(hex: "#0D1117"),
            secondary: HermesRGBA(hex: "#2A3038"),
            secondaryForeground: HermesRGBA(hex: "#ADB5BF"),
            accent: HermesRGBA(hex: "#1E2530"),
            accentForeground: HermesRGBA(hex: "#C0C8D0"),
            border: HermesRGBA(hex: "#30363D"),
            input: HermesRGBA(hex: "#30363D"),
            ring: HermesRGBA(hex: "#58A6FF"),
            midground: HermesRGBA(hex: "#58A6FF"),
            destructive: HermesRGBA(hex: "#CF4848"),
            destructiveForeground: HermesRGBA(hex: "#FEF2F2"),
            sidebarBackground: HermesRGBA(hex: "#090D13"),
            sidebarBorder: HermesRGBA(hex: "#1C2228"),
            userBubble: HermesRGBA(hex: "#1E2A38"),
            userBubbleBorder: HermesRGBA(hex: "#2E4060")))
}
