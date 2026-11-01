import Foundation

/// Pure mathematical helper for WCAG 2.1 relative luminance and contrast ratio calculations.
public struct RGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = min(max(red, 0.0), 1.0)
        self.green = min(max(green, 0.0), 1.0)
        self.blue = min(max(blue, 0.0), 1.0)
        self.alpha = min(max(alpha, 0.0), 1.0)
    }

    /// Parse a 6-character or 8-character hex string (with or without leading '#').
    public init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }

        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else { return nil }

        if cleanHex.count == 6 {
            let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = Double(rgbValue & 0x0000FF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: 1.0)
        } else if cleanHex.count == 8 {
            let r = Double((rgbValue & 0xFF000000) >> 24) / 255.0
            let g = Double((rgbValue & 0x00FF0000) >> 16) / 255.0
            let b = Double((rgbValue & 0x0000FF00) >> 8) / 255.0
            let a = Double(rgbValue & 0x000000FF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: a)
        } else {
            return nil
        }
    }

    /// WCAG 2.1 relative luminance:
    /// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
    public var relativeLuminance: Double {
        func channelLinear(_ c: Double) -> Double {
            if c <= 0.04045 {
                return c / 12.92
            } else {
                return pow((c + 0.055) / 1.055, 2.4)
            }
        }

        let rLin = channelLinear(red)
        let gLin = channelLinear(green)
        let bLin = channelLinear(blue)

        return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
    }

    /// WCAG 2.1 contrast ratio between two colors: (L1 + 0.05) / (L2 + 0.05)
    /// Returns a value between 1.0 and 21.0.
    public func contrastRatio(with other: RGBColor) -> Double {
        let l1 = self.relativeLuminance
        let l2 = other.relativeLuminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// Palette contrast verification helpers and color fixtures.
public enum PaletteContrast {
    public static let white = RGBColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = RGBColor(red: 0.0, green: 0.0, blue: 0.0)
    public static let darkBackground = RGBColor(hex: "#1C1C1E")!
    public static let lightBackground = RGBColor(hex: "#FFFFFF")!

    /// Check if contrast meets WCAG AA normal text requirement (≥ 4.5:1).
    public static func meetsWcagAA(text: RGBColor, background: RGBColor) -> Bool {
        text.contrastRatio(with: background) >= 4.5
    }

    /// Check if contrast meets WCAG AA large text / graphical component requirement (≥ 3.0:1).
    public static func meetsWcagAALarge(foreground: RGBColor, background: RGBColor) -> Bool {
        foreground.contrastRatio(with: background) >= 3.0
    }
}
