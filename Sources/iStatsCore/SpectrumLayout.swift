import Foundation

/// Input marker representing a temperature value to be placed on a spectrum bar.
public struct SpectrumMarker: Sendable, Equatable, Identifiable {
    public let id: String
    public let value: Double
    public let label: String

    public init(id: String = UUID().uuidString, value: Double, label: String = "") {
        self.id = id
        self.value = value
        self.label = label
    }
}

/// Placed marker with layout coordinates, resolved collision tier, and clamping.
public struct PlacedMarker: Sendable, Equatable, Identifiable {
    public let id: String
    public let value: Double
    public let label: String
    public let x: Double
    public let tier: Int

    public init(id: String, value: Double, label: String, x: Double, tier: Int = 0) {
        self.id = id
        self.value = value
        self.label = label
        self.x = x
        self.tier = tier
    }
}

/// Pure collision layout engine for placing markers along a spectrum bar (ADR 0009 / Task 8.8d).
public enum SpectrumLayout {
    public static let defaultMinCelsius: Double = 30.0
    public static let defaultMaxCelsius: Double = 110.0

    /// Places markers across `width` resolving collisions via vertical tiers (tested: no overlaps, preserves order, handles identical temperatures).
    public static func place(
        markers: [SpectrumMarker],
        width: Double,
        minSpacing: Double = 14.0,
        minValue: Double = defaultMinCelsius,
        maxValue: Double = defaultMaxCelsius
    ) -> [PlacedMarker] {
        guard width > 0, !markers.isEmpty else { return [] }
        let range = max(1.0, maxValue - minValue)

        // Preserve input order for ties, but sort primarily by value ascending
        let indexed = markers.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { a, b in
            if a.1.value == b.1.value {
                return a.0 < b.0
            }
            return a.1.value < b.1.value
        }

        var placed: [PlacedMarker] = []
        var tierLastX: [Int: Double] = [:]

        for (_, marker) in sorted {
            let normalized = max(0.0, min(1.0, (marker.value - minValue) / range))
            let rawX = normalized * width

            var chosenTier = 0
            while true {
                if let lastX = tierLastX[chosenTier] {
                    if abs(rawX - lastX) < minSpacing {
                        chosenTier += 1
                        continue
                    }
                }
                break
            }

            tierLastX[chosenTier] = rawX
            placed.append(PlacedMarker(
                id: marker.id,
                value: marker.value,
                label: marker.label,
                x: rawX,
                tier: chosenTier
            ))
        }

        return placed
    }

    /// Alternate non-overlapping 1D horizontal placement that shifts positions along the x-axis.
    public static func placeHorizontal(
        markers: [SpectrumMarker],
        width: Double,
        minSpacing: Double = 14.0,
        minValue: Double = defaultMinCelsius,
        maxValue: Double = defaultMaxCelsius
    ) -> [PlacedMarker] {
        guard width > 0, !markers.isEmpty else { return [] }
        let range = max(1.0, maxValue - minValue)

        let indexed = markers.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { a, b in
            if a.1.value == b.1.value {
                return a.0 < b.0
            }
            return a.1.value < b.1.value
        }

        var xs: [Double] = sorted.map { _, marker in
            let norm = max(0.0, min(1.0, (marker.value - minValue) / range))
            return norm * width
        }

        // Left-to-right push
        for i in 1..<xs.count {
            if xs[i] < xs[i - 1] + minSpacing {
                xs[i] = xs[i - 1] + minSpacing
            }
        }

        // Right-to-left adjustment if overflowing width
        if let last = xs.last, last > width {
            let overflow = last - width
            for i in (0..<xs.count).reversed() {
                xs[i] = max(0.0, xs[i] - overflow)
            }
            for i in 1..<xs.count {
                if xs[i] < xs[i - 1] + minSpacing {
                    xs[i] = min(width, xs[i - 1] + minSpacing)
                }
            }
        }

        return sorted.enumerated().map { i, item in
            PlacedMarker(
                id: item.1.id,
                value: item.1.value,
                label: item.1.label,
                x: xs[i],
                tier: 0
            )
        }
    }
}

