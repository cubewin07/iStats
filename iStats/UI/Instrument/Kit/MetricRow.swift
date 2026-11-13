import SwiftUI
import iStatsCore

/// Standard metric key-value row with optional micro-sparkline, status indicator, and bottom hairline (ADR 0009 / Task 8.5.7 Kit v2).
/// Height: 26 pt. Hover highlight and `doc.on.doc` copy affordance appear only when `isCopyable == true` (fixes B11).
public struct MetricRow: View {
    public let label: String
    public let valueText: String
    public var valueDouble: Double?
    public var unit: String?
    public var sparklineHistory: [Double]?
    public var sparklineColor: Color?
    public var statusLevel: StatusLevel?
    public var isCopyable: Bool
    public var showHairline: Bool

    @State private var isHovered: Bool = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.motionPolicy) private var motionPolicy

    public init(
        label: String,
        valueText: String,
        valueDouble: Double? = nil,
        unit: String? = nil,
        sparklineHistory: [Double]? = nil,
        sparklineColor: Color? = nil,
        statusLevel: StatusLevel? = nil,
        isCopyable: Bool = false,
        showHairline: Bool = false
    ) {
        self.label = label
        self.valueText = valueText
        self.valueDouble = valueDouble
        self.unit = unit
        self.sparklineHistory = sparklineHistory
        self.sparklineColor = sparklineColor
        self.statusLevel = statusLevel
        self.isCopyable = isCopyable
        self.showHairline = showHairline
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Optional status dot (only when >= elevated, per Principle 3)
            if let level = statusLevel, !level.isQuiet {
                if differentiateWithoutColor {
                    Image(systemName: level.symbolName)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(level.color)
                } else {
                    Circle()
                        .fill(level.color)
                        .frame(width: 6, height: 6)
                }
            }

            Text(label)
                .font(Instrument.Typography.body)
                .foregroundColor(.secondary)

            Spacer()

            // Optional micro-sparkline (40x12 pt)
            if let history = sparklineHistory, history.count >= 2 {
                microSparkline(history: history, color: sparklineColor ?? .secondary)
                    .frame(width: 40, height: 12)
            }

            // Value text / rolling number + subtle hover copy icon when copyable
            HStack(spacing: 5) {
                if isCopyable && isHovered {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }

                if let val = valueDouble {
                    LiveNumber(value: val, font: Instrument.Typography.value, unit: unit)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(valueText)
                            .font(Instrument.Typography.value)
                            .foregroundColor(.primary)
                        if let u = unit {
                            Text(u)
                                .font(Instrument.Typography.micro)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .if(isCopyable) { view in
                view.copyable(text: "\(valueText)\(unit != nil ? " " + unit! : "")")
            }
        }
        .frame(height: 26)
        .padding(.horizontal, 4)
        .background {
            if isCopyable {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovered ? Instrument.Surface.moduleHover : Color.clear)
            }
        }
        .overlay(alignment: .bottom) {
            if showHairline {
                Rectangle()
                    .fill(Instrument.Surface.hairline)
                    .frame(height: 0.5)
            }
        }
        .if(isCopyable) { view in
            view.onHover { hovering in
                withAnimation(motionPolicy.allowsEasing ? Motion.snappy : nil) {
                    isHovered = hovering
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(valueText)\(unit != nil ? " " + unit! : "")")
    }

    private func microSparkline(history: [Double], color: Color) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let maxBound = LiveChartMath.computeMaxBound(values: history)
            guard maxBound > 0, history.count >= 2 else { return }

            let dx = w / CGFloat(history.count - 1)
            let points = history.enumerated().map { i, v in
                LiveChartMath.Point2D(
                    x: Double(CGFloat(i) * dx),
                    y: Double(h * (1.0 - CGFloat(max(0.0, min(maxBound, v)) / maxBound)))
                )
            }
            let segments = LiveChartMath.smoothSegments(points: points)

            var path = Path()
            if let first = segments.first {
                path.move(to: CGPoint(x: first.start.x, y: first.start.y))
                for seg in segments {
                    path.addCurve(to: CGPoint(x: seg.end.x, y: seg.end.y), control1: CGPoint(x: seg.control1.x, y: seg.control1.y), control2: CGPoint(x: seg.control2.x, y: seg.control2.y))
                }
            }
            context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1.0)
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#if DEBUG
struct MetricRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 4) {
            MetricRow(
                label: "Memory Pressure",
                valueText: "Warning",
                statusLevel: .elevated
            )
            MetricRow(
                label: "Download Rate",
                valueText: "42.8",
                valueDouble: 42.8,
                unit: "MB/s",
                sparklineHistory: [10, 20, 15, 30, 42.8],
                sparklineColor: .blue
            )
            MetricRow(
                label: "Active Swap",
                valueText: "0 B",
                statusLevel: .fine
            )
        }
        .padding()
        .frame(width: 300)
        .background(Instrument.Surface.module)
    }
}
#endif
