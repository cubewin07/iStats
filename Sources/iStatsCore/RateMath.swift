import Foundation

/// Pure functions for deriving rates and utilization from cumulative counters.
///
/// This is the single most bug-prone part of a system monitor (see
/// `docs/prerequisites-and-learning.md`, "Counters vs. rates"), so it lives here
/// as pure, unit-tested logic with no OS dependency.
public enum RateMath {

    /// Compute CPU utilization percent (0...100) from cumulative tick counters.
    ///
    /// - Parameters:
    ///   - busyDelta: busy ticks elapsed since the previous sample (user + system + nice).
    ///   - totalDelta: total ticks elapsed since the previous sample (busy + idle).
    /// - Returns: utilization clamped to 0...100. Returns 0 if `totalDelta <= 0`
    ///   (e.g., the very first sample, or no elapsed time).
    public static func cpuUsagePercent(busyDelta: Double, totalDelta: Double) -> Double {
        guard totalDelta > 0 else { return 0 }
        let pct = (busyDelta / totalDelta) * 100
        return min(100, max(0, pct))
    }

    /// Compute a per-second byte rate from two cumulative counter samples.
    ///
    /// Handles the counter-reset case (Requirement 6.4): if the new counter is
    /// less than the previous one (interface restarted / counter wrapped), the
    /// delta is treated as 0 for this cycle rather than producing a negative or
    /// absurd rate.
    ///
    /// - Returns: bytes per second, never negative. Returns 0 if `elapsedSeconds <= 0`.
    public static func bytesPerSecond(previous: UInt64, current: UInt64, elapsedSeconds: Double) -> Double {
        guard elapsedSeconds > 0 else { return 0 }
        guard current >= previous else { return 0 } // counter reset/wrap
        let delta = Double(current - previous)
        return delta / elapsedSeconds
    }
}
