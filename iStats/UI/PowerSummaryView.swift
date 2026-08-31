import SwiftUI
import iStatsCore

/// A Battery & Power metrics card view:
/// 1. Filling Battery Glyph + Power Budget Bar (draw vs adapter watts)
/// 2. Battery percentage & charging hero with prominent font + time remaining
/// 3. 60-sample wattage sparkline & collapsible health wear diagnostics.
public struct PowerSummaryView: View {
    public let sample: PowerSample?
    public let history: [Sample<PowerSample>]

    @State private var isHealthExpanded: Bool = false

    public init(
        sample: PowerSample? = nil,
        history: [Sample<PowerSample>] = []
    ) {
        self.sample = sample
        self.history = history
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluatePower(sample)
    }

    private var historyPowerDraw: [Double] {
        history.compactMap { $0.value.powerDrawWatts }
    }

    private var peakPowerDraw: Double {
        let maxHist = historyPowerDraw.max() ?? 0.0
        let cur = sample?.powerDrawWatts ?? 0.0
        return max(maxHist, cur, 30.0)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Hero Row: Battery Glyph + Battery & Charging Metrics
            HStack(alignment: .center, spacing: 14) {
                // Live Battery Glyph Illustration
                PowerBudgetIllustrationView(
                    sample: sample,
                    peakDraw: peakPowerDraw,
                    size: CGSize(width: 54, height: 64)
                )

                // High-Readability Power Metrics
                powerHeroMetrics
                Spacer(minLength: 0)
            }

            // MARK: - Power Budget Bar (Draw vs Adapter / Soft Peak)
            if let sample = sample, let draw = sample.powerDrawWatts {
                powerBudgetBar(sample: sample, draw: draw)
            }

            // MARK: - 60-Sample Power Draw History Sparkline (if draw exposed)
            if !historyPowerDraw.isEmpty {
                powerSparkline
            }

            // MARK: - Collapsible Diagnostics (Battery Health, Cycles, Condition)
            if let sample = sample, sample.hasBattery {
                CollapsibleSection(
                    title: "Battery Health",
                    count: nil,
                    isExpanded: $isHealthExpanded
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

    // MARK: - Power Hero Metrics

    @ViewBuilder
    private var powerHeroMetrics: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let sample = sample {
                if sample.hasBattery {
                    // Large Battery Charge %
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if let charge = sample.charge {
                            Text(String(format: "%.0f%%", charge))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }

                        Text(sample.state == .charging ? "Charging" : (sample.state == .charged ? "Fully Charged" : (sample.state == .acConnected ? "AC Connected" : "On Battery")))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor((sample.state == .charging || sample.state == .charged) ? .green : .secondary)

                        if sample.state == .charging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }

                    // Time Remaining or State Details
                    if let timeRemaining = sample.timeRemaining {
                        Text(formatDuration(timeRemaining) + (sample.state == .charging ? " to full" : " remaining"))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else if sample.state == .charged || (sample.state == .acConnected && (sample.charge ?? 0) >= 99.0) {
                        Text("Fully charged / On AC power")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                    } else if sample.state == .acConnected {
                        Text("Connected to power / Not charging")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    // Instantaneous Power Draw
                    if let draw = sample.powerDrawWatts {
                        Text(String(format: "Power Draw: %.1f W", draw))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.85))
                    }
                } else {
                    Text("On AC Power")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.green)

                    if let draw = sample.powerDrawWatts {
                        Text(String(format: "System Draw: %.1f W", draw))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Sampling power telemetry...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Power Sparkline

    private var powerSparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            RollingGraphView(
                values: historyPowerDraw,
                minValue: 0.0,
                maxValue: max(peakPowerDraw * 1.1, 20.0),
                tintColor: .green,
                capacity: 60,
                height: 44,
                showGrid: true
            )

            HStack {
                Text("last 2 min (draw)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "peak %.1f W", peakPowerDraw))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Power Budget Bar

    private func powerBudgetBar(sample: PowerSample, draw: Double) -> some View {
        let adapterWatts = sample.adapterWatts ?? 0
        let ceiling = adapterWatts > 0 ? Double(adapterWatts) : max(peakPowerDraw, 30.0)
        let ratio = min(max(draw / ceiling, 0.0), 1.0)

        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(ratio > 0.85 ? Color.orange : Color.green)
                        .frame(width: max(0, geo.size.width * CGFloat(ratio)))
                }
            }
            .frame(height: 5)

            HStack {
                Text(String(format: "Draw %.1f W", draw))
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                if adapterWatts > 0 {
                    Text(String(format: "Adapter %d W", adapterWatts))
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Diagnostics Content

    @ViewBuilder
    private func diagnosticsContent(sample: PowerSample) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
            if let maxCap = sample.currentMaxCapacity, let desCap = sample.designCapacity, desCap > 0 {
                let healthPct = min(Double(maxCap) / Double(desCap) * 100.0, 100.0)
                healthTile(label: "Maximum Capacity", value: String(format: "%.0f%%", healthPct), icon: "heart.fill", color: .green)
            }

            if let cycles = sample.cycleCount {
                healthTile(label: "Cycle Count", value: "\(cycles) Cycles", icon: "arrow.triangle.2.circlepath", color: .blue)
            }

            if let condition = sample.condition {
                healthTile(label: "Condition", value: condition, icon: "checkmark.seal.fill", color: .green)
            }

            if let adapter = sample.adapterWatts {
                healthTile(label: "Power Source", value: "\(adapter)W Adapter", icon: "powerplug.fill", color: .secondary)
            }
        }
        .padding(.top, 4)
    }

    private func healthTile(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }
}
