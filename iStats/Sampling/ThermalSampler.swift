import Foundation
import Darwin
import IOKit
import iStatsCore

// MARK: - SMC Data Structures & Interop (ADR 0003)

/// Exact 80-byte C-compatible memory layout matching Darwin kernel AppleSMC user clients.
public struct SMCParamStruct: Sendable {
    public var key: UInt32 = 0
    public var vers_major: UInt8 = 0
    public var vers_minor: UInt8 = 0
    public var vers_build: UInt8 = 0
    public var vers_reserved: UInt8 = 0
    public var vers_release: UInt16 = 0
    public var _pad0: (UInt8, UInt8) = (0, 0)
    public var pLimit_version: UInt16 = 0
    public var pLimit_length: UInt16 = 0
    public var pLimit_cpuPLimit: UInt32 = 0
    public var pLimit_gpuPLimit: UInt32 = 0
    public var pLimit_memPLimit: UInt32 = 0
    public var keyInfo_dataSize: UInt32 = 0
    public var keyInfo_dataType: UInt32 = 0
    public var keyInfo_dataAttributes: UInt8 = 0
    public var _pad1: (UInt8, UInt8, UInt8) = (0, 0, 0)
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var _pad2: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                      (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

    public init() {}
}

private let kSMCGetKeyInfo: UInt8 = 9
private let kSMCReadKey: UInt8 = 5
private let kSMCHandleYPCEvent: UInt32 = 2

private func fourCharCode(_ str: String) -> UInt32 {
    var result: UInt32 = 0
    for char in str.utf8.prefix(4) {
        result = (result << 8) | UInt32(char)
    }
    return result
}

private func fourCharCodeToString(_ code: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

// MARK: - Thermal Provider Protocol

/// Abstract provider for reading hardware thermal sensors and system thermal pressure.
public protocol ThermalInfoProvider: Sendable {
    /// Returns available named thermal sensor readings in degrees Celsius.
    func thermalSensors() throws -> [SensorReading]

    /// Returns the system thermal pressure state if exposed by macOS.
    func thermalPressure() throws -> ThermalPressure?
}

public extension ThermalInfoProvider {
    func thermalPressure() throws -> ThermalPressure? { nil }
}

// MARK: - Host Thermal Info Provider

/// Darwin AppleSMC, IOHID, and ProcessInfo implementation of `ThermalInfoProvider`.
public struct HostThermalInfoProvider: ThermalInfoProvider {

    /// Sensor definition describing an SMC key and its canonical human-readable label.
    private struct SMCSensorDescriptor {
        let key: String
        let label: String
    }

    /// Known thermal sensor keys on Apple Silicon and Intel Macs (ADR 0003).
    private static let candidateSensors: [SMCSensorDescriptor] = [
        // CPU & SoC Package
        SMCSensorDescriptor(key: "Tp0T", label: "CPU Package"),
        SMCSensorDescriptor(key: "Tp01", label: "CPU Core 1"),
        SMCSensorDescriptor(key: "Tp05", label: "CPU Core 2"),
        SMCSensorDescriptor(key: "Tp09", label: "CPU Core 3"),
        SMCSensorDescriptor(key: "Tp0k", label: "CPU Core 4"),
        SMCSensorDescriptor(key: "TC0P", label: "CPU Proximity"),
        SMCSensorDescriptor(key: "TC0D", label: "CPU Die"),
        SMCSensorDescriptor(key: "TC0E", label: "CPU Core E"),
        SMCSensorDescriptor(key: "TC0F", label: "CPU Core F"),

        // Efficiency Cores (Apple Silicon)
        SMCSensorDescriptor(key: "Te05", label: "Efficiency Cores"),
        SMCSensorDescriptor(key: "Te0S", label: "Efficiency Cores Cluster"),

        // GPU Clusters
        SMCSensorDescriptor(key: "Tg05", label: "GPU Cluster 1"),
        SMCSensorDescriptor(key: "Tg0S", label: "GPU Cluster 2"),
        SMCSensorDescriptor(key: "TG0P", label: "GPU Proximity"),
        SMCSensorDescriptor(key: "TG0D", label: "GPU Die"),

        // Memory & Chipset
        SMCSensorDescriptor(key: "TCHP", label: "Chipset / SoC"),
        SMCSensorDescriptor(key: "TCMb", label: "Memory Module A"),
        SMCSensorDescriptor(key: "TCMz", label: "Memory Module B"),
        SMCSensorDescriptor(key: "TM0P", label: "Memory Proximity"),

        // Battery Gas Gauge
        SMCSensorDescriptor(key: "TB0T", label: "Battery (Sensor 1)"),
        SMCSensorDescriptor(key: "TB1T", label: "Battery (Sensor 2)"),
        SMCSensorDescriptor(key: "TB2T", label: "Battery (Sensor 3)"),

        // Die Array (Apple Silicon)
        SMCSensorDescriptor(key: "TD00", label: "Die Array 0"),
        SMCSensorDescriptor(key: "TD01", label: "Die Array 1"),
        SMCSensorDescriptor(key: "TD02", label: "Die Array 2"),
        SMCSensorDescriptor(key: "TD03", label: "Die Array 3"),
        SMCSensorDescriptor(key: "TD04", label: "Die Array 4"),
        SMCSensorDescriptor(key: "TD05", label: "Die Array 5"),
        SMCSensorDescriptor(key: "TD06", label: "Die Array 6"),
        SMCSensorDescriptor(key: "TD07", label: "Die Array 7"),

        // Heatsink & System
        SMCSensorDescriptor(key: "Th0H", label: "Heatsink"),
        SMCSensorDescriptor(key: "Ts0P", label: "System Proximity")
    ]

    public init() {}

    public func thermalSensors() throws -> [SensorReading] {
        var readings: [SensorReading] = []

        // 1. Read sensors via AppleSMC
        if let smcReadings = readAppleSMCThermals(), !smcReadings.isEmpty {
            readings.append(contentsOf: smcReadings)
        }

        // Return discovered sensors if available
        if !readings.isEmpty {
            return readings
        }

        // If no sensors were accessible via SMC, check if system thermal pressure is available
        // If even thermal pressure is unavailable, throw unsupported to degrade gracefully (ADR 0003, Req 3.3).
        let pressure = try? thermalPressure()
        if pressure == nil && readings.isEmpty {
            throw SamplerError.unsupported("No thermal sensors or thermal pressure available on this system")
        }

        return readings
    }

    public func thermalPressure() throws -> ThermalPressure? {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return nil
        }
    }

    // MARK: - AppleSMC Reader

    private func readAppleSMCThermals() -> [SensorReading]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let openRes = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard openRes == KERN_SUCCESS else {
            return nil
        }
        defer { IOServiceClose(conn) }

        var results: [SensorReading] = []
        for descriptor in Self.candidateSensors {
            if let temp = readSMCKeyTemperature(keyStr: descriptor.key, connection: conn) {
                // Filter to physically plausible operating temperatures (0°C to 150°C)
                if temp > 0.0 && temp < 150.0 {
                    results.append(SensorReading(name: descriptor.label, celsius: temp))
                }
            }
        }

        return results
    }

