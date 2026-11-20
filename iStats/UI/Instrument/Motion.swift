import SwiftUI
import iStatsCore

/// Animation curves and motion tokens for the Instrument design language (ADR 0009 / design.md §5).
public enum Motion {
    /// Snappy spring for page switches, puck transitions, pin detachment, and status ribbons.
    public static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Smooth spring for panel height changes and module appearances.
    public static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.92)

    /// Dynamic easing for values, gauges, bars, and rolling numerals.
    public static func value(interval: Double = 1.0) -> Animation {
        .easeOut(duration: MotionMath.valueDuration(interval: interval))
    }

    /// Linear glide for continuous live chart scrolling between samples.
    public static func glide(interval: Double) -> Animation {
        .linear(duration: interval)
    }

    /// Scale and fade transition for panel presentation.
    public static let panelIn = snappy
    public static let panelOut = Animation.easeIn(duration: 0.12)
}

// MARK: - Motion Policy Environment

private struct MotionPolicyKey: EnvironmentKey {
    static let defaultValue: MotionPolicy = .full
}

extension EnvironmentValues {
    /// Active motion policy governing animations across all instrument views.
    public var motionPolicy: MotionPolicy {
        get { self[MotionPolicyKey.self] }
        set { self[MotionPolicyKey.self] = newValue }
    }
}

extension View {
    /// Sets the motion policy for this view hierarchy.
    public func motionPolicy(_ policy: MotionPolicy) -> some View {
        environment(\.motionPolicy, policy)
    }
}
