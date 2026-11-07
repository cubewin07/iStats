import SwiftUI
import iStatsCore

/// 3-Node animated power flow diagram (Adapter · Mac · Battery) driven by PowerFlowMath (ADR 0009 / Task 8.8h).
public struct PowerFlowView: View {
    public let flow: PowerFlow
    public let variant: PowerStateVariant

    @Environment(\.motionPolicy) private var motionPolicy

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
        Color.secondary.opacity(0.12)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: motionPolicy != .full)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            VStack(spacing: 8) {
                // Topology Canvas: height 92 pt
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
                        context.stroke(pathAdapterToMac, with: .color(activeColor), style: trackStroke)
                        if motionPolicy == .full {
                            drawParticles(
                                in: &context,
                                path: pathAdapterToMac,
                                speed: flow.speedAdapterToMac,
                                time: elapsed,
                                color: activeColor
                            )
                        }
                    }

                    // Edge 2: Battery -> Mac
                    if let w = flow.batteryToMac, w > 0 {
                        let col = (variant == .powerDeficit) ? CategoryPalette.statusColor(for: .warning) : activeColor
                        context.stroke(pathBatteryToMac, with: .color(col), style: trackStroke)
                        if motionPolicy == .full {
                            drawParticles(
                                in: &context,
                                path: pathBatteryToMac,
                                speed: flow.speedBatteryToMac,
                                time: elapsed,
                                color: col
                            )
                        }
                    }

                    // Edge 3: Adapter -> Battery
                    if let w = flow.adapterToBattery, w > 0 {
                        context.stroke(pathAdapterToBattery, with: .color(activeColor), style: trackStroke)
                        if motionPolicy == .full {
                            drawParticles(
                                in: &context,
                                path: pathAdapterToBattery,
                                speed: flow.speedAdapterToBattery,
                                time: elapsed,
                                color: activeColor
                            )
                        }
                    }
                }
                .frame(height: 92)
                .overlay(
                    // Interactive Node Views
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

    // MARK: - Canvas Particle Renderer

    private func drawParticles(
        in context: inout GraphicsContext,
        path: Path,
        speed: Double,
        time: TimeInterval,
        color: Color
    ) {
        guard speed > 0 else { return }
        let duration = max(0.4, 2.0 / speed)
        let phase = CGFloat(time.truncatingRemainder(dividingBy: duration) / duration)

        // Draw 3 spaced particles along the path
        for i in 0..<3 {
            let offset = (phase + CGFloat(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
            if let point = pointAlong(path: path, fraction: offset) {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
                    with: .color(color)
                )
            }
        }
    }

    private func pointAlong(path: Path, fraction: CGFloat) -> CGPoint? {
        guard fraction >= 0 && fraction <= 1.0 else { return nil }
        var totalLen: CGFloat = 0
        var start = CGPoint.zero

        path.forEach { element in
            switch element {
            case .move(to: let p):
                start = p
            case .line(to: let p):
                totalLen += hypot(p.x - start.x, p.y - start.y)
                start = p
            case .quadCurve(to: let p, control: let c):
                var prev = start
                for step in 1...10 {
                    let t = CGFloat(step) / 10.0
                    let pt = quadBezierPoint(p0: start, c: c, p1: p, t: t)
                    totalLen += hypot(pt.x - prev.x, pt.y - prev.y)
                    prev = pt
                }
                start = p
            default:
                break
            }
        }

        guard totalLen > 0 else { return nil }
        let targetLen = totalLen * fraction
        var currentLen: CGFloat = 0
        var resultPoint: CGPoint? = nil

        start = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(to: let p):
                start = p
            case .line(to: let p):
                let segLen = hypot(p.x - start.x, p.y - start.y)
                if currentLen + segLen >= targetLen && resultPoint == nil {
                    let segFrac = segLen > 0 ? (targetLen - currentLen) / segLen : 0
                    resultPoint = CGPoint(
                        x: start.x + (p.x - start.x) * segFrac,
                        y: start.y + (p.y - start.y) * segFrac
                    )
                }
                currentLen += segLen
                start = p
            case .quadCurve(to: let p, control: let c):
                var prev = start
                for step in 1...10 {
                    let t = CGFloat(step) / 10.0
                    let pt = quadBezierPoint(p0: start, c: c, p1: p, t: t)
                    let subLen = hypot(pt.x - prev.x, pt.y - prev.y)
                    if currentLen + subLen >= targetLen && resultPoint == nil {
                        let subFrac = subLen > 0 ? (targetLen - currentLen) / subLen : 0
                        resultPoint = CGPoint(
                            x: prev.x + (pt.x - prev.x) * subFrac,
                            y: prev.y + (pt.y - prev.y) * subFrac
                        )
                    }
                    currentLen += subLen
                    prev = pt
                }
                start = p
            default:
                break
            }
        }

        return resultPoint ?? start
    }

    private func quadBezierPoint(p0: CGPoint, c: CGPoint, p1: CGPoint, t: CGFloat) -> CGPoint {
        let invT = 1.0 - t
        let x = invT * invT * p0.x + 2.0 * invT * t * c.x + t * t * p1.x
        let y = invT * invT * p0.y + 2.0 * invT * t * c.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }
}

#if DEBUG
struct PowerFlowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            // Charging
            PowerFlowView(
                flow: PowerFlow(adapterToMac: 18.5, adapterToBattery: 30.0, batteryToMac: nil, batteryNetWatts: 30.0),
                variant: .charging
            )
            // Discharging
            PowerFlowView(
                flow: PowerFlow(adapterToMac: nil, adapterToBattery: nil, batteryToMac: 22.0, batteryNetWatts: -22.0),
                variant: .discharging
            )
            // Power Deficit
            PowerFlowView(
                flow: PowerFlow(adapterToMac: 30.0, adapterToBattery: nil, batteryToMac: 25.0, batteryNetWatts: -25.0),
                variant: .powerDeficit
            )
        }
        .padding()
        .background(Color.black)
    }
}
#endif

