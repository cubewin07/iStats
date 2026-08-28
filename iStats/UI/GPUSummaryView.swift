import SwiftUI
import iStatsCore

/// A detailed GPU metrics card view displaying live core utilization, rolling history graphs,
/// memory consumption (VRAM / unified memory), GPU temperature, and power draw
/// (Requirements 5.1, 5.2, 5.3, 10.1, 10.2).
public struct GPUSummaryView: View {
    public let sample: GPUSample?
    public let history: [Sample<GPUSample>]
    public let temperatureUnit: Units.TemperatureUnit
    public let byteStandard: Units.ByteUnitStandard

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

    private var historyPercentages: [Double] {
        history.compactMap { $0.value.utilization }
    }

    private var hasAnyMetrics: Bool {
        guard let s = sample else { return false }
        return s.utilization != nil || s.memoryUsed != nil || s.tempCelsius != nil || s.powerWatts != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hero Metric Row: Core Utilization % and Status Badge
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("GPU Core Activity")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    if let sample = sample, let util = sample.utilization {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", util))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(usageColor(for: util))

                            Text("%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(usageColor(for: util))
                        }
                    } else if sample != nil {
                        Text("Active")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.purple)
                    } else {
                        Text("Sampling...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let sample = sample {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 6, height: 6)
                            Text("Renderer")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.purple)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())

                        if let util = sample.utilization {
                            Text(util > 5.0 ? "Under Load" : "Idle")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if hasAnyMetrics {
                // Utilization Progress Bar
                if let util = sample?.utilization {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 5)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(0.8), usageColor(for: util)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * CGFloat(util / 100.0)), height: 5)
                        }
                    }
                    .frame(height: 5)
                }

                // Rolling 60s GPU Activity Graph
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
                            Text("GPU Activity History")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            if let maxVal = historyPercentages.max() {
                                Text(String(format: "Peak: %.1f%%", maxVal))
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Key Telemetry Row (VRAM, Temperature, Power Draw)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    telemetryCard(
                        title: "Memory Used",
                        value: sample?.memoryUsed != nil ? Units.formatBytes(sample!.memoryUsed!, standard: byteStandard, fractionDigits: 1) : "—",
                        color: .purple,
                        icon: "memorychip"
                    )

                    telemetryCard(
                        title: "Temperature",
                        value: sample?.tempCelsius != nil ? Units.formatTemperature(sample!.tempCelsius!, unit: temperatureUnit, fractionDigits: 0) : "—",
                        color: sample?.tempCelsius != nil ? tempColor(sample!.tempCelsius!) : .secondary,
                        icon: "thermometer.medium"
                    )

                    telemetryCard(
                        title: "Power Draw",
                        value: sample?.powerWatts != nil ? String(format: "%.1f W", sample!.powerWatts!) : "—",
                        color: sample?.powerWatts != nil ? .orange : .secondary,
                        icon: "bolt.fill"
                    )
                }
            } else if sample == nil {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Reading GPU statistics...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("GPU performance metrics unavailable on this hardware.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

    // MARK: - Telemetry Card

    private func telemetryCard(title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Color Helpers

    private func usageColor(for percentage: Double) -> Color {
        switch percentage {
        case ..<50.0:
            return .purple
        case 50.0..<80.0:
            return .orange
        default:
            return .red
        }
    }

    private func tempColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60.0:
            return .green
        case 60.0..<80.0:
            return .orange
        default:
            return .red
        }
    }
}

