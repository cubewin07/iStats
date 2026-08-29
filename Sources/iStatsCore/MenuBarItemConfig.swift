import Foundation

/// The visual presentation style for an item in the macOS menu bar.
public enum MetricDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case text
    case throughput
    case bar
    case gauge
    case sparkline
    case symbol
    case cpuTemp = "cpuTemp"
    case gpuTemp = "gpuTemp"
    case memoryTemp = "memoryTemp"
    case storageTemp = "storageTemp"
    case batteryTemp = "batteryTemp"

    public var id: String { rawValue }

    // MARK: - Codable Migration

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "tachometer":
            self = .gauge
        case "blades":
            self = .symbol
        default:
            if let matched = MetricDisplayStyle(rawValue: raw) {
                self = matched
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown MetricDisplayStyle raw value: \(raw)"
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: - Display Names

    /// Category-specific descriptive metric name for preferences and menus.
    public func displayName(for category: MetricCategory) -> String {
        switch (category, self) {
        // CPU
        case (.cpu, .text): return "CPU %"
        case (.cpu, .gauge): return "User/System"
        case (.cpu, .bar): return "Core Cluster"
        case (.cpu, .sparkline): return "Usage History"

        // Memory
        case (.memory, .text): return "Used %"
        case (.memory, .gauge): return "Composition"
        case (.memory, .bar): return "Allocation"
        case (.memory, .sparkline): return "Used % History"
        case (.memory, .symbol): return "Pressure"

        // GPU
        case (.gpu, .text): return "GPU %"
        case (.gpu, .gauge): return "Load Ring"
        case (.gpu, .bar): return "Load Bar"
        case (.gpu, .sparkline): return "Load History"
        case (.gpu, .symbol): return "GPU Die"

        // Thermal
        case (.thermal, .text): return "Peak °C"
        case (.thermal, .cpuTemp): return "CPU °C"
        case (.thermal, .gpuTemp): return "GPU °C"
        case (.thermal, .memoryTemp): return "Memory °C"
        case (.thermal, .storageTemp): return "SSD °C"
        case (.thermal, .batteryTemp): return "Battery °C"
        case (.thermal, .gauge): return "Temp Ring"
        case (.thermal, .sparkline): return "Peak History"

        // Fans
        case (.fan, .text): return "Fan %"
        case (.fan, .throughput): return "Dual RPM"
        case (.fan, .gauge): return "Tachometer"
        case (.fan, .bar): return "Fan Bars"
        case (.fan, .sparkline): return "RPM History"
        case (.fan, .symbol): return "Blades"

        // Network
        case (.network, .throughput): return "Up / Down"
        case (.network, .bar): return "In / Out Bars"
        case (.network, .sparkline): return "Duplex History"
        case (.network, .symbol): return "Activity Arrows"

        // Disk
        case (.disk, .throughput): return "Read / Write"
        case (.disk, .gauge): return "Storage Ring"
        case (.disk, .bar): return "Storage Bar"
        case (.disk, .sparkline): return "I/O History"
        case (.disk, .symbol): return "R/W LEDs"

        // Power
        case (.power, .text): return "Charge + Time"
        case (.power, .throughput): return "Draw / Adapter W"
        case (.power, .gauge): return "Charge Ring"
        case (.power, .bar): return "Charge Bar"
        case (.power, .sparkline): return "Wattage History"
        case (.power, .symbol): return "Battery"

        default:
            return genericDisplayName
        }
    }

    /// Generic presentation family name.
    public var displayName: String {
        genericDisplayName
    }

    private var genericDisplayName: String {
        switch self {
        case .text: return "Single-Line Text"
        case .throughput: return "Stacked 2-Line Text"
        case .bar: return "Load Bar"
        case .gauge: return "Gauge / Donut"
        case .sparkline: return "History Graph"
        case .symbol: return "Activity Instrument"
        case .cpuTemp: return "CPU Temperature"
        case .gpuTemp: return "GPU Temperature"
        case .memoryTemp: return "Memory Temperature"
        case .storageTemp: return "SSD Temperature"
        case .batteryTemp: return "Battery Temperature"
        }
    }

    /// Default compatible styles for a given metric category.
    public static func supportedStyles(for category: MetricCategory, hasBattery: Bool = true) -> [MetricDisplayStyle] {
        switch category {
        case .cpu:
            return [.text, .gauge, .bar, .sparkline]
        case .memory:
            return [.text, .gauge, .bar, .sparkline, .symbol]
        case .gpu:
            return [.text, .gauge, .bar, .sparkline, .symbol]
        case .thermal:
            return hasBattery
                ? [.text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .batteryTemp, .gauge, .sparkline]
                : [.text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .gauge, .sparkline]
        case .fan:
            return [.text, .throughput, .gauge, .bar, .sparkline, .symbol]
        case .network:
            return [.throughput, .bar, .sparkline, .symbol]
        case .disk:
            return [.throughput, .gauge, .bar, .sparkline, .symbol]
        case .power:
            return hasBattery
                ? [.text, .throughput, .gauge, .bar, .sparkline, .symbol]
                : [.text, .throughput, .sparkline]
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
            MenuBarItemConfig(category: .cpu, style: .bar),
            MenuBarItemConfig(category: .memory, style: .bar),
            MenuBarItemConfig(category: .network, style: .throughput)
        ]
    }
}


