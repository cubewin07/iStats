import Foundation

/// The categories of metrics iStats can monitor. Each maps to one `Sampler`.
///
/// See `docs/architecture.md` for how categories flow from the Sampling layer
/// through the Domain Core to the Presentation layer.
public enum MetricCategory: String, CaseIterable, Sendable, Codable, Identifiable {
    case cpu
    case memory
    case thermal
    case fan
    case gpu
    case network
    case disk
    case power

    public var id: String { rawValue }

    /// Human-readable name for display in the UI.
    public var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .thermal: return "Temperature"
        case .fan: return "Fans"
        case .gpu: return "GPU"
        case .network: return "Network"
        case .disk: return "Disk"
        case .power: return "Battery & Power"
        }
    }

    /// Canonical SF Symbol name representing this metric category.
    public func symbolName(hasBattery: Bool = true) -> String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .fan: return "fan"
        case .gpu: return "square.3.layers.3d"
        case .network: return "arrow.up.arrow.down"
        case .disk: return "internaldrive"
        case .power: return hasBattery ? "battery.100percent.bolt" : "powerplug.fill"
        }
    }

    /// Default SF Symbol name assuming standard battery-supported hardware.
    public var symbolName: String {
        symbolName(hasBattery: true)
    }

    /// Standard 3-letter abbreviation used for vertical widget labels.
    public func shortLabel(hasBattery: Bool = true) -> String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .thermal: return "TMP"
        case .fan: return "FAN"
        case .gpu: return "GPU"
        case .network: return "NET"
        case .disk: return "SSD"
        case .power: return hasBattery ? "BAT" : "PWR"
        }
    }

    /// Standard 3-letter abbreviation defaulting to battery Mac representation.
    public var shortLabel: String {
        shortLabel(hasBattery: true)
    }
}
