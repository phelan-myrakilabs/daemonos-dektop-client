import SwiftUI

// MARK: - Color value + mix math

/// Flat sRGB color used by the skin seed tables and the token derivation.
///
/// CSS `color-mix(in srgb, A P%, B)` interpolates *premultiplied* sRGB components:
/// `alpha = P*aA + (1-P)*aB`, `channel = (P*aA*cA + (1-P)*aB*cB) / alpha`. For two
/// opaque endpoints this collapses to the plain per-channel lerp the reference JS
/// `mix(a, b, amount)` helper performs (there in rounded 0-255 integer space; we
/// keep Double precision -- the sub-1/255 difference is invisible). A `transparent`
/// endpoint contributes weight but no hue, matching the CSS keyword. This is the
/// single place the approximation lives; every formula below goes through it.
struct HermesRGBA: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Accepts "#RGB", "#RRGGBB" or "#RRGGBBAA" (leading "#" optional).
    init(hex: String, alpha: Double = 1) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }

        var bits: UInt64 = 0
        Scanner(string: value).scanHexInt64(&bits)

        if value.count == 8 {
            self.init(
                red: Double((bits >> 24) & 0xFF) / 255,
                green: Double((bits >> 16) & 0xFF) / 255,
                blue: Double((bits >> 8) & 0xFF) / 255,
                alpha: Double(bits & 0xFF) / 255 * alpha)
        } else {
            self.init(
                red: Double((bits >> 16) & 0xFF) / 255,
                green: Double((bits >> 8) & 0xFF) / 255,
                blue: Double(bits & 0xFF) / 255,
                alpha: alpha)
        }
    }

    static let white = HermesRGBA(red: 1, green: 1, blue: 1)
    static let black = HermesRGBA(red: 0, green: 0, blue: 0)
    static let transparent = HermesRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    func withAlpha(_ value: Double) -> HermesRGBA {
        HermesRGBA(red: red, green: green, blue: blue, alpha: value)
    }

    /// `color-mix(in srgb, a P%, b)` with P = `weightOfA` in 0...1.
    static func mix(_ a: HermesRGBA, _ weightOfA: Double, _ b: HermesRGBA) -> HermesRGBA {
        let wa = weightOfA * a.alpha
        let wb = (1 - weightOfA) * b.alpha
        let alpha = wa + wb
        guard alpha > 0 else { return .transparent }
        return HermesRGBA(
            red: (wa * a.red + wb * b.red) / alpha,
            green: (wa * a.green + wb * b.green) / alpha,
            blue: (wa * a.blue + wb * b.blue) / alpha,
            alpha: alpha)
    }

    /// The reference JS `mix(a, b, amount)`: interpolation from `a` toward `b`.
    static func lerp(_ a: HermesRGBA, _ b: HermesRGBA, _ amount: Double) -> HermesRGBA {
        mix(b, amount, a)
    }

    /// Non-gamma luminance (0.2126/0.7152/0.0722) -- used ONLY for the reference's
    /// light/dark chrome bucketing rule (`renderedModeFor`, threshold 0.5).
    var naiveLuminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// WCAG relative luminance (gamma-corrected).
    var relativeLuminance: Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    static func contrastRatio(_ a: HermesRGBA, _ b: HermesRGBA) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `readableOn(hex)` from the reference color helpers.
    var readableForeground: HermesRGBA {
        relativeLuminance > 0.58 ? HermesRGBA(hex: "#161616") : .white
    }

    /// `ensureContrast(color, bg, min)`: mixes toward white (dark bg) or black
    /// (light bg) in steps of 0.2 until the ratio clears `minimum`; returns the
    /// last attempt if it never does. Used by the VS Code theme import seam
    /// (ACCENT_MIN_CONTRAST = 4.5); built-in skins never pass through it.
    func ensuringContrast(on background: HermesRGBA, minimum: Double) -> HermesRGBA {
        if Self.contrastRatio(self, background) >= minimum { return self }
        // TODO(protocol): spec does not name the light/dark predicate ensureContrast
        // uses to pick its mix target; readableOn's 0.58 relative-luminance
        // threshold is reused here for consistency.
        let target: HermesRGBA = background.relativeLuminance > 0.58 ? .black : .white
        var attempt = self
        for step in 1...5 {
            attempt = Self.lerp(self, target, Double(step) * 0.2)
            if Self.contrastRatio(attempt, background) >= minimum { return attempt }
        }
        return attempt
    }
}

