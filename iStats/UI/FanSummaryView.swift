import SwiftUI
import iStatsCore

/// A detailed Fan metrics view displaying live RPM speeds per fan, min/max hardware speed bounds,
/// rolling history graphs, and fanless system detection (Requirements 4.1, 4.2, 10.1, 10.2, 11.3).
public struct FanSummaryView: View {
    public let sample: FanSample?
    public let history: [Sample<FanSample>]

    public init(
        sample: FanSample? = nil,
        history: [Sample<FanSample>] = []
    ) {
        self.sample = sample
        self.history = history
    }

    /// Primary fan to feature (first available fan).
    private var primaryFan: FanReading? {
        sample?.fans.first
    }

    /// Maximum RPM across current fans.
    private var maxRPM: Int? {
        sample?.fans.map(\.rpm).max()
    }

    /// History values of the primary or max fan RPM for sparkline graph rendering.
    private var historyRPMs: [Double] {
        history.compactMap { hist in
            let fans = hist.value.fans
            guard !fans.isEmpty else { return nil }
            return Double(fans.map(\.rpm).max() ?? 0)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sample = sample {
                if !sample.fans.isEmpty {
                    // Hero Fan Cooling Card
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(primaryFan?.name ?? "Cooling Fans")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)

                            if let primary = primaryFan {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(primary.rpm)")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundColor(rpmColor(primary))

                                    Text("RPM")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(rpmColor(primary))
                                }
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.cyan)
                                Text("Auto (Firmware)")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.cyan)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.cyan.opacity(0.12))
                            .clipShape(Capsule())

                            if sample.fans.count > 1, let maxVal = maxRPM {
                                Text("Peak: \(Units.formatRPM(maxVal))")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Rolling 60s RPM History Graph
                    if !historyRPMs.isEmpty && historyRPMs.contains(where: { $0 > 0 }) {
                        VStack(alignment: .leading, spacing: 4) {
                            RollingGraphView(
                                values: historyRPMs,
                                minValue: 0.0,
                                maxValue: Double(sample.fans.compactMap(\.maxRPM).max() ?? 6000),
                                tintColor: headerColor,
                                capacity: 60,
                                height: 44,
                                showGrid: true
                            )

                            HStack {
                                Text("60s Fan Speed History")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let cur = primaryFan?.rpm ?? maxRPM {
                                    Text("Current: \(Units.formatRPM(cur))")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // Per-Fan Breakdown Cards
                    VStack(spacing: 5) {
                        ForEach(sample.fans, id: \.name) { fan in
                            fanCard(fan)
                        }
                    }

                    // Firmware Policy Footnote
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.top, 1)
                        Text(FanControlPolicy.readOnlyExplanation)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 1)
                } else {
                    // Passive Cooling Card (e.g. MacBook Air)
                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Passive Cooling Architecture")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)
                            Text("This Mac operates silently with no internal fans.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.secondary.opacity(0.06))
                    )
                }
            } else {
                Text("Waiting for fan telemetry...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - Fan Card

    private func fanCard(_ fan: FanReading) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "fanblades")
                    .font(.system(size: 10))
                    .foregroundColor(rpmColor(fan))

                Text(fan.name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Text(Units.formatRPM(fan.rpm))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(rpmColor(fan))
            }

            // Gauge Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.8), rpmColor(fan)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(fanFraction(fan)))), height: 4)
                }
            }
            .frame(height: 4)

            // Bounds / Limits
            if let boundsStr = Units.formatFanBounds(min: fan.minRPM, max: fan.maxRPM) {
                Text("Hardware limits: \(boundsStr)")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Helpers

    private var headerColor: Color {
        if let maxR = maxRPM, maxR > 4000 {
            return .orange
        }
        return .cyan
    }

    private func fanFraction(_ fan: FanReading) -> Double {
        if let maxR = fan.maxRPM, maxR > 0 {
            let minR = fan.minRPM ?? 0
            if maxR > minR {
                let clampedRPM = max(minR, min(fan.rpm, maxR))
                return Double(clampedRPM - minR) / Double(maxR - minR)
            }
            return Double(fan.rpm) / Double(maxR)
        }
        return min(1.0, Double(fan.rpm) / 6000.0)
    }

    private func rpmColor(_ fan: FanReading) -> Color {
        let fraction = fanFraction(fan)
        if fraction >= 0.85 {
            return .red
        } else if fraction >= 0.65 {
            return .orange
        } else if fraction >= 0.35 {
            return .cyan
        } else {
            return .blue
        }
    }
}

