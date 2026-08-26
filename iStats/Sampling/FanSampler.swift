import Foundation
import Darwin
import IOKit
import iStatsCore

// MARK: - Fan Info Provider Protocol

/// Abstract provider for reading physical fan telemetry and speed bounds from macOS hardware.
public protocol FanInfoProvider: Sendable {
    /// Returns the number of physical fans detected on the machine.
    func fanCount() throws -> Int

    /// Returns telemetry for each detected fan, including current RPM and min/max RPM bounds if exposed.
    func fans() throws -> [FanReading]
}

public extension FanInfoProvider {
    func fanCount() throws -> Int {
        try fans().count
    }
}

// MARK: - Host Fan Info Provider

/// Darwin AppleSMC implementation of `FanInfoProvider` (ADR 0003, Requirements 4.1, 4.2).
public struct HostFanInfoProvider: FanInfoProvider {

    private let kSMCGetKeyInfo: UInt8 = 9
    private let kSMCReadKey: UInt8 = 5
    private let kSMCHandleYPCEvent: UInt32 = 2

    public init() {}

    public func fanCount() throws -> Int {
        guard let conn = openSMCConnection() else {
            throw SamplerError.unsupported("AppleSMC service not available")
        }
        defer { IOServiceClose(conn) }

        return readFanCount(connection: conn)
    }

    public func fans() throws -> [FanReading] {
        guard let conn = openSMCConnection() else {
            throw SamplerError.unsupported("AppleSMC service not available")
        }
        defer { IOServiceClose(conn) }

        let count = readFanCount(connection: conn)
        guard count > 0 else {
            // Fanless systems (e.g. MacBook Air) report 0 fans cleanly (Requirement 4.4, ADR 0003)
            return []
        }

        var results: [FanReading] = []
        for i in 0..<count {
            let actualKey = "F\(i)Ac"
            let minKey = "F\(i)Mn"
            let maxKey = "F\(i)Mx"
            let idKey = "F\(i)ID"

            let actualRPM = readSMCKeyNumeric(keyStr: actualKey, connection: conn).map { Int(round($0)) } ?? 0
            let minRPM = readSMCKeyNumeric(keyStr: minKey, connection: conn).map { Int(round($0)) }
            let maxRPM = readSMCKeyNumeric(keyStr: maxKey, connection: conn).map { Int(round($0)) }
            let fanName = readSMCKeyString(keyStr: idKey, connection: conn) ?? defaultFanName(index: i, total: count)

            results.append(
                FanReading(
                    name: fanName,
                    rpm: max(0, actualRPM),
                    minRPM: minRPM.flatMap { $0 >= 0 ? $0 : nil },
                    maxRPM: maxRPM.flatMap { $0 >= 0 ? $0 : nil }
                )
            )
        }

        return results
    }

    // MARK: - SMC Connection Helper

    private func openSMCConnection() -> io_connect_t? {
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
        return conn
    }

    // MARK: - SMC Key Readers

    private func readFanCount(connection: io_connect_t) -> Int {
        // Read FNum key
        if let countVal = readSMCKeyNumeric(keyStr: "FNum", connection: connection) {
            let count = Int(countVal)
            if count >= 0 && count <= 16 {
                return count
            }
        }

        // Fallback: check if F0Ac exists
        if readSMCKeyNumeric(keyStr: "F0Ac", connection: connection) != nil {
            if readSMCKeyNumeric(keyStr: "F1Ac", connection: connection) != nil {
                return 2
            }
            return 1
        }

        return 0
    }

    private func defaultFanName(index: Int, total: Int) -> String {
        if total == 1 {
            return "Fan"
        } else if total == 2 {
            return index == 0 ? "Left Fan" : "Right Fan"
        } else {
            return "Fan \(index + 1)"
        }
    }

    private func readSMCKeyNumeric(keyStr: String, connection: io_connect_t) -> Double? {
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
        case "ui32":
            if dataSize == 4 {
                let raw = (UInt32(rawBytes[0]) << 24) | (UInt32(rawBytes[1]) << 16) | (UInt32(rawBytes[2]) << 8) | UInt32(rawBytes[3])
                return Double(raw)
            }
        default:
            break
        }

        return nil
    }

    private func readSMCKeyString(keyStr: String, connection: io_connect_t) -> String? {
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

        let dataSize = min(output.keyInfo_dataSize, 32)
        guard dataSize > 0 else { return nil }

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
        // Filter non-null characters and trim whitespace
        let cleanedBytes = rawBytes.prefix(while: { $0 != 0 })
        if let str = String(bytes: cleanedBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
            return str
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

// MARK: - Concrete Fan Sampler

/// Concrete sampler for reading fan RPM and hardware speed bounds.
///
/// Conforms to `Sampler` (Requirements 4.1, 4.2, 11.3, ADR 0003, ADR 0004).
/// Strictly read-only; executes background work only via `SampleScheduler`.
public final class FanSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .fan

    private let provider: any FanInfoProvider

    public init(provider: any FanInfoProvider = HostFanInfoProvider()) {
        self.provider = provider
    }

    /// Samples fan speeds and RPM bounds. Runs off the main thread.
    public func sample() throws -> FanSample {
        let fans = try provider.fans()
        return Self.calculateSample(fans: fans)
    }

    /// Pure calculation helper constructing a validated `FanSample`.
    public static func calculateSample(fans: [FanReading]) -> FanSample {
        let validFans = fans.map { fan in
            FanReading(
                name: fan.name,
                rpm: max(0, fan.rpm),
                minRPM: fan.minRPM.flatMap { $0 >= 0 ? $0 : nil },
                maxRPM: fan.maxRPM.flatMap { $0 >= 0 ? $0 : nil }
            )
        }
        return FanSample(fans: validFans)
    }
}
