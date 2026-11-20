import Foundation

/// Pure mathematical helpers for the Instrument motion system (ADR 0009 / Task 8.2).
public enum MotionMath {
    /// Computes the value transition duration based on sample interval: min(0.6, interval × 0.6).
    public static func valueDuration(interval: Double) -> Double {
        guard interval > 0 else { return 0.0 }
        return min(0.6, interval * 0.6)
    }
}

/// Motion policy driving all animated UI components, resolved from accessibility and system states.
public enum MotionPolicy: String, Codable, Sendable, Equatable {
    /// Full continuous animations, glide, turbine spin, liquid particles, rolling digits.
    case full

    /// Reduced motion: instant/step updates, crossfade digits, static glyphs, no gliding charts.
    case reduced

    /// Frozen: no updates, paused chart, sampling inactive or view hidden.
    case frozen

    /// Whether continuous animations (gliding charts, pulse rings, turbine blades) are permitted.
    public var allowsContinuousAnimation: Bool {
        self == .full
    }

    /// Whether discrete value easing (progress bars, numerals) is permitted.
    public var allowsEasing: Bool {
        self != .frozen
    }

    /// Pure resolver deciding motion policy from system environmental flags.
    public static func resolve(
        reduceMotion: Bool,
        lowPower: Bool,
        paused: Bool,
        visible: Bool
    ) -> MotionPolicy {
        guard visible else { return .frozen }
        if paused || lowPower {
            return .frozen
        }
        if reduceMotion {
            return .reduced
        }
        return .full
    }
}
