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

    private var hsv: (hue: Double, saturation: Double, value: Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC
        guard delta > 0 else { return (0, 0, maxC) }
        var h: Double
        if maxC == red {
            h = (green - blue) / delta
            if h < 0 { h += 6 }
        } else if maxC == green {
            h = (blue - red) / delta + 2
        } else {
            h = (red - green) / delta + 4
        }
        return (h * 60, delta / maxC, maxC)
    }

    /// HSV hue in degrees, 0..<360 (0 for greys).
    public var hueDegrees: Double { hsv.hue }

    /// HSV saturation 0...1.
    public var saturation: Double { hsv.saturation }

    /// Shortest angular distance between two hues, 0...180.
    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
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
        /// Category identity tints. Each category keeps one hue family across appearances
        /// (light = darker variant for white surfaces, dark = brighter variant for dark surfaces).
        /// Hue targets: CPU 215, Memory 160 (mint), GPU 262, Temperature 22, Fans 212 (steel: low
        /// saturation, so it is separated from CPU by saturation, not hue), Network 188 (cyan),
        /// Disk 335 (pink), Power 85 (lime, off the status green at ~136).
        public static func categoryTint(for category: MetricCategory) -> (light: String, dark: String) {
            switch category {
            case .cpu:     return ("#0264ED", "#5CA0FF")
            case .memory:  return ("#067D55", "#30DBA2")
            case .gpu:     return ("#6B1DF2", "#AE80FF")
            case .thermal: return ("#BA4A09", "#FF8E4D")
            case .fan:     return ("#616E7D", "#8FABCC")
            case .network: return ("#07788A", "#2FD2EB")
            case .disk:    return ("#CD256B", "#FF6BA9")
            case .power:   return ("#4E7912", "#9DE03F")
            }
        }

        /// Darker gradient terminals, same hue as the tint.
        public static func categoryDeep(for category: MetricCategory) -> (light: String, dark: String) {
            switch category {
            case .cpu:     return ("#0043A1", "#3165AD")
            case .memory:  return ("#005539", "#15956A")
            case .gpu:     return ("#440BA5", "#6E49AD")
            case .thermal: return ("#7E2E00", "#AD5826")
            case .fan:     return ("#3E4955", "#566F8B")
            case .network: return ("#00515E", "#138DA0")
            case .disk:    return ("#8B1245", "#AD3B6B")
            case .power:   return ("#335208", "#66991F")
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

        public static let cpuSystem        = (light: "#C23B1E", dark: "#FF7A59")
        public static let cpuEfficiency    = (light: "#09749B", dark: "#38BDF8")
        public static let networkUpload    = (light: "#6D28D9", dark: "#A78BFA")
        public static let diskWrite        = (light: "#B8470B", dark: "#FF8A4C")
        public static let memoryApp        = (light: "#005EB8", dark: "#38BDF8")
        public static let memoryWired      = (light: "#0B7A5E", dark: "#20A884")
        public static let memoryCompressed = (light: "#6D4AFF", dark: "#9B82FF")
        public static let memoryCached     = (light: "#267394", dark: "#58B4D8")
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
