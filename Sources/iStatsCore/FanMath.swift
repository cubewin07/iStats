import Foundation

/// Pure mathematical transformations and visual speed curves for fan turbines (ADR 0009 / Task 8.8e).
public enum FanMath {
    /// Maximum visual rotation speed in revolutions per second (rps) to prevent strobing or visual blur.
    public static let maxVisualRPS: Double = 1.5
    /// Minimum visual rotation speed when spinning at idle/minimum RPM.
    public static let minVisualRPS: Double = 0.2
    /// Fallback maximum RPM for scaling when hardware limits are not exposed.
    public static let fallbackMaxRPM: Double = 6000.0

    /// Calculates revolutions per second for animating a turbine blade.
    /// Returns 0.0 when RPM <= 0, scales smoothly between minVisualRPS and maxVisualRPS,
    /// and is strictly capped at maxVisualRPS (1.5 rps).
    public static func visualSpeed(rpm: Double, min minRPM: Double? = nil, max maxRPM: Double? = nil) -> Double {
        guard rpm > 0 else { return 0.0 }

        let minBound = minRPM ?? 0.0
        let maxBound = maxRPM ?? fallbackMaxRPM

        let effectiveSpan = max(1.0, maxBound - minBound)
        let normalized = max(0.0, min(1.0, (rpm - minBound) / effectiveSpan))

        let speed = minVisualRPS + (normalized * (maxVisualRPS - minVisualRPS))
        return min(maxVisualRPS, max(0.0, speed))
    }

    /// Convenience overload for integer RPM readings.
    public static func visualSpeed(rpm: Int, min minRPM: Int? = nil, max maxRPM: Int? = nil) -> Double {
        visualSpeed(
            rpm: Double(rpm),
            min: minRPM.map { Double($0) },
            max: maxRPM.map { Double($0) }
        )
    }

    /// Computes the normalized fraction (0.0 ... 1.0) for an RPM value between bounds.
    public static func fraction(rpm: Int, min minRPM: Int? = nil, max maxRPM: Int? = nil) -> Double {
        let current = Double(rpm)
        let minBound = minRPM.map { Double($0) } ?? 0.0
        let maxBound = maxRPM.map { Double($0) } ?? fallbackMaxRPM
        let span = max(1.0, maxBound - minBound)
        return max(0.0, min(1.0, (current - minBound) / span))
    }

    /// Computes rotation angle in degrees for a given timestamp and rotation speed.
    public static func rotationDegrees(time: TimeInterval, speedRPS: Double) -> Double {
        (time * speedRPS * 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// Steps rotation angle incrementally based on elapsed time dt (in seconds) and rotation speed in rps.
    /// This avoids phase jumps when speedRPS changes between sampling intervals.
    public static func stepRotationDegrees(currentDegrees: Double, dt: TimeInterval, speedRPS: Double) -> Double {
        guard speedRPS > 0, dt > 0 else { return currentDegrees }
        let clampedDt = min(0.1, dt) // Bound dt to 100ms to prevent huge jumps on unpause
        return (currentDegrees + (clampedDt * speedRPS * 360.0)).truncatingRemainder(dividingBy: 360.0)
    }
}

