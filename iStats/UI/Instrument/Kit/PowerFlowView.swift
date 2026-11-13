import SwiftUI
import iStatsCore

/// 3-Node animated power flow diagram (Adapter · Mac · Battery) driven by PowerFlowMath (ADR 0009 / Task 8.5.8h).
/// Dash flow velocity scales calmly with real wattage (< 8 W gentle drift, > 45 W brisk flow without strobe).
public struct PowerFlowView: View {
    public let flow: PowerFlow
    public let variant: PowerStateVariant

    @Environment(\.motionPolicy) private var motionPolicy
    @State private var animationOrigin: TimeInterval = Date().timeIntervalSinceReferenceDate

    private static let dashPattern: [CGFloat] = [5.0, 7.0]
    private static let dashPeriod: Double = 12.0

    public init(flow: PowerFlow, variant: PowerStateVariant) {
        self.flow = flow
        self.variant = variant
    }

    private var activeColor: Color {
        if variant == .powerDeficit {
            return CategoryPalette.statusColor(for: .warning)
        } else if variant == .onHold {
            return CategoryPalette.statusColor(for: .elevated)
        } else {
            return CategoryPalette.color(for: .power)
        }
    }

    private var inactiveColor: Color {
        Color.secondary.opacity(0.14)
    }

    /// Maps real wattage to a calm, strobe-free dash velocity in points per second.
    /// - `< 8 W`: gentle drift (`4...10 pt/s`)
    /// - `8...45 W`: steady ramp (`10...28 pt/s`)
    /// - `> 45 W`: brisk flow (`28...38 pt/s`, capped to avoid visual strobe at 30 Hz)
    internal static func dashVelocity(watts: Double) -> Double {
        guard watts > 0, watts.isFinite else { return 0.0 }
        if watts < 8.0 {
            return 4.0 + (watts / 8.0) * 6.0
        } else if watts <= 45.0 {
            let t = (watts - 8.0) / (45.0 - 8.0)
            return 10.0 + t * 18.0
        } else {
            let extra = min(1.0, (watts - 45.0) / 55.0)
            return 28.0 + extra * 10.0
        }
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: motionPolicy != .full)) { timeline in
            let elapsed = max(0.0, timeline.date.timeIntervalSinceReferenceDate - animationOrigin)

            Canvas { context, size in
                let adapterPos = CGPoint(x: 45, y: 54)
                let macPos = CGPoint(x: size.width / 2.0, y: 18)
                let batteryPos = CGPoint(x: size.width - 45, y: 54)

                // Path 1: Adapter -> Mac
                var pathAdapterToMac = Path()
                pathAdapterToMac.move(to: CGPoint(x: adapterPos.x + 14, y: adapterPos.y - 8))
                pathAdapterToMac.addLine(to: CGPoint(x: macPos.x - 14, y: macPos.y + 10))

                // Path 2: Battery -> Mac
                var pathBatteryToMac = Path()
                pathBatteryToMac.move(to: CGPoint(x: batteryPos.x - 14, y: batteryPos.y - 8))
                pathBatteryToMac.addLine(to: CGPoint(x: macPos.x + 14, y: macPos.y + 10))

                // Path 3: Adapter -> Battery (Curved along bottom)
                var pathAdapterToBattery = Path()
                pathAdapterToBattery.move(to: CGPoint(x: adapterPos.x, y: adapterPos.y + 16))
                pathAdapterToBattery.addQuadCurve(
                    to: CGPoint(x: batteryPos.x, y: batteryPos.y + 16),
                    control: CGPoint(x: size.width / 2.0, y: 88)
                )

                // Draw baseline tracks
                let trackStroke = StrokeStyle(lineWidth: 2, lineCap: .round)
                context.stroke(pathAdapterToMac, with: .color(inactiveColor), style: trackStroke)
                context.stroke(pathBatteryToMac, with: .color(inactiveColor), style: trackStroke)
                context.stroke(pathAdapterToBattery, with: .color(inactiveColor), style: trackStroke)

                // Edge 1: Adapter -> Mac
                if let w = flow.adapterToMac, w > 0 {
                    drawActiveFlow(
                        in: &context,
                        path: pathAdapterToMac,
                        watts: w,
                        elapsed: elapsed,
                        color: activeColor
                    )
                }

                // Edge 2: Battery -> Mac
                if let w = flow.batteryToMac, w > 0 {
                    let col = (variant == .powerDeficit)
                        ? CategoryPalette.statusColor(for: .warning)
                        : activeColor
                    drawActiveFlow(
                        in: &context,
                        path: pathBatteryToMac,
                        watts: w,
                        elapsed: elapsed,
                        color: col
                    )
                }

                // Edge 3: Adapter -> Battery
                if let w = flow.adapterToBattery, w > 0 {
                    drawActiveFlow(
                        in: &context,
                        path: pathAdapterToBattery,
                        watts: w,
                        elapsed: elapsed,
                        color: activeColor
                    )
                }
            }
            .frame(height: 92)
            .overlay(
                HStack(alignment: .top) {
                    // Node 1: Adapter
                    let adapterW = (flow.adapterToMac ?? 0) + (flow.adapterToBattery ?? 0)
                    powerNode(
                        icon: "powerplug.fill",
                        label: "Adapter",
                        watts: adapterW > 0 ? adapterW : nil,
                        isActive: adapterW > 0
                    )
                    .padding(.top, 36)

                    Spacer()

                    // Node 2: Mac
                    let macW = (flow.adapterToMac ?? 0) + (flow.batteryToMac ?? 0)
                    powerNode(
                        icon: "laptopcomputer",
                        label: "Mac",
                        watts: macW > 0 ? macW : nil,
                        isActive: macW > 0
                    )

                    Spacer()

                    // Node 3: Battery
                    let battW = flow.adapterToBattery ?? flow.batteryToMac
                    powerNode(
                        icon: "battery.100percent",
                        label: "Battery",
                        watts: battW,
                        wattsPrefix: flow.adapterToBattery != nil ? "+" : (flow.batteryToMac != nil ? "-" : nil),
                        isActive: battW != nil && battW! > 0
                    )
                    .padding(.top, 36)
                }
                .padding(.horizontal, 10)
            )
        }
    }

    // MARK: - Active Flow Renderer

    private func drawActiveFlow(
        in context: inout GraphicsContext,
        path: Path,
        watts: Double,
        elapsed: TimeInterval,
        color: Color
    ) {
        let baseOpacity = (motionPolicy == .full) ? 0.25 : 0.80
        context.stroke(
            path,
            with: .color(color.opacity(baseOpacity)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
        )

        guard motionPolicy == .full else { return }

        let velocity = Self.dashVelocity(watts: watts)
        guard velocity > 0 else { return }

        let distance = (elapsed * velocity).truncatingRemainder(dividingBy: Self.dashPeriod)
        let dashStyle = StrokeStyle(
            lineWidth: 2.2,
            lineCap: .round,
            dash: Self.dashPattern,
            dashPhase: -CGFloat(distance)
        )
        context.stroke(path, with: .color(color), style: dashStyle)
    }

    // MARK: - Node Component

    @ViewBuilder
    private func powerNode(
        icon: String,
        label: String,
        watts: Double?,
        wattsPrefix: String? = nil,
        isActive: Bool
    ) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 32, height: 32)

                Circle()
                    .stroke(isActive ? activeColor : inactiveColor, lineWidth: 1.5)
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isActive ? activeColor : .secondary)
            }

            Text(label)
                .font(Instrument.Typography.micro)
                .foregroundColor(.secondary)

            if let w = watts, w > 0 {
                let prefix = wattsPrefix ?? ""
                Text("\(prefix)\(String(format: "%.1f", w)) W")
                    .font(Instrument.Typography.micro.monospacedDigit())
                    .foregroundColor(isActive ? .primary : .secondary)
            } else {
                Text("—")
                    .font(Instrument.Typography.micro.monospacedDigit())
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .frame(width: 64)
    }
}

#if DEBUG
struct PowerFlowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            // Gentle low-draw charging
            PowerFlowView(
                flow: PowerFlow(adapterToMac: 5.2, adapterToBattery: 18.0, batteryToMac: nil, batteryNetWatts: 18.0),
                variant: .charging
            )
            // Discharging
            PowerFlowView(
                flow: PowerFlow(adapterToMac: nil, adapterToBattery: nil, batteryToMac: 22.0, batteryNetWatts: -22.0),
                variant: .discharging
            )
            // High-draw Power Deficit
            PowerFlowView(
                flow: PowerFlow(adapterToMac: 30.0, adapterToBattery: nil, batteryToMac: 52.0, batteryNetWatts: -52.0),
                variant: .powerDeficit
            )
        }
        .padding()
        .background(Color.black)
    }
}
#endif
