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
/// Multiple items can exist for the same `MetricCategory` (Requirement ADR 0007).
public struct MenuBarItemConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var category: MetricCategory
    public var style: MetricDisplayStyle
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        category: MetricCategory,
        style: MetricDisplayStyle,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.category = category
        self.style = style
        self.isEnabled = isEnabled
    }

    /// Sensible default starter widgets for the app.
    public static func defaultConfigs() -> [MenuBarItemConfig] {
        [
            MenuBarItemConfig(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, category: .cpu, style: .gauge),
            MenuBarItemConfig(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, category: .memory, style: .gauge),
            MenuBarItemConfig(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, category: .network, style: .throughput)
        ]
    }
}

