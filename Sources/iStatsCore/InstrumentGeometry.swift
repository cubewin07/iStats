import Foundation

/// Pure geometry and layout algorithms for the Instrument Kit (ADR 0009 / Task 8.5).
public enum SegmentLayout {

    /// Computes pixel widths for multi-segment bars (e.g. SplitCapsule), ensuring non-zero values
    /// are visibly represented with `minVisible`, while the total width including gaps fits within `totalWidth`.
    public static func widths(
        values: [Double],
        totalWidth: Double,
        minVisible: Double = 3.0,
        gap: Double = 1.0
    ) -> [Double] {
        guard !values.isEmpty, totalWidth > 0 else { return [] }
        let count = values.count
        let totalGaps = Double(max(0, count - 1)) * gap
        let availableWidth = max(0.0, totalWidth - totalGaps)
        guard availableWidth > 0 else { return Array(repeating: 0.0, count: count) }

        let sumValues = values.reduce(0.0) { $0 + max(0.0, $1) }
        guard sumValues > 0 else {
            return Array(repeating: 0.0, count: count)
        }

        // Identify indices with non-zero values
        let nonZeroIndices = values.indices.filter { values[$0] > 0 }
        let totalMinNeeded = Double(nonZeroIndices.count) * minVisible

        if totalMinNeeded >= availableWidth {
            // Allocate proportionally within availableWidth
            return values.map { max(0.0, $0) / sumValues * availableWidth }
        }

        // Initial proportional distribution
        var allocated = values.map { max(0.0, $0) / sumValues * availableWidth }

        // Guarantee minimum visible width for non-zero elements
        var deficits = 0.0
        var flexibleIndices: [Int] = []
        var flexibleSum = 0.0

        for i in nonZeroIndices {
            if allocated[i] < minVisible {
                deficits += (minVisible - allocated[i])
                allocated[i] = minVisible
            } else {
                flexibleIndices.append(i)
                flexibleSum += allocated[i]
            }
        }

        // Reclaim deficit from segments larger than minVisible
        if deficits > 0 && flexibleSum > 0 {
            for i in flexibleIndices {
                let share = (allocated[i] / flexibleSum) * deficits
                allocated[i] = max(minVisible, allocated[i] - share)
            }
        }

        // Final normalization to ensure sum + gaps <= totalWidth
        let currentSum = allocated.reduce(0.0, +)
        if currentSum > 0 && abs(currentSum - availableWidth) > 1e-4 {
            let scale = availableWidth / currentSum
            allocated = allocated.map { $0 * scale }
        }

        return allocated
    }
}

public enum GaugeMath {

    /// Computes the rotational angle in degrees for an arc gauge given a value, range, sweep angle, and start angle.
    public static func angle(
        value: Double,
        range: ClosedRange<Double>,
        sweep: Double = 200.0,
        startAngle: Double = -100.0
    ) -> Double {
        guard range.upperBound > range.lowerBound else { return startAngle }
        let clamped = max(range.lowerBound, min(range.upperBound, value))
        let fraction = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return startAngle + fraction * sweep
    }
}
