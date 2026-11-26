import Foundation

/// Layout orientation for dual-value (throughput) menu bar widgets.
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
///
/// Aligned to the shared six-family vocabulary (ADR 0011):
/// - `.text` -> **Value**
/// - `.throughput` -> **Dual**
/// - `.bar` -> **Bar**
/// - `.gauge` -> **Ring**
/// - `.sparkline` -> **Graph**
/// - `.glyph` -> **Glyph**
///
/// Raw values remain `"text"`, `"throughput"`, `"bar"`, `"gauge"`, `"sparkline"`, `"glyph"`
/// for persisted config compatibility; all legacy raw values (including `"symbol"`, `"tachometer"`,
/// `"blades"`, and the five legacy per-sensor thermal styles) migrate deterministically on decode.
public enum MetricDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case text
    case throughput
    case bar
    case gauge
    case sparkline
    case glyph

    // MARK: - Vocabulary & Compatibility Aliases

    public static let value: MetricDisplayStyle = .text
    public static let dual: MetricDisplayStyle = .throughput
    public static let ring: MetricDisplayStyle = .gauge
    public static let graph: MetricDisplayStyle = .sparkline
    /// Legacy alias preserved for source compatibility; unified under `.glyph`.
    public static let symbol: MetricDisplayStyle = .glyph

    public var id: String { rawValue }

    /// Shared vocabulary family (ADR 0011).
    public var widgetFamily: WidgetFamily {
        switch self {
        case .text: return .value
        case .throughput: return .dual
        case .bar: return .bar
        case .gauge: return .ring
        case .sparkline: return .graph
        case .glyph: return .glyph
        }
    }

    /// Canonical shared vocabulary name ("Value", "Dual", "Bar", "Ring", "Graph", "Glyph").
    public var vocabularyName: String {
        switch self {
        case .text: return "Value"
        case .throughput: return "Dual"
        case .bar: return "Bar"
        case .gauge: return "Ring"
        case .sparkline: return "Graph"
        case .glyph: return "Glyph"
        }
    }

    // MARK: - Codable Migration

    /// Migrates a standalone raw style string (including legacy and vocabulary aliases) into a canonical style.
    public static func migrated(fromRawValue raw: String) -> MetricDisplayStyle? {
        switch raw {
        case "text", "value", "cpuTemp", "gpuTemp", "memoryTemp", "storageTemp", "batteryTemp":
            return .text
        case "throughput", "dual":
            return .throughput
        case "bar":
            return .bar
        case "gauge", "ring":
            return .gauge
        case "sparkline", "graph":
            return .sparkline
        case "glyph", "symbol", "tachometer", "blades":
            return .glyph
        default:
            return MetricDisplayStyle(rawValue: raw)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let matched = Self.migrated(fromRawValue: raw) {
            self = matched
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown MetricDisplayStyle raw value: \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: - Display Names

    /// Category-specific descriptive metric name for preferences, catalog, and menus.
    public func displayName(for category: MetricCategory, hasBattery: Bool = true) -> String {
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

        // GPU (4)
        case (.gpu, .text): return "GPU %"
        case (.gpu, .gauge): return "Load Ring"
        case (.gpu, .bar): return "Load Bar"
        case (.gpu, .sparkline): return "Load History"

        // Thermal (3)
        case (.thermal, .text): return "Temperature"
        case (.thermal, .glyph): return "Thermometer"
        case (.thermal, .sparkline): return "Peak History"

        // Fans (4)
        case (.fan, .text): return "Fan RPM"
        case (.fan, .glyph): return "Fan Glyph"
        case (.fan, .bar): return "Fan Bars"
        case (.fan, .sparkline): return "RPM History"

        // Network (3)
        case (.network, .throughput): return "Up / Down"
        case (.network, .sparkline): return "Duplex History"
        case (.network, .glyph): return "Activity Arrows"

        // Disk (5)
        case (.disk, .throughput): return "Read / Write"
        case (.disk, .sparkline): return "I/O History"
        case (.disk, .glyph): return "R/W LEDs"
        case (.disk, .gauge): return "Storage Ring"
        case (.disk, .text): return "Free Space"

        // Power (3 battery / 2 desktop)
        case (.power, .glyph): return "Battery"
        case (.power, .text): return hasBattery ? "Charge + Time" : "Power Draw"
        case (.power, .sparkline): return "Wattage History"

        default:
            return vocabularyName
        }
    }

    /// Generic presentation family name.
    public var displayName: String {
        vocabularyName
    }

    /// Supported high-signal styles for a given metric category (29 with battery, 28 on desktop).
    ///
    /// Overloaded `.throughput` on Fan and Power is removed, Temperature's per-sensor styles
    /// collapse into `.text` with `source`, and duplicate rings/bars are eliminated.
    public static func supportedStyles(for category: MetricCategory, hasBattery: Bool = true) -> [MetricDisplayStyle] {
        switch category {
        case .cpu:
            return [.text, .gauge, .bar, .sparkline] // 4: Value, Ring, Bar, Graph
        case .memory:
            return [.text, .gauge, .bar, .sparkline] // 4: Value, Ring, Bar, Graph
        case .gpu:
            return [.text, .gauge, .bar, .sparkline] // 4: Value, Ring, Bar, Graph
        case .thermal:
            return [.text, .glyph, .sparkline] // 3: Value (with source), Glyph, Graph
        case .fan:
            return [.text, .glyph, .bar, .sparkline] // 4: Value, Glyph, Bar, Graph
        case .network:
            return [.throughput, .sparkline, .glyph] // 3: Dual, Graph, Glyph
        case .disk:
            return [.throughput, .sparkline, .glyph, .gauge, .text] // 5: Dual, Graph, Glyph, Ring, Value
        case .power:
            return hasBattery
                ? [.glyph, .text, .sparkline] // 3: Glyph (Battery), Value (Charge + Time), Graph
                : [.text, .sparkline] // 2: Value (Power Draw), Graph
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
    /// Layout option for dual (throughput) widgets.
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

    // MARK: - Legacy Raw-Value Migration Map

    /// All legacy raw style values that have existed across prior schemas, used for migration verification.
    public static let allLegacyStyleRawValues: [String] = [
        "text", "value",
        "throughput", "dual",
        "bar",
        "gauge", "ring",
        "sparkline", "graph",
        "symbol", "glyph",
        "tachometer", "blades",
        "cpuTemp", "gpuTemp", "memoryTemp", "storageTemp", "batteryTemp"
    ]

    /// Deterministic migration map from any legacy raw style string to a valid supported style
    /// (and optional sensor source) for `category`, so persisted configs are never dropped silently.
    public static func migratedStyle(
        for category: MetricCategory,
        rawStyle: String,
        source: MetricSource? = nil
    ) -> (style: MetricDisplayStyle, source: MetricSource?) {
        // Normalize vocabulary synonyms first.
        let normalized: String
        switch rawStyle {
        case "value": normalized = "text"
        case "dual": normalized = "throughput"
        case "ring": normalized = "gauge"
        case "graph": normalized = "sparkline"
        default: normalized = rawStyle
        }

        var targetStyle: MetricDisplayStyle
        var resolvedSource = source

        switch (category, normalized) {
        // CPU (supported: .text, .gauge, .bar, .sparkline)
        case (.cpu, "symbol"), (.cpu, "glyph"), (.cpu, "tachometer"), (.cpu, "blades"):
            targetStyle = .gauge
        case (.cpu, "throughput"):
            targetStyle = .bar

        // Memory (supported: .text, .gauge, .bar, .sparkline)
        case (.memory, "symbol"), (.memory, "glyph"), (.memory, "tachometer"), (.memory, "blades"):
            targetStyle = .gauge
        case (.memory, "throughput"):
            targetStyle = .bar

        // GPU (supported: .text, .gauge, .bar, .sparkline)
        case (.gpu, "symbol"), (.gpu, "glyph"), (.gpu, "tachometer"), (.gpu, "blades"):
            targetStyle = .gauge
        case (.gpu, "throughput"):
            targetStyle = .bar

        // Thermal (supported: .text, .glyph, .sparkline)
        case (.thermal, "cpuTemp"):
            targetStyle = .text
            resolvedSource = .cpu
        case (.thermal, "gpuTemp"):
            targetStyle = .text
            resolvedSource = .gpu
        case (.thermal, "memoryTemp"):
            targetStyle = .text
            resolvedSource = .memory
        case (.thermal, "storageTemp"):
            targetStyle = .text
            resolvedSource = .ssd
        case (.thermal, "batteryTemp"):
            targetStyle = .text
            resolvedSource = .battery
        case (.thermal, "gauge"), (.thermal, "symbol"), (.thermal, "glyph"), (.thermal, "tachometer"), (.thermal, "blades"):
            targetStyle = .glyph
            resolvedSource = resolvedSource ?? .peak
        case (.thermal, "bar"), (.thermal, "throughput"):
            targetStyle = .text
            resolvedSource = resolvedSource ?? .peak

        // Fans (supported: .text, .glyph, .bar, .sparkline)
        case (.fan, "throughput"):
            // Overloaded .throughput removed from Fan; migrate cleanly to Value (Fan RPM).
            targetStyle = .text
        case (.fan, "gauge"), (.fan, "symbol"), (.fan, "tachometer"), (.fan, "blades"), (.fan, "glyph"):
            targetStyle = .glyph

        // Network (supported: .throughput, .sparkline, .glyph)
        case (.network, "symbol"), (.network, "glyph"), (.network, "bar"), (.network, "tachometer"), (.network, "blades"):
            targetStyle = .glyph
        case (.network, "text"), (.network, "gauge"):
            targetStyle = .throughput

        // Disk (supported: .throughput, .sparkline, .glyph, .gauge, .text)
        case (.disk, "symbol"), (.disk, "glyph"), (.disk, "tachometer"), (.disk, "blades"):
            targetStyle = .glyph
        case (.disk, "bar"):
            targetStyle = .text

        // Power (supported: .glyph, .text, .sparkline)
        case (.power, "symbol"), (.power, "glyph"), (.power, "gauge"), (.power, "bar"), (.power, "tachometer"), (.power, "blades"):
            targetStyle = .glyph
        case (.power, "throughput"):
            // Overloaded .throughput removed from Power; migrate cleanly to Value (Charge + Time / Power Draw).
            targetStyle = .text

        default:
            if let direct = MetricDisplayStyle.migrated(fromRawValue: normalized),
               MetricDisplayStyle.supportedStyles(for: category).contains(direct) {
                targetStyle = direct
            } else {
                targetStyle = MetricDisplayStyle.supportedStyles(for: category).first ?? .text
            }
        }

        // Final safety net: guarantee the migrated style is always supported for the category.
        let supported = MetricDisplayStyle.supportedStyles(for: category)
        if !supported.contains(targetStyle) {
            targetStyle = supported.first ?? .text
        }

        if category == .thermal && (targetStyle == .text || targetStyle == .glyph) {
            resolvedSource = resolvedSource ?? .peak
        }

        return (targetStyle, resolvedSource)
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
        let decodedSource = try container.decodeIfPresent(MetricSource.self, forKey: .source)

        let migrated = Self.migratedStyle(for: cat, rawStyle: rawStyle, source: decodedSource)
        self.style = migrated.style
        self.source = migrated.source
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

    /// All available standard widget configurations across all categories.
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

    /// Sensible default starter widgets for the app (matches `MenuBarPreset.balanced`).
    public static func defaultConfigs() -> [MenuBarItemConfig] {
        [
            MenuBarItemConfig(category: .cpu, style: .bar),
            MenuBarItemConfig(category: .memory, style: .bar),
            MenuBarItemConfig(category: .network, style: .throughput)
        ]
    }
}
