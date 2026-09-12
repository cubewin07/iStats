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

/// Classification of CPU core type (Efficiency vs Performance vs Standard).
public enum CPUCoreType: String, Sendable, Equatable, Codable {
    case efficiency
    case performance
    case standard
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
    /// Number of Efficiency (E) cores if known (e.g. Apple Silicon).
    public let efficiencyCoreCount: Int?
    /// Number of Performance (P) cores if known (e.g. Apple Silicon).
    public let performanceCoreCount: Int?

    public init(
        totalUsage: Double,
        perCore: [Double],
        user: Double,
        system: Double,
        idle: Double,
        loadAverage: LoadAverage? = nil,
        frequencyHz: UInt64? = nil,
        efficiencyCoreCount: Int? = nil,
        performanceCoreCount: Int? = nil
    ) {
        self.totalUsage = totalUsage
        self.perCore = perCore
        self.user = user
        self.system = system
        self.idle = idle
        self.loadAverage = loadAverage
        self.frequencyHz = frequencyHz
        self.efficiencyCoreCount = efficiencyCoreCount
        self.performanceCoreCount = performanceCoreCount
    }

    /// Average utilization percentage across Efficiency cores (0...100), if present.
    public var efficiencyUsage: Double? {
        guard let eCount = efficiencyCoreCount, eCount > 0, !perCore.isEmpty else { return nil }
        let validCount = min(eCount, perCore.count)
        guard validCount > 0 else { return nil }
        let sum = perCore[0..<validCount].reduce(0.0, +)
        return sum / Double(validCount)
    }

    /// Average utilization percentage across Performance cores (0...100), if present.
    public var performanceUsage: Double? {
        guard let pCount = performanceCoreCount, pCount > 0, !perCore.isEmpty else { return nil }
        let startIndex = min(efficiencyCoreCount ?? 0, perCore.count)
        let endIndex = min(startIndex + pCount, perCore.count)
        guard endIndex > startIndex else { return nil }
        let count = endIndex - startIndex
        let sum = perCore[startIndex..<endIndex].reduce(0.0, +)
        return sum / Double(count)
    }

    /// Returns the core type for a given core index (0-indexed).
    public func coreType(at index: Int) -> CPUCoreType {
        guard index >= 0 && index < perCore.count else { return .standard }
        if let eCount = efficiencyCoreCount, eCount > 0 {
            if index < eCount {
                return .efficiency
            } else if let pCount = performanceCoreCount, index < (eCount + pCount) {
                return .performance
            }
        } else if let pCount = performanceCoreCount, pCount > 0 {
            if index < pCount {
                return .performance
            }
        }
        return .standard
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

/// Type of network connection.
public enum NetworkConnectionType: String, Sendable, Equatable, Codable, CaseIterable {
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case vpn = "VPN"
    case thunderbolt = "Thunderbolt"
    case cellular = "Cellular"
    case other = "Network"

    public var displayName: String {
        rawValue
    }

    public var iconName: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .vpn: return "lock.shield.fill"
        case .thunderbolt: return "bolt.horizontal.fill"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        }
    }

    /// Infers connection type from interface device name.
    public static func infer(from interfaceName: String) -> NetworkConnectionType {
        if interfaceName.hasPrefix("en") {
            return interfaceName == "en0" ? .wifi : .ethernet
        }
        if interfaceName.hasPrefix("utun") || interfaceName.hasPrefix("ipsec") || interfaceName.hasPrefix("ppp") {
            return .vpn
        }
        if interfaceName.hasPrefix("bridge") {
            return .thunderbolt
        }
        if interfaceName.hasPrefix("pdp_ip") {
            return .cellular
        }
        return .other
    }
}

/// Detailed Wi-Fi physical and radio link statistics.
public struct WiFiLinkTelemetry: Sendable, Equatable, Codable {
    public let ssid: String?
    public let rssi: Int?          // dBm, e.g. -65
    public let noise: Int?         // dBm, e.g. -92
    public let txRate: Double?     // Mbps, e.g. 585.0
    public let channel: Int?       // Channel number, e.g. 36
    public let band: String?       // e.g. "5 GHz", "2.4 GHz", "6 GHz"

    public init(
        ssid: String? = nil,
        rssi: Int? = nil,
        noise: Int? = nil,
        txRate: Double? = nil,
        channel: Int? = nil,
        band: String? = nil
    ) {
        self.ssid = ssid
        self.rssi = rssi
        self.noise = noise
        self.txRate = txRate
        self.channel = channel
        self.band = band
    }

    /// Signal-to-Noise Ratio (SNR) in dB, if both RSSI and Noise are available.
    public var snr: Int? {
        guard let r = rssi, let n = noise else { return nil }
        return r - n
    }

    /// Computed signal quality rating (0 to 100%).
    public var signalPercent: Int? {
        guard let r = rssi else { return nil }
        let clamped = max(-100, min(-50, r))
        return Int(round(Double(clamped + 100) * 2.0))
    }

