import SwiftUI
import iStatsCore

/// Semantic status severity level strictly adhering to the 4 universal status colors.
public enum StatusLevel: String, Sendable, Equatable, CaseIterable {
    case fine       // Green: Fine, Quiet, Plenty of space, Normal
    case elevated   // Yellow: Warm, Busy, Spinning up, Getting full
    case warning    // Orange: High, Loud, Under pressure, Warning
    case critical   // Red: Problem now, Critical, Too hot, Almost full, Max

    public var color: Color {
        switch self {
        case .fine: return .green
        case .elevated: return .yellow
        case .warning: return .orange
        case .critical: return .red
        }
    }

    public var iconName: String {
        switch self {
        case .fine: return "checkmark.circle.fill"
        case .elevated: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

/// A human-first verdict that evaluates raw telemetry into an instant answer followed by diagnostic proof.
public struct MetricVerdict: Sendable, Equatable {
    public let level: StatusLevel
    public let badgeText: String
    public let dadSentence: String
    public let primaryValue: String
    public let secondaryValue: String?

    public init(
        level: StatusLevel,
        badgeText: String,
        dadSentence: String,
        primaryValue: String,
        secondaryValue: String? = nil
    ) {
        self.level = level
        self.badgeText = badgeText
        self.dadSentence = dadSentence
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
    }
}

// MARK: - Category Verdict Evaluators

public enum VerdictEvaluator {
    // MARK: - CPU
    public static func evaluateCPU(_ sample: CPUSample?) -> MetricVerdict {
        guard let s = sample else {
            return MetricVerdict(
                level: .fine,
                badgeText: "Ready",
                dadSentence: "Sampling processor telemetry...",
                primaryValue: "—%"
            )
        }

        let usage = s.totalUsage
        let level: StatusLevel
        let badge: String
        let sentence: String

        if usage >= 90.0 {
            level = .critical
            badge = "Maxed"
            sentence = "The processor is maxed out"
        } else if usage >= 65.0 {
            level = .warning
            badge = "Very busy"
            sentence = "Heavy processing workload active"
        } else if usage >= 25.0 {
            level = .elevated
            badge = "Busy"
            sentence = "Apps are using the processor"
        } else {
            level = .fine
            badge = "Fine"
            sentence = usage < 5.0 ? "Mostly idle" : "Working normally"
        }

        let secondary = "Apps \(String(format: "%.0f%%", s.user))  ·  System \(String(format: "%.0f%%", s.system))"

        return MetricVerdict(
            level: level,
            badgeText: badge,
            dadSentence: sentence,
            primaryValue: String(format: "%.1f%%", usage),
            secondaryValue: secondary
        )
    }

    // MARK: - Memory
    public static func evaluateMemory(_ sample: MemorySample?, standard: Units.ByteUnitStandard = .iec) -> MetricVerdict {
        guard let s = sample else {
            return MetricVerdict(
                level: .fine,
                badgeText: "Ready",
                dadSentence: "Sampling memory allocation...",
                primaryValue: "—"
            )
        }

        let level: StatusLevel
        let badge: String
        let sentence: String

        switch s.pressure {
        case .normal:
            level = .fine
            badge = "Fine"
            sentence = "Plenty of memory available"
        case .warning:
            level = .warning
            badge = "Warning"
            sentence = "macOS is reclaiming memory. Apps may feel slower."
        case .critical:
            level = .critical
            badge = "Critical"
            sentence = "The Mac is out of usable memory. Close some apps."
        }

        let usedStr = Units.formatBytes(s.used, standard: standard, fractionDigits: 1)
        let totalStr = Units.formatBytes(s.total, standard: standard, fractionDigits: 0)

        var secondary = "\(usedStr) of \(totalStr)"
        if s.swapUsed > 0 {
            secondary += "  ·  Swap used: \(Units.formatBytes(s.swapUsed, standard: standard, fractionDigits: 1))"
        }

        return MetricVerdict(
            level: level,
            badgeText: badge,
            dadSentence: sentence,
            primaryValue: s.pressure.displayName,
            secondaryValue: secondary
        )
    }

    // MARK: - Thermals
    public static func evaluateThermal(_ sample: ThermalSample?, unit: Units.TemperatureUnit = .celsius) -> MetricVerdict {
        guard let s = sample, !s.sensors.isEmpty else {
            return MetricVerdict(
                level: .fine,
                badgeText: "Ready",
                dadSentence: "Monitoring internal temperatures...",
                primaryValue: "—°"
            )
        }

        // Primary SoC / Package sensor
        let primary = s.sensors.first(where: {
            $0.name.contains("Package") || $0.name.contains("SoC") || $0.name.contains("CPU")
        }) ?? s.sensors.first!

        let maxSensor = s.sensors.max(by: { $0.celsius < $1.celsius })
        let maxTemp = maxSensor?.celsius ?? primary.celsius
        let level: StatusLevel
        let badge: String
        let sentence: String

        switch s.pressure {
        case .critical:
            level = .critical
            badge = "Critical"
            sentence = "macOS reports critical thermal pressure"
        case .serious:
            level = .warning
            badge = "Serious"
            sentence = "macOS reports serious thermal pressure"
        case .fair:
            level = .elevated
            badge = "Fair"
            sentence = "macOS reports fair thermal pressure"
        case .nominal:
            level = .fine
            badge = "Nominal"
            sentence = "macOS reports nominal thermal pressure"
        case nil:
            level = .fine
            badge = "Unavailable"
            sentence = "Thermal pressure is not reported"
        }

        let primaryFormatted = Units.formatTemperature(primary.celsius, unit: unit, fractionDigits: 0)
        let secondary = maxSensor != nil && maxSensor!.name != primary.name
            ? "Hottest: \(cleanSensorName(maxSensor!.name)) \(Units.formatTemperature(maxTemp, unit: unit, fractionDigits: 0))"
            : "\(primary.name): \(Units.formatTemperature(primary.celsius, unit: unit, fractionDigits: 1))"

        return MetricVerdict(
            level: level,
            badgeText: badge,
            dadSentence: sentence,
            primaryValue: primaryFormatted,
            secondaryValue: secondary
        )
    }

    // MARK: - Fans
    public static func evaluateFan(_ sample: FanSample?) -> MetricVerdict {
        guard let s = sample else {
            return MetricVerdict(
                level: .fine,
                badgeText: "Ready",
                dadSentence: "Monitoring cooling subsystem...",
                primaryValue: "—"
            )
        }

        guard let maxRPM = s.fans.map(\.rpm).max() else {
            return MetricVerdict(level: .fine, badgeText: "No fans detected",
                                 dadSentence: "No fan readings are reported",
                                 primaryValue: "—")
        }
        return MetricVerdict(level: .fine, badgeText: "Monitoring",
                             dadSentence: "Highest reported fan speed",
                             primaryValue: Units.formatRPM(maxRPM),
                             secondaryValue: "\(s.fans.count) fan\(s.fans.count == 1 ? "" : "s") reported")
    }

    // MARK: - GPU
    public static func evaluateGPU(_ sample: GPUSample?) -> MetricVerdict {
        guard let s = sample else {
            return MetricVerdict(
                level: .fine,
                badgeText: "Ready",
                dadSentence: "Monitoring graphics processor...",
                primaryValue: "—%"
            )
        }

        guard let util = s.utilization else {
            return MetricVerdict(
                level: .fine,
                badgeText: "Unavailable",
                dadSentence: "GPU load is not reported on this Mac",
                primaryValue: "—",
                secondaryValue: s.memoryUsed != nil ? Units.formatBytes(s.memoryUsed!) : nil
            )
        }

        let level: StatusLevel
        let badge: String
        let sentence: String

        if util >= 90.0 {
            level = .critical
            badge = "Maxed"
            sentence = "Graphics processor at maximum capacity"
        } else if util >= 50.0 {
            level = .warning
            badge = "Working hard"
            sentence = "Heavy 3D rendering or compute workload"
        } else if util >= 15.0 {
            level = .elevated
            badge = "Working"
            sentence = "Apps are using graphics rendering"
        } else {
            level = .fine
            badge = "Idle"
            sentence = "Graphics processor is mostly idle"
        }

        return MetricVerdict(
            level: level,
            badgeText: badge,
            dadSentence: sentence,
            primaryValue: String(format: "%.1f%%", util),
            secondaryValue: s.memoryUsed != nil ? "GPU memory: \(Units.formatBytes(s.memoryUsed!))" : nil
        )
    }

    // MARK: - Network
    public static func evaluateNetwork(_ sample: NetworkSample?, unit: Units.NetworkUnit = .bytesPerSecond, standard: Units.ByteUnitStandard = .iec) -> MetricVerdict {
        guard let s = sample else {
            return MetricVerdict(
                level: .fine,
                badgeText: "Ready",
                dadSentence: "Monitoring network traffic...",
                primaryValue: "—"
            )
        }

        let downRate = s.totalBytesInPerSec
        let upRate = s.totalBytesOutPerSec
        let totalRate = downRate + upRate

        let level: StatusLevel
        let badge: String
        let sentence: String

        // Thresholds: > 5MB/s = busy, > 500KB/s = active
        if totalRate > 5_000_000 {
            level = .elevated
            if downRate > upRate * 3 {
                badge = "Downloading"
                sentence = "Fast download in progress"
            } else if upRate > downRate * 3 {
                badge = "Uploading"
                sentence = "Large upload in progress"
            } else {
                badge = "Busy"
                sentence = "Heavy bidirectional network traffic"
            }
        } else if totalRate > 200_000 {
            level = .fine
            if downRate > upRate * 2 {
                badge = "Downloading"
                sentence = "Network receiving data"
            } else if upRate > downRate * 2 {
                badge = "Uploading"
                sentence = "Network sending data"
            } else {
                badge = "Active"
                sentence = "Network traffic flowing"
            }
        } else {
            level = .fine
            badge = "Idle"
            sentence = "Network connection is mostly idle"
        }

        let downStr = Units.formatNetworkRate(downRate, unit: unit, standard: standard, fractionDigits: 1)
        let upStr = Units.formatNetworkRate(upRate, unit: unit, standard: standard, fractionDigits: 1)

        return MetricVerdict(
            level: level,
            badgeText: badge,
            dadSentence: sentence,
            primaryValue: downStr,
            secondaryValue: "↓ \(downStr)  ↑ \(upStr)"
        )
    }

    // MARK: - Disk
    public static func evaluateDisk(_ sample: DiskSample?, standard: Units.ByteUnitStandard = .iec) -> MetricVerdict {
        guard let s = sample, let bootVol = s.volumes.first(where: { $0.mountPoint == "/" }) ?? s.volumes.first else {
            return MetricVerdict(
                level: .fine,
                badgeText: "Ready",
                dadSentence: "Monitoring disk storage...",
                primaryValue: "—"
            )
        }

        let total = Double(bootVol.total)
        let used = Double(bootVol.used)
        let usedRatio = total > 0 ? (used / total) * 100.0 : 0.0

        let level: StatusLevel
        let badge: String
        let sentence: String

        if usedRatio >= 95.0 {
            level = .critical
            badge = "Almost full"
            sentence = "macOS needs free space. Storage critical."
        } else if usedRatio >= 85.0 {
            level = .elevated
            badge = "Getting full"
            sentence = "Storage is over 85% capacity"
        } else {
            level = .fine
            badge = "Plenty of space"
            sentence = "Storage capacity is healthy"
        }

        let freeStr = Units.formatBytes(bootVol.free, standard: standard, fractionDigits: 0)
        let totalStr = Units.formatBytes(bootVol.total, standard: standard, fractionDigits: 0)

        return MetricVerdict(
            level: level,
            badgeText: badge,
            dadSentence: sentence,
            primaryValue: "\(freeStr) free",
            secondaryValue: "\(freeStr) free of \(totalStr)"
        )
    }

    // MARK: - Battery & Power
    public static func evaluatePower(_ sample: PowerSample?) -> MetricVerdict {
        guard let s = sample else {
            return MetricVerdict(level: .fine, badgeText: "Ready", dadSentence: "Waiting for power readings", primaryValue: "—")
        }
        guard s.hasBattery else {
            return MetricVerdict(level: .fine, badgeText: "No battery", dadSentence: "No internal battery reported",
                                 primaryValue: s.powerDrawWatts.map { String(format: "%.1f W", $0) } ?? "—")
        }
        let charge = s.charge.map { String(format: "%.0f%%", $0) } ?? "—"
        let badge: String
        let sentence: String
        var level: StatusLevel = .fine
        switch s.state {
        case .charging:
            badge = "Charging"; sentence = "Battery is charging"
        case .charged:
            badge = "Charged"; sentence = "Battery is charged"
        case .acConnected:
            badge = "Connected"; sentence = "Connected to power"
        case .discharging:
            if let value = s.charge, value <= 10 { level = .critical; badge = "Low battery" }
            else if let value = s.charge, value <= 20 { level = .warning; badge = "Low battery" }
            else { badge = "On battery" }
            sentence = "Battery is discharging"
        case .unknown, nil:
            badge = "Unavailable"; sentence = "Battery state is not reported"
        }
        return MetricVerdict(level: level, badgeText: badge, dadSentence: sentence, primaryValue: charge)
    }

    private static func cleanSensorName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "Module ", with: "RAM ")
            .replacingOccurrences(of: "Flash (NAND)", with: "SSD")
            .replacingOccurrences(of: "Efficiency Cores", with: "E-Cores")
            .replacingOccurrences(of: "Package", with: "SoC")
    }
}
