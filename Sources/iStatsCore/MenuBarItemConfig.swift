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
        case (.fan, .text): return "Fan RPM"
        case (.fan, .throughput): return "Fan Speeds"
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
                : [.throughput, .sparkline]
        }
    }
    /// Primary widget choices. Legacy styles stay supported so existing menu
    /// bar configurations are preserved and can still be removed or edited.
    public static func recommendedStyles(for category: MetricCategory, hasBattery: Bool = true) -> [MetricDisplayStyle] {
        switch category {
        case .cpu: return [.text, .bar, .gauge, .sparkline]
        case .memory: return [.symbol, .text, .bar, .sparkline]
        case .gpu: return [.text, .bar, .sparkline]
        case .thermal: return hasBattery
            ? [.text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .batteryTemp, .sparkline]
            : [.text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .sparkline]
        case .fan: return [.text, .throughput, .bar, .sparkline]
        case .network: return [.throughput, .sparkline, .symbol]
        case .disk: return [.throughput, .bar, .sparkline]
        case .power: return hasBattery ? [.symbol, .text, .throughput, .sparkline] : [.throughput, .sparkline]
        }
    }

}

// MARK: - Popover Presentation Style (ADR 0007 Decoupled Popover Customization)

/// Selectable popover designs that can be bound to any menu bar widget.
public enum PopoverStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The default overview popover for the category (e.g. CPUPopoverView, MemoryPopoverView).
    case categoryDefault = "categoryDefault"

    /// Shared rolling telemetry history graph popover.
    case history = "history"

    // MARK: CPU Popovers
    case cpuUserSystem = "cpuUserSystem"
    case cpuCluster = "cpuCluster"

    // MARK: Memory Popovers
    case memoryComposition = "memoryComposition"
    case memoryAllocation = "memoryAllocation"
    case memoryPressure = "memoryPressure"

    // MARK: Thermal Popovers
    case thermalCPU = "thermalCPU"
    case thermalGPU = "thermalGPU"
    case thermalMemory = "thermalMemory"
    case thermalStorage = "thermalStorage"
    case thermalBattery = "thermalBattery"
    case thermalRing = "thermalRing"

    // MARK: Fan Popovers
    case fanDualRPM = "fanDualRPM"
    case fanTachometer = "fanTachometer"
    case fanBlades = "fanBlades"
    case fanBars = "fanBars"

    // MARK: GPU Popovers
    case gpuLoadRing = "gpuLoadRing"
    case gpuEngine = "gpuEngine"
    case gpuDie = "gpuDie"

    // MARK: Network Popovers
    case networkBars = "networkBars"
    case networkDiagnostics = "networkDiagnostics"

    // MARK: Disk Popovers
    case diskStorageRing = "diskStorageRing"
    case diskStorageTanks = "diskStorageTanks"
    case diskActivityLEDs = "diskActivityLEDs"

    // MARK: Power Popovers
    case powerBudget = "powerBudget"
    case powerWattage = "powerWattage"
    case powerChargeRing = "powerChargeRing"
    case powerBar = "powerBar"

    public var id: String { rawValue }

    /// Human-readable title for menus and pickers.
    public func displayName(for category: MetricCategory) -> String {
        switch self {
        case .categoryDefault:
            return "\(category.displayName) Overview"
        case .history:
            switch category {
            case .cpu: return "Usage History"
            case .memory: return "Memory History"
            case .thermal: return "Temperature History"
            case .fan: return "RPM History"
            case .gpu: return "GPU Utilization History"
            case .network: return "Traffic History"
            case .disk: return "I/O History"
            case .power: return "Wattage History"
            }
        // CPU
        case .cpuUserSystem: return "User / System"
        case .cpuCluster: return "Cores"

        // Memory
        case .memoryComposition: return "Memory Breakdown"
        case .memoryAllocation: return "Allocation Bars"
        case .memoryPressure: return "Pressure & Swap"

        // Thermal
        case .thermalCPU: return "CPU Thermals"
        case .thermalGPU: return "GPU Thermals"
        case .thermalMemory: return "Memory Thermals"
        case .thermalStorage: return "SSD Thermals"
        case .thermalBattery: return "Battery Thermals"
        case .thermalRing: return "Thermal Ring"

        // Fans
        case .fanDualRPM: return "Dual RPM"
        case .fanTachometer: return "Tachometers"
        case .fanBlades: return "Fan Blades"
        case .fanBars: return "Speed Bars"

        // GPU
        case .gpuLoadRing: return "Load Ring"
        case .gpuEngine: return "GPU Details"
        case .gpuDie: return "GPU Die"

        // Network
        case .networkBars: return "Bandwidth Bars"
        case .networkDiagnostics: return "Connection Details"

        // Disk
        case .diskStorageRing: return "Storage Volumes"
        case .diskStorageTanks: return "Storage Tanks"
        case .diskActivityLEDs: return "Disk Activity"

        // Power
        case .powerBudget: return "Power Budget"
        case .powerWattage: return "Power Details"
        case .powerChargeRing: return "Charge Ring"
        case .powerBar: return "Charge Bar"
        }
    }

    /// Supported popover styles for a given category.
    public static func supportedPopovers(for category: MetricCategory, hasBattery: Bool = true) -> [PopoverStyle] {
        switch category {
        case .cpu:
            return [.categoryDefault, .cpuUserSystem, .cpuCluster, .history]
        case .memory:
            return [.categoryDefault, .memoryComposition, .memoryAllocation, .memoryPressure, .history]
        case .thermal:
            return hasBattery
                ? [.categoryDefault, .thermalCPU, .thermalGPU, .thermalMemory, .thermalStorage, .thermalBattery, .thermalRing, .history]
                : [.categoryDefault, .thermalCPU, .thermalGPU, .thermalMemory, .thermalStorage, .thermalRing, .history]
        case .fan:
            return [.categoryDefault, .fanDualRPM, .fanTachometer, .fanBlades, .fanBars, .history]
        case .gpu:
            return [.categoryDefault, .gpuLoadRing, .gpuEngine, .gpuDie, .history]
        case .network:
            return [.categoryDefault, .networkBars, .networkDiagnostics, .history]
        case .disk:
            return [.categoryDefault, .diskStorageRing, .diskStorageTanks, .diskActivityLEDs, .history]
        case .power:
            return hasBattery
                ? [.categoryDefault, .powerBudget, .powerWattage, .powerChargeRing, .powerBar, .history]
                : [.categoryDefault, .powerWattage, .history]
        }
    }

    /// Destinations shown in the picker. Legacy styles remain supported for
    /// decoding and are routed to the closest destination at presentation time.
    public static func purposefulPopovers(for category: MetricCategory, hasBattery: Bool = true) -> [PopoverStyle] {
        switch category {
        case .cpu: return [.categoryDefault, .cpuCluster, .history]
        case .memory: return [.categoryDefault, .memoryComposition, .history]
        case .gpu: return [.categoryDefault, .gpuEngine, .history]
        case .thermal:
            return hasBattery
                ? [.categoryDefault, .thermalCPU, .thermalGPU, .thermalMemory, .thermalStorage, .thermalBattery, .history]
                : [.categoryDefault, .thermalCPU, .thermalGPU, .thermalMemory, .thermalStorage, .history]
        case .fan: return [.categoryDefault, .history]
        case .network: return [.categoryDefault, .networkDiagnostics, .history]
        case .disk: return [.categoryDefault, .diskStorageRing, .diskActivityLEDs]
        case .power:
            return [.categoryDefault, .powerWattage, .history]
        }
    }

    /// Maps older visual treatments to a destination without rewriting the
    /// stored value. This lets older preferences continue to decode safely.
    public func purposefulStyle(for category: MetricCategory) -> PopoverStyle {
        switch (category, self) {
        case (.cpu, .cpuUserSystem),
             (.memory, .memoryPressure),
             (.gpu, .gpuLoadRing), (.gpu, .gpuDie),
             (.thermal, .thermalRing),
             (.fan, .fanDualRPM), (.fan, .fanTachometer), (.fan, .fanBlades), (.fan, .fanBars),
             (.network, .networkBars),
             (.power, .powerBudget), (.power, .powerChargeRing), (.power, .powerBar):
            return .categoryDefault
        case (.memory, .memoryAllocation): return .memoryComposition
        case (.disk, .diskStorageTanks): return .diskStorageRing
        case (.disk, .history): return .diskActivityLEDs
        default: return self
        }
    }

    /// Natural default popover style for a given category and menu bar widget style.
    public static func defaultStyle(for category: MetricCategory, widgetStyle: MetricDisplayStyle, hasBattery: Bool = true) -> PopoverStyle {
        switch (category, widgetStyle) {
        // CPU
        case (.cpu, .gauge): return .cpuUserSystem
        case (.cpu, .bar): return .cpuCluster
        case (.cpu, .sparkline): return .history

        // Memory
        case (.memory, .gauge): return .memoryComposition
        case (.memory, .bar): return .memoryAllocation
        case (.memory, .symbol): return .memoryPressure
        case (.memory, .sparkline): return .history

        // GPU
        case (.gpu, .gauge): return .gpuLoadRing
        case (.gpu, .bar): return .gpuEngine
        case (.gpu, .symbol): return .gpuDie
        case (.gpu, .sparkline): return .history

        // Thermal (Specialized thermal subsystem widgets default to their dedicated popovers)
        case (.thermal, .cpuTemp): return .thermalCPU
        case (.thermal, .gpuTemp): return .thermalGPU
        case (.thermal, .memoryTemp): return .thermalMemory
        case (.thermal, .storageTemp): return .thermalStorage
        case (.thermal, .batteryTemp): return hasBattery ? .thermalBattery : .categoryDefault
        case (.thermal, .gauge): return .thermalRing
        case (.thermal, .sparkline): return .history

        // Fans
        case (.fan, .throughput): return .fanDualRPM
        case (.fan, .gauge): return .fanTachometer
        case (.fan, .symbol): return .fanBlades
        case (.fan, .bar): return .fanBars
        case (.fan, .sparkline): return .history

        // Network
        case (.network, .bar): return .networkBars
        case (.network, .sparkline): return .history
        case (.network, .symbol): return .networkDiagnostics

        // Disk
        case (.disk, .gauge): return .diskStorageRing
        case (.disk, .bar): return .diskStorageTanks
        case (.disk, .sparkline): return .history
        case (.disk, .symbol): return .diskActivityLEDs

        // Power
        case (.power, .text): return hasBattery ? .powerBudget : .powerWattage
        case (.power, .throughput): return .powerWattage
        case (.power, .gauge): return hasBattery ? .powerChargeRing : .powerWattage
        case (.power, .bar): return hasBattery ? .powerBar : .powerWattage
        case (.power, .sparkline): return .history
        case (.power, .symbol): return .categoryDefault

        default:
            return .categoryDefault
        }
    }
}

/// A user-configured metric item/widget to be displayed in the macOS menu bar.
/// Identified deterministically by composite `category.style` key.
public struct MenuBarItemConfig: Identifiable, Codable, Hashable, Equatable, Sendable {
    public var category: MetricCategory
    public var style: MetricDisplayStyle
    /// Explicit popover style assigned to this widget. When `nil`, uses the widget's default popover style.
    public var popoverStyle: PopoverStyle?

    public var id: String {
        "\(category.rawValue).\(style.rawValue)"
    }

    public init(
        category: MetricCategory,
        style: MetricDisplayStyle,
        popoverStyle: PopoverStyle? = nil
    ) {
        self.category = category
        self.style = style
        self.popoverStyle = popoverStyle
    }

    /// Resolves the effective popover style for this widget, falling back to the widget's default popover style.
    public var resolvedPopoverStyle: PopoverStyle {
        popoverStyle ?? PopoverStyle.defaultStyle(for: category, widgetStyle: style)
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


