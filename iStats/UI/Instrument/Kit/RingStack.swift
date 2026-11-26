import SwiftUI
import iStatsCore

public struct RingData: Identifiable, Sendable {
    public let id: String
    public let fraction: Double // 0.0 ... 1.0
    public let color: Color
    public let label: String

    public init(id: String? = nil, fraction: Double, color: Color, label: String) {
        self.id = id ?? label
        self.fraction = max(0.0, min(1.0, fraction))
        self.color = color
        self.label = label
    }
}

/// 1–3 concentric rings with round caps and inset tracks (ADR 0009 / Task 8.5).
public struct RingStack: View {
    @Environment(\.motionPolicy) private var motionPolicy

    public let rings: [RingData]
    public var size: CGFloat
    public var ringWidth: CGFloat
    public var ringGap: CGFloat

    public init(
        rings: [RingData],
        size: CGFloat = 64,
        ringWidth: CGFloat = 5,
        ringGap: CGFloat = 3
    ) {
        self.rings = Array(rings.prefix(3))
        self.size = size
        self.ringWidth = ringWidth
        self.ringGap = ringGap
    }

    public var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let radius = (size / 2.0) - (ringWidth / 2.0) - CGFloat(index) * (ringWidth + ringGap)
                if radius > 0 {
                    // Track
                    Circle()
                        .stroke(
                            Instrument.Surface.inset,
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .frame(width: radius * 2.0, height: radius * 2.0)

                    // Value Arc
                    Circle()
                        .trim(from: 0.0, to: CGFloat(ring.fraction))
                        .stroke(
                            ring.color,
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: radius * 2.0, height: radius * 2.0)
                        .animation(motionPolicy == .full ? Motion.smooth : nil, value: ring.fraction)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activity rings")
        .accessibilityValue(rings.map { "\($0.label): \(Int($0.fraction * 100))%" }.joined(separator: ", "))
    }
}

#if DEBUG
struct RingStack_Previews: PreviewProvider {
    static var previews: some View {
        RingStack(
            rings: [
                RingData(fraction: 0.85, color: .red, label: "User"),
                RingData(fraction: 0.52, color: .green, label: "System"),
                RingData(fraction: 0.20, color: .blue, label: "Idle")
            ],
            size: 72
        )
        .padding()
        .background(Instrument.Surface.module)
    }
}
#endif
