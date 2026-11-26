import AppKit
import iStatsCore

/// One renderer per `WidgetFamily`. A renderer is a pure function from `WidgetModel` to image.
@MainActor
protocol WidgetRenderer {
    static func draw(_ model: WidgetModel) -> NSImage
}

/// Dispatches a model to the renderer of its family.
@MainActor
enum WidgetRenderers {
    static func draw(_ model: WidgetModel) -> NSImage {
        switch model.family {
        case .value: return ValueWidget.draw(model)
        case .dual: return DualWidget.draw(model)
        case .bar: return BarWidget.draw(model)
        case .ring: return RingWidget.draw(model)
        case .graph: return GraphWidget.draw(model)
        case .glyph: return GlyphWidget.draw(model)
        }
    }
}

/// Resolves semantic color roles through the shared palette (never `.systemX`).
@MainActor
enum WidgetColor {
    static func resolve(_ role: WidgetColorRole, category: MetricCategory) -> NSColor {
        switch role {
        case .label: return .labelColor
        case .category: return CategoryPalette.nsColor(for: category)
        case .status(let level): return CategoryPalette.statusNSColor(for: level)
        }
    }

    /// `nil` for the template (label) role so the image can be a template.
    static func optional(_ role: WidgetColorRole, category: MetricCategory) -> NSColor? {
        if case .label = role { return nil }
        return resolve(role, category: category)
    }
}

/// Fixed canvas widths per width class. Measured from the class's worst-case string, once.
@MainActor
enum WidgetMetrics {
    private static var cache: [WidgetWidthClass: CGFloat] = [:]

    /// Worst-case (prefix, value) pairs of the two-line classes, measured with the two-line fonts.
    private static func twoLineSamples(_ widthClass: WidgetWidthClass) -> [(String, String)] {
        switch widthClass {
        case .twoLineRate:
            // Every prefix (network arrows, disk R/W) against the widest value strings (IEC suffixes, one decimal, bits).
            let prefixes = ["\u{2191}", "\u{2193}", "R", "W"]
            let values = ["999 MiB/s", "9.9 MiB/s", "999 Mbps", "9.9 Mbps"]
            return prefixes.flatMap { p in values.map { (p, $0) } }
        case .twoLineFan: return [("L", "9999"), ("R", "9999")]
        case .twoLinePower: return [("", "100% \u{26A1}"), ("", "Charging")]
        default: return []
        }
    }

    static func width(_ widthClass: WidgetWidthClass) -> CGFloat {
        if let cached = cache[widthClass] { return cached }
        var width = CGFloat(widthClass.minWidth)
        let pFont = NSFont.systemFont(ofSize: 9.0, weight: .bold)
        let vFont = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
        for (prefix, value) in twoLineSamples(widthClass) {
            let p = prefix.isEmpty ? 0.0 : (prefix as NSString).size(withAttributes: [.font: pFont]).width + 2.0
            let v = (value as NSString).size(withAttributes: [.font: vFont]).width
            width = max(width, ceil(2.0 + p + v + 2.0))
        }
        if let worst = widthClass.worstCase, twoLineSamples(widthClass).isEmpty {
            let measured = MenuBarIconRenderer.formatCompactValueAttributedString(value: worst, color: .labelColor).size().width
            switch widthClass {
            case .thermometer:
                width = max(width, ceil(12.0 + measured + 2.0))
            case .fanGlyph:
                break
            default:
                width = max(width, ceil(measured + 2.0))
            }
        }
        cache[widthClass] = width
        return width
    }
}
