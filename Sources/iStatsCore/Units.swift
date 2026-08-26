import Foundation

/// Pure unit-conversion helpers (Requirement 11.3). No OS dependency.
public enum Units {

    // MARK: Temperature

    public static func celsiusToFahrenheit(_ c: Double) -> Double {
        c * 9.0 / 5.0 + 32.0
    }

    public static func fahrenheitToCelsius(_ f: Double) -> Double {
        (f - 32.0) * 5.0 / 9.0
    }

    /// Temperature display unit.
    public enum TemperatureUnit: String, CaseIterable, Identifiable, Codable, Sendable {
        case celsius = "celsius"
        case fahrenheit = "fahrenheit"

        public var id: String { rawValue }

        public var symbol: String {
            switch self {
            case .celsius: return "°C"
            case .fahrenheit: return "°F"
            }
        }

        public var displayName: String {
            switch self {
            case .celsius: return "Celsius (°C)"
            case .fahrenheit: return "Fahrenheit (°F)"
            }
        }
    }

    /// Format a temperature in Celsius to a formatted string based on the chosen unit (°C vs °F) (Requirement 11.3).
    public static func formatTemperature(
        _ celsius: Double,
        unit: TemperatureUnit = .celsius,
        fractionDigits: Int = 1
    ) -> String {
        guard celsius.isFinite && !celsius.isNaN else {
            return "N/A"
        }
        let value = unit == .fahrenheit ? celsiusToFahrenheit(celsius) : celsius
        return String(format: "%.\(fractionDigits)f %@", value, unit.symbol)
    }

    /// Format a SensorReading using the specified TemperatureUnit (Requirement 3.2, 11.3).
    public static func formatTemperatureSensor(
        _ sensor: SensorReading,
        unit: TemperatureUnit = .celsius,
        fractionDigits: Int = 1
    ) -> String {
        formatTemperature(sensor.celsius, unit: unit, fractionDigits: fractionDigits)
    }

    /// Network rate display unit.
    public enum NetworkUnit: String, CaseIterable, Identifiable, Codable, Sendable {
        case bytesPerSecond = "bytesPerSecond"
        case bitsPerSecond = "bitsPerSecond"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .bytesPerSecond: return "Bytes/sec (B/s, KB/s, MB/s)"
            case .bitsPerSecond: return "Bits/sec (bps, Kbps, Mbps)"
            }
        }
    }

    // MARK: Data size

    /// How byte values are grouped for display.
    public enum ByteUnitStandard: String, CaseIterable, Identifiable, Codable, Sendable {
        /// 1 KB = 1000 bytes (SI / decimal).
        case si = "si"
        /// 1 KiB = 1024 bytes (IEC / binary).
        case iec = "iec"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .si: return "SI / Decimal (1000 B = 1 KB)"
            case .iec: return "IEC / Binary (1024 B = 1 KiB)"
            }
        }
    }

    private static let siSuffixes = ["B", "KB", "MB", "GB", "TB", "PB"]
    private static let iecSuffixes = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]

    /// Format a byte count into a human-readable string, e.g. "1.50 GB".
    public static func formatBytes(_ bytes: UInt64,
                                   standard: ByteUnitStandard = .iec,
                                   fractionDigits: Int = 2) -> String {
        let base: Double = standard == .si ? 1000 : 1024
        let suffixes = standard == .si ? siSuffixes : iecSuffixes
        var value = Double(bytes)
        var index = 0
        while value >= base && index < suffixes.count - 1 {
            value /= base
            index += 1
        }
        if index == 0 {
            return "\(bytes) \(suffixes[0])"
        }
        return String(format: "%.\(fractionDigits)f %@", value, suffixes[index])
    }

    /// Convert bytes-per-second to bits-per-second (network displays sometimes use bits).
    public static func bytesPerSecToBitsPerSec(_ bytesPerSec: Double) -> Double {
        bytesPerSec * 8.0
    }

    // MARK: - Transfer / Throughput Rates

    private static let bytePerSecSiSuffixes = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s", "PB/s"]
    private static let bytePerSecIecSuffixes = ["B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s"]
    private static let bitPerSecSuffixes = ["bps", "Kbps", "Mbps", "Gbps", "Tbps", "Pbps"]

    /// Format a network transfer rate into a human-readable string based on unit and standard (Requirement 11.3).
    public static func formatNetworkRate(
        _ bytesPerSec: Double,
        unit: NetworkUnit = .bytesPerSecond,
        standard: ByteUnitStandard = .iec,
        fractionDigits: Int = 2
    ) -> String {
        guard bytesPerSec.isFinite && !bytesPerSec.isNaN else {
            switch unit {
            case .bytesPerSecond: return "0 B/s"
            case .bitsPerSecond: return "0 bps"
            }
        }

        switch unit {
        case .bytesPerSecond:
            let base: Double = standard == .si ? 1000.0 : 1024.0
            let suffixes = standard == .si ? bytePerSecSiSuffixes : bytePerSecIecSuffixes
            var value = max(0.0, bytesPerSec)
            var index = 0
            while value >= base && index < suffixes.count - 1 {
                value /= base
                index += 1
            }
            if index == 0 && value.rounded() == value {
                return "\(Int(value)) \(suffixes[0])"
            }
            return String(format: "%.\(fractionDigits)f %@", value, suffixes[index])

        case .bitsPerSecond:
            let base: Double = 1000.0
            let suffixes = bitPerSecSuffixes
            var value = max(0.0, bytesPerSecToBitsPerSec(bytesPerSec))
            var index = 0
            while value >= base && index < suffixes.count - 1 {
                value /= base
                index += 1
            }
            if index == 0 && value.rounded() == value {
                return "\(Int(value)) \(suffixes[0])"
            }
            return String(format: "%.\(fractionDigits)f %@", value, suffixes[index])
        }
    }

    /// Format a disk I/O transfer rate (in bytes per second) into a human-readable string.
    public static func formatDiskRate(
        _ bytesPerSec: Double,
        standard: ByteUnitStandard = .iec,
        fractionDigits: Int = 2
    ) -> String {
        formatNetworkRate(bytesPerSec, unit: .bytesPerSecond, standard: standard, fractionDigits: fractionDigits)
    }

    // MARK: Frequency

    private static let hzSuffixes = ["Hz", "kHz", "MHz", "GHz", "THz"]

    /// Format a frequency in Hertz into a human-readable string, e.g. "2.40 GHz" or "800.00 MHz".
    public static func formatFrequencyHz(_ hz: UInt64, fractionDigits: Int = 2) -> String {
        let base: Double = 1000.0
        var value = Double(hz)
        var index = 0
        while value >= base && index < hzSuffixes.count - 1 {
            value /= base
            index += 1
        }
        if index == 0 {
            return "\(hz) \(hzSuffixes[0])"
        }
        return String(format: "%.\(fractionDigits)f %@", value, hzSuffixes[index])
    }
}
