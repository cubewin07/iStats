import Foundation

/// Pure utility providing spike-preserving bucket downsampling for scalar telemetry series.
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
}
