import Foundation
import Darwin
import IOKit
import Metal
import AppKit
import iStatsCore

// MARK: - Raw GPU Statistics

/// Raw GPU metrics snapshot captured from IOKit accelerator performance dictionaries and hardware sensors.
public struct RawGPUStatistics: Sendable, Equatable {
    /// GPU core utilization percentage (0...100).
    public let utilization: Double?
    /// GPU memory currently in use in bytes.
    public let memoryUsed: UInt64?
    /// Total system memory allocated for GPU in bytes.
    public let allocatedMemory: UInt64?
    /// GPU temperature in degrees Celsius.
    public let tempCelsius: Double?
    /// GPU power draw in Watts.
    public let powerWatts: Double?
    /// Renderer pipeline utilization percentage (0...100).
    public let rendererUtilization: Double?
    /// Tiler pipeline utilization percentage (0...100).
    public let tilerUtilization: Double?
    /// Detected GPU device name / model identifier.
    public let deviceName: String?
    /// Number of active GPU cores.
    public let coreCount: Int?
    /// Maximum recommended working set size in bytes.
    public let recommendedMaxMemory: UInt64?
    /// Indicates whether GPU uses unified memory architecture.
    public let isUnifiedMemory: Bool?
    /// Number of active connected displays.
    public let displayCount: Int?
    /// Descriptions of connected displays with resolution & refresh rate.
    public let displayDescriptions: [String]?
    /// GPU driver recovery / restart count.
    public let recoveryCount: Int?

    public init(
        utilization: Double? = nil,
        memoryUsed: UInt64? = nil,
        allocatedMemory: UInt64? = nil,
        tempCelsius: Double? = nil,
        powerWatts: Double? = nil,
        rendererUtilization: Double? = nil,
        tilerUtilization: Double? = nil,
        deviceName: String? = nil,
        coreCount: Int? = nil,
        recommendedMaxMemory: UInt64? = nil,
        isUnifiedMemory: Bool? = nil,
        displayCount: Int? = nil,
        displayDescriptions: [String]? = nil,
        recoveryCount: Int? = nil
    ) {
        self.utilization = utilization
        self.memoryUsed = memoryUsed
        self.allocatedMemory = allocatedMemory
        self.tempCelsius = tempCelsius
        self.powerWatts = powerWatts
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.deviceName = deviceName
        self.coreCount = coreCount
        self.recommendedMaxMemory = recommendedMaxMemory
        self.isUnifiedMemory = isUnifiedMemory
        self.displayCount = displayCount
        self.displayDescriptions = displayDescriptions
        self.recoveryCount = recoveryCount
    }
}

// MARK: - GPU Info Provider Protocol

/// Abstract provider for reading GPU utilization, memory usage, and hardware telemetry.
public protocol GPUInfoProvider: Sendable {
    /// Returns the latest raw GPU statistics, or nil if unavailable on this hardware.
    func gpuStatistics() throws -> RawGPUStatistics?
}

// MARK: - Host GPU Info Provider

/// Darwin IOKit `IOAccelerator` (`AGXAccelerator`) and AppleSMC implementation of `GPUInfoProvider`
/// (Requirements 5.1, 5.2, 5.3, ADR 0003).
public struct HostGPUInfoProvider: GPUInfoProvider {

    public init() {}

    public func gpuStatistics() throws -> RawGPUStatistics? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS, iterator != 0 else {
            return fallbackSMCGPUStats()
        }
        defer { IOObjectRelease(iterator) }

        var bestUtilization: Double?
        var bestMemoryUsed: UInt64?
        var bestAllocatedMemory: UInt64?
        var bestRendererUtilization: Double?
        var bestTilerUtilization: Double?
        var bestTemp: Double?
        var bestPower: Double?
        var bestName: String?
        var bestCoreCount: Int?
        var bestRecoveryCount: Int?
        var foundAny = false

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            foundAny = true

            // Read core count
            if bestCoreCount == nil {
                if let cores = dict["gpu-core-count"] as? NSNumber {
                    bestCoreCount = cores.intValue
                } else if let cores = dict["gpu-core-count"] as? Int {
                    bestCoreCount = cores
                } else if let cores = dict["core-count"] as? NSNumber {
                    bestCoreCount = cores.intValue
                } else if let cfg = dict["GPUConfigurationVariable"] as? [String: Any],
                          let numCores = cfg["num_cores"] as? NSNumber {
                    bestCoreCount = numCores.intValue
                }
            }

