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
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColorFromHex(isDark ? darkHex : lightHex)
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
        switch category {
        case .cpu:
            return dynamicNSColor(lightHex: "#2E6BF0", darkHex: "#5C8DFF")
        case .memory:
            return dynamicNSColor(lightHex: "#0FA37F", darkHex: "#33D1A6")
        case .gpu:
            return dynamicNSColor(lightHex: "#7C4DEB", darkHex: "#A386FF")
        case .thermal:
            return dynamicNSColor(lightHex: "#E2611E", darkHex: "#FF8A4C")
        case .fan:
            return dynamicNSColor(lightHex: "#0C93B8", darkHex: "#3CC6E8")
        case .network:
            return dynamicNSColor(lightHex: "#4F55E6", darkHex: "#8389FF")
        case .disk:
            return dynamicNSColor(lightHex: "#D23D72", darkHex: "#FF6E9C")
        case .power:
            return dynamicNSColor(lightHex: "#2AA44F", darkHex: "#4ADE80")
        }
    }

    // MARK: - Category Deep Colors (~12° hue shift, darker, for gradient terminals)

    public static func tintDeep(for category: MetricCategory) -> Color {
        deep(for: category)
    }

    public static func deep(for category: MetricCategory) -> Color {
        Color(nsColor: nsDeep(for: category))
    }

    public static func nsDeep(for category: MetricCategory) -> NSColor {
        switch category {
        case .cpu:
            return dynamicNSColor(lightHex: "#244DBA", darkHex: "#3B5BDB")
        case .memory:
            return dynamicNSColor(lightHex: "#0D8265", darkHex: "#13997A")
        case .gpu:
            return dynamicNSColor(lightHex: "#5A38B8", darkHex: "#6E4BD8")
        case .thermal:
            return dynamicNSColor(lightHex: "#BF421E", darkHex: "#E0532A")
        case .fan:
            return dynamicNSColor(lightHex: "#0A7491", darkHex: "#1A8FB5")
        case .network:
            return dynamicNSColor(lightHex: "#3A3FB8", darkHex: "#5A5FE0")
        case .disk:
            return dynamicNSColor(lightHex: "#A82E59", darkHex: "#D8467A")
        case .power:
            return dynamicNSColor(lightHex: "#1B7A38", darkHex: "#22A355")
        }
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
        public static let networkUpload = CategoryPalette.dynamicColor(lightHex: "#D9683B", darkHex: "#FF8A5B")

        // Disk
        public static let diskRead = CategoryPalette.color(for: .disk)
        public static let diskWrite = CategoryPalette.dynamicColor(lightHex: "#C98E18", darkHex: "#F5B83D")

        // CPU
        public static let cpuUser = CategoryPalette.color(for: .cpu)
        public static let cpuSystem = CategoryPalette.dynamicColor(lightHex: "#D94F43", darkHex: "#FF6B5E")

        // Memory composition
        public static let memoryApp = CategoryPalette.color(for: .memory)
        public static let memoryWired = CategoryPalette.deep(for: .memory)
        public static let memoryCompressed = CategoryPalette.color(for: .memory).opacity(0.55)
        public static let memoryCached = CategoryPalette.color(for: .memory).opacity(0.28)
    }

    // MARK: - Semantic Status Severity Colors
    public static func statusColor(for level: StatusLevel) -> Color {
        Color(nsColor: statusNSColor(for: level))
    }

    public static func statusNSColor(for level: StatusLevel) -> NSColor {
        switch level {
        case .fine:
            return dynamicNSColor(lightHex: "#2AA44F", darkHex: "#4ADE80")
        case .elevated:
            return dynamicNSColor(lightHex: "#C98A00", darkHex: "#FFC53D")
        case .warning:
            return dynamicNSColor(lightHex: "#E06A00", darkHex: "#FF9F45")
        case .critical:
            return dynamicNSColor(lightHex: "#D92D2D", darkHex: "#FF5C5C")
        }
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
