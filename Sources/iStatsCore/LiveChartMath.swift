import Foundation

/// Pure mathematical and layout algorithms for the Instrument LiveChart (ADR 0009 / Task 8.4).
public enum LiveChartMath {

    public struct Point2D: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct CubicSegment: Equatable, Sendable {
        public var start: Point2D
        public var control1: Point2D
        public var control2: Point2D
        public var end: Point2D

        public init(start: Point2D, control1: Point2D, control2: Point2D, end: Point2D) {
            self.start = start
            self.control1 = control1
            self.control2 = control2
            self.end = end
        }
    }

    public struct Stats: Equatable, Sendable {
        public let min: Double
        public let avg: Double
        public let max: Double
        public let now: Double

        public init(min: Double, avg: Double, max: Double, now: Double) {
            self.min = min
            self.avg = avg
            self.max = max
            self.now = now
        }
    }

    // MARK: - Monotone Cubic Spline (Fritsch–Carlson)

    /// Computes smooth monotone cubic Hermite segments (Fritsch–Carlson) connecting the given points.
    /// Monotonicity guarantee: For any segment between (x_k, y_k) and (x_{k+1}, y_{k+1}),
    /// the control point y-coordinates are guaranteed to stay bounded between min(y_k, y_{k+1}) and max(y_k, y_{k+1}),
    /// preventing negative dips below zero or unphysical overshoot above maximums.
    public static func smoothSegments(points: [Point2D], tension: Double = 1.0) -> [CubicSegment] {
        let n = points.count
        guard n >= 2 else { return [] }

        if n == 2 {
            let p0 = points[0]
            let p1 = points[1]
            let clampedTension = max(0.0, min(1.0, tension))
            let dx = (p1.x - p0.x) / 3.0 * clampedTension
            let dy = (p1.y - p0.y) / 3.0 * clampedTension
            let c1 = Point2D(x: p0.x + dx, y: p0.y + dy)
            let c2 = Point2D(x: p1.x - dx, y: p1.y - dy)
            return [CubicSegment(start: p0, control1: c1, control2: c2, end: p1)]
        }

        // 1. Compute secants Delta_k = (y_{k+1} - y_k) / (x_{k+1} - x_k)
        var deltas: [Double] = []
        deltas.reserveCapacity(n - 1)
        for i in 0..<(n - 1) {
            let dx = points[i + 1].x - points[i].x
            if abs(dx) < 1e-9 {
                deltas.append(0.0)
            } else {
                deltas.append((points[i + 1].y - points[i].y) / dx)
            }
        }

        // 2. Initial tangents d_k
        var tangents: [Double] = Array(repeating: 0.0, count: n)
        tangents[0] = deltas[0]
        tangents[n - 1] = deltas[n - 2]
        for i in 1..<(n - 1) {
            let h0 = points[i].x - points[i - 1].x
            let h1 = points[i + 1].x - points[i].x
            let totalH = h0 + h1
            if totalH > 1e-9 {
                tangents[i] = (h0 * deltas[i] + h1 * deltas[i - 1]) / totalH
            } else {
                tangents[i] = (deltas[i - 1] + deltas[i]) / 2.0
            }
        }

        // 3. Monotonicity pass (Fritsch–Carlson)
        for i in 0..<(n - 1) {
            let delta = deltas[i]
            if abs(delta) < 1e-9 {
                tangents[i] = 0.0
                tangents[i + 1] = 0.0
            } else {
                let alpha = tangents[i] / delta
                let beta = tangents[i + 1] / delta
                if alpha < 0.0 { tangents[i] = 0.0 }
                if beta < 0.0 { tangents[i + 1] = 0.0 }
                let sumSq = alpha * alpha + beta * beta
                if sumSq > 9.0 {
                    let tau = 3.0 / sqrt(sumSq)
                    tangents[i] = tau * alpha * delta
                    tangents[i + 1] = tau * beta * delta
                }
            }
        }

        // 4. Construct Bezier control points
        let clampedTension = max(0.0, min(1.0, tension))
        var segments: [CubicSegment] = []
        segments.reserveCapacity(n - 1)

        for i in 0..<(n - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let dx = (p1.x - p0.x) / 3.0 * clampedTension

            let c1 = Point2D(x: p0.x + dx, y: p0.y + (tangents[i] * dx))
            let c2 = Point2D(x: p1.x - dx, y: p1.y - (tangents[i + 1] * dx))

            // Extra safety clamp ensuring control point y does not exceed interval bounds
            let minY = min(p0.y, p1.y)
            let maxY = max(p0.y, p1.y)
            let safeC1Y = max(minY, min(maxY, c1.y))
            let safeC2Y = max(minY, min(maxY, c2.y))

            segments.append(
                CubicSegment(
                    start: p0,
                    control1: Point2D(x: c1.x, y: safeC1Y),
                    control2: Point2D(x: c2.x, y: safeC2Y),
                    end: p1
                )
            )
        }

        return segments
    }

