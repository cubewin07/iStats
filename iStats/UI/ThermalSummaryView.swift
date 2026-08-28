import SwiftUI
import iStatsCore

/// A detailed Thermal metrics view displaying live temperatures across CPU, GPU, memory,
/// battery, and chipset sensors, system thermal pressure, rolling history graphs, and
/// configurable °C/°F temperature unit formatting (Requirements 3.1, 3.2, 3.3, 3.4, 11.3).
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
            // Hero Temperature Card
            if let sample = sample, !sample.sensors.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(primarySensor?.name ?? "Primary SoC Sensor")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)

                        if let primary = primarySensor {
                            Text(Units.formatTemperature(primary.celsius, unit: temperatureUnit))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(temperatureColor(primary.celsius))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        if let pressure = sample.pressure {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(pressureColor(pressure))
                                    .frame(width: 5, height: 5)
                                Text("Thermal: \(pressure.displayName)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(pressureColor(pressure))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(pressureColor(pressure).opacity(0.12))
                            .clipShape(Capsule())
                        }

                        if let maxTemp = maxTemperature {
                            Text("Peak: \(Units.formatTemperature(maxTemp, unit: temperatureUnit, fractionDigits: 1))")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Rolling 60s Temperature History Graph
                if !historyTemperatures.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        RollingGraphView(
                            values: historyTemperatures,
                            minValue: 20.0,
                            maxValue: max(100.0, (historyTemperatures.max() ?? maxTemperature ?? 80.0) + 5.0),
                            tintColor: headerColor,
                            capacity: 60,
                            height: 44,
                            showGrid: true
                        )

                        HStack {
                            Text("Temperature History")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            if let cur = primarySensor?.celsius ?? maxTemperature {
                                Text("Current: \(Units.formatTemperature(cur, unit: temperatureUnit, fractionDigits: 1))")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Expandable Per-Sensor List
                sensorsSection(sensors: sample.sensors)
            } else if let sample = sample, sample.sensors.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Hardware temperature sensors unavailable. System thermal pressure monitored above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                Text("Waiting for thermal telemetry...")
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

    // MARK: - Sensors Section

    private func sensorsSection(sensors: [SensorReading]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSensorsExpanded.toggle()
                }
            }) {
                HStack {
                    Text("All Sensors (\(sensors.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isSensorsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isSensorsExpanded {
                VStack(spacing: 4) {
                    ForEach(sensors, id: \.name) { sensor in
                        sensorRow(sensor)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
    }

    private func sensorRow(_ sensor: SensorReading) -> some View {
        HStack(spacing: 6) {
            Text(sensor.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Mini horizontal thermal gauge bar (20°C to 100°C)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 4)

                    Capsule()
                        .fill(temperatureColor(sensor.celsius))
                        .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(min(max(sensor.celsius, 0), 100) / 100.0))), height: 4)
                }
            }
            .frame(width: 50, height: 4)

            Text(Units.formatTemperature(sensor.celsius, unit: temperatureUnit, fractionDigits: 1))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 2.5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.05))
        )
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

