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

    public enum InsightUnit: Sendable, Equatable {
        case percent
        case celsius
        case fahrenheit
        case rpm
        case bytesPerSecond(standard: Units.ByteUnitStandard)
        case watts

        public static let bytesPerSecond = InsightUnit.bytesPerSecond(standard: .si)

        public func format(value: Double) -> String {
            switch self {
            case .percent:
                return "\(Int(round(value)))%"
            case .celsius:
                return "\(Int(round(value)))°C"
            case .fahrenheit:
                return "\(Int(round(value)))°F"
            case .rpm:
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                let str = formatter.string(from: NSNumber(value: Int(round(value)))) ?? "\(Int(round(value)))"
                return "\(str) rpm"
            case .bytesPerSecond(let standard):
                let bytes = Int64(round(value))
                return (standard == .iec ? Units.formatBytesIEC(bytes) : Units.formatBytesSI(bytes)) + "/s"
            case .watts:
                return String(format: "%.1f W", value)
            }
        }
    }

    public struct ThresholdBand: Sendable {
        public let quietFloor: Double
        public let elevated: Double
        public let warning: Double
        public let spikeDelta: Double
        public let trendDelta: Double
        public let peakMargin: Double

        public init(
            quietFloor: Double = 10.0,
            elevated: Double = 50.0,
            warning: Double = 80.0,
            spikeDelta: Double = 15.0,
            trendDelta: Double = 10.0,
            peakMargin: Double = 10.0
        ) {
            self.quietFloor = quietFloor
            self.elevated = elevated
            self.warning = warning
            self.spikeDelta = spikeDelta
            self.trendDelta = trendDelta
            self.peakMargin = peakMargin
        }

        public static let percentage = ThresholdBand(
            quietFloor: 10.0,
            elevated: 50.0,
            warning: 80.0,
            spikeDelta: 15.0,
            trendDelta: 10.0,
            peakMargin: 10.0
        )

        public static func thermalCelsius() -> ThresholdBand {
            ThresholdBand(
                quietFloor: 45.0,
                elevated: 65.0,
                warning: 85.0,
                spikeDelta: 8.0,
                trendDelta: 5.0,
                peakMargin: 6.0
            )
        }

        public static func thermal(unit: Units.TemperatureUnit) -> ThresholdBand {
            guard unit == .fahrenheit else { return thermalCelsius() }
            return ThresholdBand(
                quietFloor: Units.celsiusToFahrenheit(45.0),
                elevated: Units.celsiusToFahrenheit(65.0),
                warning: Units.celsiusToFahrenheit(85.0),
                spikeDelta: 8.0 * 1.8,
                trendDelta: 5.0 * 1.8,
                peakMargin: 6.0 * 1.8
            )
        }

        public static func throughputBytesPerSec() -> ThresholdBand {
            ThresholdBand(
                quietFloor: 50_000.0,     // 50 KB/s
                elevated: 10_000_000.0,  // 10 MB/s
                warning: 50_000_000.0,   // 50 MB/s
                spikeDelta: 5_000_000.0, // 5 MB/s
                trendDelta: 2_000_000.0, // 2 MB/s
                peakMargin: 5_000_000.0  // 5 MB/s
            )
        }

        public static func fanRPM(minRPM: Double = 1200.0, maxRPM: Double = 6000.0) -> ThresholdBand {
            let span = max(500.0, maxRPM - minRPM)
            return ThresholdBand(
                quietFloor: minRPM + 0.10 * span,
                elevated: minRPM + 0.45 * span,
                warning: minRPM + 0.75 * span,
                spikeDelta: 300.0,
                trendDelta: 200.0,
                peakMargin: 250.0
            )
        }

        public static let powerWatts = ThresholdBand(
            quietFloor: 8.0,
            elevated: 25.0,
            warning: 45.0,
            spikeDelta: 8.0,
            trendDelta: 5.0,
            peakMargin: 6.0
        )
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
        // A spike occurred within the last 30 s that was >= 1.5x previous baseline and >= spikeDelta jump.
        let window30Samples = max(1, Int(30.0 / interval))
        if count > window30Samples {
            let recentWindow = series.suffix(window30Samples)
            let priorWindow = series.prefix(count - window30Samples)
            let priorAvg = priorWindow.reduce(0.0, +) / Double(priorWindow.count)

            if let maxRecent = recentWindow.max(), let maxRecentIdx = series.lastIndex(of: maxRecent) {
                let secondsAgo = Double(count - 1 - maxRecentIdx) * interval
                if maxRecent >= 1.5 * max(priorAvg, 1.0) && (maxRecent - priorAvg) >= thresholds.spikeDelta && secondsAgo <= 30.0 {
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
            if peakVal >= 1.25 * max(current, 1.0) && secondsAgo >= 30.0 && (peakVal - current) >= thresholds.peakMargin {
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
        // |Delta| >= trendDelta and window has >= 60 samples.
        if count >= 60 {
            let avg = series.reduce(0.0, +) / Double(count)
            let diff = current - avg
            if abs(diff) >= thresholds.trendDelta {
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

