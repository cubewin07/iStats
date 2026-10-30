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

    /// Shared category identity used in preferences and popover headers.
    /// Metric-specific indicators remain independent from these static symbols.
    public var systemImageName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .fan: return "fan"
        case .gpu: return "square.grid.2x2"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "battery.100percent"
        }
    }

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
}
