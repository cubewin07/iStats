import SwiftUI
import iStatsCore

/// A Fans & Cooling metrics card view:
/// 1. Rotating Fan Blades Illustration (% of max speed mapping)
/// 2. Primary fan speed / % of max hero with prominent font
/// 3. 60-sample RPM history sparkline & collapsible diagnostics.
public struct FanSummaryView: View {
    public let sample: FanSample?
    public let history: [Sample<FanSample>]

    @State private var isDetailsExpanded: Bool = false

    public init(sample: FanSample? = nil, history: [Sample<FanSample>] = []) {
        self.sample = sample
        self.history = history
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateFan(sample)
    }

    private var primaryFan: FanReading? {
        sample?.fans.first
    }

    private var historyRPMs: [Double] {
        history.compactMap { hist in
            let fans = hist.value.fans
            guard !fans.isEmpty else { return nil }
            return Double(fans.map(\.rpm).max() ?? 0)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Hero Row: Fan Blades + Fan Speed Metrics
            HStack(alignment: .center, spacing: 14) {
                // Live Rotating Fan Blades Illustration
                FanBladesIllustrationView(sample: sample, size: 68)

                // High-Readability Fan Speed Metrics
                VStack(alignment: .leading, spacing: 3) {
                    if let sample = sample {
                        if sample.isFanless {
                            Text("Passive Cooling")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.green)

                            Text("No mechanical fans")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            // Primary % of Max or RPM Hero
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(verdict.primaryValue)
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                Text("cooling effort")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }

                            // Secondary RPM & Fan Count
                            if let sec = verdict.secondaryValue {
                                Text(sec)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Text("Automatic Firmware Control")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.85))
                        }
                    } else {
                        Text("Sampling cooling telemetry...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            // MARK: - 60-Sample Fan Speed History Sparkline (if has fans)
            if let sample = sample, !sample.isFanless, !historyRPMs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    let maxRange = Double(sample.fans.compactMap(\.maxRPM).max() ?? 6000)

                    RollingGraphView(
                        values: historyRPMs,
                        minValue: 0.0,
                        maxValue: maxRange,
                        tintColor: verdict.level.color,
                        capacity: 60,
                        height: 44,
                        showGrid: true
                    )

                    HStack {
                        Text("last 2 min")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        if let maxHist = historyRPMs.max() {
                            Text(String(format: "peak %.0f RPM", maxHist))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            // MARK: - Collapsible Diagnostics (Per-Fan Hardware Ranges)
            if let sample = sample, !sample.isFanless, !sample.fans.isEmpty {
                CollapsibleSection(
                    title: "Fans",
                    count: sample.fans.count,
                    isExpanded: $isDetailsExpanded
                ) {
                    diagnosticsContent(sample: sample)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - Diagnostics Content

    @ViewBuilder
    private func diagnosticsContent(sample: FanSample) -> some View {
        VStack(spacing: 4) {
            ForEach(sample.fans, id: \.name) { fan in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(fan.name)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.primary)

                        if let minR = fan.minRPM, let maxR = fan.maxRPM {
                            Text("Range: \(minR)–\(maxR) RPM")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(fan.rpm) RPM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)

                        if let minR = fan.minRPM, let maxR = fan.maxRPM, maxR > minR {
                            let pct = Swift.max(0.0, Swift.min(100.0, Double(fan.rpm - minR) / Double(maxR - minR) * 100.0))
                            Text(String(format: "%.0f%% effort", pct))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.secondary)
                        } else if let maxR = fan.maxRPM, maxR > 0 {
                            let pct = Double(fan.rpm) / Double(maxR) * 100.0
                            Text(String(format: "%.0f%%", pct))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.04))
                )
            }
        }
        .padding(.top, 4)
    }
}
