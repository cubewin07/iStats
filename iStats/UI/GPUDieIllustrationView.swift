import SwiftUI
import iStatsCore

/// Live GPU die illustration that fills like a battery/cell with a faint glow at high load,
/// accompanied by a clean 3-pill stats row (VRAM, Temp, Watts).
public struct GPUDieIllustrationView: View {
    public let sample: GPUSample?
    public let temperatureUnit: Units.TemperatureUnit
    public let byteStandard: Units.ByteUnitStandard
    public let size: CGFloat
    public let showPills: Bool

    public init(
        sample: GPUSample?,
        temperatureUnit: Units.TemperatureUnit = .celsius,
        byteStandard: Units.ByteUnitStandard = .iec,
        size: CGFloat = 68,
        showPills: Bool = true
    ) {
        self.sample = sample
        self.temperatureUnit = temperatureUnit
        self.byteStandard = byteStandard
        self.size = size
        self.showPills = showPills
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Rounded GPU Die Container
            ZStack(alignment: .bottom) {
                // Die Frame
                RoundedRectangle(cornerRadius: size * 0.14)
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
                        RoundedRectangle(cornerRadius: size * 0.14)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.4), Color.primary.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.purple.opacity(glowOpacity), radius: 6, x: 0, y: 0)

                // Fill level
                if let util = sample?.utilization {
                    GeometryReader { geo in
                        let h = geo.size.height * CGFloat(min(max(util / 100.0, 0.05), 1.0))
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: size * 0.12)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple, Color.indigo.opacity(0.85)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: h)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
                    .padding(3)
                }

                // GPU Icon & Display Grid
                VStack(spacing: 2) {
                    Image(systemName: "display")
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundColor(sample?.utilization != nil ? .white : .purple.opacity(0.6))
                        .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)

                    if let util = sample?.utilization, size >= 50 {
                        Text(String(format: "%.0f%%", util))
                            .font(.system(size: size * 0.15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, size * 0.15)
            }
            .frame(width: size, height: size)

            // 3-Pill Stats Row (VRAM, Temp, Watts)
            if showPills {
                HStack(spacing: 4) {
                    if let mem = sample?.memoryUsed {
                        statPill(icon: "memorychip", value: Units.formatBytes(mem, standard: byteStandard, fractionDigits: 1), color: .purple)
                    }
                    if let temp = sample?.tempCelsius {
                        statPill(icon: "thermometer.medium", value: Units.formatTemperature(temp, unit: temperatureUnit, fractionDigits: 0), color: .orange)
                    }
                    if let watts = sample?.powerWatts {
                        statPill(icon: "bolt.fill", value: String(format: "%.1f W", watts), color: .green)
                    }
                }
            }
        }
    }

    private var glowOpacity: Double {
        guard let util = sample?.utilization else { return 0.0 }
        return min(util / 100.0 * 0.6, 0.6)
    }

    private func statPill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }
}
