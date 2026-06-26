import Foundation

/// The categories of metrics iStats can monitor. Each maps to one `Sampler`.
///
/// See `docs/architecture.md` for how categories flow from the Sampling layer
/// through the Domain Core to the Presentation layer.
public enum MetricCategory: String, CaseIterable, Sendable, Codable {
    case cpu
    case memory
    case thermal
    case fan
    case gpu
    case network
    case disk
    case power

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
