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
    public static let lightGlassBackground = RGBColor(hex: "#F2F2F7")!

    /// Canonical hex definitions shared between `CategoryPalette` and `PaletteContrastTests`.
    public enum Hex {
        public static func categoryTint(for category: MetricCategory) -> (light: String, dark: String) {
            switch category {
            case .cpu:     return ("#0058D6", "#5C8DFF")
            case .memory:  return ("#006E80", "#33D1A6")
            case .gpu:     return ("#6D28D9", "#A386FF")
            case .thermal: return ("#B54308", "#FF8A4C")
            case .fan:     return ("#0B6E66", "#3CC6E8")
            case .network: return ("#087054", "#8389FF")
            case .disk:    return ("#364FC7", "#FF6E9C")
            case .power:   return ("#147530", "#4ADE80")
            }
        }

        public static func categoryDeep(for category: MetricCategory) -> (light: String, dark: String) {
            switch category {
            case .cpu:     return ("#003E99", "#3B5BDB")
            case .memory:  return ("#004D5A", "#13997A")
            case .gpu:     return ("#4C1D95", "#6E4BD8")
            case .thermal: return ("#7C2D12", "#E0532A")
            case .fan:     return ("#044E46", "#1A8FB5")
            case .network: return ("#064E3B", "#5A5FE0")
            case .disk:    return ("#25368A", "#D8467A")
            case .power:   return ("#0E4B20", "#22A355")
            }
        }

        public static func status(for level: StatusLevel) -> (light: String, dark: String) {
            switch level {
            case .fine:     return ("#147530", "#4ADE80")
            case .elevated: return ("#9E5800", "#FFC53D")
            case .warning:  return ("#B83E00", "#FF9F45")
            case .critical: return ("#C42014", "#FF5C5C")
            }
        }

        public static let cpuSystem     = (light: "#C23B1E", dark: "#FF7A59")
        public static let networkUpload = (light: "#6D28D9", dark: "#A78BFA")
        public static let diskWrite     = (light: "#B8470B", dark: "#FF8A4C")
        public static let memoryApp     = (light: "#005EB8", dark: "#38BDF8")
    }

    /// Check if contrast meets WCAG AA normal text requirement (≥ 4.5:1).
    public static func meetsWcagAA(text: RGBColor, background: RGBColor) -> Bool {
        text.contrastRatio(with: background) >= 4.5
    }

    /// Check if contrast meets WCAG AA large text / graphical component requirement (≥ 3.0:1).
    public static func meetsWcagAALarge(foreground: RGBColor, background: RGBColor) -> Bool {
        foreground.contrastRatio(with: background) >= 3.0
    }
}