    // MARK: - Glide Offset

    /// Computes the normalized fraction (0.0 ... 1.0) for gliding horizontal animation between samples.
    public static func glideOffset(elapsed: Double, interval: Double) -> Double {
        guard interval > 0.0 else { return 0.0 }
        let raw = elapsed / interval
        return min(1.0, max(0.0, raw))
    }

    // MARK: - Nice Axis Ticks

    /// Generates clean 1-2-5 step tick values up to max.
    public static func niceTicks(max: Double, count: Int = 4) -> [Double] {
        guard max > 0, count > 0 else { return [0.0] }
        let roughStep = max / Double(count)
        let exponent = floor(log10(roughStep))
        let magnitude = pow(10.0, exponent)
        let fraction = roughStep / magnitude

        let niceFraction: Double
        if fraction <= 1.5 {
            niceFraction = 1.0
        } else if fraction <= 3.0 {
            niceFraction = 2.0
        } else if fraction <= 7.0 {
            niceFraction = 5.0
        } else {
            niceFraction = 10.0
        }

        let step = niceFraction * magnitude
        var ticks: [Double] = []
        var current = 0.0
        while current <= max + (step * 0.001) {
            ticks.append(current)
            current += step
        }
        if ticks.isEmpty { ticks = [0.0, max] }
        return ticks
    }

    // MARK: - Peak & Stats

    /// Returns the index of the highest sample in the series (first occurrence), or nil if empty.
    public static func peakIndex(values: [Double]) -> Int? {
        guard !values.isEmpty else { return nil }
        var maxIdx = 0
        var maxVal = values[0]
        for (idx, val) in values.enumerated() {
            if val > maxVal {
                maxVal = val
                maxIdx = idx
            }
        }
        return maxIdx
    }

    /// Computes summary statistics (Min, Avg, Max, Now) across a series.
    public static func computeStats(for values: [Double]) -> Stats? {
        guard let first = values.first, !values.isEmpty else { return nil }
        var minVal = first
        var maxVal = first
        var sum = 0.0
        for v in values {
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
            sum += v
        }
        let avgVal = sum / Double(values.count)
        let nowVal = values.last ?? first
        return Stats(min: minVal, avg: avgVal, max: maxVal, now: nowVal)
    }

    /// Resolves the nearest sample index from a continuous horizontal hover position.
    public static func hoverIndex(for xPosition: Double, totalWidth: Double, count: Int) -> Int? {
        guard count > 0, totalWidth > 0 else { return nil }
        let fraction = max(0.0, min(1.0, xPosition / totalWidth))
        let index = Int(round(fraction * Double(count - 1)))
        return max(0, min(count - 1, index))
    }

    /// Computes an auto-scaling upper ceiling boundary with decay floor.
    public static func computeMaxBound(values: [Double], fixedMax: Double? = nil, floor: Double = 1.0) -> Double {
        if let fm = fixedMax, fm > 0 { return fm }
        let observed = values.max() ?? 0.0
        return max(observed * 1.15, floor)
    }

    /// Formats relative time elapsed from sample index and interval.
    public static func formatRelativeTime(secondsAgo: Double) -> String {
        let sec = max(0, Int(round(secondsAgo)))
        if sec < 60 {
            return "\(sec)s ago"
        } else if sec < 3600 {
            let mins = sec / 60
            let rem = sec % 60
            return rem > 0 ? "\(mins)m \(rem)s ago" : "\(mins)m ago"
        } else {
            return "\(sec / 3600)h ago"
        }
    }
}

/// Backward compatibility alias for folded TrendChartMath
public typealias TrendChartMath = LiveChartMath

// MARK: - Time-Domain Chart Types (ADR 0010 / Task 8.5.1)

