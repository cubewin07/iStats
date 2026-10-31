import Foundation

/// Semantic status severity level strictly adhering to the 4 universal status colors.
public enum StatusLevel: String, Codable, CaseIterable, Sendable, Comparable {
    case fine       // Normal, quiet, nominal headroom
    case elevated   // Warm, busy, spinning up, noticeable usage
    case warning    // High, loud, under pressure, warning threshold reached
    case critical   // Maxed out, overheating, emergency throttling

    public var severityRank: Int {
        switch self {
        case .fine: return 0
        case .elevated: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: StatusLevel, rhs: StatusLevel) -> Bool {
        lhs.severityRank < rhs.severityRank
    }
}

/// Canonical, pure severity evaluation tables for all metric categories.
public enum StatusThresholds {
    /// Evaluates total CPU usage percentage.
    public static func cpu(usagePercent: Double) -> StatusLevel {
        if usagePercent >= 90.0 {
            return .critical
        } else if usagePercent >= 65.0 {
            return .warning
        } else if usagePercent >= 25.0 {
            return .elevated
        } else {
            return .fine
        }
    }

    /// Evaluates memory health based on kernel memory pressure and swap utilization.
    public static func memory(pressure: MemoryPressure, swapUsedBytes: UInt64 = 0) -> StatusLevel {
        switch pressure {
        case .critical:
            return .critical
        case .warning:
            return .warning
        case .normal:
            // High swap usage (> 1 GB) on normal pressure indicates moderate memory churn
            if swapUsedBytes >= 1_000_000_000 {
                return .elevated
            }
            return .fine
        }
    }

    /// Evaluates GPU utilization percentage.
    public static func gpu(utilizationPercent: Double) -> StatusLevel {
        if utilizationPercent >= 92.0 {
            return .critical
        } else if utilizationPercent >= 75.0 {
            return .warning
        } else if utilizationPercent >= 50.0 {
            return .elevated
        } else {
            return .fine
        }
    }

    /// Evaluates component temperature against source-specific thresholds and system thermal pressure.
    public static func temperature(
        celsius: Double,
        source: MetricSource = .peak,
        pressure: ThermalPressure? = nil
    ) -> StatusLevel {
        // OS thermal pressure overrides if more severe
        let pressureLevel: StatusLevel
        switch pressure {
        case .critical:
            pressureLevel = .critical
        case .serious:
            pressureLevel = .warning
        case .fair:
            pressureLevel = .elevated
        case .nominal, .none:
            pressureLevel = .fine
        }

        let tempLevel: StatusLevel
        switch source {
        case .cpu, .gpu, .peak:
            if celsius >= 90.0 {
                tempLevel = .critical
            } else if celsius >= 75.0 {
                tempLevel = .warning
            } else if celsius >= 60.0 {
                tempLevel = .elevated
            } else {
                tempLevel = .fine
            }
        case .memory:
            if celsius >= 75.0 {
                tempLevel = .critical
            } else if celsius >= 60.0 {
                tempLevel = .warning
            } else if celsius >= 50.0 {
                tempLevel = .elevated
            } else {
                tempLevel = .fine
            }
        case .ssd:
            if celsius >= 70.0 {
                tempLevel = .critical
            } else if celsius >= 55.0 {
                tempLevel = .warning
            } else if celsius >= 45.0 {
                tempLevel = .elevated
            } else {
                tempLevel = .fine
            }
        case .battery:
            if celsius >= 45.0 {
                tempLevel = .critical
            } else if celsius >= 38.0 {
                tempLevel = .warning
            } else if celsius >= 32.0 {
                tempLevel = .elevated
            } else {
                tempLevel = .fine
            }
        }

        return max(tempLevel, pressureLevel)
    }

    /// Evaluates fan speed as a fraction of physical operational range.
    public static func fan(rpm: Double, minRPM: Double, maxRPM: Double) -> StatusLevel {
        guard maxRPM > minRPM else { return .fine }
        let fraction = max(0.0, min(1.0, (rpm - minRPM) / (maxRPM - minRPM)))
        if fraction >= 0.95 {
            return .critical
        } else if fraction >= 0.80 {
            return .warning
        } else if fraction >= 0.50 {
            return .elevated
        } else {
            return .fine
        }
    }

    /// Evaluates volume disk capacity used percentage.
    public static func disk(usedPercent: Double) -> StatusLevel {
        if usedPercent >= 95.0 {
            return .critical
        } else if usedPercent >= 90.0 {
            return .warning
        } else if usedPercent >= 85.0 {
            return .elevated
        } else {
            return .fine
        }
    }

    /// Evaluates battery state, charge percentage, and power deficit.
    public static func battery(
        chargePercent: Double,
        isCharging: Bool,
        powerDeficitWatts: Double? = nil
    ) -> StatusLevel {
        if let deficit = powerDeficitWatts, deficit > 0 {
            return .warning
        }

        if !isCharging {
            if chargePercent <= 10.0 {
                return .critical
            } else if chargePercent <= 20.0 {
                return .warning
            } else if chargePercent <= 30.0 {
                return .elevated
            }
        }
        return .fine
    }
}
