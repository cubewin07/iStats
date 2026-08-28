import Foundation

/// The visual presentation style for an item in the macOS menu bar.
public enum MetricDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case symbol
    case gauge
    case bar
    case sparkline
    case text
    case throughput

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gauge: return "Donut / Pie Chart"
        case .bar: return "Load Bar / Core Cluster"
        case .sparkline: return "Real-Time History Graph"
        case .throughput: return "Stacked 2-Line Text"
        case .text: return "Single-Line Text"
        case .symbol: return "Activity Instrument"
        }
    }

    /// Default compatible styles for a given metric category.
    public static func supportedStyles(for category: MetricCategory) -> [MetricDisplayStyle] {
        switch category {
        case .cpu, .memory, .gpu:
            return [.gauge, .bar, .sparkline, .text, .symbol]
        case .thermal, .fan:
            return [.gauge, .bar, .sparkline, .text, .symbol]
        case .network:
            return [.throughput, .gauge, .bar, .sparkline, .text, .symbol]
        case .disk:
            return [.throughput, .gauge, .bar, .sparkline, .text, .symbol]
        case .power:
            return [.gauge, .bar, .sparkline, .text, .symbol]
        }
    }
}

/// A user-configured metric item/widget to be displayed in the macOS menu bar.
/// Identified deterministically by composite `category.style` key.
public struct MenuBarItemConfig: Identifiable, Codable, Hashable, Equatable, Sendable {
    public var category: MetricCategory
    public var style: MetricDisplayStyle

    public var id: String {
        "\(category.rawValue).\(style.rawValue)"
    }

    public init(
        category: MetricCategory,
        style: MetricDisplayStyle
    ) {
        self.category = category
        self.style = style
    }

    /// All possible widget configurations supported by the system.
    public static var allAvailableItems: [MenuBarItemConfig] {
        MetricCategory.allCases.flatMap { category in
            MetricDisplayStyle.supportedStyles(for: category).map { style in
                MenuBarItemConfig(category: category, style: style)
            }
        }
    }

    /// All supported widget configurations for a specific metric category.
    public static func allStyles(for category: MetricCategory) -> [MenuBarItemConfig] {
        MetricDisplayStyle.supportedStyles(for: category).map { style in
            MenuBarItemConfig(category: category, style: style)
        }
    }

    /// Sensible default starter widgets for the app.
    public static func defaultConfigs() -> [MenuBarItemConfig] {
        [
            MenuBarItemConfig(category: .cpu, style: .gauge),
            MenuBarItemConfig(category: .memory, style: .gauge),
            MenuBarItemConfig(category: .network, style: .throughput)
        ]
    }
}

