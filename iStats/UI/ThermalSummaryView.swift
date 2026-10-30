import SwiftUI
import iStatsCore

/// Reports actual sensor values and the operating-system thermal pressure state.
public struct ThermalSummaryView: View {
    public let sample: ThermalSample?
    public let history: [Sample<ThermalSample>]
    public let temperatureUnit: Units.TemperatureUnit
    public let refreshInterval: TimeInterval
    @State private var isSensorsExpanded = false

    public init(sample: ThermalSample? = nil, history: [Sample<ThermalSample>] = [],
                temperatureUnit: Units.TemperatureUnit = .celsius, refreshInterval: TimeInterval = 2.0) {
        self.sample = sample
        self.history = history
        self.temperatureUnit = temperatureUnit
        self.refreshInterval = refreshInterval
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sensor = sample?.sensors.max(by: { $0.celsius < $1.celsius }) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hottest reported sensor").font(.system(size: 10)).foregroundColor(.secondary)
                        Text(sensor.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    Spacer()
                    Text(Units.formatTemperature(sensor.celsius, unit: temperatureUnit, fractionDigits: 1))
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text(sample == nil ? "Waiting for temperature readings…" : "No temperature sensors reported.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            HStack {
                Text("macOS thermal pressure").foregroundColor(.secondary)
                Spacer()
                Text(sample?.pressure?.displayName ?? "Unavailable").fontWeight(.medium)
            }.font(.system(size: 11))

            let points = history.map { item in
                HistoryPoint(timestamp: item.timestamp, value: item.availability.isAvailable
                             ? item.value.sensors.map(\.celsius).max() : nil)
            }
            let maxTemp = points.compactMap(\.value).max() ?? 80
            Text("Highest sensor over time").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            TimestampedHistoryGraph(timeline: HistoryTimeline(points: points, expectedInterval: refreshInterval),
                                    minValue: 0, maxValue: max(100, maxTemp + 5), tintColor: .orange, height: 44)
            Text("The hottest sensor can change between samples.")
                .font(.system(size: 10)).foregroundColor(.secondary)

            if let sensors = sample?.sensors, !sensors.isEmpty {
                CollapsibleSection(title: "Sensors", count: sensors.count, isExpanded: $isSensorsExpanded) {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(Array(sensors.sorted { $0.celsius > $1.celsius }.enumerated()), id: \.offset) { _, sensor in
                                HStack {
                                    Text(sensor.name).lineLimit(1)
                                    Spacer()
                                    Text(Units.formatTemperature(sensor.celsius, unit: temperatureUnit, fractionDigits: 1)).monospacedDigit()
                                }.font(.system(size: 10)).accessibilityElement(children: .combine)
                            }
                        }
                    }.frame(maxHeight: 180)
                }
            }
        }
    }
}
