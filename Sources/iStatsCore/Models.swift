import Foundation

// Pure value types describing one reading per metric category. These are
// produced by the Sampling layer and consumed by the UI. They contain no
// OS-specific code and are fully testable.

/// System load average for 1, 5, and 15 minute intervals.
public struct LoadAverage: Sendable, Equatable, Codable {
    public let oneMinute: Double
    public let fiveMinute: Double
    public let fifteenMinute: Double

    public init(oneMinute: Double, fiveMinute: Double, fifteenMinute: Double) {
        self.oneMinute = oneMinute
        self.fiveMinute = fiveMinute
        self.fifteenMinute = fifteenMinute
    }
}

/// CPU utilization and metrics for one sample.
public struct CPUSample: Sendable, Equatable, Codable {
    /// Aggregate utilization across all cores, 0...100.
    public let totalUsage: Double
    /// Per-core utilization, each 0...100.
    public let perCore: [Double]
    /// Fraction of time in user space for this interval, 0...100.
    public let user: Double
    /// Fraction of time in the kernel for this interval, 0...100.
    public let system: Double
    /// Fraction of time idle for this interval, 0...100.
    public let idle: Double
    /// System load average (1, 5, 15 minutes) if available.
    public let loadAverage: LoadAverage?
    /// CPU frequency in Hertz (Hz) if exposed by hardware / sysctl.
    public let frequencyHz: UInt64?

    public init(
        totalUsage: Double,
        perCore: [Double],
        user: Double,
        system: Double,
        idle: Double,
        loadAverage: LoadAverage? = nil,
        frequencyHz: UInt64? = nil
    ) {
        self.totalUsage = totalUsage
        self.perCore = perCore
        self.user = user
        self.system = system
        self.idle = idle
        self.loadAverage = loadAverage
        self.frequencyHz = frequencyHz
    }
}

/// macOS memory pressure level.
public enum MemoryPressure: String, Sendable, Equatable, Codable, Comparable {
    case normal
    case warning
    case critical

    /// Human-readable title of the memory pressure state.
    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    /// Whether memory pressure is in an elevated (warning or critical) state.
    public var isElevated: Bool {
        self != .normal
    }

    /// Numeric severity rank (0 = normal, 1 = warning, 2 = critical).
    public var severityRank: Int {
        switch self {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
        lhs.severityRank < rhs.severityRank
    }
}

/// Memory statistics for one sample. All byte values are in bytes.
public struct MemorySample: Sendable, Equatable, Codable {
    public let total: UInt64
    public let used: UInt64
    public let free: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    public let swapUsed: UInt64
    public let pressure: MemoryPressure
    public let appMemory: UInt64?
    public let active: UInt64?
    public let inactive: UInt64?
    public let swapTotal: UInt64?
    public let swapFree: UInt64?

    public init(
        total: UInt64,
        used: UInt64,
        free: UInt64,
        wired: UInt64,
        compressed: UInt64,
        cached: UInt64,
        swapUsed: UInt64,
        pressure: MemoryPressure,
        appMemory: UInt64? = nil,
        active: UInt64? = nil,
        inactive: UInt64? = nil,
        swapTotal: UInt64? = nil,
        swapFree: UInt64? = nil
    ) {
        self.total = total
        self.used = used
        self.free = free
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.pressure = pressure
        self.appMemory = appMemory
        self.active = active
        self.inactive = inactive
        self.swapTotal = swapTotal
        self.swapFree = swapFree
    }
}

/// macOS thermal pressure level.
public enum ThermalPressure: String, Sendable, Equatable, Codable, Comparable {
    case nominal
    case fair
    case serious
    case critical

    /// Human-readable title of the thermal pressure state.
    public var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        }
    }

    /// Whether thermal pressure is elevated above nominal.
    public var isElevated: Bool {
        self != .nominal
    }

    /// Numeric severity rank (0 = nominal, 1 = fair, 2 = serious, 3 = critical).
    public var severityRank: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: ThermalPressure, rhs: ThermalPressure) -> Bool {
        lhs.severityRank < rhs.severityRank
    }
}

/// A single named temperature sensor reading, in degrees Celsius.
public struct SensorReading: Sendable, Equatable, Codable {
    public let name: String
    public let celsius: Double
    public init(name: String, celsius: Double) {
        self.name = name
        self.celsius = celsius
    }
}

/// Thermal statistics for one sample.
public struct ThermalSample: Sendable, Equatable, Codable {
    public let sensors: [SensorReading]
    public let pressure: ThermalPressure?

