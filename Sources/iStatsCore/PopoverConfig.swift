import Foundation

/// Navigation tabs available within a category popover.
public enum PopoverTab: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview
    case detail
    case history

    public var id: String { rawValue }

    /// Returns the user-facing title for this tab within a given category.
    public func title(for category: MetricCategory, hasDetailedGPUEngines: Bool = true) -> String {
        switch self {
        case .overview:
            return "Overview"
        case .history:
            return "History"
        case .detail:
            switch category {
            case .cpu: return "Cores"
            case .memory: return "Pressure"
            case .gpu: return hasDetailedGPUEngines ? "Engines" : "Device"
            case .thermal: return "Sensors"
            case .fan: return "Fans"
            case .network: return "Connection"
            case .disk: return "Volumes"
            case .power: return "Health"
            }
        }
    }

    /// Returns the ordered list of tabs supported by a category on the current hardware.
    public static func supportedTabs(for category: MetricCategory, hasBattery: Bool = true) -> [PopoverTab] {
        switch category {
        case .fan:
            return [.overview, .history]
        case .power:
            return hasBattery ? [.overview, .detail, .history] : [.overview, .history]
        case .cpu, .memory, .gpu, .thermal, .network, .disk:
            return [.overview, .detail, .history]
        }
    }
}

/// Configuration specifying the opening behavior and initial focus of a category popover.
public struct PopoverConfig: Codable, Hashable, Equatable, Sendable {
    public var openingTab: PopoverTab
    public var rememberLastTab: Bool
    public var focusSource: MetricSource?

    public init(
        openingTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        focusSource: MetricSource? = nil
    ) {
        self.openingTab = openingTab
        self.rememberLastTab = rememberLastTab
        self.focusSource = focusSource
    }

    /// Migrates a legacy Phase 6 `PopoverStyle` raw string into a modern `PopoverConfig`.
    public static func migrated(
        fromLegacyRawValue raw: String,
        category: MetricCategory,
        widgetSource: MetricSource? = nil
    ) -> PopoverConfig {
        switch raw {
        case "categoryDefault", "cpuUserSystem", "memoryComposition", "memoryAllocation",
             "gpuLoadRing", "thermalRing", "networkBars", "diskStorageRing",
             "diskActivityLEDs", "powerBudget", "powerWattage", "powerChargeRing", "powerBar":
            return PopoverConfig(openingTab: .overview, focusSource: widgetSource)
        case _ where raw.hasPrefix("fan"):
            return PopoverConfig(openingTab: .overview)
        case "thermalCPU":
            return PopoverConfig(openingTab: .overview, focusSource: .cpu)
        case "thermalGPU":
            return PopoverConfig(openingTab: .overview, focusSource: .gpu)
        case "thermalMemory":
            return PopoverConfig(openingTab: .overview, focusSource: .memory)
        case "thermalStorage":
            return PopoverConfig(openingTab: .overview, focusSource: .ssd)
        case "thermalBattery":
            return PopoverConfig(openingTab: .overview, focusSource: .battery)
        case "cpuCluster", "memoryPressure", "gpuEngine", "gpuDie", "networkDiagnostics", "diskStorageTanks":
            return PopoverConfig(openingTab: .detail)
        case "history":
            return PopoverConfig(openingTab: .history)
        default:
            return PopoverConfig(openingTab: .overview, focusSource: widgetSource)
        }
    }
}
