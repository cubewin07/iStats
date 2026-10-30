import SwiftUI
import iStatsCore

/// Overview of every reported fan and recent highest-fan RPM.
public struct FanSummaryView: View {
    public let sample: FanSample?
    public let history: [Sample<FanSample>]
    public let refreshInterval: TimeInterval

    public init(sample: FanSample? = nil, history: [Sample<FanSample>] = [], refreshInterval: TimeInterval = 2.0) {
        self.sample = sample
        self.history = history
        self.refreshInterval = refreshInterval
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sample = sample {
                if sample.fans.isEmpty {
                    Label("No fans detected", systemImage: "fan")
                        .font(.system(size: 13, weight: .semibold))
                    Text("This Mac may be fanless, or fan readings may not be available.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                } else {
                    ForEach(Array(sample.fans.enumerated()), id: \.offset) { _, fan in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(fan.name, systemImage: "fan")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(Units.formatRPM(fan.rpm))
                                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            }
                            if let minimum = fan.minRPM, let maximum = fan.maxRPM, maximum > minimum {
                                ProgressView(value: min(1, max(0, Double(fan.rpm - minimum) / Double(maximum - minimum))))
                                    .tint(.teal)
                                Text("Reported range: \(Units.formatRPM(minimum))–\(Units.formatRPM(maximum))")
                                    .font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    let points = history.map { item in
                        HistoryPoint(timestamp: item.timestamp, value: item.availability.isAvailable
                                     ? item.value.fans.map(\.rpm).max().map(Double.init) : nil)
                    }
                    let maxRPM = max(1, points.compactMap(\.value).max() ?? 1)
                    Text("Highest reported fan speed")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                    TimestampedHistoryGraph(timeline: HistoryTimeline(points: points, expectedInterval: refreshInterval),
                                            maxValue: maxRPM, tintColor: .teal, height: 44)
                }
            } else {
                Text("Waiting for fan readings…").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }
}
