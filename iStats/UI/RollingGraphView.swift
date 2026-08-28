import SwiftUI

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