// MARK: - Skin seed palette

/// Mirrors the reference `DesktopThemeColors` (~28 seed colors per skin). Optional
/// keys carry the reference fallback chains, applied in `HermesSkinDerivation`.
struct HermesSkinPalette {
    var background: HermesRGBA
    var foreground: HermesRGBA
    var card: HermesRGBA
    var cardForeground: HermesRGBA
    var muted: HermesRGBA
    var mutedForeground: HermesRGBA
    var popover: HermesRGBA
    var popoverForeground: HermesRGBA
    var primary: HermesRGBA
    var primaryForeground: HermesRGBA
    var secondary: HermesRGBA
    var secondaryForeground: HermesRGBA
    var accent: HermesRGBA
    var accentForeground: HermesRGBA
    var border: HermesRGBA
    var input: HermesRGBA
    var ring: HermesRGBA
    var midground: HermesRGBA? = nil           // falls back to ring
    var midgroundForeground: HermesRGBA? = nil // falls back to readableOn(midground)
    var composerRing: HermesRGBA? = nil        // falls back to midground
    var destructive: HermesRGBA
    var destructiveForeground: HermesRGBA
    var sidebarBackground: HermesRGBA? = nil   // falls back to background
    var sidebarBorder: HermesRGBA? = nil       // falls back to border
    var userBubble: HermesRGBA? = nil          // falls back to popover
    var userBubbleBorder: HermesRGBA? = nil    // falls back to border
}

// MARK: - Derivation (seeds -> ui -> semantic tokens)

enum HermesSkinDerivation {
    /// Per-rendered-mode constants: the neutral seeds and surface mix knobs from
    /// styles.css `:root` / `:root.dark`, plus the mode-keyed status palette,
    /// inline-code and selection values. These are global -- skins never override
    /// them; they only move the seeds fed into the formulas.
    struct ModeConstants {
        var neutralChrome: HermesRGBA
        var neutralSidebar: HermesRGBA
        var neutralCard: HermesRGBA
        var mixChrome: Double
        var mixSidebar: Double
        var mixCard: Double
        var mixElevated: Double
        var mixBubble: Double
        var red: HermesRGBA
        var green: HermesRGBA
        var yellow: HermesRGBA
        var inlineCodeBackground: HermesRGBA
        var inlineCodeForeground: HermesRGBA
        var selectionBackground: HermesRGBA

        static let light = ModeConstants(
            neutralChrome: HermesRGBA(hex: "#F3F3F3"),
            neutralSidebar: HermesRGBA(hex: "#F3F3F3"),
            neutralCard: HermesRGBA(hex: "#FCFCFC"),
            mixChrome: 0.92,
            mixSidebar: 1.0,
            mixCard: 0.22,
            mixElevated: 0.28,
            mixBubble: 0.0,
            red: HermesRGBA(hex: "#CF2D56"),
            green: HermesRGBA(hex: "#1F8A65"),
            yellow: HermesRGBA(hex: "#C08532"),
            inlineCodeBackground: HermesRGBA(hex: "#141414").withAlpha(0.05),
            inlineCodeForeground: HermesRGBA(hex: "#141414").withAlpha(0.88),
            selectionBackground: HermesRGBA(hex: "#FFD24A").withAlpha(0.55))

        static let dark = ModeConstants(
            neutralChrome: HermesRGBA(hex: "#0D0D0E"),
            neutralSidebar: HermesRGBA(hex: "#0A0A0B"),
            neutralCard: HermesRGBA(hex: "#161618"),
            mixChrome: 0.74,
            mixSidebar: 1.0,
            mixCard: 0.38,
            mixElevated: 0.46,
            mixBubble: 0.46,
            red: HermesRGBA(hex: "#E75E78"),
            green: HermesRGBA(hex: "#55A583"),
            yellow: HermesRGBA(hex: "#C08532"),
            inlineCodeBackground: HermesRGBA.white.withAlpha(0.07),
            inlineCodeForeground: HermesRGBA.white.withAlpha(0.88),
            selectionBackground: HermesRGBA(hex: "#FFD24A").withAlpha(0.38))
    }

