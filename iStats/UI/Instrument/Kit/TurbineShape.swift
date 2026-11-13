import SwiftUI
import iStatsCore

/// Custom 5-blade aerodynamic turbine shape (ADR 0009 / Task 8.8e).
public struct TurbineShape: Shape {
    public let bladeCount: Int

    public init(bladeCount: Int = 5) {
        self.bladeCount = bladeCount
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0
        let hubRadius = radius * 0.28
        let bladeRadius = radius * 0.94

        let angleStep = (2.0 * Double.pi) / Double(bladeCount)
        for i in 0..<bladeCount {
            let baseAngle = Double(i) * angleStep
            let bladeWidthAngle = angleStep * 0.38

            let startHub = CGPoint(
                x: center.x + CGFloat(cos(baseAngle)) * hubRadius,
                y: center.y + CGFloat(sin(baseAngle)) * hubRadius
            )
            let endHub = CGPoint(
                x: center.x + CGFloat(cos(baseAngle + bladeWidthAngle)) * hubRadius,
                y: center.y + CGFloat(sin(baseAngle + bladeWidthAngle)) * hubRadius
            )
            let tipLeading = CGPoint(
                x: center.x + CGFloat(cos(baseAngle + angleStep * 0.55)) * bladeRadius,
                y: center.y + CGFloat(sin(baseAngle + angleStep * 0.55)) * bladeRadius
            )
            let tipTrailing = CGPoint(
                x: center.x + CGFloat(cos(baseAngle + angleStep * 0.68)) * (bladeRadius * 0.88),
                y: center.y + CGFloat(sin(baseAngle + angleStep * 0.68)) * (bladeRadius * 0.88)
            )

            var bladePath = Path()
            bladePath.move(to: startHub)
            bladePath.addQuadCurve(
                to: tipLeading,
                control: CGPoint(
                    x: center.x + CGFloat(cos(baseAngle + angleStep * 0.25)) * (radius * 0.7),
                    y: center.y + CGFloat(sin(baseAngle + angleStep * 0.25)) * (radius * 0.7)
                )
            )
            bladePath.addLine(to: tipTrailing)
            bladePath.addQuadCurve(
                to: endHub,
                control: CGPoint(
                    x: center.x + CGFloat(cos(baseAngle + angleStep * 0.45)) * (radius * 0.55),
                    y: center.y + CGFloat(sin(baseAngle + angleStep * 0.45)) * (radius * 0.55)
                )
            )
            bladePath.closeSubpath()
            path.addPath(bladePath)
        }

        // Center hub
        path.addEllipse(in: CGRect(
            x: center.x - hubRadius,
            y: center.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        ))

        return path
    }
}

private final class TurbineDriver {
    var degrees: Double = 0
    var lastTime: TimeInterval?

    func step(to time: TimeInterval, speed: Double) -> Double {
        if let last = lastTime {
            let dt = max(0.0, time - last)
            degrees = FanMath.stepRotationDegrees(currentDegrees: degrees, dt: dt, speedRPS: speed)
        }
        lastTime = time
        return degrees
    }

    func reset() {
        lastTime = nil
    }
}

/// Rotating instrument turbine widget driven by pure `FanMath` visual speed curves.
public struct TurbineView: View {
    public let rpm: Int
    public let minRPM: Int?
    public let maxRPM: Int?
    public var size: CGFloat
    public var isPaused: Bool

    @Environment(\.motionPolicy) private var motionPolicy
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var driver = TurbineDriver()

    public init(
        rpm: Int,
        minRPM: Int? = nil,
        maxRPM: Int? = nil,
        size: CGFloat = 64,
        isPaused: Bool = false
    ) {
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.size = size
        self.isPaused = isPaused
    }

    public var body: some View {
        let speed = FanMath.visualSpeed(rpm: rpm, min: minRPM, max: maxRPM)
        let shouldSpin = (motionPolicy == .full) && (speed > 0.0) && !isPaused
        let bezelWidth: CGFloat = size <= 36 ? 1.5 : 2.0
        let bladeSize = max(8.0, size - (size <= 36 ? 5.0 : 8.0))
        let bladeTint = CategoryPalette.tint(for: .fan).opacity(rpm > 0 ? 1.0 : 0.45)
        let bezelColor = colorSchemeContrast == .increased
            ? Color.primary.opacity(0.25)
            : Instrument.Surface.inset

        ZStack {
            // Bezel Ring
            Circle()
                .stroke(bezelColor, lineWidth: bezelWidth)
                .frame(width: size, height: size)

            // Turbine Blades
            if shouldSpin {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                    let degrees = driver.step(
                        to: context.date.timeIntervalSinceReferenceDate,
                        speed: speed
                    )
                    TurbineShape()
                        .fill(bladeTint)
                        .rotationEffect(.degrees(degrees))
                        .frame(width: bladeSize, height: bladeSize)
                }
            } else {
                TurbineShape()
                    .fill(bladeTint)
                    .rotationEffect(.degrees(driver.degrees))
                    .frame(width: bladeSize, height: bladeSize)
                    .onAppear {
                        driver.reset()
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fan Turbine")
        .accessibilityValue(rpm > 0 ? "\(rpm) RPM" : "Stopped")
    }
}

#if DEBUG
struct TurbineView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 24) {
            TurbineView(rpm: 1200, minRPM: 1200, maxRPM: 6000)
            TurbineView(rpm: 4500, minRPM: 1200, maxRPM: 6000)
            TurbineView(rpm: 0, minRPM: 1200, maxRPM: 6000)
        }
        .padding()
        .background(Instrument.Surface.panel)
    }
}
#endif