/// A timestamped scalar sample in wall-clock seconds (`TimeInterval` since 1970).
public struct ChartPoint: Equatable, Sendable, Codable {
    public let timestamp: TimeInterval
    public let value: Double

    public init(timestamp: TimeInterval, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }

    public init(scalarPoint: ScalarPoint) {
        self.timestamp = scalarPoint.timestamp.timeIntervalSince1970
        self.value = scalarPoint.value
    }
}

/// A timestamped dual-channel sample for stacked or mirrored charts.
public struct DualChartPoint: Equatable, Sendable, Codable {
    public let timestamp: TimeInterval
    public let primary: Double
    public let secondary: Double

    public init(timestamp: TimeInterval, primary: Double, secondary: Double) {
        self.timestamp = timestamp
        self.primary = primary
        self.secondary = secondary
    }
}

/// Pure time-domain right-edge cursor with one-sample delay, monotonic advance,
/// sleep-gap snap, and freeze-in-place scrub catch-up (ADR 0010 / Task 8.5.1).
public struct ChartTimeline: Equatable, Sendable {
    public private(set) var edge: TimeInterval
    public private(set) var frozenEdge: TimeInterval?
    public let sampleInterval: TimeInterval

    private var hasInitialEdge: Bool
    private var catchUpStartEdge: TimeInterval?
    private var catchUpElapsed: TimeInterval?

    /// Ease-out catch-up duration after releasing a hover scrub.
    public static let scrubCatchUpDuration: TimeInterval = 0.25

    public init(
        edge: TimeInterval? = nil,
        frozenEdge: TimeInterval? = nil,
        sampleInterval: TimeInterval = 1.0
    ) {
        self.sampleInterval = max(1e-3, sampleInterval)
        if let edge {
            self.edge = edge
            self.hasInitialEdge = true
        } else {
            self.edge = 0.0
            self.hasInitialEdge = false
        }
        self.frozenEdge = frozenEdge
        self.catchUpStartEdge = nil
        self.catchUpElapsed = nil
    }

    /// Computes the delayed right-edge target trailing the latest sample by one interval.
    public func targetEdge(now: TimeInterval, latestTimestamp: TimeInterval) -> TimeInterval {
        min(now - sampleInterval, latestTimestamp)
    }

    /// Advances the timeline cursor by `dt` seconds.
    /// - Freezes `edge` while `isScrubbing` is true.
    /// - Snaps immediately if `abs(targetEdge - edge) > 3.0 * sampleInterval` (e.g., wake from sleep).
    /// - Otherwise advances monotonically at `1.0 s/s` (with a `250 ms` ease-out catch-up after scrub release).
    @discardableResult
    public mutating func step(
        now: TimeInterval,
        latestTimestamp: TimeInterval,
        dt: TimeInterval,
        isScrubbing: Bool
    ) -> TimeInterval {
        let target = targetEdge(now: now, latestTimestamp: latestTimestamp)

        if !hasInitialEdge {
            edge = target
            hasInitialEdge = true
            if isScrubbing {
                frozenEdge = edge
            }
            return edge
        }

        if isScrubbing {
            if frozenEdge == nil {
                frozenEdge = edge
            }
            catchUpStartEdge = nil
            catchUpElapsed = nil
            edge = frozenEdge ?? edge
            return edge
        }

        let wasScrubbing = frozenEdge != nil
        let releasedFrom = frozenEdge
        if wasScrubbing {
            frozenEdge = nil
        }

        if abs(target - edge) > 3.0 * sampleInterval {
            edge = target
            catchUpStartEdge = nil
            catchUpElapsed = nil
            return edge
        }

        if wasScrubbing, let startEdge = releasedFrom, target > startEdge {
            catchUpStartEdge = startEdge
            catchUpElapsed = 0.0
        }

        let clampedDt = max(0.0, dt)

        if let startEdge = catchUpStartEdge, let elapsed = catchUpElapsed {
            let newElapsed = elapsed + clampedDt
            let progress = min(1.0, newElapsed / Self.scrubCatchUpDuration)
            let eased = 1.0 - pow(1.0 - progress, 3.0)
            let candidate = startEdge + (target - startEdge) * eased
            edge = max(edge, min(target, candidate))

            if progress >= 1.0 || edge >= target {
                catchUpStartEdge = nil
                catchUpElapsed = nil
            } else {
                catchUpElapsed = newElapsed
            }
            return edge
        }

        if target > edge {
            edge = min(target, edge + clampedDt)
        }
        return edge
    }