    /// Human-friendly qualitative signal rating.
    public var qualityRating: String? {
        guard let p = signalPercent else { return nil }
        if p >= 80 { return "Excellent" }
        if p >= 60 { return "Good" }
        if p >= 40 { return "Fair" }
        return "Weak"
    }
}

/// Throughput for one network interface, in bytes per second plus session totals.
public struct InterfaceThroughput: Sendable, Equatable, Codable {
    public let interfaceName: String
    public let bytesInPerSec: Double
    public let bytesOutPerSec: Double
    public let totalBytesIn: UInt64
    public let totalBytesOut: UInt64
    public let ipv4Address: String?
    public let type: NetworkConnectionType

    public init(
        interfaceName: String,
        bytesInPerSec: Double,
        bytesOutPerSec: Double,
        totalBytesIn: UInt64,
        totalBytesOut: UInt64,
        ipv4Address: String? = nil,
        type: NetworkConnectionType? = nil
    ) {
        self.interfaceName = interfaceName
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
        self.totalBytesIn = totalBytesIn
        self.totalBytesOut = totalBytesOut
        self.ipv4Address = ipv4Address
        self.type = type ?? NetworkConnectionType.infer(from: interfaceName)
    }
}

/// Network statistics across all monitored interfaces for one sample.
public struct NetworkSample: Sendable, Equatable, Codable {
    public let interfaces: [InterfaceThroughput]

    // Enhanced connectivity & routing telemetry
    public let primaryInterface: String?
    public let primaryType: NetworkConnectionType?
    public let localIPv4: String?
    public let gatewayIPv4: String?
    public let primaryDNS: String?
    public let wifiDetails: WiFiLinkTelemetry?

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

    public init(
        interfaces: [InterfaceThroughput] = [],
        primaryInterface: String? = nil,
        primaryType: NetworkConnectionType? = nil,
        localIPv4: String? = nil,
        gatewayIPv4: String? = nil,
        primaryDNS: String? = nil,
        wifiDetails: WiFiLinkTelemetry? = nil
    ) {
        self.interfaces = interfaces
        self.primaryInterface = primaryInterface
        self.primaryType = primaryType
        self.localIPv4 = localIPv4
        self.gatewayIPv4 = gatewayIPv4
        self.primaryDNS = primaryDNS
        self.wifiDetails = wifiDetails
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

    // Enhanced hardware & battery diagnostics
    public let voltageVolts: Double?
    public let amperageMilliAmps: Double?
    public let designCycleCount: Int?
    public let adapterName: String?

    public init(hasBattery: Bool, charge: Double? = nil, state: BatteryState? = nil,
                timeRemaining: TimeInterval? = nil, cycleCount: Int? = nil, condition: String? = nil,
                designCapacity: Int? = nil, currentMaxCapacity: Int? = nil,
                powerDrawWatts: Double? = nil, adapterWatts: Double? = nil,
                voltageVolts: Double? = nil, amperageMilliAmps: Double? = nil,
                designCycleCount: Int? = nil, adapterName: String? = nil) {
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
        self.voltageVolts = voltageVolts
        self.amperageMilliAmps = amperageMilliAmps
        self.designCycleCount = designCycleCount
        self.adapterName = adapterName
    }

    /// Computed dynamic operational and visual power state variant.
    public var variant: PowerStateVariant {
        PowerStateVariant.resolve(
            charge: charge,
            state: state,
            hasBattery: hasBattery,
            drawWatts: powerDrawWatts,
            adapterWatts: adapterWatts,
            amperageMilliAmps: amperageMilliAmps
        )
    }

    /// Whether charging is currently held / paused while connected to AC power.
    public var isOnHold: Bool { variant == .onHold }

    /// Whether system load exceeds connected adapter capacity, causing battery drain.
    public var isPowerDeficit: Bool { variant == .powerDeficit }

    /// Whether the battery is at or below the low battery threshold (<= 20%).
    public var isLowBattery: Bool { variant == .lowBattery }

    /// Whether the Mac is operating on battery power (normal or low).
    public var isUsingBatteryPower: Bool { variant == .discharging || variant == .lowBattery }
}

/// Distinct operational and visual power state variants.
public enum PowerStateVariant: String, Sendable, Equatable, Codable, CaseIterable {
    /// Actively charging from an external AC power adapter.
    case charging
    /// Connected to AC power, but charging is intentionally held / paused (e.g. 80% optimized limit or thermal pause).
    case onHold
    /// Connected to AC power, but active system power draw exceeds the adapter's wattage capability (battery assisting).
    case powerDeficit
    /// Operating normally on internal battery power (> 20%).
    case discharging
    /// Operating on battery with low or critical charge level (<= 20%).
    case lowBattery
    /// Connected to AC power with battery at 100% (or AC bypass).
    case charged
    /// Desktop Mac (Mac mini, Mac Studio, Mac Pro) or system without an internal battery.
    case acDesktop
    /// Battery or power telemetry is unavailable / unmetered.
    case unavailable

