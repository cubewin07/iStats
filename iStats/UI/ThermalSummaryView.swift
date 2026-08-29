import SwiftUI
import iStatsCore

/// A Thermal metrics card view:
/// 1. Enlarged 4-Zone Mac Heat Map Silhouette (CPU, GPU, RAM, SSD)
/// 2. High-Contrast Peak Sensor Card (Hottest component readout)
/// 3. 60-sample temperature sparkline & collapsible diagnostics (Sensors list).
public struct ThermalSummaryView: View {
    public let sample: ThermalSample?
    public let history: [Sample<ThermalSample>]
    public let temperatureUnit: Units.TemperatureUnit

    @State private var isSensorsExpanded: Bool = false

    public init(
        sample: ThermalSample? = nil,
        history: [Sample<ThermalSample>] = [],
        temperatureUnit: Units.TemperatureUnit = .celsius
    ) {
        self.sample = sample
        self.history = history
        self.temperatureUnit = temperatureUnit
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateThermal(sample, unit: temperatureUnit)
    }

    private var maxSensor: SensorReading? {
        sample?.sensors.max(by: { $0.celsius < $1.celsius })
    }

    private var historyTemperatures: [Double] {
        history.compactMap { hist in
            let sensors = hist.value.sensors
            return sensors.map(\.celsius).max()
        }
    }

    private var peakColor: Color {
        guard let maxS = maxSensor else { return .secondary }
        if maxS.celsius >= 95.0 { return .red }
        if maxS.celsius >= 80.0 { return .orange }
        if maxS.celsius >= 68.0 { return .yellow }
        return .teal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Hero Row: Enlarged 4-Zone Heat Map + High-Contrast Peak Sensor Card
            HStack(alignment: .center, spacing: 10) {
                // Live 4-Zone Mac Silhouette Heat Map (CPU, GPU, RAM, SSD)
                ThermalHeatMapIllustrationView(
                    sample: sample,
                    temperatureUnit: temperatureUnit,
                    size: CGSize(width: 148, height: 86)
                )

                // High-Contrast Peak Thermal Sensor Card
                if let maxS = maxSensor {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        peakColor.opacity(0.20),
                                        peakColor.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(peakColor.opacity(0.45), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 3.5) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(peakColor)

                                Text("PEAK SENSOR")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(peakColor)
                            }

                            Text(Units.formatTemperature(maxS.celsius, unit: temperatureUnit, fractionDigits: 0))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(peakColor)

                            Text(cleanSensorName(maxS.name))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text("Hottest Component")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 86)
                } else {
                    Text("Monitoring thermals...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - 60-Sample Temperature Sparkline
            VStack(alignment: .leading, spacing: 4) {
                RollingGraphView(
                    values: historyTemperatures,
                    minValue: 20.0,
                    maxValue: max(100.0, (historyTemperatures.max() ?? 80.0) + 5.0),
                    tintColor: verdict.level.color,
                    capacity: 60,
                    height: 44,
                    showGrid: true
                )

                HStack {
                    Text("last 2 min (peak history)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let maxHist = historyTemperatures.max() {
                        Text("peak \(Units.formatTemperature(maxHist, unit: temperatureUnit, fractionDigits: 0))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 2)
            }

            // MARK: - Collapsible Diagnostics (33 Individual Sensor Keys)
            if let sample = sample, !sample.sensors.isEmpty {
                CollapsibleSection(
                    title: "Sensors",
                    count: sample.sensors.count,
                    isExpanded: $isSensorsExpanded
                ) {
                    sensorsList(sample: sample)
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

    // MARK: - Sensors List

    @ViewBuilder
    private func sensorsList(sample: ThermalSample) -> some View {
        VStack(spacing: 3) {
            ForEach(sample.sensors.sorted(by: { $0.celsius > $1.celsius }), id: \.name) { sensor in
                HStack {
                    Text(cleanSensorName(sensor.name))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(Units.formatTemperature(sensor.celsius, unit: temperatureUnit, fractionDigits: 1))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(sensorColor(sensor.celsius))
                }
                .padding(.vertical, 1.5)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.04))
                )
            }
        }
        .padding(.top, 4)
    }

    private func cleanSensorName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "Thermal Sensor", with: "")
            .replacingOccurrences(of: "Die Temperature", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func sensorColor(_ celsius: Double) -> Color {
        if celsius >= 95.0 { return .red }
        if celsius >= 82.0 { return .orange }
        if celsius >= 68.0 { return .yellow }
        return .primary
    }
}
