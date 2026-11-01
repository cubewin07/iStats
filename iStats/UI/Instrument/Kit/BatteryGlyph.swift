import SwiftUI
import iStatsCore

/// 88×40 custom battery glyph with charge proportional fill, status colors, and charging shimmer (ADR 0009 / Task 8.8h).
public struct BatteryGlyph: View {
    public let charge: Double?
    public let isCharging: Bool
    public let statusLevel: StatusLevel

    @Environment(\.motionPolicy) private var motionPolicy
    @State private var shimmerPhase: CGFloat = -1.0

    public init(
        charge: Double?,
        isCharging: Bool,
        statusLevel: StatusLevel = .fine
    ) {
        self.charge = charge
        self.isCharging = isCharging
        self.statusLevel = statusLevel
    }

    private var fillFraction: CGFloat {
        guard let c = charge else { return 0.0 }
        return CGFloat(max(0.0, min(100.0, c))) / 100.0
    }

    private var fillColor: Color {
        if statusLevel == .critical || (charge != nil && charge! <= 10.0) {
            return .red
        } else if statusLevel == .warning || (charge != nil && charge! <= 20.0) {
            return .orange
        } else {
            return CategoryPalette.color(for: .power)
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Main battery body: 80×40 pt
            ZStack(alignment: .leading) {
                // Outline border
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )

                // Fill area: inset by 3 pt
                let availableWidth: CGFloat = 80 - 6
                let fillWidth = max(4.0, availableWidth * fillFraction)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [fillColor, fillColor.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: 40 - 6)

                    // Charging Shimmer Sweep (MotionPolicy.full only)
                    if isCharging && motionPolicy == .full {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 28, height: 40 - 6)
                        .offset(x: shimmerPhase * (fillWidth + 28) - 14)
                        .mask(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .frame(width: fillWidth, height: 40 - 6)
                        )
                    }
                }
                .padding(.leading, 3)

                // Center Icon / Percentage
                HStack {
                    Spacer()
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
                    } else if let c = charge {
                        Text("\(Int(round(c)))%")
                            .font(Instrument.Typography.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.5), radius: 1, x: 0, y: 1)
                    } else {
                        Text("—")
                            .font(Instrument.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .frame(width: 80, height: 40)

            // Right terminal nub: 4×16 pt with 2 pt corner radius
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 4, height: 16)
        }
        .frame(width: 88, height: 40)
        .onAppear {
            if isCharging && motionPolicy == .full {
                withAnimation(
                    .easeInOut(duration: 1.6)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerPhase = 1.0
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level \(Int(charge ?? 0))%, \(isCharging ? "Charging" : "Discharging")")
    }
}

#if DEBUG
struct BatteryGlyph_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            BatteryGlyph(charge: 85, isCharging: true)
            BatteryGlyph(charge: 54, isCharging: false)
            BatteryGlyph(charge: 18, isCharging: false, statusLevel: .warning)
            BatteryGlyph(charge: 8, isCharging: false, statusLevel: .critical)
        }
        .padding()
        .background(Color.black)
    }
}
#endif
