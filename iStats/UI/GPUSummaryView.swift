import SwiftUI
import iStatsCore

/// GPU utilization, optional engine readings and graphics memory telemetry.
public struct GPUSummaryView: View {
    public let sample: GPUSample?
    public let history: [Sample<GPUSample>]
    public let temperatureUnit: Units.TemperatureUnit
    public let byteStandard: Units.ByteUnitStandard
    public let refreshInterval: TimeInterval

    public init(sample: GPUSample? = nil, history: [Sample<GPUSample>] = [],
                temperatureUnit: Units.TemperatureUnit = .celsius,
                byteStandard: Units.ByteUnitStandard = .iec, refreshInterval: TimeInterval = 2.0) {
        self.sample = sample
        self.history = history
        self.temperatureUnit = temperatureUnit
        self.byteStandard = byteStandard
        self.refreshInterval = refreshInterval
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: MetricCategory.gpu.systemImageName).foregroundColor(.purple)
                Text(sample?.deviceName ?? "Graphics processor").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                if let count = sample?.coreCount { Text("\(count) cores").font(.system(size: 10)).foregroundColor(.secondary) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(sample?.utilization.map { String(format: "%.0f%%", $0) } ?? "Unavailable")
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("GPU utilization").font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
            }
            let points = history.map { item in
                HistoryPoint(timestamp: item.timestamp, value: item.availability.isAvailable ? item.value.utilization : nil)
            }
            TimestampedHistoryGraph(timeline: HistoryTimeline(points: points, expectedInterval: refreshInterval),
                                    maxValue: 100, tintColor: .purple, height: 44)
            if let sample = sample {
                if let renderer = sample.rendererUtilization { row("Renderer", String(format: "%.0f%%", renderer)) }
                if let tiler = sample.tilerUtilization { row("Tiler", String(format: "%.0f%%", tiler)) }
                if let memory = sample.memoryUsed { row("GPU memory used", Units.formatBytes(memory, standard: byteStandard)) }
                if let allocated = sample.allocatedMemory { row("Allocated memory", Units.formatBytes(allocated, standard: byteStandard)) }
                if sample.isUnifiedMemory == true {
                    Text("Graphics memory is shared with the system.").font(.system(size: 10)).foregroundColor(.secondary)
                }
                if let temp = sample.tempCelsius { row("Temperature", Units.formatTemperature(temp, unit: temperatureUnit, fractionDigits: 1)) }
                if let watts = sample.powerWatts { row("Power", String(format: "%.1f W", watts)) }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundColor(.secondary); Spacer(); Text(value).fontWeight(.medium).monospacedDigit() }
            .font(.system(size: 11)).accessibilityElement(children: .combine)
    }
}
