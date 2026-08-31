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
            secondary += "  ·  Swap active"
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
        let pressure = s.pressure ?? .nominal

        let level: StatusLevel
        let badge: String
        let sentence: String

        switch pressure {
        case .critical:
            level = .critical
            badge = "Too hot"
            sentence = "macOS is throttling CPU to cool down"
        case .serious:
            level = .warning
            badge = "Hot"
            sentence = "System running hot under sustained load"
        case .fair:
            level = .elevated
            badge = "Warm"
            sentence = "Warm, but macOS has not throttled"
        case .nominal:
            if maxTemp >= 95.0 {
                level = .warning
                badge = "Hot"
                sentence = "Hottest sensor elevated; not throttling"
            } else if primary.celsius >= 75.0 {
                level = .elevated
                badge = "Warm"
                sentence = "macOS has not throttled"
            } else {
                level = .fine
                badge = "Cool"
                sentence = "Temperatures are optimal"
            }
        }

        let primaryFormatted = Units.formatTemperature(primary.celsius, unit: unit, fractionDigits: 0)
        let secondary = maxSensor != nil && maxSensor!.name != primary.name
            ? "Hottest: \(cleanSensorName(maxSensor!.name)) \(Units.formatTemperature(maxTemp, unit: unit, fractionDigits: 0))"
            : "SoC Package: \(Units.formatTemperature(primary.celsius, unit: unit, fractionDigits: 1))"

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

        if s.isFanless {
            return MetricVerdict(
                level: .fine,
                badgeText: "Fanless",
                dadSentence: "This Mac has no fans (passive cooling)",
                primaryValue: "Passive",
                secondaryValue: "Silent operation"
            )
        }

        let maxRPM = s.fans.map(\.rpm).max() ?? 0
        let maxPossibleRPM = s.fans.compactMap(\.maxRPM).max() ?? 6000
        let minPossibleRPM = s.fans.compactMap(\.minRPM).min() ?? 1200
        
        let ratio: Double
        if maxPossibleRPM > minPossibleRPM {
            ratio = max(0.0, min(1.0, Double(maxRPM - minPossibleRPM) / Double(maxPossibleRPM - minPossibleRPM)))
        } else {
            ratio = max(0.0, min(1.0, Double(maxRPM) / Double(maxPossibleRPM)))
        }

        let pctOfMax = Int(ratio * 100)

        let level: StatusLevel
        let badge: String
        let sentence: String

        if pctOfMax >= 80 {
            level = .critical
            badge = "Max"
            sentence = "Fans running at maximum cooling power"
        } else if pctOfMax >= 45 {
            level = .warning
            badge = "Loud"
            sentence = "Cooling under sustained heat"
        } else if pctOfMax >= 15 {
            level = .elevated
            badge = "Spinning up"
            sentence = "Fans actively dissipating heat"
        } else {
            level = .fine
            badge = "Quiet"
            sentence = "Whisper quiet / idle cooling"
        }

        let secondary = "\(Units.formatRPM(maxRPM)) · firmware auto"

        return MetricVerdict(
            level: level,
            badgeText: badge,
            dadSentence: sentence,
            primaryValue: "\(pctOfMax)%",
            secondaryValue: secondary
        )
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
                badgeText: "Active",
                dadSentence: "GPU load is not reported on this Mac",
                primaryValue: "Active",
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
            secondaryValue: s.memoryUsed != nil ? "VRAM: \(Units.formatBytes(s.memoryUsed!))" : nil
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
            return MetricVerdict(
                level: .fine,
                badgeText: "Ready",
                dadSentence: "Monitoring power telemetry...",
                primaryValue: "—"
            )
        }

        if !s.hasBattery {
            let watts = s.powerDrawWatts != nil ? "\(Int(s.powerDrawWatts!)) W" : "AC"
            return MetricVerdict(
                level: .fine,
                badgeText: "On AC Power",
                dadSentence: "This Mac is on power. Drawing \(watts).",
                primaryValue: watts,
                secondaryValue: "Desktop Mac (AC Powered)"
            )
        }

        let charge = s.charge ?? 100.0
        let state = s.state ?? .discharging

        let level: StatusLevel
        let badge: String
        let sentence: String

        switch state {
        case .charging:
            level = .fine
            if let time = s.timeRemaining, time > 0 && time < 86400 {
                let mins = Int(time / 60)
                if mins >= 60 {
                    badge = "\(mins / 60)h \(mins % 60)m to full"
                } else {
                    badge = "\(mins) min to full"
                }
                sentence = "Battery charging rapidly"
            } else {
                badge = "Charging"
                sentence = "Connected to power adapter"
            }
        case .charged:
            level = .fine
            badge = "Fully Charged"
            sentence = "On AC power. Battery full."
        case .acConnected:
            level = .fine
            if charge >= 99.0 {
                badge = "Fully Charged"
                sentence = "On AC power. Battery full."
            } else {
                badge = "Not Charging"
                sentence = "Connected to power. Battery not charging."
            }
        case .discharging, .unknown:
            if charge <= 10.0 {
                level = .critical
                badge = "Plug in now"
                sentence = "Battery is critically low"
            } else if charge <= 20.0 {
                level = .warning
                badge = "Plug in soon"
                sentence = "Battery level is low"
            } else if charge <= 40.0 {
                level = .elevated
                badge = "Running down"
                sentence = formatBatteryTimeSentence(s.timeRemaining)
            } else {
                level = .fine
                badge = formatBatteryTimeBadge(s.timeRemaining)
                sentence = "Battery discharge is normal"
            }
        }

        let chargeStr = String(format: "%.0f%%", charge)
        var secondary = chargeStr
        if let watts = s.powerDrawWatts {
            secondary += " · \(String(format: "%.1f W", watts))"
        }

        return MetricVerdict(
            level: level,
            badgeText: badge,
            dadSentence: sentence,
            primaryValue: chargeStr,
            secondaryValue: secondary
        )
    }

    private static func formatBatteryTimeBadge(_ timeRemaining: TimeInterval?) -> String {
        guard let time = timeRemaining, time > 0 && time < 86400 else {
            return "On Battery"
        }
        let mins = Int(time / 60)
        let hours = mins / 60
        let remainingMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remainingMins)m left"
        }
        return "\(mins)m left"
    }

    private static func formatBatteryTimeSentence(_ timeRemaining: TimeInterval?) -> String {
        guard let time = timeRemaining, time > 0 && time < 86400 else {
            return "Discharging on battery"
        }
        let mins = Int(time / 60)
        let hours = mins / 60
        let remainingMins = mins % 60
        if hours > 0 {
            return "About \(hours) hours and \(remainingMins) minutes left"
        }
        return "About \(mins) minutes remaining"
    }

    private static func cleanSensorName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "Module ", with: "RAM ")
            .replacingOccurrences(of: "Flash (NAND)", with: "SSD")
            .replacingOccurrences(of: "Efficiency Cores", with: "E-Cores")
            .replacingOccurrences(of: "Package", with: "SoC")
    }
}
