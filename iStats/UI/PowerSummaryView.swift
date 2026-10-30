import SwiftUI
import iStatsCore

/// Battery state and reported power readings without inferred adapter balance.
public struct PowerSummaryView: View {
    public let sample: PowerSample?
    public let history: [Sample<PowerSample>]
    public let refreshInterval: TimeInterval
    @State private var isHealthExpanded = false

    public init(sample: PowerSample? = nil, history: [Sample<PowerSample>] = [], refreshInterval: TimeInterval = 2.0) {
        self.sample = sample
        self.history = history
        self.refreshInterval = refreshInterval
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sample = sample {
                if sample.hasBattery {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "battery.100percent").foregroundColor(.green)
                        Text(sample.charge.map { String(format: "%.0f%%", $0) } ?? "Unavailable")
                            .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                        Spacer()
                        Text(stateLabel(sample.state)).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    }
                    if let charge = sample.charge {
                        ProgressView(value: min(1, max(0, charge / 100))).tint(.green)
                    }
                    if let time = sample.timeRemaining, time > 0, time < 86400,
                       sample.state == .charging || sample.state == .discharging {
                        Text("Estimated \(Int(time / 60)) min \(sample.state == .charging ? "to full" : "remaining")")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    CollapsibleSection(title: "Battery health", count: nil, isExpanded: $isHealthExpanded) {
                        VStack(spacing: 5) {
                            detailRow("Condition", sample.condition)
                            detailRow("Cycle count", sample.cycleCount.map(String.init))
                            if let current = sample.currentMaxCapacity, let design = sample.designCapacity, design > 0 {
                                detailRow("Capacity estimate", String(format: "%.0f%% of design", Double(current) / Double(design) * 100))
                                Text("Calculated from reported maximum and design capacities.")
                                    .font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Label("No internal battery reported", systemImage: "powerplug")
                        .font(.system(size: 12, weight: .semibold))
                }
                detailRow("Power reading", sample.powerDrawWatts.map { String(format: "%.1f W", $0) })
            } else {
                Text("Waiting for power readings…").font(.system(size: 11)).foregroundColor(.secondary)
            }
            let points = history.map { item in
                HistoryPoint(timestamp: item.timestamp, value: item.availability.isAvailable ? item.value.powerDrawWatts : nil)
            }
            if points.contains(where: { $0.value != nil }) {
                Text("Reported power over time").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                TimestampedHistoryGraph(timeline: HistoryTimeline(points: points, expectedInterval: refreshInterval),
                                        maxValue: max(1, points.compactMap(\.value).max() ?? 1), tintColor: .orange, height: 44)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func stateLabel(_ state: BatteryState?) -> String {
        switch state {
        case .charging: return "Charging"
        case .discharging: return "On battery"
        case .charged: return "Charged"
        case .acConnected: return "Connected to power"
        case .unknown, nil: return "State unavailable"
        }
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value ?? "Unavailable").fontWeight(.medium).monospacedDigit()
        }.font(.system(size: 10)).accessibilityElement(children: .combine)
    }
}
