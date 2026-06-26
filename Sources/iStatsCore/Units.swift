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

    // MARK: Data size

    /// How byte values are grouped for display.
    public enum ByteUnitStandard: Sendable {
        /// 1 KB = 1000 bytes (SI / decimal).
        case si
        /// 1 KiB = 1024 bytes (IEC / binary).
        case iec
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
