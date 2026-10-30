import SwiftUI
import iStatsCore

/// CPU utilization, user/system breakdown, recent history and core activity.
public struct CPUSummaryView: View {
    public let sample: CPUSample?
    public let history: [Sample<CPUSample>]
    @State private var isCoresExpanded = false

    public init(sample: CPUSample? = nil, history: [Sample<CPUSample>] = []) {
        self.sample = sample
        self.history = history
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(sample.map { String(format: "%.0f%%", $0.totalUsage) } ?? "—")
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("CPU utilization").font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
            }
            let points = history.map { item in
                HistoryPoint(timestamp: item.timestamp, value: item.availability.isAvailable ? item.value.totalUsage : nil)
            }
            // The overview has no preference dependency; use observed sample cadence
            // for gap detection rather than assuming a fixed refresh setting.
            let intervals = zip(history, history.dropFirst()).map { pair in pair.1.timestamp.timeIntervalSince(pair.0.timestamp) }.filter { $0 > 0 }.sorted()
            let cadence = intervals.isEmpty ? 2 : intervals[intervals.count / 2]
            TimestampedHistoryGraph(timeline: HistoryTimeline(points: points, expectedInterval: cadence), maxValue: 100, tintColor: .blue, height: 44)
            if let sample = sample {
                HStack {
                    metric("User", sample.user)
                    metric("System", sample.system)
                    metric("Idle", sample.idle)
                }
                if let load = sample.loadAverage {
                    HStack {
                        Text("Load average · 1 / 5 / 15 min").foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f / %.2f / %.2f", load.oneMinute, load.fiveMinute, load.fifteenMinute))
                            .fontWeight(.medium).monospacedDigit()
                    }.font(.system(size: 10))
                }
                if !sample.perCore.isEmpty {
                    CollapsibleSection(title: "Cores", count: sample.perCore.count, isExpanded: $isCoresExpanded) {
                        VStack(spacing: 4) {
                            ForEach(Array(sample.perCore.enumerated()), id: \.offset) { index, usage in
                                HStack {
                                    Text("Core \(index + 1)")
                                    Spacer()
                                    Text(String(format: "%.0f%%", usage)).monospacedDigit()
                                }.font(.system(size: 10)).accessibilityElement(children: .combine)
                                ProgressView(value: min(1, max(0, usage / 100))).tint(.blue)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundColor(.secondary)
            Text(String(format: "%.0f%%", value)).fontWeight(.semibold).monospacedDigit()
        }.font(.system(size: 10)).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