    /// Maps a sample timestamp to horizontal screen coordinate within `[0, width]`.
    public func xPosition(for timestamp: TimeInterval, width: Double, window: TimeInterval) -> Double {
        Self.xPosition(for: timestamp, edge: edge, width: width, window: window)
    }

    /// Pure coordinate projection for a given right-edge timestamp.
    public static func xPosition(
        for timestamp: TimeInterval,
        edge: TimeInterval,
        width: Double,
        window: TimeInterval
    ) -> Double {
        guard window > 0.0 else { return width }
        return width * (1.0 - (edge - timestamp) / window)
    }

    /// Evaluates the spline-interpolated value at `edge` so the live head bead
    /// sits directly on the Fritsch–Carlson curve at `x = plotWidth`.
    public func valueAtEdge(points: [ChartPoint]) -> Double? {
        value(at: edge, points: points)
    }

    /// Evaluates the Fritsch–Carlson monotone cubic spline at an arbitrary `timestamp`.
    public func value(at timestamp: TimeInterval, points: [ChartPoint]) -> Double? {
        Self.interpolateValue(at: timestamp, points: points)
    }

    /// Evaluates the Fritsch–Carlson monotone cubic spline at `timestamp` across `points`.
    public static func interpolateValue(at timestamp: TimeInterval, points: [ChartPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        let ordered: [ChartPoint]
        if zip(points, points.dropFirst()).contains(where: { $0.timestamp > $1.timestamp }) {
            ordered = points.sorted { $0.timestamp < $1.timestamp }
        } else {
            ordered = points
        }

        guard let first = ordered.first, let last = ordered.last else { return nil }
        if ordered.count == 1 || timestamp <= first.timestamp {
            return first.value
        }
        if timestamp >= last.timestamp {
            return last.value
        }

        let pts2D = ordered.map { LiveChartMath.Point2D(x: $0.timestamp, y: $0.value) }
        let segments = LiveChartMath.smoothSegments(points: pts2D, tension: 1.0)
        for seg in segments {
            if timestamp >= seg.start.x && timestamp <= seg.end.x {
                let dx = seg.end.x - seg.start.x
                guard dx > 1e-9 else { return seg.end.y }
                // Because smoothSegments(tension: 1.0) places control1.x at 1/3 and control2.x at 2/3,
                // B_x(u) is strictly linear in u, so u = (timestamp - start.x) / dx is exact.
                let u = max(0.0, min(1.0, (timestamp - seg.start.x) / dx))
                let omt = 1.0 - u
                let omt2 = omt * omt
                let u2 = u * u
                return (omt2 * omt * seg.start.y)
                    + (3.0 * omt2 * u * seg.control1.y)
                    + (3.0 * omt * u2 * seg.control2.y)
                    + (u2 * u * seg.end.y)
            }
        }
        return last.value
    }
}

// MARK: - Adaptive Nice-Number Y-Axis Scale & Domain Floors (ADR 0010 / Task 8.5.1)

/// Pure nice-number Y-axis scale utilities and per-category domain floors.
public enum ChartScale {
    private static let niceLadder: [Double] = [1.0, 2.0, 2.5, 5.0]

    /// Computes a clean 3-interval ceiling and ticks using `{1, 2, 2.5, 5} × 10^k`.
    public static func niceCeiling(
        for maxVal: Double,
        floorVal: Double = 0.0,
        minSpan: Double = 1.0
    ) -> (floor: Double, ceiling: Double, ticks: [Double]) {
        let safeFloor = floorVal.isFinite ? floorVal : 0.0
        let safeMax = maxVal.isFinite ? maxVal : safeFloor
        let safeMinSpan = (minSpan.isFinite && minSpan > 0.0) ? minSpan : 1.0

        let rawSpan = max(safeMinSpan, (safeMax - safeFloor) * 1.10)
        let roughStep = rawSpan / 3.0
        let exponent = floor(log10(roughStep))
        let magnitude = pow(10.0, exponent)
        let fraction = roughStep / magnitude

        let niceFraction = niceLadder.first(where: { fraction <= $0 + 1e-9 }) ?? 10.0
        let step = niceFraction * magnitude
        let ceiling = safeFloor + 3.0 * step
        let ticks = [
            safeFloor,
            safeFloor + step,
            safeFloor + 2.0 * step,
            ceiling
        ]
        return (floor: safeFloor, ceiling: ceiling, ticks: ticks)
    }

