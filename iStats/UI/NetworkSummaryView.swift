import SwiftUI
import iStatsCore

/// A comprehensive Network metrics view displaying aggregate throughput, live rolling history graph,
/// session cumulative transfer totals, and per-interface bandwidth breakdown (Requirements 6.1-6.4, 10.1, 11.3).
public struct NetworkSummaryView: View {
    public let sample: NetworkSample?
    public let history: [Sample<NetworkSample>]
    public let networkUnit: Units.NetworkUnit
    public let byteStandard: Units.ByteUnitStandard

    @State private var isInterfacesExpanded: Bool = true

    public init(
        sample: NetworkSample? = nil,
        history: [Sample<NetworkSample>] = [],
        networkUnit: Units.NetworkUnit = .bytesPerSecond,
        byteStandard: Units.ByteUnitStandard = .iec
    ) {
        self.sample = sample
        self.history = history
        self.networkUnit = networkUnit
        self.byteStandard = byteStandard
    }

    /// History values converted according to current network unit preference.
    private var historyRates: [Double] {
        history.map { s in
            let totalBytesPerSec = s.value.totalBytesInPerSec + s.value.totalBytesOutPerSec
            return networkUnit == .bitsPerSecond ? Units.bytesPerSecToBitsPerSec(totalBytesPerSec) : totalBytesPerSec
        }
    }

    private var currentTotalRate: Double {
        guard let sample = sample else { return 0.0 }
        let total = sample.totalBytesInPerSec + sample.totalBytesOutPerSec
        return networkUnit == .bitsPerSecond ? Units.bytesPerSecToBitsPerSec(total) : total
    }

    private var peakRate: Double {
        let maxHist = historyRates.max() ?? 0.0
        return max(maxHist, currentTotalRate, 1.0)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Category Icon, Name, Live Aggregate Throughput
            HStack {
                Label {
                    Text("Network")
                        .font(.headline)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "network")
                        .foregroundColor(.teal)
                }

                Spacer()

                if let sample = sample {
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.teal)
                            Text(Units.formatNetworkRate(sample.totalBytesInPerSec, unit: networkUnit, standard: byteStandard))
                                .font(.system(size: 11, design: .monospaced))
                                .fontWeight(.semibold)
                        }

                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.cyan)
                            Text(Units.formatNetworkRate(sample.totalBytesOutPerSec, unit: networkUnit, standard: byteStandard))
                                .font(.system(size: 11, design: .monospaced))
                                .fontWeight(.semibold)
                        }
                    }
                } else {
                    Text("Sampling...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Rolling Short-Term History Graph (Requirement 10.2)
            VStack(alignment: .leading, spacing: 4) {
                RollingGraphView(
                    values: historyRates,
                    minValue: 0.0,
                    maxValue: peakRate,
                    tintColor: .teal,
                    capacity: 60,
                    height: 48,
                    showGrid: true
                )

                HStack {
                    Text("60s throughput")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Spacer()
                    if sample != nil {
                        let peakBytesPerSec = networkUnit == .bitsPerSecond ? (peakRate / 8.0) : peakRate
                        Text("Peak: \(Units.formatNetworkRate(peakBytesPerSec, unit: networkUnit, standard: byteStandard))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let sample = sample {
                // Session Cumulative Transfer Totals (Requirement 6.3)
                HStack(spacing: 12) {
                    metricBadge(
                        title: "Session In",
                        value: Units.formatBytes(sample.totalBytesIn, standard: byteStandard),
                        color: .teal
                    )
                    metricBadge(
                        title: "Session Out",
                        value: Units.formatBytes(sample.totalBytesOut, standard: byteStandard),
                        color: .cyan
                    )
                }
                .padding(.top, 2)

                // Per-Interface Breakdown (Requirement 6.2)
                if !sample.interfaces.isEmpty {
                    interfacesSection(interfaces: sample.interfaces)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Per-Interface Section

    private func interfacesSection(interfaces: [InterfaceThroughput]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isInterfacesExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Interfaces (\(interfaces.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isInterfacesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isInterfacesExpanded {
                VStack(spacing: 5) {
                    ForEach(interfaces, id: \.interfaceName) { iface in
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: interfaceIcon(for: iface.interfaceName))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(iface.interfaceName)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .frame(width: 60, alignment: .leading)

                            Spacer()

                            HStack(spacing: 8) {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 8))
                                        .foregroundColor(.teal)
                                    Text(Units.formatNetworkRate(iface.bytesInPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 8))
                                        .foregroundColor(.cyan)
                                    Text(Units.formatNetworkRate(iface.bytesOutPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.06))
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func metricBadge(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title):")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interfaceIcon(for name: String) -> String {
        if name.hasPrefix("en0") || name.hasPrefix("en1") {
            return "wifi"
        } else if name.hasPrefix("pdp_ip") || name.hasPrefix("cellular") {
            return "antenna.radiowaves.left.and.right"
        } else if name.hasPrefix("bridge") || name.hasPrefix("vlan") {
            return "network"
        } else {
            return "cable.connector"
        }
    }
}
