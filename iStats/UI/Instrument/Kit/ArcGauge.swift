import SwiftUI
import iStatsCore

public struct GaugeZone: Sendable {
    public let upToFraction: Double // 0.0 ... 1.0
    public let color: Color

    public init(upToFraction: Double, color: Color) {
        self.upToFraction = upToFraction
        self.color = color
    }
}

/// Circular arc gauge with configurable sweep, zones, indicator, and center readout (ADR 0009 / Task 8.5).
public struct ArcGauge: View {
    @Environment(\.motionPolicy) private var motionPolicy

    public let value: Double
    public let range: ClosedRange<Double>
    public var sweep: Double
    public var startAngle: Double
    public var zones: [GaugeZone]
    public var tint: Color
    public var size: CGFloat
    public var centerTitle: String?
    public var centerSubtitle: String?

    public init(
        value: Double,
        range: ClosedRange<Double> = 0...100,
        sweep: Double = 200.0,
        startAngle: Double = 170.0,
        zones: [GaugeZone] = [],
        tint: Color = .accentColor,
        size: CGFloat = 80,
        centerTitle: String? = nil,
        centerSubtitle: String? = nil
    ) {
        self.value = value
        self.range = range
        self.sweep = sweep
        self.startAngle = startAngle
        self.zones = zones
        self.tint = tint
        self.size = size
        self.centerTitle = centerTitle
        self.centerSubtitle = centerSubtitle
    }

    public var body: some View {
        ZStack {
            let clamped = max(range.lowerBound, min(range.upperBound, value))
            let fraction = (clamped - range.lowerBound) / max(0.001, (range.upperBound - range.lowerBound))
            let currentAngle = GaugeMath.angle(value: value, range: range, sweep: sweep, startAngle: startAngle)

            // Background Track Arc
            arcPath(from: startAngle, to: startAngle + sweep)
                .stroke(
                    Instrument.Surface.inset,
                    style: StrokeStyle(lineWidth: size >= 100 ? 8 : 6, lineCap: .round)
                )

            // Active Value Arc
            arcPath(from: startAngle, to: currentAngle)
                .stroke(
                    activeColor(for: fraction),
                    style: StrokeStyle(lineWidth: size >= 100 ? 8 : 6, lineCap: .round)
                )
                .animation(motionPolicy == .full ? Motion.smooth : nil, value: value)

            // Center Readout
            VStack(spacing: 0) {
                if let title = centerTitle {
                    Text(title)
                        .font(size >= 100 ? Instrument.Typography.title : Instrument.Typography.displayCompact)
                        .foregroundColor(.primary)
                }
                if let sub = centerSubtitle {
                    Text(sub)
                        .font(Instrument.Typography.micro)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(centerSubtitle ?? "Gauge")
        .accessibilityValue(centerTitle ?? "\(Int(value))")
    }

    private func arcPath(from: Double, to: Double) -> Path {
        let center = CGPoint(x: size / 2.0, y: size / 2.0)
        let radius = (size / 2.0) - (size >= 100 ? 10 : 8)
        return Path { path in
            guard to > from else { return }
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(from),
                endAngle: .degrees(to),
                clockwise: false
            )
        }
    }

    private func activeColor(for fraction: Double) -> Color {
        for zone in zones {
            if fraction <= zone.upToFraction {
                return zone.color
            }
        }
        return tint
    }
}

#if DEBUG
struct ArcGauge_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            ArcGauge(
                value: 45,
                range: 0...100,
                tint: .blue,
                centerTitle: "45%",
                centerSubtitle: "CPU"
            )

            ArcGauge(
                value: 82,
                range: 0...100,
                zones: [
                    GaugeZone(upToFraction: 0.6, color: .green),
                    GaugeZone(upToFraction: 0.85, color: .yellow),
                    GaugeZone(upToFraction: 1.0, color: .red)
                ],
                centerTitle: "82°",
                centerSubtitle: "DIE"
            )
        }
        .padding()
        .background(Instrument.Surface.module)
    }
}
#endif
