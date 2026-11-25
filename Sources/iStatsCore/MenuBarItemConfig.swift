import Foundation

/// Layout orientation for throughput (dual value) menu bar widgets.
public enum ThroughputLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case stacked
    case singleLine

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .stacked: return "Stacked (2 lines)"
        case .singleLine: return "Single Line"
        }
    }
}

/// The visual presentation style for an item in the macOS menu bar.
public enum MetricDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case text
    case throughput
    case bar
    case gauge
    case sparkline
    case symbol
    case glyph

    // MARK: - Legacy Deprecated Styles (preserved for decode migration)
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
            self = .glyph
        case "blades":
            self = .glyph
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
        // CPU (4)
        case (.cpu, .text): return "CPU %"
        case (.cpu, .gauge): return "Load Ring"
        case (.cpu, .bar): return "Cluster Bars"
        case (.cpu, .sparkline): return "Usage History"

        // Memory (4)
        case (.memory, .text): return "Used %"
        case (.memory, .gauge): return "Pressure Ring"
        case (.memory, .bar): return "Allocation"
        case (.memory, .sparkline): return "Used % History"
        case (.memory, .symbol): return "Pressure"

        // GPU (4)
        case (.gpu, .text): return "GPU %"
        case (.gpu, .gauge): return "Load Ring"
        case (.gpu, .bar): return "Load Bar"
        case (.gpu, .sparkline): return "Load History"
        case (.gpu, .symbol): return "GPU Die"

        // Thermal (3)
        case (.thermal, .text): return "Temperature"
        case (.thermal, .glyph): return "Thermometer"
        case (.thermal, .sparkline): return "Peak History"
        case (.thermal, .gauge): return "Temp Ring"
        case (.thermal, .cpuTemp): return "CPU °C"
        case (.thermal, .gpuTemp): return "GPU °C"
        case (.thermal, .memoryTemp): return "Memory °C"
        case (.thermal, .storageTemp): return "SSD °C"
        case (.thermal, .batteryTemp): return "Battery °C"

        // Fans (5)
        case (.fan, .text): return "Fan RPM"
        case (.fan, .throughput): return "Dual RPM"
        case (.fan, .glyph): return "Fan Glyph"
        case (.fan, .bar): return "Fan Bars"
        case (.fan, .sparkline): return "RPM History"
        case (.fan, .gauge): return "Tachometer"
        case (.fan, .symbol): return "Blades"

        // Network (3)
        case (.network, .throughput): return "Up / Down"
        case (.network, .sparkline): return "Duplex History"
        case (.network, .symbol): return "Activity Arrows"
        case (.network, .bar): return "In / Out Bars"

        // Disk (5)
        case (.disk, .throughput): return "Read / Write"
        case (.disk, .sparkline): return "I/O History"
        case (.disk, .symbol): return "R/W LEDs"
        case (.disk, .gauge): return "Storage Ring"
        case (.disk, .text): return "Free Space"
        case (.disk, .bar): return "Storage Bar"

        // Power (4 battery / 2 desktop)
        case (.power, .symbol): return "Battery"
        case (.power, .text): return "Charge + Time"
        case (.power, .throughput): return "Draw / Adapter W"
        case (.power, .sparkline): return "Wattage History"
        case (.power, .gauge): return "Charge Ring"
        case (.power, .bar): return "Charge Bar"

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
        case .text: return "Numeric Text"
        case .throughput: return "Throughput Rates"
        case .bar: return "Bar Meter"
        case .gauge: return "Ring Gauge"
        case .sparkline: return "Sparkline Chart"
        case .symbol: return "Icon Symbol"
        case .glyph: return "Glyph Reading"
        case .cpuTemp: return "CPU Temperature"
        case .gpuTemp: return "GPU Temperature"
        case .memoryTemp: return "Memory Temperature"
        case .storageTemp: return "SSD Temperature"
        case .batteryTemp: return "Battery Temperature"
        }
    }

    /// Supported high-signal styles for a given metric category (32 total across all categories).
    public static func supportedStyles(for category: MetricCategory, hasBattery: Bool = true) -> [MetricDisplayStyle] {
        switch category {
        case .cpu:
            return [.text, .gauge, .bar, .sparkline] // 4
        case .memory:
            return [.text, .gauge, .bar, .sparkline] // 4
        case .gpu:
            return [.text, .gauge, .bar, .sparkline] // 4
        case .thermal:
            return [.text, .glyph, .sparkline] // 3
        case .fan:
            return [.text, .throughput, .glyph, .bar, .sparkline] // 5
        case .network:
            return [.throughput, .sparkline, .symbol] // 3
        case .disk:
            return [.throughput, .sparkline, .symbol, .gauge, .text] // 5
        case .power:
            return hasBattery
                ? [.symbol, .text, .throughput, .sparkline] // 4
                : [.throughput, .sparkline] // 2
        }
    }
}

// MARK: - Menu Bar Item Configuration

