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

    private var batteryHealthPercentage: Int? {
        guard let maxCap = sample?.currentMaxCapacity, let designCap = sample?.designCapacity, designCap > 0 else { return nil }
        return min(100, Int(round(Double(maxCap) / Double(designCap) * 100.0)))
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

            // MARK: - 60-Sample Power Draw History Sparkline (if draw exposed)
            if !historyPowerDraw.isEmpty {
                powerSparkline
            }

            // MARK: - Collapsible Battery Details
            if let sample = sample, sample.hasBattery {
                CollapsibleSection(
                    title: "Battery Details",
                    count: nil,
                    isExpanded: $isHealthExpanded
                ) {
                    batteryDetailsContent(sample: sample)
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
        VStack(alignment: .leading, spacing: 6) {
            if let sample = sample {
                if sample.hasBattery {
                    // Primary Hero Status / Live Power Draw & Adapter
                    HStack(alignment: .firstTextBaseline) {
                        if sample.state == .charging {
                            if let draw = sample.powerDrawWatts {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.1f W", draw))
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                        .foregroundColor(.green)

                                    Text("Charging")
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)

                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            } else if let timeRemaining = sample.timeRemaining, timeRemaining > 0 {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(formatDuration(timeRemaining))
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                        .foregroundColor(.green)

                                    Text("until full")
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)

                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("Charging")
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                        .foregroundColor(.green)

                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            }
                        } else if sample.state == .acConnected || sample.state == .charged {
                            if let draw = sample.powerDrawWatts {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.1f W", draw))
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)

                                    Text("Draw")
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Power Connected")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                        } else {
                            // On battery / discharging
                            if let timeRemaining = sample.timeRemaining, timeRemaining > 0 {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(formatDuration(timeRemaining))
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)

                                    Text("remaining")
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            } else if let draw = sample.powerDrawWatts {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.1f W", draw))
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)

                                    Text("Draw")
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("On Battery")
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                        }

                        Spacer(minLength: 8)

                        if let adapter = sample.adapterWatts, adapter > 0 {
                            let adapterWatts = Int(round(adapter))
                            Text("\(adapterWatts)W Adapter")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.12))
                                )
                        } else if sample.state != .charging && sample.state != .acConnected && sample.state != .charged {
                            if let time = sample.timeRemaining, time > 0, let draw = sample.powerDrawWatts {
                                Text(String(format: "%.1f W Draw", draw))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Integrated Power Budget Bar (bridges Draw to Adapter limit)
                    if let adapter = sample.adapterWatts, adapter > 0, let draw = sample.powerDrawWatts {
                        let ceiling = max(adapter, 10.0)
                        let ratio = min(max(draw / ceiling, 0.0), 1.0)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))

                                Capsule()
                                    .fill(ratio > 0.85 ? Color.orange : Color.green)
                                    .frame(width: max(3, geo.size.width * CGFloat(ratio)))
                            }
                        }
                        .frame(height: 4.5)
                    }

                    // Prominent Diagnostics Badges (Health & Cycles - spacious and un-truncated)
                    HStack(spacing: 8) {
                        if let health = batteryHealthPercentage {
                            heroBadge(icon: "heart.fill", text: "\(health)% Health", color: .pink)
                        }
                        if let cycles = sample.cycleCount, cycles > 0 {
                            heroBadge(icon: "arrow.triangle.2.circlepath", text: "\(cycles) Cycles", color: .blue)
                        } else if let condition = sample.condition, batteryHealthPercentage == nil {
                            heroBadge(icon: "checkmark.seal.fill", text: condition, color: .green)
                        }
                    }
                } else {
                    // Desktop Mac
                    HStack(alignment: .firstTextBaseline) {
                        if let draw = sample.powerDrawWatts {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f W", draw))
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                Text("System Draw")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("System Powered")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                        }

                        Spacer(minLength: 8)

                        if let adapter = sample.adapterWatts, adapter > 0 {
                            let adapterWatts = Int(round(adapter))
                            Text("\(adapterWatts)W Supply")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.12))
                                )
                        }
                    }

                    if let adapter = sample.adapterWatts, adapter > 0, let draw = sample.powerDrawWatts {
                        let ceiling = max(adapter, 10.0)
                        let ratio = min(max(draw / ceiling, 0.0), 1.0)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))

                                Capsule()
                                    .fill(ratio > 0.85 ? Color.orange : Color.green)
                                    .frame(width: max(3, geo.size.width * CGFloat(ratio)))
                            }
                        }
                        .frame(height: 4.5)
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

    // MARK: - Battery Details Content

    @ViewBuilder
    private func batteryDetailsContent(sample: PowerSample) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
            if let maxCap = sample.currentMaxCapacity, maxCap > 0 {
                detailTile(label: "Full Capacity", value: "\(formatNumber(maxCap)) mAh", icon: "battery.100", color: .green)
            }

            if let desCap = sample.designCapacity, desCap > 0 {
                detailTile(label: "Design Capacity", value: "\(formatNumber(desCap)) mAh", icon: "chart.bar.fill", color: .blue)
            }

            if let voltage = sample.voltageVolts {
                detailTile(label: "Voltage", value: String(format: "%.2f V", voltage), icon: "bolt.fill", color: .yellow)
            } else if let adapter = sample.adapterWatts, adapter > 0 {
                detailTile(label: "Power Source", value: "\(Int(round(adapter)))W Adapter", icon: "powerplug.fill", color: .secondary)
            }

            if let condition = sample.condition {
                detailTile(label: "Condition", value: condition, icon: "checkmark.seal.fill", color: .green)
            }
        }
        .padding(.top, 4)
    }

    private func detailTile(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
                .foregroundColor(color)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
    }

    private func formatNumber(_ number: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: number), number: .decimal)
    }

    private func heroBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
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
