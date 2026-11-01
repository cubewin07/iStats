import Foundation

/// Pure headline copy generator for Instrument panel glance cards (ADR 0009 / Task 8.7).
/// Generates terse, numeric diagnostic copy for all 8 categories, omitting nil fields.
public enum PanelHeadline {

    // MARK: - CPU
    public static func cpu(sample: CPUSample?, clockSpeedHz: UInt64? = nil) -> String {
        guard let s = sample else { return "Processor telemetry unavailable" }
        var parts: [String] = []

        let usage = s.totalUsage
        if usage >= 85.0 {
            parts.append("Heavy load")
        } else if usage >= 50.0 {
            parts.append("Moderate load")
        } else if usage >= 15.0 {
            parts.append("Light load")
        } else {
            parts.append("Mostly idle")
        }

        let coreCount = s.perCore.count
        if coreCount > 0 {
            parts.append("\(coreCount) cores")
        }

        let hz = clockSpeedHz ?? s.frequencyHz
        if let hz = hz, hz > 0 {
            parts.append(Units.formatFrequencyHz(hz))
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Memory
    public static func memory(sample: MemorySample?) -> String {
        guard let s = sample else { return "Memory telemetry unavailable" }
        var parts: [String] = []

        switch s.pressure {
        case .critical:
            parts.append("Pressure critical")
        case .warning:
            parts.append("Pressure elevated")
        case .normal:
            parts.append("Pressure normal")
        }

        if s.compressed > 0 {
            parts.append("\(Units.formatBytesSI(Int64(s.compressed))) compressed")
        }

        if s.swapUsed > 0 {
            parts.append("\(Units.formatBytesSI(Int64(s.swapUsed))) swap")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - GPU
    public static func gpu(sample: GPUSample?) -> String {
        guard let s = sample else { return "GPU telemetry unavailable" }
        var parts: [String] = []

        let util = s.utilization ?? 0.0
        if util >= 80.0 {
            parts.append("Heavy GPU load")
        } else if util >= 25.0 {
            parts.append("Active")
        } else {
            parts.append("Idle")
        }

        parts.append(String(format: "%.0f%% utilization", util))

        if let temp = s.tempCelsius, temp > 0 {
            parts.append(String(format: "%.0f°C", temp))
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Thermal
    public static func thermal(sample: ThermalSample?, cpuTemp: Double? = nil, gpuTemp: Double? = nil) -> String {
        guard let s = sample else { return "Thermal telemetry unavailable" }
        var parts: [String] = []

        if let pressure = s.pressure {
            switch pressure {
            case .critical:
                parts.append("Critical heat")
            case .serious:
                parts.append("High heat")
            case .fair:
                parts.append("Warm")
            case .nominal:
                parts.append("Nominal temperature")
            }
        } else {
            parts.append("Nominal temperature")
        }

        var sensorTemps: [String] = []
        if let cpu = cpuTemp, cpu > 0 {
            sensorTemps.append("CPU \(Int(round(cpu)))°")
        }
        if let gpu = gpuTemp, gpu > 0 {
            sensorTemps.append("GPU \(Int(round(gpu)))°")
        }

        if !sensorTemps.isEmpty {
            parts.append(sensorTemps.joined(separator: ", "))
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Fan
    public static func fan(sample: FanSample?) -> String {
        guard let s = sample else { return "Fan telemetry unavailable" }
        if s.fans.isEmpty {
            return "Fanless passive cooling"
        }

        var parts: [String] = []
        let speeds = s.fans.map(\.rpm)
        let maxRpm = speeds.max() ?? 0

        if maxRpm > 4000 {
            parts.append("High speed")
        } else if maxRpm > 2000 {
            parts.append("Spinning")
        } else if maxRpm > 0 {
            parts.append("Quiet")
        } else {
            parts.append("Stopped")
        }

        if s.fans.count == 1 {
            parts.append(Units.formatRPM(maxRpm))
        } else {
            parts.append("\(s.fans.count) fans · \(Units.formatRPM(maxRpm)) max")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Network
    public static func network(sample: NetworkSample?) -> String {
        guard let s = sample else { return "Network telemetry unavailable" }
        var parts: [String] = []

        let down = s.totalBytesInPerSec
        let up = s.totalBytesOutPerSec
        let total = down + up

        if total > 500_000 { // > 500 KB/s
            parts.append("Active")
        } else {
            parts.append("Idle")
        }

        parts.append("↓ \(Units.formatBytesSI(Int64(down)))/s")
        parts.append("↑ \(Units.formatBytesSI(Int64(up)))/s")

        if let ip = s.localIPv4 {
            parts.append(ip)
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Disk
    public static func disk(sample: DiskSample?, freeBytes: Int64? = nil) -> String {
        guard let s = sample else { return "Disk telemetry unavailable" }
        var parts: [String] = []

        let read = s.io?.bytesReadPerSec ?? 0.0
        let write = s.io?.bytesWrittenPerSec ?? 0.0
        let totalRate = read + write

        if totalRate > 5_000_000 { // > 5 MB/s
            parts.append("Active")
            parts.append("\(Units.formatBytesSI(Int64(totalRate)))/s")
        } else {
            parts.append("Idle")
        }

        let free = freeBytes ?? s.volumes.first.map { Int64($0.free) }
        if let free = free, free > 0 {
            parts.append("\(Units.formatBytesSI(free)) free")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Power
    public static func power(sample: PowerSample?) -> String {
        guard let s = sample else { return "Power telemetry unavailable" }
        var parts: [String] = []

        switch s.variant {
        case .charging:
            parts.append("Charging")
            if let secs = s.timeRemaining, secs > 0 {
                let mins = Int(secs / 60)
                parts.append("\(mins / 60)h \(mins % 60)m to full")
            }
        case .onHold:
            parts.append("Charging on hold")
        case .powerDeficit:
            parts.append("Power deficit")
        case .charged:
            parts.append("Fully charged")
        case .acDesktop:
            parts.append("On AC power")
        case .discharging:
            parts.append("On battery")
            if let secs = s.timeRemaining, secs > 0 {
                let mins = Int(secs / 60)
                parts.append("\(mins / 60)h \(mins % 60)m left")
            }
        case .lowBattery:
            parts.append("Low battery")
            if let secs = s.timeRemaining, secs > 0 {
                let mins = Int(secs / 60)
                parts.append("\(mins / 60)h \(mins % 60)m left")
            }
        case .unavailable:
            parts.append("Power unmetered")
        }

        if let watts = s.powerDrawWatts, watts > 0 {
            parts.append(String(format: "%.1f W", watts))
        }

        return parts.joined(separator: " · ")
    }
}
