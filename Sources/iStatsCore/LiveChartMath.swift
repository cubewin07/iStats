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
}