    private func readSMCKeyTemperature(keyStr: String, connection: io_connect_t) -> Double? {
        var input = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = kSMCGetKeyInfo

        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride

        var kr = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outSize
        )
        guard kr == KERN_SUCCESS && output.result == 0 else {
            return nil
        }

        let dataSize = output.keyInfo_dataSize
        let dataType = output.keyInfo_dataType
        let typeStr = fourCharCodeToString(dataType)

        input.keyInfo_dataSize = dataSize
        input.data8 = kSMCReadKey
        outSize = MemoryLayout<SMCParamStruct>.stride

        kr = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outSize
        )
        guard kr == KERN_SUCCESS && output.result == 0 else {
            return nil
        }

        let rawBytes: [UInt8] = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(dataSize))) }
        guard !rawBytes.isEmpty else { return nil }

        switch typeStr {
        case "flt ":
            if dataSize == 4 {
                let val = rawBytes.withUnsafeBytes { $0.load(as: Float.self) }
                return Double(val)
            }
        case "sp78":
            if dataSize == 2 {
                let raw = (Int16(rawBytes[0]) << 8) | Int16(rawBytes[1])
                return Double(raw) / 256.0
            }
        case "fpe2":
            if dataSize == 2 {
                let raw = (UInt16(rawBytes[0]) << 8) | UInt16(rawBytes[1])
                return Double(raw) / 4.0
            }
        case "ui8 ":
            if dataSize == 1 {
                return Double(rawBytes[0])
            }
        case "ui16":
            if dataSize == 2 {
                let raw = (UInt16(rawBytes[0]) << 8) | UInt16(rawBytes[1])
                return Double(raw)
            }
        default:
            break
        }

        return nil
    }
}

// MARK: - Concrete Thermal Sampler

/// Concrete sampler for system temperatures and thermal pressure.
///
/// Conforms to `Sampler` (Requirements 3.1, 3.2, 3.3, 3.4, 11.3, ADR 0003). Reads AppleSMC / IOHID thermal sensors
/// and `ProcessInfo` thermal pressure in background work, ensuring safety and graceful degradation to `.unavailable`.
public final class ThermalSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .thermal

    private let provider: any ThermalInfoProvider

    public init(provider: any ThermalInfoProvider = HostThermalInfoProvider()) {
        self.provider = provider
    }

    /// Samples thermal metrics. Runs off the main thread.
    public func sample() throws -> ThermalSample {
        let sensors = (try? provider.thermalSensors()) ?? []
        let pressure = try? provider.thermalPressure()

        if sensors.isEmpty && pressure == nil {
            throw SamplerError.unsupported("Thermal telemetry is unavailable on this hardware configuration")
        }

        return Self.calculateSample(sensors: sensors, pressure: pressure)
    }

    /// Pure calculation helper constructing a validated `ThermalSample`.
    public static func calculateSample(
        sensors: [SensorReading],
        pressure: ThermalPressure? = nil
    ) -> ThermalSample {
        // Filter any non-finite or invalid temperatures
        let validSensors = sensors.filter { $0.celsius.isFinite && !$0.celsius.isNaN && $0.celsius > 0.0 && $0.celsius < 150.0 }
        return ThermalSample(sensors: validSensors, pressure: pressure)
    }
}
