import SwiftUI

// Reference design constants beyond the frozen HermesTheme surface. All values
// converted at 1rem = 16pt.

// MARK: - Radii

/// Radius ladder, each already multiplied by `HermesTheme.radiusScalar` (0.6).
enum HermesRadius {
    static let xs = HermesTheme.radius(2)    // --radius-xs (0.125rem)
    static let sm = HermesTheme.radius(8)    // --radius-sm (0.5rem)
    static let md = HermesTheme.radius(10)   // --radius-md (0.625rem)
    static let lg = HermesTheme.radius(12)   // --radius-lg (0.75rem)
    static let xl = HermesTheme.radius(16)   // --radius-xl (1rem)
    static let xl2 = HermesTheme.radius(24)  // --radius-2xl (1.5rem)
    static let xl3 = HermesTheme.radius(32)  // --radius-3xl (2rem)
    static let xl4 = HermesTheme.radius(40)  // --radius-4xl (2.5rem)
    /// Icon buttons share a fixed 4pt radius (unscaled); text buttons are square.
    static let iconButton: CGFloat = 4
    /// Composer drag-region hatch frame (0.4rem, unscaled).
    static let composerHatch: CGFloat = 6.4
}

// MARK: - Shadows

/// One black drop-shadow layer. SwiftUI has no spread parameter; negative spreads
/// (which pool the reference shadows below the panel) are approximated by folding
/// spread into the blur: radius = max(0, (blur + spread) / 2).
struct HermesShadowLayer: Equatable {
    var opacity: Double
    var y: CGFloat
    var blur: CGFloat
    var spread: CGFloat = 0
}

enum HermesShadow {
    /// --shadow-nous — THE overlay shadow. Pair with a 1pt hairline stroke of the
    /// current text color at `overlayHairlineAlpha` (--stroke-nous), never a border.
    static let overlay: [HermesShadowLayer] = [
        HermesShadowLayer(opacity: 0.07, y: 2, blur: 4, spread: -2),
        HermesShadowLayer(opacity: 0.06, y: 8, blur: 12, spread: -6),
        HermesShadowLayer(opacity: 0.06, y: 20, blur: 28, spread: -14),
        HermesShadowLayer(opacity: 0.00, y: 36, blur: 48, spread: -28),
    ]

    /// --stroke-nous: currentColor at 3%.
    static let overlayHairlineAlpha: Double = 0.03

    /// --shadow-xs (also --shadow-composer).
    static let xs: [HermesShadowLayer] = [
        HermesShadowLayer(opacity: 0.05, y: 1, blur: 2),
    ]

    /// --shadow-sm drop layers (plus a 1pt foreground ring at `ringAlphaSM`).
    static let sm: [HermesShadowLayer] = [
        HermesShadowLayer(opacity: 0.04, y: 2, blur: 8),
    ]

    /// --shadow-md drop layers (plus a 1pt foreground ring at `ringAlphaMD`).
    /// Popover/menu/dialog surfaces use this over a 96%-alpha elevated background.
    static let md: [HermesShadowLayer] = [
        HermesShadowLayer(opacity: 0.08, y: 4, blur: 16),
        HermesShadowLayer(opacity: 0.18, y: 16, blur: 32, spread: -24),
    ]

    /// --shadow-lg drop layer (plus foreground ring at `ringAlphaMD` and an inset
    /// white 28% top highlight the port may approximate with a top hairline).
    static let lg: [HermesShadowLayer] = [
        HermesShadowLayer(opacity: 0.12, y: 12, blur: 32),
    ]

    static let ringAlphaSM: Double = 0.06
    static let ringAlphaMD: Double = 0.08
}

extension View {
    /// Applies a layered drop-shadow spec (all layers x = 0, pure black).
    func hermesShadow(_ layers: [HermesShadowLayer]) -> some View {
        var view = AnyView(self)
        for layer in layers where layer.opacity > 0 {
            view = AnyView(view.shadow(
                color: Color.black.opacity(layer.opacity),
                radius: max(0, (layer.blur + layer.spread) / 2),
                x: 0,
                y: layer.y))
        }
        return view
    }
}

