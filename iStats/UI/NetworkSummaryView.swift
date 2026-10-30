import SwiftUI
import iStatsCore

/// Current traffic across monitored interfaces and timestamped direction trends.
public struct NetworkSummaryView: View {
    public let sample: NetworkSample?
    public let history: [Sample<NetworkSample>]
    public let networkUnit: Units.NetworkUnit
    public let byteStandard: Units.ByteUnitStandard
    public let refreshInterval: TimeInterval

    public init(sample: NetworkSample? = nil, history: [Sample<NetworkSample>] = [],
                networkUnit: Units.NetworkUnit = .bytesPerSecond,
                byteStandard: Units.ByteUnitStandard = .iec, refreshInterval: TimeInterval = 2.0) {
        self.sample = sample
        self.history = history
        self.networkUnit = networkUnit
        self.byteStandard = byteStandard
        self.refreshInterval = refreshInterval
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sample = sample {
                HStack {
                    Image(systemName: sample.primaryType?.iconName ?? "network")
                    Text(sample.primaryInterface ?? "Primary interface unavailable")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(sample.primaryType?.displayName ?? "")
                        .foregroundColor(.secondary)
                }.font(.system(size: 11))
                HStack(spacing: 12) {
                    rate("↓ Download", sample.totalBytesInPerSec, color: .teal)
                    rate("↑ Upload", sample.totalBytesOutPerSec, color: .blue)
                }
                Text("Rates sum monitored interfaces and may include VPN traffic.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let address = sample.localIPv4 {
                    HStack { Text("Local IPv4").foregroundColor(.secondary); Spacer(); Text(address).monospacedDigit() }
                        .font(.system(size: 10))
                }
            } else {
                Text("Waiting for network readings…").font(.system(size: 11)).foregroundColor(.secondary)
            }
            historyGraph("↓ Download", inbound: true, color: .teal)
            historyGraph("↑ Upload", inbound: false, color: .blue)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func rate(_ label: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            Text(Units.formatNetworkRate(value, unit: networkUnit, standard: byteStandard))
                .font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundColor(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private func historyGraph(_ label: String, inbound: Bool, color: Color) -> some View {
        let points = history.map { item in
            HistoryPoint(timestamp: item.timestamp, value: item.availability.isAvailable
                         ? (inbound ? item.value.totalBytesInPerSec : item.value.totalBytesOutPerSec) : nil)
        }
        let maxRate = max(1, points.compactMap(\.value).max() ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            TimestampedHistoryGraph(timeline: HistoryTimeline(points: points, expectedInterval: refreshInterval),
                                    maxValue: maxRate, tintColor: color, height: 38)
        }
    }
}