/// A user-configured metric item/widget to be displayed in the macOS menu bar.
/// Identified deterministically by composite `category.style[.source]` key.
public struct MenuBarItemConfig: Identifiable, Codable, Hashable, Equatable, Sendable {
    public var category: MetricCategory
    public var style: MetricDisplayStyle
    /// Tabbed popover configuration (ADR 0008).
    public var popover: PopoverConfig?
    /// Specific hardware subcomponent source for multi-source categories (e.g. Temperature).
    public var source: MetricSource?
    /// Layout option for throughput widgets.
    public var throughputLayout: ThroughputLayout?
    /// Whether to render a 3-letter vertical label for sparklines and rings.
    public var showLabel: Bool

    public var id: String {
        if let src = source {
            return "\(category.rawValue).\(style.rawValue).\(src.rawValue)"
        }
        return "\(category.rawValue).\(style.rawValue)"
    }

    public init(
        category: MetricCategory,
        style: MetricDisplayStyle,
        popover: PopoverConfig? = nil,
        source: MetricSource? = nil,
        throughputLayout: ThroughputLayout? = nil,
        showLabel: Bool = false
    ) {
        self.category = category
        self.style = style
        self.popover = popover
        self.source = source ?? (category == .thermal && (style == .text || style == .glyph) ? .peak : nil)
        self.throughputLayout = throughputLayout
        self.showLabel = showLabel
    }

    // MARK: - Codable Migration & Compatibility

    enum CodingKeys: String, CodingKey {
        case category
        case style
        case popover
        /// Decode-only: the pre-v2 `PopoverStyle` raw string, folded into `popover`.
        case popoverStyle
        case source
        case throughputLayout
        case showLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cat = try container.decode(MetricCategory.self, forKey: .category)
        self.category = cat

        let rawStyle = try container.decode(String.self, forKey: .style)
        var decodedSource = try container.decodeIfPresent(MetricSource.self, forKey: .source)

        // Decode-time migration table (plan.md §6)
        var targetStyle: MetricDisplayStyle
        switch (cat, rawStyle) {
        case (.memory, "symbol"):
            targetStyle = .gauge
        case (.gpu, "symbol"):
            targetStyle = .gauge
        case (.thermal, "cpuTemp"):
            targetStyle = .text
            decodedSource = .cpu
        case (.thermal, "gpuTemp"):
            targetStyle = .text
            decodedSource = .gpu
        case (.thermal, "memoryTemp"):
            targetStyle = .text
            decodedSource = .memory
        case (.thermal, "storageTemp"):
            targetStyle = .text
            decodedSource = .ssd
        case (.thermal, "batteryTemp"):
            targetStyle = .text
            decodedSource = .battery
        case (.thermal, "gauge"):
            targetStyle = .glyph
            decodedSource = .peak
        case (.fan, "gauge"), (.fan, "symbol"), (.fan, "tachometer"), (.fan, "blades"):
            targetStyle = .glyph
        case (.network, "bar"):
            targetStyle = .symbol
        case (.disk, "bar"):
            targetStyle = .text
        case (.power, "gauge"), (.power, "bar"):
            targetStyle = .symbol
        default:
            targetStyle = MetricDisplayStyle(rawValue: rawStyle) ?? .text
        }

        self.style = targetStyle
        self.source = decodedSource ?? (cat == .thermal && (targetStyle == .text || targetStyle == .glyph) ? .peak : nil)
        self.throughputLayout = try container.decodeIfPresent(ThroughputLayout.self, forKey: .throughputLayout)
        self.showLabel = try container.decodeIfPresent(Bool.self, forKey: .showLabel) ?? false

        let decodedPopover = try container.decodeIfPresent(PopoverConfig.self, forKey: .popover)
        // Pre-v2 data may carry a `popoverStyle` raw string; fold it into `popover` and never write it back.
        let legacyPopoverStyle = try container.decodeIfPresent(String.self, forKey: .popoverStyle)

        if let p = decodedPopover {
            self.popover = p
        } else if let legacy = legacyPopoverStyle {
            self.popover = PopoverConfig.migrated(fromLegacyRawValue: legacy, category: cat, widgetSource: self.source)
        } else {
            self.popover = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(style, forKey: .style)
        try container.encodeIfPresent(popover, forKey: .popover)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(throughputLayout, forKey: .throughputLayout)
        try container.encode(showLabel, forKey: .showLabel)
    }

    /// Resolves the effective popover configuration for this widget.
    public var resolvedPopoverConfig: PopoverConfig {
        if let p = popover { return p }
        let defaultTab: PopoverTab = (style == .sparkline) ? .history : .overview
        return PopoverConfig(openingTab: defaultTab, focusSource: source)
    }

    /// Deduplicates active menu bar items while strictly preserving first-occurrence order.
    public static func deduplicated(_ items: [MenuBarItemConfig]) -> [MenuBarItemConfig] {
        var seen = Set<String>()
        var result = [MenuBarItemConfig]()
        for item in items {
            if seen.insert(item.id).inserted {
                result.append(item)
            }
        }
        return result
    }

    /// All available standard widget configurations (32 widgets total).
    public static var allAvailableItems: [MenuBarItemConfig] {
        MetricCategory.allCases.flatMap { category in
            allStyles(for: category)
        }
    }

    /// All supported widget configurations for a specific metric category.
    public static func allStyles(for category: MetricCategory, hasBattery: Bool = true) -> [MenuBarItemConfig] {
        MetricDisplayStyle.supportedStyles(for: category, hasBattery: hasBattery).map { style in
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
