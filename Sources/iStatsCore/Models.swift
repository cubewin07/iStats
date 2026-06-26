import Foundation

// Pure value types describing one reading per metric category. These are
// produced by the Sampling layer and consumed by the UI. They contain no
// OS-specific code and are fully testable.

/// CPU utilization for one sample.
public struct CPUSample: Sendable, Equatable {
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

    public init(totalUsage: Double, perCore: [Double], user: Double, system: Double, idle: Double) {
        self.totalUsage = totalUsage
        self.perCore = perCore
        self.user = user
        self.system = system
        self.idle = idle
    }
}

/// macOS memory pressure level.
public enum MemoryPressure: String, Sendable, Equatable, Codable {
    case normal
    case warning
    case critical
}

/// Memory statistics for one sample. All byte values are in bytes.
public struct MemorySample: Sendable, Equatable {
    public let total: UInt64
    public let used: UInt64
    public let free: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    public let swapUsed: UInt64
    public let pressure: MemoryPressure

    public init(total: UInt64, used: UInt64, free: UInt64, wired: UInt64,
                compressed: UInt64, cached: UInt64, swapUsed: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.used = used
        self.free = free
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.pressure = pressure
    }
}

/// A single named temperature sensor reading, in degrees Celsius.
public struct SensorReading: Sendable, Equatable {
    public let name: String
    public let celsius: Double
    public init(name: String, celsius: Double) {
        self.name = name
        self.celsius = celsius
    }
}

/// A single fan reading.
public struct FanReading: Sendable, Equatable {
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

/// Throughput for one network interface, in bytes per second plus session totals.
public struct InterfaceThroughput: Sendable, Equatable {
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
