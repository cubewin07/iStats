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
        case .symbol: return "Icon / Symbol"
        case .gauge: return "Circular Gauge"
        case .bar: return "Load Bar"
        case .sparkline: return "History Graph"
        case .text: return "Text Reading"
        case .throughput: return "Throughput (Speed)"
        }
    }

    /// Default compatible styles for a given metric category.
    public static func supportedStyles(for category: MetricCategory) -> [MetricDisplayStyle] {
        switch category {
        case .cpu, .memory, .gpu:
            return [.gauge, .bar, .sparkline, .text, .symbol]
        case .thermal:
            return [.text, .gauge, .sparkline, .symbol]
        case .fan:
            return [.text, .gauge, .symbol]
        case .network:
            return [.throughput, .sparkline, .text, .symbol]
        case .disk:
            return [.throughput, .text, .gauge, .symbol]
        case .power:
            return [.gauge, .text, .bar, .symbol]
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

