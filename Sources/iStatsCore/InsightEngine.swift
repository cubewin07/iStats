import Foundation

/// Pure insight detection engine for Instrument panel headlines and scrub lenses (ADR 0009 / Task 8.7).
public enum InsightEngine {

    public enum InsightKind: String, Sendable, CaseIterable {
        case sustained
        case recentSpike
        case peak
        case trendVsAverage
        case quietStreak
    }

    public struct Insight: Equatable, Sendable {
        public let kind: InsightKind
        public let text: String
        public let priority: Int

        public init(kind: InsightKind, text: String, priority: Int) {
            self.kind = kind
            self.text = text
            self.priority = priority
        }
    }

    public enum InsightUnit: Sendable {
        case percent
        case celsius
        case rpm
        case bytesPerSecond
        case watts

        public func format(value: Double) -> String {
            switch self {
            case .percent:
                return "\(Int(round(value)))%"
            case .celsius:
                return "\(Int(round(value)))°"
            case .rpm:
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                let str = formatter.string(from: NSNumber(value: Int(round(value)))) ?? "\(Int(round(value)))"
                return "\(str) rpm"
            case .bytesPerSecond:
                return Units.formatBytesSI(Int64(round(value))) + "/s"
            case .watts:
                return String(format: "%.1f W", value)
            }
        }
    }

    public struct ThresholdBand: Sendable {
        public let quietFloor: Double
        public let elevated: Double
        public let warning: Double

        public init(quietFloor: Double = 10.0, elevated: Double = 50.0, warning: Double = 80.0) {
            self.quietFloor = quietFloor
            self.elevated = elevated
            self.warning = warning
        }
    }

    // MARK: - Core Evaluator

    /// Evaluates the scalar history series and returns all qualifying insights sorted by priority descending.
    public static func insights(
        series: [Double],
        interval: TimeInterval,
        unit: InsightUnit,
        thresholds: ThresholdBand = ThresholdBand()
    ) -> [Insight] {
        guard !series.isEmpty, interval > 0 else { return [] }
        var result: [Insight] = []

        let count = series.count
        let current = series[count - 1]

        // 1. Sustained rule (Priority 5)
        // Current band >= elevated, continuously for >= 60 s.
        var sustainedCount = 0
        for val in series.reversed() {
            if val >= thresholds.elevated {
                sustainedCount += 1
            } else {
                break
            }
        }
        let sustainedDuration = Double(sustainedCount) * interval
        if sustainedDuration >= 60.0 {
            let durStr = formatDuration(sustainedDuration)
            result.append(
                Insight(
                    kind: .sustained,
                    text: "Busy for \(durStr)",
                    priority: 5
                )
            )
        }

        // 2. Recent Spike rule (Priority 4)
        // A spike occurred within the last 30 s that was >= 1.5x previous baseline and >= 15 pt jump.
        let window30Samples = max(1, Int(30.0 / interval))
        if count > window30Samples {
            let recentWindow = series.suffix(window30Samples)
            let priorWindow = series.prefix(count - window30Samples)
            let priorAvg = priorWindow.reduce(0.0, +) / Double(priorWindow.count)

            if let maxRecent = recentWindow.max(), let maxRecentIdx = series.lastIndex(of: maxRecent) {
                let secondsAgo = Double(count - 1 - maxRecentIdx) * interval
                if maxRecent >= 1.5 * max(priorAvg, 1.0) && (maxRecent - priorAvg) >= 15.0 && secondsAgo <= 30.0 {
                    let secStr = "\(Int(round(secondsAgo)))s"
                    result.append(
                        Insight(
                            kind: .recentSpike,
                            text: "Spike to \(unit.format(value: maxRecent)) · \(secStr) ago",
                            priority: 4
                        )
                    )
                }
            }
        }

        // 3. Peak rule (Priority 3)
        // Peak is >= 1.25x the current value and >= 30 s old.
        if let peakIdx = LiveChartMath.peakIndex(values: series) {
            let peakVal = series[peakIdx]
            let secondsAgo = Double(count - 1 - peakIdx) * interval
            if peakVal >= 1.25 * max(current, 1.0) && secondsAgo >= 30.0 && (peakVal - current) >= 10.0 {
                let durStr = formatDuration(secondsAgo)
                result.append(
                    Insight(
                        kind: .peak,
                        text: "Peak \(unit.format(value: peakVal)) · \(durStr) ago",
                        priority: 3
                    )
                )
            }
        }

        // 4. Trend vs Average rule (Priority 2)
        // |Delta| >= 10% and window has >= 60 samples.
        if count >= 60 {
            let avg = series.reduce(0.0, +) / Double(count)
            let diff = current - avg
            if abs(diff) >= 10.0 {
                let windowDur = formatDuration(Double(count) * interval)
                let direction = diff > 0 ? "Up" : "Down"
                let diffStr = unit == .percent ? "\(Int(round(abs(diff))))%" : unit.format(value: abs(diff))
                result.append(
                    Insight(
                        kind: .trendVsAverage,
                        text: "\(direction) \(diffStr) vs \(windowDur) avg",
                        priority: 2
                    )
                )
            }
        }

        // 5. Quiet Streak rule (Priority 1)
        // Below the fine-band floor for >= 5m (300 s).
        var quietCount = 0
        for val in series.reversed() {
            if val <= thresholds.quietFloor {
                quietCount += 1
            } else {
                break
            }
        }
        let quietDuration = Double(quietCount) * interval
        if quietDuration >= 300.0 {
            let durStr = formatDuration(quietDuration)
            result.append(
                Insight(
                    kind: .quietStreak,
                    text: "Idle for \(durStr)",
                    priority: 1
                )
            )
        }

        // Sort by priority descending
        return result.sorted { $0.priority > $1.priority }
    }

    /// Returns the highest-priority qualifying insight, or nil if none qualify.
    public static func best(
        series: [Double],
        interval: TimeInterval,
        unit: InsightUnit,
        thresholds: ThresholdBand = ThresholdBand()
    ) -> Insight? {
        insights(series: series, interval: interval, unit: unit, thresholds: thresholds).first
    }

    // MARK: - Duration Formatter Helper

    public static func formatDuration(_ seconds: Double) -> String {
        let sec = Int(round(seconds))
        if sec < 60 {
            return "\(sec)s"
        } else if sec < 3600 {
            let mins = sec / 60
            let rem = sec % 60
            return rem > 0 ? "\(mins)m \(rem)s" : "\(mins)m"
        } else {
            let hrs = sec / 3600
            let remMins = (sec % 3600) / 60
            return remMins > 0 ? "\(hrs)h \(remMins)m" : "\(hrs)h"
        }
    }
}