// MARK: - Motion

/// Durations in seconds. All decorative animation is disabled under
/// reduced-motion; only fades remain.
enum HermesMotion {
    /// Quick functional transitions on controls.
    static let control: TimeInterval = 0.10
    /// Tool/thinking scaffold opacity lift (0.67 → 1).
    static let scaffoldFade: TimeInterval = 0.12
    /// Input chrome border-color transition (only the border animates; bg snaps).
    static let inputBorder: TimeInterval = 0.20
    /// Composer drag-hatch fade.
    static let hatchFade: TimeInterval = 0.15
    static let codeCardEnter: TimeInterval = 0.18
    static let codeCardGlowPeriod: TimeInterval = 1.8
    static let cardIdle: TimeInterval = 0.18
    static let jumpButtonIn: TimeInterval = 0.20
    static let jumpButtonOut: TimeInterval = 0.18

    /// cubic-bezier(0.16, 1, 0.3, 1) — code-card stream enter.
    static let codeCardEnterCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: codeCardEnter)
    /// cubic-bezier(0.22, 1, 0.36, 1) — jump-to-bottom enter.
    static let jumpInCurve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: jumpButtonIn)
}

// MARK: - Type metrics

enum HermesTypeSize {
    static let body: CGFloat = 13                 // 0.8125rem
    static let conversation: CGFloat = 13         // --conversation-text-font-size
    static let tool: CGFloat = 11                 // --conversation-tool-font-size
    static let caption: CGFloat = 12              // --conversation-caption-font-size
    static let intro: CGFloat = 14                // intro body copy (0.875rem)
    static let conversationLineHeight: CGFloat = 18
    static let captionLineHeight: CGFloat = 16
    static let assistantLineHeightMultiple: CGFloat = 1.5
    static let userLineHeightMultiple: CGFloat = 1.3   // --human-msg-line-height
    /// Wordmark: uppercase, tracking 0.08em, leading 0.9, min size 2.75rem.
    static let wordmarkTracking: CGFloat = 0.08
    static let wordmarkLineHeightMultiple: CGFloat = 0.9
    static let wordmarkMinPointSize: CGFloat = 44
}

// MARK: - Conversation & chrome spacing

enum HermesSpacing {
    static let messageTextIndent: CGFloat = 12    // --message-text-indent
    static let turnGap: CGFloat = 6               // --conversation-turn-gap
    static let blockGap: CGFloat = 12             // --turn-block-gap
    static let toolRowGap: CGFloat = 6            // --tool-row-gap
    static let paragraphGap: CGFloat = 11.2       // --paragraph-gap (0.7rem)
    static let threadInlinePadding: CGFloat = 24  // thread content padding-inline
    static let sidebarContentInlinePadding: CGFloat = 16
    static let chatMinWidth: CGFloat = 448        // --chat-min-width
    static let fileTreeRowHeight: CGFloat = 22
    static let titlebarControlSize: CGFloat = 20
    static let titlebarControlHeight: CGFloat = 22
    static let composerControlSize: CGFloat = 24
    static let composerPrimaryControlSize: CGFloat = 26
    static let composerControlGap: CGFloat = 4
    static let composerInputMinHeight: CGFloat = 26
    static let composerInputMaxHeight: CGFloat = 150
    /// macOS traffic-light position inside the 34pt titlebar.
    static let trafficLightPosition = CGPoint(x: 24, y: 10)
}

// MARK: - Fixed opacities

enum HermesOpacity {
    /// Tool/thinking scaffolding idle opacity (lifts to 1 on hover/focus).
    static let toolScaffoldIdle: Double = 0.67
    /// Message action-bar icons idle opacity.
    static let messageActionIdle: Double = 0.5
    /// Composer drag-hatch on hover/drag.
    static let dragHatchHover: Double = 0.33
    /// Popover surface alpha over its blurred backdrop.
    static let popoverSurface: Double = 0.96
}
