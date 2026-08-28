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

/// Darwin IOHIDEventSystem, AppleSMC, and ProcessInfo implementation of `ThermalInfoProvider`.
public struct HostThermalInfoProvider: ThermalInfoProvider {

    // MARK: - IOHID Dynamic Function Bindings (Apple Silicon & Modern macOS)

    private struct IOHIDBindings: @unchecked Sendable {
        typealias EventSystemClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias EventSystemClientSetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
        typealias EventSystemClientCopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
        typealias ServiceClientCopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
        typealias ServiceClientCopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
        typealias EventGetFloatValue = @convention(c) (AnyObject, Int32) -> Double

        let clientCreate: EventSystemClientCreate
        let clientSetMatching: EventSystemClientSetMatching
        let clientCopyServices: EventSystemClientCopyServices
        let serviceClientCopyProperty: ServiceClientCopyProperty
        let serviceClientCopyEvent: ServiceClientCopyEvent
        let eventGetFloatValue: EventGetFloatValue

        static let shared: IOHIDBindings? = {
            guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
                return nil
            }
            guard let createSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
                  let setMatchingSym = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
                  let copyServicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
                  let copyPropertySym = dlsym(handle, "IOHIDServiceClientCopyProperty"),
                  let copyEventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
                  let getFloatValueSym = dlsym(handle, "IOHIDEventGetFloatValue") else {
                return nil
            }
            return IOHIDBindings(
                clientCreate: unsafeBitCast(createSym, to: EventSystemClientCreate.self),
                clientSetMatching: unsafeBitCast(setMatchingSym, to: EventSystemClientSetMatching.self),
                clientCopyServices: unsafeBitCast(copyServicesSym, to: EventSystemClientCopyServices.self),
                serviceClientCopyProperty: unsafeBitCast(copyPropertySym, to: ServiceClientCopyProperty.self),
                serviceClientCopyEvent: unsafeBitCast(copyEventSym, to: ServiceClientCopyEvent.self),
                eventGetFloatValue: unsafeBitCast(getFloatValueSym, to: EventGetFloatValue.self)
            )
        }()
    }

    private final class IOHIDClientHolder: @unchecked Sendable {
        static let shared = IOHIDClientHolder()
        let client: AnyObject?
        private let lock = NSLock()
        private var cachedServices: [(service: AnyObject, product: String)]?

        init() {
            guard let bindings = IOHIDBindings.shared else {
                self.client = nil
                return
            }
            if let c = bindings.clientCreate(kCFAllocatorDefault)?.takeRetainedValue() {
                let matching: [String: Any] = [
                    "PrimaryUsagePage": 0xff00,
                    "PrimaryUsage": 5
                ]
                bindings.clientSetMatching(c, matching as CFDictionary)
                self.client = c
            } else {
                self.client = nil
            }
        }

        func activeServices(bindings: IOHIDBindings) -> [(service: AnyObject, product: String)] {
            lock.lock()
            defer { lock.unlock() }

            if let cached = cachedServices {
                return cached
            }

            guard let client = client,
                  let allServices = bindings.clientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else {
                return []
            }

            var matchingServices: [(service: AnyObject, product: String)] = []
            for service in allServices {
                let product = (bindings.serviceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? ""
                if product.hasPrefix("PMU tdie") || product == "PMU tcal" || product.hasPrefix("NAND") || product == "gas gauge battery" {
                    matchingServices.append((service: service, product: product))
                }
            }

            cachedServices = matchingServices
            return matchingServices
        }
    }

    /// Sensor definition describing an SMC key and its canonical human-readable label.
    private struct SMCSensorDescriptor {
        let key: String
        let label: String
    }

    /// Verified thermal sensor keys on Apple Silicon and Intel Macs (ADR 0003).
    /// Note: 'Tp01', 'Tp05', 'Tp09' etc. are omitted as they are power limit targets (Watts), not temperature.
    private static let candidateSensors: [SMCSensorDescriptor] = [
        // Efficiency Cores (Apple Silicon)
        SMCSensorDescriptor(key: "Te05", label: "Efficiency Cores Cluster"),
        SMCSensorDescriptor(key: "Te0S", label: "Efficiency Cores Die"),

        // GPU Clusters
        SMCSensorDescriptor(key: "Tg05", label: "GPU Cluster 1"),
        SMCSensorDescriptor(key: "Tg0S", label: "GPU Cluster 2"),
        SMCSensorDescriptor(key: "Tg1V", label: "GPU Cluster 3"),
        SMCSensorDescriptor(key: "TG0P", label: "GPU Proximity"),
        SMCSensorDescriptor(key: "TG0D", label: "GPU Die"),

        // Memory, Chipset & SoC
        SMCSensorDescriptor(key: "TfC0", label: "SoC Core Cluster A"),
        SMCSensorDescriptor(key: "TfC1", label: "SoC Core Cluster B"),
        SMCSensorDescriptor(key: "TCHP", label: "Chipset / SoC"),
        SMCSensorDescriptor(key: "TCMb", label: "Memory Module A"),
        SMCSensorDescriptor(key: "TCMz", label: "Memory Module B"),
        SMCSensorDescriptor(key: "TM0P", label: "Memory Proximity"),

        // Battery Gas Gauge
        SMCSensorDescriptor(key: "TB0T", label: "Battery (Sensor 1)"),
        SMCSensorDescriptor(key: "TB1T", label: "Battery (Sensor 2)"),
        SMCSensorDescriptor(key: "TB2T", label: "Battery (Sensor 3)"),

        // Proximity & Enclosure
        SMCSensorDescriptor(key: "Ts0P", label: "Palm Rest Proximity"),
        SMCSensorDescriptor(key: "Ts1P", label: "Trackpad Proximity"),
        SMCSensorDescriptor(key: "TaLP", label: "Air Intake Left"),
        SMCSensorDescriptor(key: "TaRP", label: "Air Intake Right"),
        SMCSensorDescriptor(key: "Th0H", label: "Heatsink"),

        // Intel Legacy CPU Sensors (Fallbacks)
        SMCSensorDescriptor(key: "TC0P", label: "CPU Proximity"),
        SMCSensorDescriptor(key: "TC0D", label: "CPU Die"),
        SMCSensorDescriptor(key: "TC0E", label: "CPU Core E"),
        SMCSensorDescriptor(key: "TC0F", label: "CPU Core F")
    ]

    public init() {}

    public func thermalSensors() throws -> [SensorReading] {
        var readings: [SensorReading] = []

        // 1. Read high-resolution per-core and SoC thermals via IOHID (Apple Silicon / modern macOS)
        if let hidReadings = readIOHIDThermals(), !hidReadings.isEmpty {
            readings.append(contentsOf: hidReadings)
        }

        // 2. Read auxiliary sensors via AppleSMC
        if let smcReadings = readAppleSMCThermals(), !smcReadings.isEmpty {
            let existingNames = Set(readings.map(\.name))
            for reading in smcReadings where !existingNames.contains(reading.name) {
                readings.append(reading)
            }
        }

        // Return discovered sensors if available
        if !readings.isEmpty {
            // If CPU Package is not explicitly present, synthesize it from the max CPU Core
            if !readings.contains(where: { $0.name == "CPU Package" }) {
                let cpuCores = readings.filter { $0.name.hasPrefix("CPU Core") }
                if let maxCore = cpuCores.max(by: { $0.celsius < $1.celsius }) {
                    readings.insert(SensorReading(name: "CPU Package", celsius: maxCore.celsius), at: 0)
                }
            }
            return readings
        }

        // If no sensors were accessible via IOHID or SMC, check if system thermal pressure is available
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

    // MARK: - IOHID Reader (Apple Silicon Per-Core & SoC Thermals)

    private func readIOHIDThermals() -> [SensorReading]? {
        guard let bindings = IOHIDBindings.shared else { return nil }
        let services = IOHIDClientHolder.shared.activeServices(bindings: bindings)
        guard !services.isEmpty else { return nil }

        let kIOHIDEventTypeTemperature: Int64 = 15
        let IOHIDEventFieldBase: Int32 = 15 << 16

        var coreReadings: [Int: [Double]] = [:]
        var namedReadings: [String: Double] = [:]

        for item in services {
            let service = item.service
            let product = item.product

            if let event = bindings.serviceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0)?.takeRetainedValue() {
                let temp = bindings.eventGetFloatValue(event, IOHIDEventFieldBase)
                guard temp > 0.0 && temp < 150.0 else { continue }

                if product.hasPrefix("PMU tdie") {
                    let numStr = product.replacingOccurrences(of: "PMU tdie", with: "")
                    if let coreNum = Int(numStr) {
                        coreReadings[coreNum, default: []].append(temp)
                    }
                } else if product == "PMU tcal" {
                    namedReadings["CPU Package"] = temp
                } else if product.hasPrefix("NAND") {
                    namedReadings["Storage Flash (NAND)"] = temp
                } else if product == "gas gauge battery" {
                    namedReadings["Battery"] = temp
                }
            }
        }

        var results: [SensorReading] = []

        if let pkgTemp = namedReadings["CPU Package"] {
            results.append(SensorReading(name: "CPU Package", celsius: pkgTemp))
        }

        for coreIndex in coreReadings.keys.sorted() {
            let temps = coreReadings[coreIndex]!
            let avgTemp = temps.reduce(0.0, +) / Double(temps.count)
            results.append(SensorReading(name: "CPU Core \(coreIndex)", celsius: avgTemp))
        }

        if let nandTemp = namedReadings["Storage Flash (NAND)"] {
            results.append(SensorReading(name: "Storage Flash (NAND)", celsius: nandTemp))
        }

        if let battTemp = namedReadings["Battery"] {
            results.append(SensorReading(name: "Battery", celsius: battTemp))
        }

        return results.isEmpty ? nil : results
    }

    // MARK: - SMC Sensor Discovery Cache

    private final class SMCSensorCache: @unchecked Sendable {
        static let shared = SMCSensorCache()
        private let lock = NSLock()
        private var activeSensors: [SMCSensorDescriptor]?

        func getOrDiscoverSensors(
            connection: io_connect_t,
            candidates: [SMCSensorDescriptor],
            reader: (String, io_connect_t) -> Double?
        ) -> [SMCSensorDescriptor] {
            lock.lock()
            defer { lock.unlock() }

            if let cached = activeSensors {
                return cached
            }

            var discovered: [SMCSensorDescriptor] = []
            for descriptor in candidates {
                if let temp = reader(descriptor.key, connection), temp > 0.0 && temp < 150.0 {
                    discovered.append(descriptor)
                }
            }
            activeSensors = discovered
            return discovered
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

        let activeDescriptors = SMCSensorCache.shared.getOrDiscoverSensors(
            connection: conn,
            candidates: Self.candidateSensors,
            reader: { key, c in self.readSMCKeyTemperature(keyStr: key, connection: c) }
        )

        var results: [SensorReading] = []
        for descriptor in activeDescriptors {
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