            // Read model name if present
            if bestName == nil {
                if let modelData = dict["model"] as? Data, let modelStr = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters), !modelStr.isEmpty {
                    bestName = modelStr
                } else if let modelStr = dict["model"] as? String, !modelStr.isEmpty {
                    bestName = modelStr
                } else if let nameMatch = dict["IONameMatch"] as? String, !nameMatch.isEmpty {
                    bestName = nameMatch
                }
            }

            // Inspect PerformanceStatistics dictionary
            if let perf = dict["PerformanceStatistics"] as? [String: Any] {
                // Utilization
                if let util = extractDouble(from: perf, keys: [
                    "Device Utilization %",
                    "GPU Activity(%)",
                    "GPU Core Utilization",
                    "Renderer Utilization %",
                    "Utilization %"
                ]) {
                    bestUtilization = max(bestUtilization ?? 0, util)
                }

                // Renderer Utilization
                if let renderUtil = extractDouble(from: perf, keys: ["Renderer Utilization %"]) {
                    bestRendererUtilization = max(bestRendererUtilization ?? 0, renderUtil)
                }

                // Tiler Utilization
                if let tilerUtil = extractDouble(from: perf, keys: ["Tiler Utilization %"]) {
                    bestTilerUtilization = max(bestTilerUtilization ?? 0, tilerUtil)
                }

                // Memory In Use
                if let mem = extractUInt64(from: perf, keys: [
                    "In use system memory",
                    "vramUsedBytes",
                    "In use memory"
                ]) {
                    bestMemoryUsed = max(bestMemoryUsed ?? 0, mem)
                }

                // Allocated Memory
                if let allocMem = extractUInt64(from: perf, keys: [
                    "Alloc system memory",
                    "vramTotalBytes",
                    "Allocated system memory"
                ]) {
                    bestAllocatedMemory = max(bestAllocatedMemory ?? 0, allocMem)
                }

                // Recovery count
                if let rec = perf["recoveryCount"] as? NSNumber {
                    bestRecoveryCount = rec.intValue
                }

                // Temperature in PerformanceStatistics
                if let temp = extractDouble(from: perf, keys: [
                    "temperature",
                    "Temperature(C)",
                    "GPU Temperature"
                ]) {
                    bestTemp = temp
                }

                // Power in PerformanceStatistics
                if let pwr = extractDouble(from: perf, keys: [
                    "Power(W)",
                    "gpu-power",
                    "GPU Power"
                ]) {
                    bestPower = pwr
                }
            }
        }

        // If temperature was not in PerformanceStatistics, query AppleSMC GPU thermal keys
        if bestTemp == nil {
            bestTemp = readSMCGPUTemperature()
        }

        // Metal device enrichment (name, unified memory, recommended working set)
        let metalDevice = MTLCopyAllDevices().first
        if bestName == nil {
            bestName = metalDevice?.name
        }
        let isUnified = metalDevice?.hasUnifiedMemory
        let recommendedMax = metalDevice?.recommendedMaxWorkingSetSize
        let (dispCount, dispDescs) = Self.queryConnectedDisplays()

        guard foundAny || bestUtilization != nil || bestMemoryUsed != nil || bestTemp != nil || bestPower != nil || bestCoreCount != nil else {
            return fallbackSMCGPUStats()
        }

        return RawGPUStatistics(
            utilization: bestUtilization,
            memoryUsed: bestMemoryUsed,
            allocatedMemory: bestAllocatedMemory,
            tempCelsius: bestTemp,
            powerWatts: bestPower,
            rendererUtilization: bestRendererUtilization,
            tilerUtilization: bestTilerUtilization,
            deviceName: bestName,
            coreCount: bestCoreCount,
            recommendedMaxMemory: recommendedMax,
            isUnifiedMemory: isUnified,
            displayCount: dispCount > 0 ? dispCount : nil,
            displayDescriptions: !dispDescs.isEmpty ? dispDescs : nil,
            recoveryCount: bestRecoveryCount
        )
    }

    // MARK: - Helpers

    private func extractDouble(from dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let num = dict[key] as? NSNumber {
                return num.doubleValue
            } else if let str = dict[key] as? String, let val = Double(str) {
                return val
            }
        }
        return nil
    }

    private func extractUInt64(from dict: [String: Any], keys: [String]) -> UInt64? {
        for key in keys {
            if let num = dict[key] as? NSNumber {
                return num.uint64Value
            } else if let str = dict[key] as? String, let val = UInt64(str) {
                return val
            }
        }
        return nil
    }

    // MARK: - SMC GPU Thermal Fallback

    private func readSMCGPUTemperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            return nil
        }
        defer { IOServiceClose(conn) }

        // Candidate Apple Silicon & Intel GPU thermal keys
        let candidateKeys = ["Tg05", "Tg0S", "TG0P", "TG0D", "TG0T", "TG0B"]
        for keyStr in candidateKeys {
            if let temp = readSMCKeyNumeric(keyStr: keyStr, connection: conn), temp > 0.0, temp < 150.0 {
                return temp
            }
        }
        return nil
    }

    private func fallbackSMCGPUStats() -> RawGPUStatistics? {
        let temp = readSMCGPUTemperature()
        let metalDevice = MTLCopyAllDevices().first
        let (dispCount, dispDescs) = Self.queryConnectedDisplays()

        guard temp != nil || metalDevice != nil || dispCount > 0 else {
            return nil
        }

        return RawGPUStatistics(
            tempCelsius: temp,
            deviceName: metalDevice?.name,
            recommendedMaxMemory: metalDevice?.recommendedMaxWorkingSetSize,
            isUnifiedMemory: metalDevice?.hasUnifiedMemory,
            displayCount: dispCount > 0 ? dispCount : nil,
            displayDescriptions: !dispDescs.isEmpty ? dispDescs : nil
        )
    }

    // MARK: - Display Outputs Helper

    private static func queryConnectedDisplays() -> (count: Int, descriptions: [String]) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return (0, []) }

        var descriptions: [String] = []
        for screen in screens {
            let name = screen.localizedName
            var hzStr = ""
            var resStr = "\(Int(screen.frame.width * screen.backingScaleFactor))×\(Int(screen.frame.height * screen.backingScaleFactor))"
            if let idNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let dID = CGDirectDisplayID(idNum.uint32Value)
                if let mode = CGDisplayCopyDisplayMode(dID) {
                    let w = mode.width
                    let h = mode.height
                    let rate = mode.refreshRate
                    if w > 0 && h > 0 {
                        resStr = "\(w)×\(h)"
                    }
                    if rate > 0 {
                        hzStr = " @ \(Int(round(rate)))Hz"
                    }
                }
            }
            descriptions.append("\(name) (\(resStr)\(hzStr))")
        }
        return (screens.count, descriptions)
    }

    private func readSMCKeyNumeric(keyStr: String, connection: io_connect_t) -> Double? {
        var input = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = 9 // kSMCGetKeyInfo

        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        var kr = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
        guard kr == KERN_SUCCESS, output.result == 0 else {
            return nil
        }

        let dataSize = output.keyInfo_dataSize
        let dataType = output.keyInfo_dataType

        input.keyInfo_dataSize = dataSize
        input.data8 = 5 // kSMCReadKey

        kr = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
        guard kr == KERN_SUCCESS, output.result == 0 else {
            return nil
        }

        let typeStr = fourCharCodeToString(dataType)
        return decodeNumericValue(bytes: output.bytes, size: Int(dataSize), type: typeStr)
    }

    private func decodeNumericValue(bytes: Any, size: Int, type: String) -> Double? {
        var rawBytes = [UInt8](repeating: 0, count: 32)
        withUnsafeBytes(of: bytes) { rawBytesPtr in
            for i in 0..<min(32, rawBytesPtr.count) {
                rawBytes[i] = rawBytesPtr[i]
            }
        }

        guard size > 0, size <= 32 else { return nil }

        switch type {
        case "flt ", "\0\0\0\0":
            if size == 4 {
                var floatVal: Float32 = 0.0
                memcpy(&floatVal, rawBytes, 4)
                return Double(floatVal)
            }
        case "sp78":
            if size == 2 {
                let raw = (Int16(rawBytes[0]) << 8) | Int16(rawBytes[1])
                return Double(raw) / 256.0
            }
        case "fpe2":
            if size == 2 {
                let raw = (Int16(rawBytes[0]) << 8) | Int16(rawBytes[1])
                return Double(raw) / 4.0
            }
        case "ui8 ", "ui8":
            if size == 1 {
                return Double(rawBytes[0])
            }
        case "ui16":
            if size == 2 {
                let raw = (UInt16(rawBytes[0]) << 8) | UInt16(rawBytes[1])
                return Double(raw)
            }
        case "ui32":
            if size == 4 {
                let raw = (UInt32(rawBytes[0]) << 24) |
                          (UInt32(rawBytes[1]) << 16) |
                          (UInt32(rawBytes[2]) << 8) |
                          UInt32(rawBytes[3])
                return Double(raw)
            }
        default:
            if size == 4 {
                var floatVal: Float32 = 0.0
                memcpy(&floatVal, rawBytes, 4)
                if floatVal.isFinite && floatVal > 0 && floatVal < 200 {
                    return Double(floatVal)
                }
            } else if size == 2 {
                let raw = (Int16(rawBytes[0]) << 8) | Int16(rawBytes[1])
                let scaled = Double(raw) / 256.0
                if scaled > 0 && scaled < 200 {
                    return scaled
                }
            }
        }

        return nil
    }

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
}

