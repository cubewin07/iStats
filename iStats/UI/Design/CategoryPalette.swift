import SwiftUI
import AppKit
import iStatsCore

/// Single source of truth for category identity colors, metric series palettes, and thermal ramps.
/// Display P3 tuned palette adhering to ADR 0009 / Phase 8 specifications.
public enum CategoryPalette {

    // MARK: - Core Color Construction (Display P3)

    private static func nsColorFromHex(_ hex: String) -> NSColor {
        var c = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasPrefix("#") { c.removeFirst() }
        var val: UInt64 = 0
        Scanner(string: c).scanHexInt64(&val)
        let r = CGFloat((val & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((val & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(val & 0x0000FF) / 255.0
        return NSColor(displayP3Red: r, green: g, blue: b, alpha: 1.0)
    }

    public static func dynamicNSColor(lightHex: String, darkHex: String) -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .darkAqua,
                .accessibilityHighContrastAqua,
                .aqua
            ])
            let isDark = (match == .darkAqua || match == .accessibilityHighContrastDarkAqua)
            let isHighContrast = (match == .accessibilityHighContrastDarkAqua || match == .accessibilityHighContrastAqua)

            let baseHex = isDark ? darkHex : lightHex
            let baseColor = nsColorFromHex(baseHex)
            if isHighContrast {
                return isDark ? (baseColor.blended(withFraction: 0.25, of: .white) ?? baseColor)
                              : (baseColor.blended(withFraction: 0.25, of: .black) ?? baseColor)
            }
            return baseColor
        })
    }

    public static func dynamicColor(lightHex: String, darkHex: String) -> Color {
        Color(nsColor: dynamicNSColor(lightHex: lightHex, darkHex: darkHex))
    }

    // MARK: - Category Tint Colors

    public static func tint(for category: MetricCategory) -> Color {
        color(for: category)
    }

    public static func color(for category: MetricCategory) -> Color {
        Color(nsColor: nsColor(for: category))
    }

    public static func nsColor(for category: MetricCategory) -> NSColor {
        let hex = PaletteContrast.Hex.categoryTint(for: category)
        return dynamicNSColor(lightHex: hex.light, darkHex: hex.dark)
    }

    // MARK: - Category Deep Colors (~12° hue shift, darker, for gradient terminals)

    public static func tintDeep(for category: MetricCategory) -> Color {
        deep(for: category)
    }

    public static func deep(for category: MetricCategory) -> Color {
        Color(nsColor: nsDeep(for: category))
    }

    public static func nsDeep(for category: MetricCategory) -> NSColor {
        let hex = PaletteContrast.Hex.categoryDeep(for: category)
        return dynamicNSColor(lightHex: hex.light, darkHex: hex.dark)
    }

    // MARK: - Gradients

    /// Full-bleed chart gradient fading from tint → tintDeep → clear.
    public static func gradient(for category: MetricCategory) -> LinearGradient {
        LinearGradient(
            colors: [
                color(for: category).opacity(0.35),
                deep(for: category).opacity(0.12),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Direct Category Color Accessors
    public static var cpu: Color { color(for: .cpu) }
    public static var memory: Color { color(for: .memory) }
    public static var gpu: Color { color(for: .gpu) }
    public static var thermal: Color { color(for: .thermal) }
    public static var fan: Color { color(for: .fan) }
    public static var network: Color { color(for: .network) }
    public static var disk: Color { color(for: .disk) }
    public static var power: Color { color(for: .power) }

    // MARK: - Dual Channel Series Colors
    public enum Series {
        // Network
        public static let networkDownload = CategoryPalette.color(for: .network)
        public static let networkUpload = CategoryPalette.dynamicColor(
            lightHex: PaletteContrast.Hex.networkUpload.light,
            darkHex: PaletteContrast.Hex.networkUpload.dark
        )

        // Disk
        public static let diskRead = CategoryPalette.color(for: .disk)
        public static let diskWrite = CategoryPalette.dynamicColor(
            lightHex: PaletteContrast.Hex.diskWrite.light,
            darkHex: PaletteContrast.Hex.diskWrite.dark
        )

        // CPU
        public static let cpuUser = CategoryPalette.color(for: .cpu)
        public static let cpuSystem = CategoryPalette.dynamicColor(
            lightHex: PaletteContrast.Hex.cpuSystem.light,
            darkHex: PaletteContrast.Hex.cpuSystem.dark
        )
        public static let cpuEfficiency = CategoryPalette.dynamicColor(
            lightHex: PaletteContrast.Hex.cpuEfficiency.light,
            darkHex: PaletteContrast.Hex.cpuEfficiency.dark
        )

        // Memory composition
        public static let memoryApp = CategoryPalette.dynamicColor(
            lightHex: PaletteContrast.Hex.memoryApp.light,
            darkHex: PaletteContrast.Hex.memoryApp.dark
        )
        public static let memoryWired = CategoryPalette.dynamicColor(
            lightHex: PaletteContrast.Hex.memoryWired.light,
            darkHex: PaletteContrast.Hex.memoryWired.dark
        )
        public static let memoryCompressed = CategoryPalette.dynamicColor(
            lightHex: PaletteContrast.Hex.memoryCompressed.light,
            darkHex: PaletteContrast.Hex.memoryCompressed.dark
        )
        public static let memoryCached = CategoryPalette.dynamicColor(
            lightHex: PaletteContrast.Hex.memoryCached.light,
            darkHex: PaletteContrast.Hex.memoryCached.dark
        )
    }

    // MARK: - Semantic Status Severity Colors
    public static func statusColor(for level: StatusLevel) -> Color {
        Color(nsColor: statusNSColor(for: level))
    }

    public static func statusNSColor(for level: StatusLevel) -> NSColor {
        let hex = PaletteContrast.Hex.status(for: level)
        return dynamicNSColor(lightHex: hex.light, darkHex: hex.dark)
    }
}

// MARK: - Thermal Spectrum Ramp

public enum ThermalRamp {
    private struct ColorStop {
        let temp: Double
        let r: Double
        let g: Double
        let b: Double
    }

    // 30 °C #4FB3FF → 55 °C #7ED957 → 75 °C #FFC53D → 90 °C #FF8A4C → 105 °C #FF4D4D
    private static let stops: [ColorStop] = [
        ColorStop(temp: 30.0,  r: 0x4F/255.0, g: 0xB3/255.0, b: 0xFF/255.0),
        ColorStop(temp: 55.0,  r: 0x7E/255.0, g: 0xD9/255.0, b: 0x57/255.0),
        ColorStop(temp: 75.0,  r: 0xFF/255.0, g: 0xC5/255.0, b: 0x3D/255.0),
        ColorStop(temp: 90.0,  r: 0xFF/255.0, g: 0x8A/255.0, b: 0x4C/255.0),
        ColorStop(temp: 105.0, r: 0xFF/255.0, g: 0x4D/255.0, b: 0x4D/255.0)
    ]

    public static var linearGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: stops.map {
                Color(nsColor: NSColor(displayP3Red: $0.r, green: $0.g, blue: $0.b, alpha: 1.0))
            }),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Evaluates smooth Display P3 interpolated color across the 30–105 °C spectrum.
    public static func color(celsius: Double) -> Color {
        if celsius <= stops.first!.temp {
            let s = stops.first!
            return Color(nsColor: NSColor(displayP3Red: s.r, green: s.g, blue: s.b, alpha: 1.0))
        }
        if celsius >= stops.last!.temp {
            let s = stops.last!
            return Color(nsColor: NSColor(displayP3Red: s.r, green: s.g, blue: s.b, alpha: 1.0))
        }

        for i in 0..<(stops.count - 1) {
            let s0 = stops[i]
            let s1 = stops[i + 1]
            if celsius >= s0.temp && celsius <= s1.temp {
                let factor = (celsius - s0.temp) / (s1.temp - s0.temp)
                let r = s0.r + factor * (s1.r - s0.r)
                let g = s0.g + factor * (s1.g - s0.g)
                let b = s0.b + factor * (s1.b - s0.b)
                return Color(nsColor: NSColor(displayP3Red: r, green: g, blue: b, alpha: 1.0))
            }
        }
        return Color.orange
    }
}

// MARK: - StatusLevel UI Convenience

extension StatusLevel {
    /// Semantic status color conforming to CategoryPalette.
    public var color: Color {
        CategoryPalette.statusColor(for: self)
    }

    /// Semantic SF Symbol name representing this status level.
    public var iconName: String {
        switch self {
        case .fine: return "checkmark.circle.fill"
        case .elevated: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}
