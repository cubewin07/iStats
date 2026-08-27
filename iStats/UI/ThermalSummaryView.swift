import SwiftUI
import iStatsCore

/// A detailed Thermal metrics view displaying live temperatures across CPU, GPU, memory,
/// battery, and chipset sensors, system thermal pressure, rolling history graphs, and
/// configurable °C/°F temperature unit formatting (Requirements 3.1, 3.2, 3.3, 3.4, 11.3).
public struct ThermalSummaryView: View {
    public let sample: ThermalSample?
    public let history: [Sample<ThermalSample>]
    public let temperatureUnit: Units.TemperatureUnit

    @State private var isSensorsExpanded: Bool = true

    public init(
        sample: ThermalSample? = nil,
        history: [Sample<ThermalSample>] = [],
        temperatureUnit: Units.TemperatureUnit = .celsius
    ) {
        self.sample = sample
        self.history = history
        self.temperatureUnit = temperatureUnit
    }

    /// Primary temperature sensor to feature (e.g. CPU Package or first available).
    private var primarySensor: SensorReading? {
        guard let sample = sample, !sample.sensors.isEmpty else { return nil }
        if let pkg = sample.sensors.first(where: { $0.name.contains("Package") || $0.name.contains("SoC") || $0.name.contains("CPU") }) {
            return pkg
        }
        return sample.sensors.first
    }

    /// Maximum temperature across current sensors.
    private var maxTemperature: Double? {
        sample?.sensors.map(\.celsius).max()
    }

    /// History values of the primary or max temperature in Celsius for graph rendering.
    private var historyTemperatures: [Double] {
        history.compactMap { hist in
            let sensors = hist.value.sensors
            if let pkg = sensors.first(where: { $0.name.contains("Package") || $0.name.contains("SoC") || $0.name.contains("CPU") }) {
                return pkg.celsius
            }
            return sensors.map(\.celsius).max()
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Category Icon, Title, Thermal Pressure Badge
            HStack {
                Label {
                    Text("Thermals")
                        .font(.headline)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "thermometer.medium")
                        .foregroundColor(headerColor)
                }

                Spacer()

                if let sample = sample {
                    if let pressure = sample.pressure {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(pressureColor(pressure))
                                .frame(width: 8, height: 8)
                            Text(pressure.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(pressureColor(pressure))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pressureColor(pressure).opacity(0.12))
                        .cornerRadius(4)
                    }
                } else {
                    Text("Sampling...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if let sample = sample {
                if !sample.sensors.isEmpty {
                    // Primary Metric Row: Featured Sensor & Max
                    HStack(alignment: .firstTextBaseline) {
                        if let primary = primarySensor {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(primary.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(Units.formatTemperature(primary.celsius, unit: temperatureUnit))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(temperatureColor(primary.celsius))
                            }
                        }

                        Spacer()

                        if let maxTemp = maxTemperature {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Peak Sensor")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(Units.formatTemperature(maxTemp, unit: temperatureUnit))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(temperatureColor(maxTemp))
                            }
                        }
                    }

                    // Rolling Temperature Graph (Requirements 10.2, 10.3)
                    if !historyTemperatures.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Temperature History")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let cur = primarySensor?.celsius ?? maxTemperature {
                                    Text(Units.formatTemperature(cur, unit: temperatureUnit))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            RollingGraphView(
                                values: historyTemperatures,
                                maxValue: 105.0,
                                tintColor: headerColor,
                                height: 38
                            )
                        }
                    }

                    Divider()

                    // Expandable Per-Sensor List (Requirement 3.1, 3.2)
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSensorsExpanded.toggle()
                            }
                        }) {
                            HStack {
                                Text("Sensors (\(sample.sensors.count))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: isSensorsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if isSensorsExpanded {
                            VStack(spacing: 5) {
                                ForEach(sample.sensors, id: \.name) { sensor in
                                    sensorRow(sensor)
                                }
                            }
                        }
                    }
                } else {
                    // Degraded State: Pressure available but no specific sensors (Requirement 3.3)
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Hardware temperature sensors unavailable. System thermal pressure monitored above.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("Waiting for thermal telemetry...")
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

    // MARK: - Sensor Row

    private func sensorRow(_ sensor: SensorReading) -> some View {
        HStack(spacing: 8) {
            Text(sensor.name)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Mini bar indicator (0°C to 100°C)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(temperatureColor(sensor.celsius))
                        .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(sensor.celsius / 100.0))), height: 4)
                }
            }
            .frame(width: 45, height: 4)

            Text(Units.formatTemperature(sensor.celsius, unit: temperatureUnit))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private var headerColor: Color {
        if let maxT = maxTemperature {
            return temperatureColor(maxT)
        }
        return .orange
    }

    private func pressureColor(_ pressure: ThermalPressure) -> Color {
        switch pressure {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        if celsius >= 90.0 {
            return .red
        } else if celsius >= 75.0 {
            return .orange
        } else if celsius >= 55.0 {
            return .yellow
        } else {
            return .green
        }
    }
}
