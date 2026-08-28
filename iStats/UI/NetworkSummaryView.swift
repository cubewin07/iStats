import SwiftUI
import iStatsCore

/// A comprehensive Network metrics view displaying aggregate throughput, live rolling history graph,
/// session cumulative transfer totals, and per-interface bandwidth breakdown (Requirements 6.1-6.4, 10.1, 11.3).
public struct NetworkSummaryView: View {
    public let sample: NetworkSample?
    public let history: [Sample<NetworkSample>]
    public let networkUnit: Units.NetworkUnit
    public let byteStandard: Units.ByteUnitStandard

    @State private var isInterfacesExpanded: Bool = false

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
            // Dual Hero Speed Cards (Download & Upload)
            HStack(spacing: 8) {
                // Download Speed Card
                speedCard(
                    title: "Download",
                    rateString: sample != nil ? Units.formatNetworkRate(sample!.totalBytesInPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1) : "—",
                    icon: "arrow.down.circle.fill",
                    color: .teal
                )

                // Upload Speed Card
                speedCard(
                    title: "Upload",
                    rateString: sample != nil ? Units.formatNetworkRate(sample!.totalBytesOutPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1) : "—",
                    icon: "arrow.up.circle.fill",
                    color: .blue
                )
            }

            // Rolling 60s Throughput Graph
            VStack(alignment: .leading, spacing: 4) {
                RollingGraphView(
                    values: historyRates,
                    minValue: 0.0,
                    maxValue: peakRate,
                    tintColor: .teal,
                    capacity: 60,
                    height: 44,
                    showGrid: true
                )

                HStack {
                    Text("Network Traffic History")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    if sample != nil {
                        let peakBytesPerSec = networkUnit == .bitsPerSecond ? (peakRate / 8.0) : peakRate
                        Text("Peak: \(Units.formatNetworkRate(peakBytesPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let sample = sample {
                // Session Cumulative Transfer Totals (Session In / Out)
                HStack(spacing: 8) {
                    sessionDataTile(
                        title: "Session Downloaded",
                        value: Units.formatBytes(sample.totalBytesIn, standard: byteStandard, fractionDigits: 2),
                        icon: "arrow.down.to.line.compact",
                        color: .teal
                    )

                    sessionDataTile(
                        title: "Session Uploaded",
                        value: Units.formatBytes(sample.totalBytesOut, standard: byteStandard, fractionDigits: 2),
                        icon: "arrow.up.to.line.compact",
                        color: .blue
                    )
                }

                // Per-Interface Breakdown
                if !sample.interfaces.isEmpty {
                    interfacesSection(interfaces: sample.interfaces)
                }
            } else {
                Text("Waiting for network telemetry...")
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

    // MARK: - Speed Card

    private func speedCard(title: String, rateString: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Text(rateString)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.2), lineWidth: 0.75)
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session Data Tile

    private func sessionDataTile(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Per-Interface Section

    private func interfacesSection(interfaces: [InterfaceThroughput]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isInterfacesExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Active Interfaces (\(interfaces.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isInterfacesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isInterfacesExpanded {
                VStack(spacing: 4) {
                    ForEach(interfaces, id: \.interfaceName) { iface in
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: interfaceIcon(for: iface.interfaceName))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)

                                Text(iface.interfaceName)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 55, alignment: .leading)

                            Spacer()

                            HStack(spacing: 8) {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.teal)
                                    Text(Units.formatNetworkRate(iface.bytesInPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.blue)
                                    Text(Units.formatNetworkRate(iface.bytesOutPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.secondary.opacity(0.05))
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
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

