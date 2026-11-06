import SwiftUI
import iStatsCore

/// Live rotating fan blades illustration.
/// Rotation speed and gauge fill are mapped to `% of max RPM` (or leaf icon for fanless Macs).
public struct FanBladesIllustrationView: View {
    public let sample: FanSample?
    public let size: CGFloat

    public init(sample: FanSample?, size: CGFloat = 68) {
        self.sample = sample
        self.size = size
    }

    private var isSpinning: Bool {
        guard let s = sample, !s.isFanless else { return false }
        return s.fans.contains(where: { $0.rpm > 0 })
    }

    public var body: some View {
        TimelineView(.animation(paused: !isSpinning)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Housing container
                RoundedRectangle(cornerRadius: size * 0.12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor).opacity(0.85),
                                Color(nsColor: .windowBackgroundColor).opacity(0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.12)
                            .strokeBorder(Color.cyan.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)

                if let s = sample {
                    if s.isFanless {
                        // Fanless Mac (Leaf glyph)
                        VStack(spacing: 2) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: size * 0.35))
                                .foregroundColor(.green)

                            if size >= 50 {
                                Text("Fanless")
                                    .font(.system(size: size * 0.12, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }
                    } else if s.fans.count >= 2 {
                        // Dual Fan Layout
                        HStack(spacing: size * 0.06) {
                            ForEach(0..<min(s.fans.count, 2), id: \.self) { i in
                                singleFanBlade(fan: s.fans[i], bladeSize: size * 0.42, elapsed: elapsed)
                            }
                        }
                    } else if let fan = s.fans.first {
                        // Single Fan Layout
                        singleFanBlade(fan: fan, bladeSize: size * 0.6, elapsed: elapsed)
                    }
                } else {
                    Image(systemName: "fan.fill")
                        .font(.system(size: size * 0.35))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func singleFanBlade(fan: FanReading, bladeSize: CGFloat, elapsed: TimeInterval) -> some View {
        let maxPossible = Double(fan.maxRPM ?? 6000)
        let minPossible = Double(fan.minRPM ?? 1200)
        let rpm = Double(fan.rpm)

        let ratio = maxPossible > minPossible
            ? max(0.0, min(1.0, (rpm - minPossible) / (maxPossible - minPossible)))
            : max(0.0, min(1.0, rpm / maxPossible))

        let color = fanColor(ratio: ratio)
        let speedDegreesPerSec = rpm <= 0 ? 0.0 : (120.0 + ratio * 360.0)
        let angle = rpm <= 0 ? 0.0 : (elapsed * speedDegreesPerSec).truncatingRemainder(dividingBy: 360.0)

        return ZStack {
            // Fan Duct Circular Housing
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
                .frame(width: bladeSize, height: bladeSize)

            // Outer Progress Ring (Fill to % of max)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.05, ratio)))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: bladeSize, height: bladeSize)

            // Rotating Blades
            Image(systemName: "fan.fill")
                .font(.system(size: bladeSize * 0.58))
                .foregroundColor(color)
                .rotationEffect(.degrees(angle))

            // Center Bearing Hub
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: bladeSize * 0.22, height: bladeSize * 0.22)
                .overlay(
                    Circle().stroke(color.opacity(0.6), lineWidth: 1)
                )
        }
    }

    private func fanColor(ratio: Double) -> Color {
        if ratio >= 0.85 {
            return .red
        } else if ratio >= 0.55 {
            return .orange
        } else if ratio >= 0.25 {
            return .cyan
        } else {
            return .green
        }
    }
}
