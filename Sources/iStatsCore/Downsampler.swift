import Foundation

/// A time-aligned envelope bucket storing min, max, and mean telemetry over a fixed wall-clock epoch.
public struct BucketPoint: Equatable, Sendable, Codable {
    public let timestamp: TimeInterval
    public let min: Double
    public let max: Double
    public let mean: Double

    public init(timestamp: TimeInterval, min: Double, max: Double, mean: Double) {
        self.timestamp = timestamp
        self.min = min
        self.max = max
        self.mean = mean
    }
}

/// Pure utility providing spike-preserving and time-aligned envelope downsampling for scalar telemetry series.
public enum Downsampler {
    /// Downsamples a slice of scalar values into at most `targetCount` buckets,
    /// selecting the peak value within each bucket to preserve transient spikes.
    public static func downsampleSpikePreserving(
        _ values: [Double],
        targetCount: Int = 120
    ) -> [Double] {
        guard values.count > targetCount, targetCount > 0 else {
            return values
        }

        var result: [Double] = []
        result.reserveCapacity(targetCount)

        let bucketSize = Double(values.count) / Double(targetCount)
        for i in 0..<targetCount {
            let start = Int(Double(i) * bucketSize)
            let end = min(Int(Double(i + 1) * bucketSize), values.count)
            guard start < end else { continue }

            let bucket = values[start..<end]
            if let peak = bucket.max() {
                result.append(peak)
            }
        }
        return result
    }

    /// Downsamples timestamped points into at most `targetCount` buckets,
    /// preserving the point with the maximum value in each bucket.
    public static func downsampleSpikePreserving(
        _ points: [ScalarPoint],
        targetCount: Int = 120
    ) -> [ScalarPoint] {
        guard points.count > targetCount, targetCount > 0 else {
            return points
        }

        var result: [ScalarPoint] = []
        result.reserveCapacity(targetCount)

        let bucketSize = Double(points.count) / Double(targetCount)
        for i in 0..<targetCount {
            let start = Int(Double(i) * bucketSize)
            let end = min(Int(Double(i + 1) * bucketSize), points.count)
            guard start < end else { continue }

            let bucket = points[start..<end]
            if let peak = bucket.max(by: { $0.value < $1.value }) {
                result.append(peak)
            }
        }
        return result
    }

    /// Groups timestamped scalar points into immutable wall-clock epoch buckets
    /// (`bucketID = Int(floor(timestamp / bucketWidth))`) over `windowDuration`.
    ///
    /// Historical buckets prior to the active epoch bucket never shift or mutate as
    /// new samples arrive, eliminating curve "boiling" on 5m and 15m charts (ADR 0010 / A6).
    public static func alignedBuckets(
        _ points: [ScalarPoint],
        bucketWidth: TimeInterval,
        windowDuration: TimeInterval
    ) -> [BucketPoint] {
        guard bucketWidth.isFinite, bucketWidth > 0.0,
              windowDuration.isFinite, windowDuration > 0.0 else {
            return []
        }

        let validPoints = points.filter { $0.value.isFinite }
        guard let latestTimestamp = validPoints.map({ $0.timestamp.timeIntervalSince1970 }).max() else {
            return []
        }

        let cutoff = latestTimestamp - windowDuration

        struct Accumulator {
            var minVal: Double
            var maxVal: Double
            var sum: Double
            var count: Int
        }

        var buckets: [Int: Accumulator] = [:]
        for point in validPoints {
            let t = point.timestamp.timeIntervalSince1970
            let bucketID = Int(floor(t / bucketWidth))
            let bucketEnd = (Double(bucketID) + 1.0) * bucketWidth
            guard bucketEnd > cutoff else { continue }

            if var existing = buckets[bucketID] {
                if point.value < existing.minVal { existing.minVal = point.value }
                if point.value > existing.maxVal { existing.maxVal = point.value }
                existing.sum += point.value
                existing.count += 1
                buckets[bucketID] = existing
            } else {
                buckets[bucketID] = Accumulator(
                    minVal: point.value,
                    maxVal: point.value,
                    sum: point.value,
                    count: 1
                )
            }
        }

        return buckets.keys.sorted().compactMap { bucketID in
            guard let acc = buckets[bucketID], acc.count > 0 else { return nil }
            let centerTimestamp = (Double(bucketID) + 0.5) * bucketWidth
            return BucketPoint(
                timestamp: centerTimestamp,
                min: acc.minVal,
                max: acc.maxVal,
                mean: acc.sum / Double(acc.count)
            )
        }
    }
}