    /// Computes the canonical Y-axis floor for a metric category.
    public static func domainFloor(
        for category: MetricCategory,
        visibleMin: Double,
        fixedFloor: Double? = nil
    ) -> Double {
        if let fixedFloor, fixedFloor.isFinite {
            return fixedFloor
        }
        switch category {
        case .thermal:
            guard visibleMin.isFinite else { return 20.0 }
            return max(20.0, floor((visibleMin - 5.0) / 10.0) * 10.0)
        case .fan:
            return 0.0
        case .cpu, .memory, .gpu, .network, .disk, .power:
            return 0.0
        }
    }
}

/// Asymmetric Y-axis scale state with immediate upward spring and 3 s hold hysteresis
/// before contracting downward (ADR 0010 / Task 8.5.1).
public struct ChartScaleState: Equatable, Sendable {
    public private(set) var displayedFloor: Double
    public private(set) var displayedCeiling: Double
    public private(set) var targetFloor: Double
    public private(set) var targetCeiling: Double
    public private(set) var belowThresholdDuration: TimeInterval
    public private(set) var isContracting: Bool

    public let holdDuration: TimeInterval
    public let contractionThresholdRatio: Double
    public let springResponse: TimeInterval
    public let contractionDuration: TimeInterval

    private var hasSeeded: Bool
    private var ceilingVelocity: Double
    private var floorVelocity: Double
    private var contractionStartCeiling: Double
    private var contractionElapsed: TimeInterval

    public init(
        initialFloor: Double = 0.0,
        initialCeiling: Double? = nil,
        holdDuration: TimeInterval = 3.0,
        contractionThresholdRatio: Double = 0.70,
        springResponse: TimeInterval = 0.35,
        contractionDuration: TimeInterval = 0.60
    ) {
        self.displayedFloor = initialFloor
        self.targetFloor = initialFloor
        if let initialCeiling {
            self.displayedCeiling = initialCeiling
            self.targetCeiling = initialCeiling
            self.hasSeeded = true
        } else {
            self.displayedCeiling = initialFloor + 1.0
            self.targetCeiling = initialFloor + 1.0
            self.hasSeeded = false
        }
        self.belowThresholdDuration = 0.0
        self.isContracting = false
        self.holdDuration = max(0.0, holdDuration)
        self.contractionThresholdRatio = contractionThresholdRatio
        self.springResponse = max(1e-3, springResponse)
        self.contractionDuration = max(1e-3, contractionDuration)
        self.ceilingVelocity = 0.0
        self.floorVelocity = 0.0
        self.contractionStartCeiling = self.displayedCeiling
        self.contractionElapsed = 0.0
    }