    static func theme(from c: HermesSkinPalette) -> HermesTheme {
        // Rendered mode follows the actual background luminance (naive, > 0.5 ->
        // light), NOT the user's toggle -- a skin with a bright "dark" palette
        // renders light-chrome. Identical to the toggle for all six built-ins.
        let renderedDark = c.background.naiveLuminance <= 0.5
        let mode: ModeConstants = renderedDark ? .dark : .light

        let base = c.foreground            // --ui-base
        let accent = c.midground ?? c.ring // --ui-accent (--theme-midground)

        // --ui-bg-* surfaces: seed mixed toward the mode neutral by the knob.
        let bgChrome = HermesRGBA.mix(c.background, mode.mixChrome, mode.neutralChrome)
        let bgSidebar = HermesRGBA.mix(c.sidebarBackground ?? c.background, mode.mixSidebar, mode.neutralSidebar)
        let bgEditor = HermesRGBA.mix(c.card, mode.mixCard, mode.neutralCard)
        let bubble = HermesRGBA.mix(c.userBubble ?? c.popover, mode.mixBubble, mode.neutralCard)
        // --composer-fill opaque fallback: color-mix(card 90%, background).
        let composer = HermesRGBA.mix(bgEditor, 0.90, bgChrome)

        // --ui-text-*: ink alphas of --ui-base.
        func ink(_ alpha: Double) -> HermesRGBA { base.withAlpha(base.alpha * alpha) }
        // --ui-stroke-* / fill pattern: color-mix(accent K%, color-mix(base B%, transparent)).
        func accentInk(_ k: Double, _ b: Double) -> HermesRGBA {
            HermesRGBA.mix(accent, k, ink(b))
        }

        return HermesTheme(
            isDark: renderedDark,
            appBackground: bgChrome.color,
            chromeBackground: bgSidebar.color,
            cardBackground: bgEditor.color,
            composerBackground: composer.color,
            textPrimary: ink(0.94).color,
            textSecondary: ink(0.74).color,
            textTertiary: ink(0.54).color,
            textDisabled: ink(0.36).color,
            strokePrimary: accentInk(0.24, 0.10).color,
            strokeSecondary: accentInk(0.16, 0.07).color,
            hairline: accentInk(0.10, 0.05).color,
            accent: accent.color,
            accentForeground: (c.midgroundForeground ?? accent.readableForeground).color,
            userBubbleBackground: bubble.color,
            userBubbleBorder: (c.userBubbleBorder ?? c.border).color,
            codeBackground: mode.inlineCodeBackground.color,
            statusSuccess: mode.green.color,
            statusWarning: mode.yellow.color,
            statusError: mode.red.color)
    }

    // MARK: Extended tokens

    /// Derived tokens beyond the frozen `HermesTheme` surface: elevated/popover
    /// backgrounds, the translucent fill ladder, hover/active state fills, seed
    /// borders and destructive colors. Same formulas, exposed for UI that needs
    /// them (`HermesSkinLibrary.extras(skinName:isDark:)`).
    struct Extras {
        var elevatedBackground: Color
        /// Popover/menu/dialog surface: elevated at 96% alpha (blur behind it).
        var popoverBackground: Color
        var fillPrimary: Color
        var fillSecondary: Color
        var fillTertiary: Color
        var fillQuaternary: Color   // soft control fill (secondary button)
        var fillQuinary: Color
        var rowHover: Color
        var rowActive: Color
        var controlHover: Color
        var controlActive: Color
        var strokeQuaternary: Color
        var border: Color           // --dt-border (seed)
        var input: Color            // --dt-input (seed)
        var sidebarBorder: Color
        var composerRing: Color
        var primary: Color          // --dt-primary (seed)
        var primaryForeground: Color
        var mutedForeground: Color
        var destructive: Color
        var destructiveForeground: Color
        var inlineCodeForeground: Color
        var selectionBackground: Color
        /// Scrollbar thumb: midground at 18% (hover 40%; portals 28%/50%).
        var scrollbarThumb: Color
    }

