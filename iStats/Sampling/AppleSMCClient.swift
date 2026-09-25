import Foundation
import IOKit

/// A centralized, thread-safe, persistent client for querying AppleSMC hardware keys
/// via IOKit. Maintains a persistent `io_connect_t` user client across samples, eliminating
/// the high kernel context-switch cost of opening and closing connections on every tick
/// (ADR 0003, ADR 0004, Energy Impact Stage 2).
public final class AppleSMCClient: @unchecked Sendable {

    /// Shared singleton instance.
    public static let shared = AppleSMCClient()

    private let lock = NSLock()
    private var _connection: io_connect_t = 0

    private let kSMCHandleYPCEvent: UInt32 = 2
    private let kSMCGetKeyInfo: UInt8 = 9
    private let kSMCReadKey: UInt8 = 5

    public init() {}

    deinit {
        close()
    }

    /// Returns the active SMC connection handle, opening it if not already open.
    public func connection() -> io_connect_t? {
        lock.lock()
        defer { lock.unlock() }
        return getOrCreateConnection()
    }

    /// Closes and invalidates the current SMC connection (useful on sleep-wake or error recovery).
    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        close()
    }

    private func getOrCreateConnection() -> io_connect_t? {
        if _connection != 0 {
            return _connection
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let openRes = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard openRes == KERN_SUCCESS, conn != 0 else {
            return nil
        }
        _connection = conn
        return conn
    }

    private func close() {
        if _connection != 0 {
            IOServiceClose(_connection)
            _connection = 0
        }
    }

    /// Reads a numeric key from SMC using the persistent connection with self-healing reconnect on failure.
    public func readNumericKey(_ keyStr: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }

        guard let conn = getOrCreateConnection() else { return nil }
        if let val = readNumericKeyInternal(keyStr: keyStr, connection: conn) {
            return val
        }

        // Retry once after reopening connection in case connection went stale across system sleep
        close()
        guard let reconnected = getOrCreateConnection() else { return nil }
        return readNumericKeyInternal(keyStr: keyStr, connection: reconnected)
    }

    /// Reads an ASCII string key from SMC using the persistent connection.
    public func readStringKey(_ keyStr: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let conn = getOrCreateConnection() else { return nil }
        if let val = readStringKeyInternal(keyStr: keyStr, connection: conn) {
            return val
        }

        close()
        guard let reconnected = getOrCreateConnection() else { return nil }
        return readStringKeyInternal(keyStr: keyStr, connection: reconnected)
    }

    // MARK: - Internal IOKit Communication

    private func readNumericKeyInternal(keyStr: String, connection: io_connect_t) -> Double? {
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
        guard kr == KERN_SUCCESS, output.result == 0 else {
            return nil
        }

        let dataSize = output.keyInfo_dataSize
        let dataType = output.keyInfo_dataType

        input.keyInfo_dataSize = dataSize
        input.data8 = kSMCReadKey

        kr = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outSize
        )
        guard kr == KERN_SUCCESS, output.result == 0 else {
            return nil
        }

        let typeStr = fourCharCodeToString(dataType)
        return decodeNumericValue(bytes: output.bytes, size: Int(dataSize), type: typeStr)
    }

    private func readStringKeyInternal(keyStr: String, connection: io_connect_t) -> String? {
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
        guard kr == KERN_SUCCESS, output.result == 0 else {
            return nil
        }

        let dataSize = output.keyInfo_dataSize
        let dataType = output.keyInfo_dataType
        let typeStr = fourCharCodeToString(dataType)

        guard typeStr == "ch8*" || typeStr == "{clh" || typeStr.hasPrefix("ch") else {
            return nil
        }

        input.keyInfo_dataSize = dataSize
        input.data8 = kSMCReadKey

        kr = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outSize
        )
        guard kr == KERN_SUCCESS, output.result == 0 else {
            return nil
        }

        return decodeStringValue(bytes: output.bytes, size: Int(dataSize))
    }

    // MARK: - Value Decoders

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
                if floatVal.isFinite && floatVal >= 0 && floatVal < 100000 {
                    return Double(floatVal)
                }
            }
        case "sp78":
            if size == 2 {
                let raw = (Int16(rawBytes[0]) << 8) | Int16(rawBytes[1])
                let scaled = Double(raw) / 256.0
                if scaled >= 0 && scaled < 100000 {
                    return scaled
                }
            }
        case "fpe2":
            if size == 2 {
                let raw = (Int16(rawBytes[0]) << 8) | Int16(rawBytes[1])
                let scaled = Double(raw) / 4.0
                if scaled >= 0 && scaled < 100000 {
                    return scaled
                }
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
                if floatVal.isFinite && floatVal >= 0 && floatVal < 100000 {
                    return Double(floatVal)
                }
            } else if size == 2 {
                let raw = (Int16(rawBytes[0]) << 8) | Int16(rawBytes[1])
                return Double(raw) / 256.0
            }
        }

        return nil
    }

    private func decodeStringValue(bytes: Any, size: Int) -> String? {
        var rawBytes = [UInt8](repeating: 0, count: 32)
        withUnsafeBytes(of: bytes) { rawBytesPtr in
            for i in 0..<min(32, rawBytesPtr.count) {
                rawBytes[i] = rawBytesPtr[i]
            }
        }

        let length = min(size, 32)
        let validBytes = rawBytes.prefix(length).filter { $0 != 0 }
        guard !validBytes.isEmpty else { return nil }

        let str = String(bytes: validBytes, encoding: .ascii) ?? String(bytes: validBytes, encoding: .utf8)
        let trimmed = str?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
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
