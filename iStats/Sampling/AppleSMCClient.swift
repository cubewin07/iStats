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

    // MARK: - Telemetry & Diagnostic Counters
    public private(set) var openConnectionCount: Int = 0
    public private(set) var reconnectCount: Int = 0

    public func resetPerformanceCounters() {
        lock.lock()
        defer { lock.unlock() }
        reconnectCount = 0
    }

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
        openConnectionCount += 1
        return conn
    }

    private func close() {
        if _connection != 0 {
            IOServiceClose(_connection)
            _connection = 0
        }
    }

    private enum SMCReadResult<T> {
        case success(T)
        case keyNotFound
        case transportError(kern_return_t)
    }

    /// Reads a numeric key from SMC using the persistent connection with self-healing reconnect on failure.
    public func readNumericKey(_ keyStr: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }

        guard let conn = getOrCreateConnection() else { return nil }
        switch readNumericKeyInternal(keyStr: keyStr, connection: conn) {
        case .success(let val):
            return val
        case .keyNotFound:
            return nil
        case .transportError:
            // Retry once after reopening connection ONLY when Mach transport / user client connection died
            close()
            reconnectCount += 1
            guard let reconnected = getOrCreateConnection() else { return nil }
            if case .success(let val) = readNumericKeyInternal(keyStr: keyStr, connection: reconnected) {
                return val
            }
            return nil
        }
    }

    /// Reads an ASCII string key from SMC using the persistent connection.
    public func readStringKey(_ keyStr: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let conn = getOrCreateConnection() else { return nil }
        switch readStringKeyInternal(keyStr: keyStr, connection: conn) {
        case .success(let val):
            return val
        case .keyNotFound:
            return nil
        case .transportError:
            close()
            reconnectCount += 1
            guard let reconnected = getOrCreateConnection() else { return nil }
            if case .success(let val) = readStringKeyInternal(keyStr: keyStr, connection: reconnected) {
                return val
            }
            return nil
        }
    }

    // MARK: - Internal IOKit Communication

    private func readNumericKeyInternal(keyStr: String, connection: io_connect_t) -> SMCReadResult<Double> {
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
        guard kr == KERN_SUCCESS else {
            return .transportError(kr)
        }
        guard output.result == 0 else {
            return .keyNotFound
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
        guard kr == KERN_SUCCESS else {
            return .transportError(kr)
        }
        guard output.result == 0 else {
            return .keyNotFound
        }

        let typeStr = fourCharCodeToString(dataType)
        let decoded = withUnsafeBytes(of: output.bytes) { buffer in
            decodeNumericValue(buffer: buffer, size: Int(dataSize), type: typeStr)
        }
        if let val = decoded {
            return .success(val)
        } else {
            return .keyNotFound
        }
    }

    private func readStringKeyInternal(keyStr: String, connection: io_connect_t) -> SMCReadResult<String> {
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
        guard kr == KERN_SUCCESS else {
            return .transportError(kr)
        }
        guard output.result == 0 else {
            return .keyNotFound
        }

        let dataSize = output.keyInfo_dataSize
        let dataType = output.keyInfo_dataType
        let typeStr = fourCharCodeToString(dataType)

        guard typeStr == "ch8*" || typeStr == "{clh" || typeStr.hasPrefix("ch") else {
            return .keyNotFound
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
        guard kr == KERN_SUCCESS else {
            return .transportError(kr)
        }
        guard output.result == 0 else {
            return .keyNotFound
        }

        let decoded = withUnsafeBytes(of: output.bytes) { buffer in
            decodeStringValue(buffer: buffer, size: Int(dataSize))
        }
        if let val = decoded {
            return .success(val)
        } else {
            return .keyNotFound
        }
    }

    // MARK: - Value Decoders

    private func decodeNumericValue(buffer: UnsafeRawBufferPointer, size: Int, type: String) -> Double? {
        guard size > 0, size <= buffer.count else { return nil }
        let rawBytes = buffer.bindMemory(to: UInt8.self)

        switch type {
        case "flt ", "\0\0\0\0":
            if size == 4 {
                var floatVal: Float32 = 0.0
                memcpy(&floatVal, rawBytes.baseAddress!, 4)
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
                memcpy(&floatVal, rawBytes.baseAddress!, 4)
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

    private func decodeStringValue(buffer: UnsafeRawBufferPointer, size: Int) -> String? {
        guard size > 0 else { return nil }
        let length = min(size, buffer.count)
        let validBytes = buffer.prefix(length).filter { $0 != 0 }
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