    /// Advances `displayedCeiling` and `displayedFloor` toward the given targets by `dt`.
    public mutating func step(
        targetCeiling newCeiling: Double,
        targetFloor newFloor: Double = 0.0,
        dt: TimeInterval
    ) {
        let safeFloor = newFloor.isFinite ? newFloor : displayedFloor
        let safeCeiling = max(safeFloor + 1e-6, newCeiling.isFinite ? newCeiling : displayedCeiling)

        targetFloor = safeFloor
        targetCeiling = safeCeiling

        if !hasSeeded {
            displayedFloor = safeFloor
            displayedCeiling = safeCeiling
            hasSeeded = true
            belowThresholdDuration = 0.0
            isContracting = false
            ceilingVelocity = 0.0
            floorVelocity = 0.0
            return
        }

        let clampedDt = max(0.0, dt)
        guard clampedDt > 0.0 else { return }

        // Smoothly adjust domain floor via critically damped spring when needed (e.g., Thermal).
        if abs(targetFloor - displayedFloor) > 1e-6 || abs(floorVelocity) > 1e-4 {
            Self.stepCriticallyDampedSpring(
                value: &displayedFloor,
                velocity: &floorVelocity,
                target: targetFloor,
                response: springResponse,
                dt: clampedDt,
                clampOvershoot: false
            )
        } else {
            displayedFloor = targetFloor
            floorVelocity = 0.0
        }

        if targetCeiling > displayedCeiling {
            // Immediate upward spring expansion.
            belowThresholdDuration = 0.0
            isContracting = false
            contractionElapsed = 0.0
            Self.stepCriticallyDampedSpring(
                value: &displayedCeiling,
                velocity: &ceilingVelocity,
                target: targetCeiling,
                response: springResponse,
                dt: clampedDt,
                clampOvershoot: true
            )
            return
        }

        ceilingVelocity = 0.0

        if isContracting {
            contractionElapsed += clampedDt
            let progress = min(1.0, contractionElapsed / contractionDuration)
            let eased = 1.0 - pow(1.0 - progress, 3.0)
            let candidate = contractionStartCeiling + (targetCeiling - contractionStartCeiling) * eased
            displayedCeiling = max(targetCeiling, min(displayedCeiling, candidate))

            if progress >= 1.0 || abs(displayedCeiling - targetCeiling) <= 1e-6 {
                displayedCeiling = targetCeiling
                isContracting = false
                belowThresholdDuration = 0.0
                contractionElapsed = 0.0
            }
            return
        }

        if targetCeiling < displayedCeiling * contractionThresholdRatio {
            belowThresholdDuration += clampedDt
            if belowThresholdDuration >= holdDuration {
                isContracting = true
                contractionStartCeiling = displayedCeiling
                contractionElapsed = belowThresholdDuration - holdDuration
                let progress = min(1.0, contractionElapsed / contractionDuration)
                let eased = 1.0 - pow(1.0 - progress, 3.0)
                displayedCeiling = contractionStartCeiling + (targetCeiling - contractionStartCeiling) * eased
                if progress >= 1.0 {
                    displayedCeiling = targetCeiling
                    isContracting = false
                    belowThresholdDuration = 0.0
                    contractionElapsed = 0.0
                }
            }
        } else {
            belowThresholdDuration = 0.0
        }
    }

    /// Convenience helper computing category-appropriate target bounds and stepping the scale state.
    @discardableResult
    public mutating func update(
        visibleMax: Double,
        visibleMin: Double = 0.0,
        category: MetricCategory,
        fixedFloor: Double? = nil,
        fixedCeiling: Double? = nil,
        minSpan: Double = 1.0,
        dt: TimeInterval
    ) -> (floor: Double, ceiling: Double, ticks: [Double]) {
        let computedFloor = ChartScale.domainFloor(
            for: category,
            visibleMin: visibleMin,
            fixedFloor: fixedFloor
        )
        let computedCeiling: Double
        if let fixedCeiling, fixedCeiling.isFinite {
            computedCeiling = max(computedFloor + max(1e-6, minSpan), fixedCeiling)
        } else if category == .cpu || category == .memory || category == .gpu {
            computedCeiling = max(computedFloor + 1e-6, 100.0)
        } else {
            computedCeiling = ChartScale.niceCeiling(
                for: visibleMax,
                floorVal: computedFloor,
                minSpan: minSpan
            ).ceiling
        }

        step(targetCeiling: computedCeiling, targetFloor: computedFloor, dt: dt)
        let stepSize = (displayedCeiling - displayedFloor) / 3.0
        let ticks = [
            displayedFloor,
            displayedFloor + stepSize,
            displayedFloor + 2.0 * stepSize,
            displayedCeiling
        ]
        return (floor: displayedFloor, ceiling: displayedCeiling, ticks: ticks)
    }

    private static func stepCriticallyDampedSpring(
        value: inout Double,
        velocity: inout Double,
        target: Double,
        response: TimeInterval,
        dt: TimeInterval,
        clampOvershoot: Bool
    ) {
        let omega = 2.0 * .pi / max(1e-4, response)
        let y0 = value - target
        let v0 = velocity
        let expTerm = exp(-omega * dt)
        let c = v0 + omega * y0
        let newY = expTerm * (y0 + c * dt)
        let newV = expTerm * (v0 - omega * c * dt)

        if clampOvershoot && y0 <= 0.0 && newY > 0.0 {
            value = target
            velocity = 0.0
            return
        }

        value = target + newY
        velocity = newV

        if abs(newY) < 1e-6 * max(1.0, abs(target)) && abs(newV) < 1e-4 {
            value = target
            velocity = 0.0
        }
    }
}
