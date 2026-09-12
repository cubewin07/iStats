import SwiftUI
import iStatsCore

/// Live battery glyph and power budget bar illustration.
/// Normalizes draw against adapter wattage when plugged in, or soft peak when on battery.
public struct PowerBudgetIllustrationView: View {
    public let sample: PowerSample?
    public let peakDraw: Double
    public let size: CGSize

    public init(
        sample: PowerSample?,
        peakDraw: Double = 60.0,
        size: CGSize = CGSize(width: 68, height: 68)
    ) {
        self.sample = sample
        self.peakDraw = max(peakDraw, 30.0)
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Housing container
            RoundedRectangle(cornerRadius: 6)
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
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)

            if let s = sample, s.hasBattery {
                batteryGlyphContent(sample: s)
            } else {
                desktopMacPowerContent(sample: sample)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Battery Glyph (Laptops)

    private func batteryGlyphContent(sample: PowerSample) -> some View {
        let charge = sample.charge ?? 100.0
        let variant = sample.variant
        let color = chargeColor(charge: charge, variant: variant)

        return VStack(spacing: 3) {
            // Battery Terminal Top Cap
            RoundedRectangle(cornerRadius: 1)
                .fill(color.opacity(0.4))
                .frame(width: 10, height: 2.5)

            // Battery Body
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(variant == .lowBattery && charge <= 10.0 ? Color.red.opacity(0.8) : Color.primary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 28, height: 38)

                // Fill level
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: max(3, 34 * CGFloat(charge / 100.0)))
                    .padding(2)

                // Multi-state overlay icon
                overlayIcon(for: variant)
            }

            Text(String(format: "%.0f%%", charge))
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private func overlayIcon(for variant: PowerStateVariant) -> some View {
        switch variant {
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.yellow)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                .padding(.bottom, 12)
        case .onHold:
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.orange)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                .padding(.bottom, 13)
        case .powerDeficit:
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.orange)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                .padding(.bottom, 12)
        case .lowBattery:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                .padding(.bottom, 12)
        case .charged:
            Image(systemName: "powerplug.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                .padding(.bottom, 13)
        case .discharging, .acDesktop, .unavailable:
            EmptyView()
        }
    }

    // MARK: - Desktop Mac Power (No Battery)

    private func desktopMacPowerContent(sample: PowerSample?) -> some View {
        VStack(spacing: 3) {
            Image(systemName: "bolt.badge.clock.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)

            if let watts = sample?.powerDrawWatts {
                Text(String(format: "%.0f W", watts))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            } else {
                Text("AC Power")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func chargeColor(charge: Double, variant: PowerStateVariant) -> Color {
        switch variant {
        case .lowBattery:
            return .red
        case .powerDeficit:
            return .orange
        case .onHold:
            return .green
        case .charging, .charged:
            return .green
        case .discharging:
            if charge <= 10 {
                return .red
            } else if charge <= 20 {
                return .orange
            } else {
                return .green
            }
        case .acDesktop, .unavailable:
            return .green
        }
    }
}
