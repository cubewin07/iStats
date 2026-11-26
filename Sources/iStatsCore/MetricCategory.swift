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

    /// Human-readable name (laptop wording; see `displayName(hasBattery:)`).
    public var displayName: String { identity.displayName() }

    public func displayName(hasBattery: Bool) -> String { identity.displayName(hasBattery: hasBattery) }

    /// Identity SF Symbol; forwards to `CategoryIdentity`.
    public func symbolName(hasBattery: Bool = true) -> String { identity.symbol(hasBattery: hasBattery) }

    public var symbolName: String { identity.symbol() }

    public func shortLabel(hasBattery: Bool = true) -> String { identity.shortLabel(hasBattery: hasBattery) }

    public var shortLabel: String { identity.shortLabel() }
}
