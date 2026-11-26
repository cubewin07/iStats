import Foundation

/// Outcome of evaluating a single reading against an `AlertRule`.
public enum AlertDecision: Equatable, Sendable {
    case none
    case fire
    case clear
}

/// Per-rule evaluation state tracked across samples.
public struct AlertRuleState: Equatable, Sendable {
    public var pendingSince: Date?
    public var lastFired: Date?
    public var armed: Bool

    public init(pendingSince: Date? = nil, lastFired: Date? = nil, armed: Bool = true) {
        self.pendingSince = pendingSince
        self.lastFired = lastFired
        self.armed = armed
    }
}

/// Pure, stateful alert engine with sustain window, cooldown, hysteresis re-arming,
/// unavailable-reading reset, and backwards clock-jump safety.
public struct AlertEvaluator: Equatable, Sendable {
    public private(set) var states: [AlertKind: AlertRuleState]

    public init(states: [AlertKind: AlertRuleState] = [:]) {
        self.states = states
    }

    /// Returns the tracked state for `kind`, defaulting to a fresh armed state.
    public func state(for kind: AlertKind) -> AlertRuleState {
        states[kind] ?? AlertRuleState()
    }

    /// Clears state for one rule kind, or for all kinds when `kind` is `nil`.
    public mutating func reset(kind: AlertKind? = nil) {
        if let kind {
            states.removeValue(forKey: kind)
        } else {
            states.removeAll()
        }
    }

    /// Clears cooldown timestamps while keeping arm/pending state intact.
    public mutating func resetCooldowns() {
        for kind in states.keys {
            states[kind]?.lastFired = nil
        }
    }

    /// Records a manual fire timestamp for `kind` (used for test/coordinator sync).
    public mutating func recordFired(kind: AlertKind, now: Date) {
        var current = states[kind] ?? AlertRuleState()
        current.pendingSince = nil
        current.lastFired = now
        current.armed = false
        states[kind] = current
    }

    /// Hysteresis band required to re-arm after firing: 2 °C for temperature, 5% of threshold otherwise.
    public static func hysteresisMargin(for rule: AlertRule) -> Double {
        switch rule.kind {
        case .temperature:
            return 2.0
        case .cpu, .memory, .batteryLow, .batteryFull, .disk:
            return max(0.5, abs(rule.threshold) * 0.05)
        }
    }

    /// Whether `value` has crossed back past the threshold by the hysteresis margin.
    public static func isRearmed(rule: AlertRule, value: Double) -> Bool {
        let margin = hysteresisMargin(for: rule)
        switch rule.comparison {
        case .above:
            return value <= rule.threshold - margin
        case .below:
            return value >= rule.threshold + margin
        }
    }

    /// Evaluates one reading (`nil` = unavailable) at `now` against `rule`.
    public mutating func evaluate(rule: AlertRule, value: Double?, now: Date) -> AlertDecision {
        var current = states[rule.kind] ?? AlertRuleState()
        defer { states[rule.kind] = current }

        guard rule.enabled else {
            current.pendingSince = nil
            current.armed = true
            return .none
        }

        guard let value, value.isFinite else {
            current.pendingSince = nil
            return .none
        }

        // Clamp stored timestamps if the wall clock jumped backwards so neither sustain nor cooldown stalls.
        if let lastFired = current.lastFired, now < lastFired {
            current.lastFired = now
        }
        if let pendingSince = current.pendingSince, now < pendingSince {
            current.pendingSince = now
        }

        if !current.armed {
            current.pendingSince = nil
            if Self.isRearmed(rule: rule, value: value) {
                current.armed = true
                return .clear
            }
            return .none
        }

        guard rule.isTriggered(by: value) else {
            current.pendingSince = nil
            return .none
        }

        let pendingSince = current.pendingSince ?? now
        current.pendingSince = pendingSince

        let sustained = now.timeIntervalSince(pendingSince)
        guard sustained >= max(0, rule.sustainSeconds) else {
            return .none
        }

        if let lastFired = current.lastFired,
           now.timeIntervalSince(lastFired) < max(0, rule.cooldownSeconds) {
            return .none
        }

        current.pendingSince = nil
        current.lastFired = now
        current.armed = false
        return .fire
    }
}