    public var displayName: String {
        switch self {
        case .charging:
            return "Charging"
        case .onHold:
            return "Charging On Hold"
        case .powerDeficit:
            return "Power Deficit"
        case .discharging:
            return "On Battery"
        case .lowBattery:
            return "Low Battery"
        case .charged:
            return "Fully Charged"
        case .acDesktop:
            return "AC Power"
        case .unavailable:
            return "Unavailable"
        }
    }

    public var shortBadge: String {
        switch self {
        case .charging:
            return "CHG"
        case .onHold:
            return "HOLD"
        case .powerDeficit:
            return "DEFICIT"
        case .discharging:
            return "BAT"
        case .lowBattery:
            return "LOW"
        case .charged:
            return "PWR"
        case .acDesktop:
            return "AC"
        case .unavailable:
            return "--"
        }
    }

    public var systemImageName: String {
        switch self {
        case .charging:
            return "bolt.fill"
        case .onHold:
            return "pause.fill"
        case .powerDeficit:
            return "bolt.trianglebadge.exclamationmark.fill"
        case .discharging:
            return "battery.100percent"
        case .lowBattery:
            return "exclamationmark.triangle.fill"
        case .charged:
            return "powerplug.fill"
        case .acDesktop:
            return "powerplug.fill"
        case .unavailable:
            return "battery.slash"
        }
    }

    /// Pure resolution of the dynamic `PowerStateVariant` based on telemetry inputs.
    public static func resolve(
        charge: Double?,
        state: BatteryState?,
        hasBattery: Bool,
        drawWatts: Double? = nil,
        adapterWatts: Double? = nil,
        amperageMilliAmps: Double? = nil
    ) -> PowerStateVariant {
        guard hasBattery else { return .acDesktop }
        guard let charge = charge else { return .unavailable }

        let isConnectedToAC = state == .acConnected || state == .charging || state == .charged || (adapterWatts != nil && adapterWatts! > 0)

        // 1. Power Deficit: Connected to AC, but power draw exceeds adapter wattage (or active discharging current)
        if isConnectedToAC {
            if let adapter = adapterWatts, adapter > 0, let draw = drawWatts, draw > (adapter + 1.0) {
                return .powerDeficit
            }
            if let amp = amperageMilliAmps, amp < -200.0 {
                return .powerDeficit
            }
        }

        // 2. Active Charging
        if state == .charging {
            return .charging
        }

        // 3. Fully Charged (AC connected & 100% or flagged charged)
        if isConnectedToAC && (state == .charged || charge >= 99.0) {
            return .charged
        }

        // 4. On Hold: Connected to AC, but not charging and not full (e.g. 80% optimized battery charging limit)
        if isConnectedToAC {
            return .onHold
        }

        // 5. Low Battery: Discharging on battery at or below 20%
        if charge <= 20.0 {
            return .lowBattery
        }

        // 6. Normal discharging on battery
        return .discharging
    }
}

/// GPU statistics for one sample.
public struct GPUSample: Sendable, Equatable, Codable {
    public let utilization: Double?
    public let memoryUsed: UInt64?
    public let tempCelsius: Double?
    public let powerWatts: Double?

    // Enhanced hardware & architecture telemetry
    public let coreCount: Int?
    public let deviceName: String?
    public let allocatedMemory: UInt64?
    public let recommendedMaxMemory: UInt64?
    public let rendererUtilization: Double?
    public let tilerUtilization: Double?
    public let isUnifiedMemory: Bool?
    public let displayCount: Int?
    public let displayDescriptions: [String]?
    public let recoveryCount: Int?
    public let supportsRaytracing: Bool?
    public let metalFeatureSet: String?

    public init(
        utilization: Double? = nil,
        memoryUsed: UInt64? = nil,
        tempCelsius: Double? = nil,
        powerWatts: Double? = nil,
        coreCount: Int? = nil,
        deviceName: String? = nil,
        allocatedMemory: UInt64? = nil,
        recommendedMaxMemory: UInt64? = nil,
        rendererUtilization: Double? = nil,
        tilerUtilization: Double? = nil,
        isUnifiedMemory: Bool? = nil,
        displayCount: Int? = nil,
        displayDescriptions: [String]? = nil,
        recoveryCount: Int? = nil,
        supportsRaytracing: Bool? = nil,
        metalFeatureSet: String? = nil
    ) {
        self.utilization = utilization
        self.memoryUsed = memoryUsed
        self.tempCelsius = tempCelsius
        self.powerWatts = powerWatts
        self.coreCount = coreCount
        self.deviceName = deviceName
        self.allocatedMemory = allocatedMemory
        self.recommendedMaxMemory = recommendedMaxMemory
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.isUnifiedMemory = isUnifiedMemory
        self.displayCount = displayCount
        self.displayDescriptions = displayDescriptions
        self.recoveryCount = recoveryCount
        self.supportsRaytracing = supportsRaytracing
        self.metalFeatureSet = metalFeatureSet
    }
}


