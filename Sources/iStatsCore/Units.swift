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
}
