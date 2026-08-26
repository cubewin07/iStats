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
            // Header: Category Icon, Title, Fan Count Badge
            HStack {
                Label {
                    Text("Fans & Cooling")
                        .font(.headline)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "fanblades")
                        .foregroundColor(headerColor)
                }

                Spacer()

                if let sample = sample {
                    if sample.fans.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                            Text("Fanless")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(4)
                    } else {
                        Text("\(sample.fans.count) \(sample.fans.count == 1 ? "Fan" : "Fans")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                } else {
                    Text("Sampling...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if let sample = sample {
                if !sample.fans.isEmpty {
                    // Primary Metric Row
                    HStack(alignment: .firstTextBaseline) {
                        if let primary = primaryFan {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(primary.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(Units.formatRPM(primary.rpm))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(rpmColor(primary))
                            }
                        }

                        Spacer()

                        if sample.fans.count > 1, let maxVal = maxRPM {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Peak Fan")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(Units.formatRPM(maxVal))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Rolling RPM Graph (Requirements 10.2, 10.3)
                    if !historyRPMs.isEmpty && historyRPMs.contains(where: { $0 > 0 }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Speed History")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let cur = primaryFan?.rpm ?? maxRPM {
                                    Text(Units.formatRPM(cur))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            RollingGraphView(
                                values: historyRPMs,
                                maxValue: Double(sample.fans.compactMap(\.maxRPM).max() ?? 6000),
                                tintColor: headerColor,
                                height: 38
                            )
                        }
                    }

                    Divider()

                    // Per-Fan Rows with RPM and Speed Range Bounds (Requirements 4.1, 4.2)
                    VStack(spacing: 8) {
                        ForEach(sample.fans, id: \.name) { fan in
                            fanRow(fan)
                        }
                    }
                } else {
                    // Fanless System View (Requirement 4.4, ADR 0003)
                    HStack(spacing: 10) {
                        Image(systemName: "wind")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Passive Cooling")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("This Mac has no internal cooling fans.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("Waiting for fan telemetry...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Fan Row

    private func fanRow(_ fan: FanReading) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(fan.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Text(Units.formatRPM(fan.rpm))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(rpmColor(fan))
            }

            // Gauge Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(rpmColor(fan))
                        .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(fanFraction(fan)))), height: 4)
                }
            }
            .frame(height: 4)

            // Bounds / Limits
            if let boundsStr = Units.formatFanBounds(min: fan.minRPM, max: fan.maxRPM) {
                Text("Range: \(boundsStr)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
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
