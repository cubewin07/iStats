import SwiftUI
import iStatsCore

/// Capsule bar meter with gradient fill, eased animation, and optional threshold marker (ADR 0009 / Task 8.5).
public struct Meter: View {
    public enum Height: CGFloat {
        case small = 6
        case medium = 10
        case large = 14
    }

    public let progress: Double // 0.0 ... 1.0
    public let height: Height
    public let tint: Color
    public let deepTint: Color?
    public var thresholdTick: Double? // 0.0 ... 1.0
    public var interval: Double

    public init(
        progress: Double,
        height: Height = .medium,
        tint: Color,
        deepTint: Color? = nil,
        thresholdTick: Double? = nil,
        interval: Double = 1.0
    ) {
        self.progress = max(0.0, min(1.0, progress))
        self.height = height
        self.tint = tint
        self.deepTint = deepTint
        self.thresholdTick = thresholdTick != nil ? max(0.0, min(1.0, thresholdTick!)) : nil
        self.interval = interval
    }

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let h = height.rawValue
            let fillWidth = totalWidth * CGFloat(progress)

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Instrument.Surface.inset)
                    .frame(height: h)

                // Fill Gradient
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, deepTint ?? tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(h, fillWidth), height: h)
                    .easedProgress(progress, interval: interval)

                // Optional Threshold Tick Marker
                if let tick = thresholdTick {
                    let tickX = totalWidth * CGFloat(tick)
                    Rectangle()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: 1.5, height: h + 4)
                        .position(x: tickX, y: h / 2.0)
                }
            }
        }
        .frame(height: height.rawValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meter")
        .accessibilityValue("\(Int(progress * 100))%")
    }
}

#if DEBUG
struct Meter_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            Meter(progress: 0.25, height: .small, tint: .green)
            Meter(progress: 0.68, height: .medium, tint: .blue, deepTint: .teal, thresholdTick: 0.8)
            Meter(progress: 0.92, height: .large, tint: .orange, deepTint: .red, thresholdTick: 0.85)
        }
        .padding()
        .frame(width: 280)
        .background(Instrument.Surface.module)
    }
}
#endif

