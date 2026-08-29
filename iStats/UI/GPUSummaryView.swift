import SwiftUI
import iStatsCore

/// A GPU metrics card view:
/// 1. Filling GPU Die Illustration + 3-pill stats row (VRAM, Temp, Watts)
/// 2. Core utilization hero with prominent font
/// 3. 60-sample utilization sparkline & collapsible diagnostics.
public struct GPUSummaryView: View {
    public let sample: GPUSample?
    public let history: [Sample<GPUSample>]
    public let temperatureUnit: Units.TemperatureUnit
    public let byteStandard: Units.ByteUnitStandard

    @State private var isDetailsExpanded: Bool = false

    public init(
        sample: GPUSample? = nil,
        history: [Sample<GPUSample>] = [],
        temperatureUnit: Units.TemperatureUnit = .celsius,
        byteStandard: Units.ByteUnitStandard = .iec
    ) {
        self.sample = sample
        self.history = history
        self.temperatureUnit = temperatureUnit
        self.byteStandard = byteStandard
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateGPU(sample)
    }

    private var historyPercentages: [Double] {
        history.compactMap { $0.value.utilization }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Hero Row: GPU Die + Utilization & Stat Tags
            HStack(alignment: .center, spacing: 14) {
                // Live Filling GPU Die Illustration
                GPUDieIllustrationView(
                    sample: sample,
                    temperatureUnit: temperatureUnit,
                    byteStandard: byteStandard,
                    size: 68,
                    showPills: false
                )

                // High-Readability GPU Metrics
                VStack(alignment: .leading, spacing: 3) {
                    if let sample = sample {
                        if let util = sample.utilization {
                            // Large Utilization Hero
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.0f%%", util))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                Text("Core Load")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Graphics Active")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.purple)
                        }

                        // 3 Compact Captions (VRAM, Temp, Watts)
                        HStack(spacing: 5) {
                            if let mem = sample.memoryUsed {
                                statTag(icon: "memorychip", text: Units.formatBytes(mem, standard: byteStandard, fractionDigits: 1))
                            }
                            if let temp = sample.tempCelsius {
                                statTag(icon: "thermometer.medium", text: Units.formatTemperature(temp, unit: temperatureUnit, fractionDigits: 0))
                            }
                            if let watts = sample.powerWatts {
                                statTag(icon: "bolt.fill", text: String(format: "%.0f W", watts))
                            }
                        }
                        .padding(.top, 2)
                    } else {
                        Text("Sampling graphics telemetry...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            // MARK: - 60-Sample GPU History Sparkline (if utilization available)
            if !historyPercentages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    RollingGraphView(
                        values: historyPercentages,
                        minValue: 0.0,
                        maxValue: 100.0,
                        tintColor: .purple,
                        capacity: 60,
                        height: 44,
                        showGrid: true
                    )

                    HStack {
                        Text("last 2 min")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        if let maxHist = historyPercentages.max() {
                            Text(String(format: "peak %.0f%%", maxHist))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            // MARK: - Collapsible Diagnostics (Unified Memory & Power)
            if let sample = sample {
                CollapsibleSection(
                    title: "Details",
                    count: nil,
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

    // MARK: - Stat Tag

    private func statTag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(.purple)
            Text(text)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.purple.opacity(0.10))
        )
    }

    // MARK: - Diagnostics Content

    @ViewBuilder
    private func diagnosticsContent(sample: GPUSample) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
            if let mem = sample.memoryUsed {
                tile(label: "VRAM Used", value: Units.formatBytes(mem, standard: byteStandard), icon: "memorychip")
            }
            if let temp = sample.tempCelsius {
                tile(label: "GPU Temp", value: Units.formatTemperature(temp, unit: temperatureUnit, fractionDigits: 1), icon: "thermometer.medium")
            }
            if let watts = sample.powerWatts {
                tile(label: "Power Draw", value: String(format: "%.1f W", watts), icon: "bolt.fill")
            }
        }
        .padding(.top, 4)
    }

    private func tile(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
                .foregroundColor(.purple)
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
}