// MARK: - Concrete GPU Sampler

/// Concrete sampler for reading GPU utilization, memory, temperature, and power metrics.
///
/// Conforms to `Sampler` (Requirements 5.1, 5.2, 5.3, 11.3, ADR 0003).
/// Non-privileged read operations execute off the main thread via `SampleScheduler`.
public final class GPUSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .gpu

    private let provider: any GPUInfoProvider

    public init(provider: any GPUInfoProvider = HostGPUInfoProvider()) {
        self.provider = provider
    }

    /// Samples GPU metrics. Runs off the main thread.
    public func sample() throws -> GPUSample {
        guard let raw = try provider.gpuStatistics() else {
            throw SamplerError.unsupported("GPU performance statistics unavailable on this system")
        }

        let sample = Self.calculateSample(raw: raw)

        // If no fields could be populated, surface as unsupported
        if sample.utilization == nil && sample.memoryUsed == nil && sample.tempCelsius == nil && sample.powerWatts == nil && sample.coreCount == nil && sample.deviceName == nil {
            throw SamplerError.unsupported("No GPU telemetry reported by hardware")
        }

        return sample
    }

    /// Pure calculation helper constructing a validated `GPUSample`.
    public static func calculateSample(raw: RawGPUStatistics?) -> GPUSample {
        guard let raw = raw else {
            return GPUSample()
        }

        let util: Double? = raw.utilization.map { max(0.0, min(100.0, $0)) }
        let mem: UInt64? = raw.memoryUsed
        let temp: Double? = raw.tempCelsius.flatMap { ($0 >= -40.0 && $0 <= 150.0) ? $0 : nil }
        let pwr: Double? = raw.powerWatts.flatMap { $0 >= 0.0 ? $0 : nil }
        let renderer: Double? = raw.rendererUtilization.map { max(0.0, min(100.0, $0)) }
        let tiler: Double? = raw.tilerUtilization.map { max(0.0, min(100.0, $0)) }
        let coreCount: Int? = raw.coreCount.flatMap { $0 > 0 ? $0 : nil }

        return GPUSample(
            utilization: util,
            memoryUsed: mem,
            tempCelsius: temp,
            powerWatts: pwr,
            coreCount: coreCount,
            deviceName: raw.deviceName,
            allocatedMemory: raw.allocatedMemory,
            recommendedMaxMemory: raw.recommendedMaxMemory,
            rendererUtilization: renderer,
            tilerUtilization: tiler,
            isUnifiedMemory: raw.isUnifiedMemory,
            displayCount: raw.displayCount,
            displayDescriptions: raw.displayDescriptions,
            recoveryCount: raw.recoveryCount
        )
    }
}
