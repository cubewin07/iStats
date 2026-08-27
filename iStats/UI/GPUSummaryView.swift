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
            // Header: Icon, Category Name, Aggregate Percentage
            HStack {
                Label {
                    Text("GPU")
                        .font(.headline)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "display")
                        .foregroundColor(.purple)
                }

                Spacer()

                if let sample = sample, let util = sample.utilization {
                    Text(String(format: "%.1f%%", util))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(usageColor(for: util))
                } else if sample != nil {
                    Text("Active")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Sampling...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if hasAnyMetrics {
                // Rolling Short-Term History Graph (Requirement 10.2)
                if !historyPercentages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        RollingGraphView(
                            values: historyPercentages,
                            minValue: 0.0,
                            maxValue: 100.0,
                            tintColor: .purple,
                            capacity: 60,
                            height: 48,
                            showGrid: true
                        )

                        HStack {
                            Text("60s history")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Spacer()
                            if let maxVal = historyPercentages.max() {
                                Text(String(format: "Peak: %.1f%%", maxVal))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Core Metrics Grid
                VStack(spacing: 8) {
                    if let util = sample?.utilization {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Core Utilization")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f%%", util))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.purple.opacity(0.15))
                                        .frame(height: 6)

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(usageColor(for: util))
                                        .frame(width: geo.size.width * CGFloat(util / 100.0), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }

                    // Key Telemetry Row
                    HStack(spacing: 12) {
                        if let mem = sample?.memoryUsed {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Memory Used")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(Units.formatBytes(mem, standard: byteStandard))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                        }

                        if let temp = sample?.tempCelsius {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Temperature")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(Units.formatTemperature(temp, unit: temperatureUnit))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(tempColor(temp))
                            }
                        }

                        if let pwr = sample?.powerWatts {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Power Draw")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f W", pwr))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()
                    }
                    .padding(.top, 2)
                }
            } else if sample == nil {
                // Loading / sampling state
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Reading GPU statistics...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                // Graceful degradation when GPU metrics unavailable
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("GPU performance metrics unavailable on this hardware.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
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
