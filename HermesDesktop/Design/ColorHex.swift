import SwiftUI

extension Color {
    /// Creates a color from a CSS-style hex string: "#RGB", "#RRGGBB", or "#RRGGBBAA".
    init(hex: String, alpha: Double = 1.0) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }

        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        var rgba: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgba)

        let r, g, b, a: Double
        switch value.count {
        case 8:
            r = Double((rgba & 0xFF00_0000) >> 24) / 255
            g = Double((rgba & 0x00FF_0000) >> 16) / 255
            b = Double((rgba & 0x0000_FF00) >> 8) / 255
            a = Double(rgba & 0x0000_00FF) / 255
        default:
            r = Double((rgba & 0xFF0000) >> 16) / 255
            g = Double((rgba & 0x00FF00) >> 8) / 255
            b = Double(rgba & 0x0000FF) / 255
            a = 1.0
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a * alpha)
    }
}
