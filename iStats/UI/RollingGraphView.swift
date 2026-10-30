import SwiftUI
import iStatsCore

/// A high-performance, reusable SwiftUI rolling history line and area graph view
/// (Requirement 10.2).
public struct RollingGraphView: View {
    public let values: [Double]
    public let minValue: Double
    public let maxValue: Double
    public let tintColor: Color
    public let capacity: Int
    public let height: CGFloat
    public let showGrid: Bool

    public init(
        values: [Double],
        minValue: Double = 0.0,
        maxValue: Double = 100.0,
        tintColor: Color = .blue,
        capacity: Int = 60,
        height: CGFloat = 44,
        showGrid: Bool = true
    ) {
        self.values = values
        self.minValue = minValue
        self.maxValue = max(maxValue, minValue + 0.001)
        self.tintColor = tintColor
        self.capacity = max(capacity, 2)
        self.height = height
        self.showGrid = showGrid
    }

    public var body: some View {
        ZStack {
            // Background container with dark glass styling
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                )

            if showGrid {
                gridLines
            }

            // Graph Path & Gradient Fill
            GeometryReader { geometry in
                let width = geometry.size.width
                let h = geometry.size.height
                let points = calculatePoints(width: width, height: h)

                if points.count >= 2 {
                    // Filled Area with glowing vertical gradient
                    fillPath(points: points, height: h)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tintColor.opacity(0.38),
                                    tintColor.opacity(0.12),
                                    tintColor.opacity(0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Line Stroke
                    strokePath(points: points)
                        .stroke(
                            LinearGradient(
                                colors: [tintColor.opacity(0.85), tintColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )

                    // Latest Value Dot & Glow Ring
                    if let last = points.last {
                        ZStack {
                            Circle()
                                .stroke(tintColor.opacity(0.4), lineWidth: 2)
                                .frame(width: 7, height: 7)
                            Circle()
                                .fill(tintColor)
                                .frame(width: 3.5, height: 3.5)
                        }
                        .position(last)
                    }
                } else {
                    // Baseline placeholder
                    Path { path in
                        path.move(to: CGPoint(x: 4, y: h - 3))
                        path.addLine(to: CGPoint(x: width - 4, y: h - 3))
                    }
                    .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .padding(3)
        }
        .frame(height: height)
        .clipped()
    }

    // MARK: - Grid Lines

    private var gridLines: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.06)
            Spacer()
            Divider().opacity(0.08)
            Spacer()
            Divider().opacity(0.06)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Point Math

    public func calculatePoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !values.isEmpty, width > 0, height > 0 else { return [] }

        let count = values.count
        let stepX = width / CGFloat(max(capacity - 1, 1))
        let startX = width - (CGFloat(count - 1) * stepX)
        let range = maxValue - minValue

        var points: [CGPoint] = []
        points.reserveCapacity(count)

        for (index, val) in values.enumerated() {
            let clamped = min(max(val, minValue), maxValue)
            let normalized = CGFloat((clamped - minValue) / range)
            let x = startX + CGFloat(index) * stepX
            let y = height - (normalized * (height - 4)) - 2
            points.append(CGPoint(x: x, y: y))
        }

        return points
    }

    private func strokePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for pt in points.dropFirst() {
            path.addLine(to: pt)
        }
        return path
    }

    private func fillPath(points: [CGPoint], height: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }

        path.move(to: CGPoint(x: first.x, y: height))
        path.addLine(to: first)

        for pt in points.dropFirst() {
            path.addLine(to: pt)
        }

        path.addLine(to: CGPoint(x: last.x, y: height))
        path.closeSubpath()
        return path
    }
}


/// Timestamp-based chart for diagnostic popovers. Missing samples and long
/// sampling gaps remain disconnected rather than being interpolated.
public struct TimestampedHistoryGraph: View {
    public let timeline: HistoryTimeline
    public let minValue: Double
    public let maxValue: Double
    public let tintColor: Color
    public let height: CGFloat

    public init(timeline: HistoryTimeline, minValue: Double = 0, maxValue: Double,
                tintColor: Color = .blue, height: CGFloat = 56) {
        self.timeline = timeline
        self.minValue = minValue
        self.maxValue = max(maxValue, minValue + 0.001)
        self.tintColor = tintColor
        self.height = height
    }

    public func position(for point: HistoryPoint, width: CGFloat, height: CGFloat) -> CGPoint? {
        guard let range = timeline.timeRange, let value = point.value, value.isFinite,
              width > 0, height > 0 else { return nil }
        let duration = range.upperBound.timeIntervalSince(range.lowerBound)
        let x = duration > 0 ? point.timestamp.timeIntervalSince(range.lowerBound) / duration : 1
        let normalized = (min(max(value, minValue), maxValue) - minValue) / (maxValue - minValue)
        return CGPoint(x: CGFloat(x) * width, y: height - CGFloat(normalized) * max(height - 4, 0) - 2)
    }

    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    Path { path in
                        for segment in timeline.segments {
                            let points = segment.compactMap { position(for: $0, width: geometry.size.width, height: geometry.size.height) }
                            guard let first = points.first else { continue }
                            path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                        }
                    }
                    .stroke(tintColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    ForEach(Array(timeline.segments.enumerated()), id: \.offset) { _, segment in
                        if segment.count == 1, let point = segment.first,
                           let position = position(for: point, width: geometry.size.width, height: geometry.size.height) {
                            Circle().fill(tintColor).frame(width: 4, height: 4).position(position)
                        }
                    }
                    if timeline.segments.isEmpty {
                        Text("No history available")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: height)
            .clipped()
            if let range = timeline.timeRange {
                HStack {
                    Text(range.lowerBound, style: .time)
                    Spacer()
                    Text(range.upperBound, style: .time)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("History chart")
        .accessibilityValue("\(timeline.segments.reduce(0) { $0 + $1.count }) recorded samples")
    }
}