    static func extras(from c: HermesSkinPalette) -> Extras {
        let renderedDark = c.background.naiveLuminance <= 0.5
        let mode: ModeConstants = renderedDark ? .dark : .light

        let base = c.foreground
        let accent = c.midground ?? c.ring
        let elevated = HermesRGBA.mix(c.popover, mode.mixElevated, mode.neutralCard)

        func accentInk(_ k: Double, _ b: Double) -> HermesRGBA {
            HermesRGBA.mix(accent, k, base.withAlpha(base.alpha * b))
        }

        return Extras(
            elevatedBackground: elevated.color,
            popoverBackground: elevated.withAlpha(elevated.alpha * 0.96).color,
            fillPrimary: accentInk(0.16, 0.10).color,
            fillSecondary: accentInk(0.11, 0.07).color,
            fillTertiary: accentInk(0.08, 0.05).color,
            fillQuaternary: accentInk(0.05, 0.04).color,
            fillQuinary: accentInk(0.03, 0.03).color,
            rowHover: accentInk(0.04, 0.03).color,
            rowActive: accentInk(0.08, 0.05).color,
            controlHover: accentInk(0.06, 0.04).color,
            controlActive: accentInk(0.08, 0.05).color,
            strokeQuaternary: accentInk(0.06, 0.03).color,
            border: c.border.color,
            input: c.input.color,
            sidebarBorder: (c.sidebarBorder ?? c.border).color,
            composerRing: (c.composerRing ?? accent).color,
            primary: c.primary.color,
            primaryForeground: c.primaryForeground.color,
            mutedForeground: c.mutedForeground.color,
            destructive: c.destructive.color,
            destructiveForeground: c.destructiveForeground.color,
            inlineCodeForeground: mode.inlineCodeForeground.color,
            selectionBackground: mode.selectionBackground.color,
            scrollbarThumb: accent.withAlpha(accent.alpha * 0.18).color)
    }

    // MARK: synthLightColors

    /// Light palette for dark-only skins, ported verbatim from `synthLightColors`.
    /// `lerp(a, b, t)` below is the reference `mix(a, b, amount)`.
    static func synthesizedLightPalette(from seed: HermesSkinPalette) -> HermesSkinPalette {
        let accent = seed.ring
        let soft = HermesRGBA.lerp(.white, accent, 0.10)
        let softer = HermesRGBA.lerp(.white, accent, 0.06)
        let border = HermesRGBA.lerp(HermesRGBA(hex: "#ECECEF"), accent, 0.14)
        let midground = seed.midground ?? accent
        let ink = HermesRGBA(hex: "#161616")

        return HermesSkinPalette(
            background: .white,
            foreground: ink,
            card: .white,
            cardForeground: ink,
            muted: softer,
            mutedForeground: HermesRGBA.lerp(HermesRGBA(hex: "#6B6B70"), accent, 0.16),
            popover: .white,
            popoverForeground: ink,
            primary: accent,
            primaryForeground: accent.readableForeground,
            secondary: soft,
            secondaryForeground: HermesRGBA.lerp(HermesRGBA(hex: "#2A2A2A"), accent, 0.34),
            accent: soft,
            accentForeground: HermesRGBA.lerp(HermesRGBA(hex: "#2A2A2A"), accent, 0.34),
            border: border,
            input: HermesRGBA.lerp(HermesRGBA(hex: "#E2E2E6"), accent, 0.18),
            ring: accent,
            midground: midground,
            midgroundForeground: midground.readableForeground,
            destructive: HermesRGBA(hex: "#B94A3A"),
            destructiveForeground: .white,
            sidebarBackground: HermesRGBA.lerp(HermesRGBA(hex: "#FAFAFA"), accent, 0.05),
            sidebarBorder: border,
            userBubble: soft,
            userBubbleBorder: border)
    }
}
