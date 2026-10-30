import SwiftUI
import iStatsCore

/// Root (or first reported) volume capacity and aggregate block-device activity.
public struct DiskSummaryView: View {
    public let sample: DiskSample?
    public let history: [Sample<DiskSample>]
    public let byteStandard: Units.ByteUnitStandard
    public let refreshInterval: TimeInterval

    public init(sample: DiskSample? = nil, history: [Sample<DiskSample>] = [],
                byteStandard: Units.ByteUnitStandard = .iec, refreshInterval: TimeInterval = 2.0) {
        self.sample = sample
        self.history = history
        self.byteStandard = byteStandard
        self.refreshInterval = refreshInterval
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let volume = sample?.volumes.first(where: { $0.mountPoint == "/" }) ?? sample?.volumes.first {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(volume.name).font(.system(size: 12, weight: .semibold))
                        Text(volume.mountPoint).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(Units.formatBytes(volume.free, standard: byteStandard)) free")
                        .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                if volume.total > 0 {
                    ProgressView(value: min(1, Double(volume.used) / Double(volume.total))).tint(.blue)
                    Text("\(Units.formatBytes(volume.used, standard: byteStandard)) used of \(Units.formatBytes(volume.total, standard: byteStandard))")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            } else {
                Text(sample == nil ? "Waiting for storage readings…" : "No mounted volumes reported.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Divider()
            HStack {
                rate("Read", sample?.io?.bytesReadPerSec)
                rate("Write", sample?.io?.bytesWrittenPerSec)
            }
            Text("Aggregate block-device activity, not per-volume I/O.")
                .font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let points = history.map { item in
                HistoryPoint(timestamp: item.timestamp, value: item.availability.isAvailable ? item.value.io.map { $0.bytesReadPerSec + $0.bytesWrittenPerSec } : nil)
            }
            Text("Total read + write").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            TimestampedHistoryGraph(timeline: HistoryTimeline(points: points, expectedInterval: refreshInterval),
                                    maxValue: max(1, points.compactMap(\.value).max() ?? 1), tintColor: .blue, height: 44)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func rate(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).foregroundColor(.secondary)
            Text(value.map { Units.formatDiskRate($0, standard: byteStandard) } ?? "Unavailable")
                .fontWeight(.semibold).monospacedDigit()
        }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
