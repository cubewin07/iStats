import Foundation
import Darwin
import IOKit
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

    public init(
        utilization: Double? = nil,
        memoryUsed: UInt64? = nil,
        allocatedMemory: UInt64? = nil,
        tempCelsius: Double? = nil,
        powerWatts: Double? = nil,
        rendererUtilization: Double? = nil,
        tilerUtilization: Double? = nil,
        deviceName: String? = nil
    ) {
        self.utilization = utilization
        self.memoryUsed = memoryUsed
        self.allocatedMemory = allocatedMemory
        self.tempCelsius = tempCelsius
        self.powerWatts = powerWatts
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.deviceName = deviceName
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
        var foundAny = false

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            foundAny = true

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

        guard foundAny || bestUtilization != nil || bestMemoryUsed != nil || bestTemp != nil || bestPower != nil else {
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
            deviceName: bestName
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
        if let temp = readSMCGPUTemperature() {
            return RawGPUStatistics(tempCelsius: temp)
        }
        return nil
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
        if sample.utilization == nil && sample.memoryUsed == nil && sample.tempCelsius == nil && sample.powerWatts == nil {
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

        return GPUSample(
            utilization: util,
            memoryUsed: mem,
            tempCelsius: temp,
            powerWatts: pwr
        )
    }
}
