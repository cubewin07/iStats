import Foundation

/// A timestamped metric value. A nil value marks a missing reading rather than zero.
public struct HistoryPoint: Sendable, Equatable {
    public let timestamp: Date
    public let value: Double?

    public init(timestamp: Date, value: Double?) {
        self.timestamp = timestamp
        self.value = value
    }
}

/// Prepares a bounded, chronological history for display. Discontinuities are
/// kept separate so a pause or unavailable reading is not drawn as measured data.
public struct HistoryTimeline: Sendable {
    public let points: [HistoryPoint]
    public let segments: [[HistoryPoint]]

    public init(points: [HistoryPoint], capacity: Int = 60, expectedInterval: TimeInterval) {
        let ordered = points.enumerated().sorted {
            $0.element.timestamp == $1.element.timestamp
                ? $0.offset < $1.offset
                : $0.element.timestamp < $1.element.timestamp
        }.map(\.element)
        self.points = Array(ordered.suffix(max(1, capacity)))

        var result: [[HistoryPoint]] = []
        var current: [HistoryPoint] = []
        let gapLimit = max(0.001, expectedInterval) * 2.5
        for point in self.points {
            guard let value = point.value, value.isFinite else {
                if !current.isEmpty { result.append(current); current = [] }
                continue
            }
            if let previous = current.last,
               point.timestamp.timeIntervalSince(previous.timestamp) > gapLimit {
                result.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { result.append(current) }
        self.segments = result
    }

    public var timeRange: ClosedRange<Date>? {
        guard let first = points.first?.timestamp, let last = points.last?.timestamp else { return nil }
        return first...last
    }
}