    public init(sensors: [SensorReading] = [], pressure: ThermalPressure? = nil) {
        self.sensors = sensors
        self.pressure = pressure
    }
}

/// A single fan reading.
public struct FanReading: Sendable, Equatable, Codable {
    public let name: String
    public let rpm: Int
    public let minRPM: Int?
    public let maxRPM: Int?
    public init(name: String, rpm: Int, minRPM: Int? = nil, maxRPM: Int? = nil) {
        self.name = name
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

/// Fan operational and control modes (ADR 0004, Requirements 4.3, 4.4).
public enum FanControlMode: String, Sendable, Equatable, Codable, CaseIterable {
    /// System firmware automatically controls cooling curves (safe default).
    case systemAutomatic = "automatic"
    /// Manual target speed set within hardware-reported min/max bounds.
    case manual = "manual"
    /// Fan control not supported on this platform/hardware.
    case unsupported = "unsupported"
}

/// Errors encountered during fan target speed validation and boundary checks (Requirement 4.3, ADR 0004).
public enum FanSafetyError: Error, Sendable, Equatable {
    case targetBelowMinimum(target: Int, minimum: Int)
    case targetAboveMaximum(target: Int, maximum: Int)
    case boundsUnavailable
    case invalidBounds(min: Int, max: Int)
}

/// Pure domain safety logic for enforcing hardware-reported fan speed bounds (Requirements 4.2, 4.3, ADR 0004).
public struct FanSafetyBounds: Sendable, Equatable {
    /// Clamps a target fan RPM strictly within the hardware-reported minimum and maximum bounds.
    /// - If `targetRPM` < `minRPM`, clamps up to `minRPM` to prevent under-cooling and thermal throttling.
    /// - If `targetRPM` > `maxRPM`, clamps down to `maxRPM` to prevent motor bearing damage.
    /// - If bounds are nil or inverted, returns the sanitized target (clamped to non-negative).
    public static func clamp(targetRPM: Int, minRPM: Int?, maxRPM: Int?) -> Int {
        var clamped = Swift.max(0, targetRPM)
        if let minVal = minRPM, minVal >= 0 {
            clamped = Swift.max(clamped, minVal)
        }
        if let maxVal = maxRPM, maxVal >= 0 {
            if let minVal = minRPM, minVal >= 0, maxVal < minVal {
                return Swift.max(0, minVal)
            }
            clamped = Swift.min(clamped, maxVal)
        }
        return clamped
    }

    /// Validates whether a target fan RPM is strictly within the hardware bounds.
    public static func validate(targetRPM: Int, minRPM: Int?, maxRPM: Int?) -> Result<Int, FanSafetyError> {
        guard let min = minRPM, let max = maxRPM else {
            return .failure(.boundsUnavailable)
        }
        guard min >= 0, max >= min else {
            return .failure(.invalidBounds(min: min, max: max))
        }
        if targetRPM < min {
            return .failure(.targetBelowMinimum(target: targetRPM, minimum: min))
        }
        if targetRPM > max {
            return .failure(.targetAboveMaximum(target: targetRPM, maximum: max))
        }
        return .success(targetRPM)
    }
}

/// Architecture policy and user explanations for fan control and privilege boundaries (Requirements 4.3, 4.4, 13.2, ADR 0004).
public struct FanControlPolicy: Sendable, Equatable {
    /// The default and enforced operating mode for iStats.
    public static let defaultMode: FanControlMode = .systemAutomatic

    /// User-facing explanation of why fans are presented in read-only / system-controlled mode.
    public static let readOnlyExplanation: String =
        "Fan speeds are automatically managed by macOS system firmware to protect thermal safety and hardware longevity."

    /// Short status label for the UI badge.
    public static let statusLabel: String = "System Controlled"

    /// Explanatory details for the privilege posture.
    public static let privilegePostureDescription: String =
        "iStats operates with zero privilege escalation and does not install root background helper daemons."
}

/// Fan statistics for one sample.
public struct FanSample: Sendable, Equatable, Codable {
    public let fans: [FanReading]

    public init(fans: [FanReading] = []) {
        self.fans = fans
    }

    public var isFanless: Bool {
        fans.isEmpty
    }
}

/// Throughput for one network interface, in bytes per second plus session totals.
public struct InterfaceThroughput: Sendable, Equatable, Codable {
    public let interfaceName: String
    public let bytesInPerSec: Double
    public let bytesOutPerSec: Double
    public let totalBytesIn: UInt64
    public let totalBytesOut: UInt64
    public init(interfaceName: String, bytesInPerSec: Double, bytesOutPerSec: Double,
                totalBytesIn: UInt64, totalBytesOut: UInt64) {
        self.interfaceName = interfaceName
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
        self.totalBytesIn = totalBytesIn
        self.totalBytesOut = totalBytesOut
    }
}

/// Network statistics across all monitored interfaces for one sample.
public struct NetworkSample: Sendable, Equatable, Codable {
    public let interfaces: [InterfaceThroughput]

    public var totalBytesInPerSec: Double {
        interfaces.reduce(0.0) { $0 + $1.bytesInPerSec }
    }

    public var totalBytesOutPerSec: Double {
        interfaces.reduce(0.0) { $0 + $1.bytesOutPerSec }
    }

    public var totalBytesIn: UInt64 {
        interfaces.reduce(0) { $0 + $1.totalBytesIn }
    }

    public var totalBytesOut: UInt64 {
        interfaces.reduce(0) { $0 + $1.totalBytesOut }
    }

    public init(interfaces: [InterfaceThroughput] = []) {
        self.interfaces = interfaces
    }
}

/// Capacity statistics for a single mounted volume.
public struct VolumeCapacity: Sendable, Equatable, Codable {
    public let name: String
    public let mountPoint: String
    public let total: UInt64
    public let used: UInt64
    public let free: UInt64

    public init(name: String, mountPoint: String, total: UInt64, used: UInt64, free: UInt64) {
        self.name = name
        self.mountPoint = mountPoint
        self.total = total
        self.used = used
        self.free = free
    }
}

/// Disk I/O activity rates.
public struct DiskIO: Sendable, Equatable, Codable {
    public let bytesReadPerSec: Double
    public let bytesWrittenPerSec: Double
    public let readOpsPerSec: Double
    public let writeOpsPerSec: Double

    public init(bytesReadPerSec: Double, bytesWrittenPerSec: Double,
                readOpsPerSec: Double, writeOpsPerSec: Double) {
        self.bytesReadPerSec = bytesReadPerSec
        self.bytesWrittenPerSec = bytesWrittenPerSec
        self.readOpsPerSec = readOpsPerSec
        self.writeOpsPerSec = writeOpsPerSec
    }
}

/// Disk statistics for one sample.
public struct DiskSample: Sendable, Equatable, Codable {
    public let volumes: [VolumeCapacity]
    public let io: DiskIO?

    public init(volumes: [VolumeCapacity] = [], io: DiskIO? = nil) {
        self.volumes = volumes
        self.io = io
    }
}

/// State of the internal battery.
public enum BatteryState: String, Sendable, Equatable, Codable {
    case charging
    case discharging
    case charged
    case acConnected
    case unknown
}

/// Battery and power statistics for one sample.
public struct PowerSample: Sendable, Equatable, Codable {
    public let hasBattery: Bool
    public let charge: Double?
    public let state: BatteryState?
    public let timeRemaining: TimeInterval?
    public let cycleCount: Int?
    public let condition: String?
    public let designCapacity: Int?
    public let currentMaxCapacity: Int?
    public let powerDrawWatts: Double?
    public let adapterWatts: Double?

    public init(hasBattery: Bool, charge: Double? = nil, state: BatteryState? = nil,
                timeRemaining: TimeInterval? = nil, cycleCount: Int? = nil, condition: String? = nil,
                designCapacity: Int? = nil, currentMaxCapacity: Int? = nil,
                powerDrawWatts: Double? = nil, adapterWatts: Double? = nil) {
        self.hasBattery = hasBattery
        self.charge = charge
        self.state = state
        self.timeRemaining = timeRemaining
        self.cycleCount = cycleCount
        self.condition = condition
        self.designCapacity = designCapacity
        self.currentMaxCapacity = currentMaxCapacity
        self.powerDrawWatts = powerDrawWatts
        self.adapterWatts = adapterWatts
    }
}

/// GPU statistics for one sample.
public struct GPUSample: Sendable, Equatable, Codable {
    public let utilization: Double?
    public let memoryUsed: UInt64?
    public let tempCelsius: Double?
    public let powerWatts: Double?

    public init(utilization: Double? = nil, memoryUsed: UInt64? = nil,
                tempCelsius: Double? = nil, powerWatts: Double? = nil) {
        self.utilization = utilization
        self.memoryUsed = memoryUsed
        self.tempCelsius = tempCelsius
        self.powerWatts = powerWatts
    }
}

