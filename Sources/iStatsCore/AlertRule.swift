import Foundation

/// The kinds of threshold alerts iStats can raise.
public enum AlertKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu
    case memory
    case batteryLow
    case batteryFull
    case temperature
    case disk

    public var id: String { rawValue }

    /// Allowed threshold range for this kind (the legacy slider bounds).
    public var thresholdRange: ClosedRange<Double> {
        switch self {
        case .cpu, .memory: return 50.0...100.0
        case .batteryLow: return 5.0...50.0
        case .batteryFull: return 100.0...100.0
        case .temperature: return 60.0...105.0 // Celsius
        case .disk: return 70.0...98.0
        }
    }

    /// Factory threshold (percent, or Celsius for temperature).
    public var defaultThreshold: Double {
        switch self {
        case .cpu: return 90.0
        case .memory: return 85.0
        case .batteryLow: return 20.0
        case .batteryFull: return 100.0
        case .temperature: return 90.0
        case .disk: return 90.0
        }
    }

    public var defaultComparison: AlertComparison {
        self == .batteryLow ? .below : .above
    }
}

public enum AlertComparison: String, Codable, Sendable, CaseIterable {
    case above
    case below
}

/// One user-configurable alert. Replaces the 15 scattered per-alert preference keys.
public struct AlertRule: Codable, Hashable, Sendable, Identifiable {
    public static let minCooldownSeconds: TimeInterval = 30.0
    public static let defaultCooldownSeconds: TimeInterval = 300.0

    public var kind: AlertKind
    public var enabled: Bool
    /// Percent (or Celsius for `.temperature`). Clamped to `kind.thresholdRange` by `clamped()`.
    public var threshold: Double
    public var comparison: AlertComparison
    /// The condition must hold this long before firing (0 = fire on a single sample).
    public var sustainSeconds: TimeInterval
    public var cooldownSeconds: TimeInterval
    /// Optional scope: a volume path (disk) or interface name (network).
    public var target: String?

    public var id: String { kind.rawValue }

    public init(
        kind: AlertKind,
        enabled: Bool = false,
        threshold: Double? = nil,
        comparison: AlertComparison? = nil,
        sustainSeconds: TimeInterval = 0,
        cooldownSeconds: TimeInterval = AlertRule.defaultCooldownSeconds,
        target: String? = nil
    ) {
        self.kind = kind
        self.enabled = enabled
        self.threshold = threshold ?? kind.defaultThreshold
        self.comparison = comparison ?? kind.defaultComparison
        self.sustainSeconds = sustainSeconds
        self.cooldownSeconds = cooldownSeconds
        self.target = target
    }

    /// Factory rule for a kind (disabled, documented defaults).
    public static func `default`(for kind: AlertKind) -> AlertRule { AlertRule(kind: kind) }

    public static var defaults: [AlertRule] { AlertKind.allCases.map { `default`(for: $0) } }

    /// A copy with threshold, sustain, and cooldown forced into their valid ranges.
    public func clamped() -> AlertRule {
        var copy = self
        let range = kind.thresholdRange
        copy.threshold = min(max(threshold, range.lowerBound), range.upperBound)
        copy.sustainSeconds = max(sustainSeconds, 0)
        copy.cooldownSeconds = max(cooldownSeconds, Self.minCooldownSeconds)
        return copy
    }

    /// Whether `value` satisfies this rule's comparison against its threshold.
    public func isTriggered(by value: Double) -> Bool {
        switch comparison {
        case .above: return value >= threshold
        case .below: return value <= threshold
        }
    }
}
