import SwiftUI
import iStatsCore

/// A Network metrics card view:
/// 1. Dynamic Dual Flow Pipes Illustration (Down in Teal, Up in Blue)
/// 2. Side-by-side prominent Dual Hero Down/Up Rates + Dual-trace sparkline
/// 3. Session cumulative transfer totals + Collapsible interface diagnostics.
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

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateNetwork(sample, unit: networkUnit, standard: byteStandard)
    }

    private var historyInRates: [Double] {
        history.map { s in
            let bytes = s.value.totalBytesInPerSec
            return networkUnit == .bitsPerSecond ? Units.bytesPerSecToBitsPerSec(bytes) : bytes
        }
    }

    private var historyOutRates: [Double] {
        history.map { s in
            let bytes = s.value.totalBytesOutPerSec
            return networkUnit == .bitsPerSecond ? Units.bytesPerSecToBitsPerSec(bytes) : bytes
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Hero Row: Dynamic Pipes + Dual Hero Rates (Down / Up)
            HStack(alignment: .center, spacing: 14) {
                // Live Dynamic Flow Pipes Illustration
                NetworkPipesIllustrationView(sample: sample, size: CGSize(width: 42, height: 64))

                // Dual Hero Rates Side-by-Side
                VStack(alignment: .leading, spacing: 3) {
                    if let sample = sample {
                        HStack(spacing: 14) {
                            // Download
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(.teal)
                                    Text("Download")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                Text(Units.formatNetworkRate(sample.totalBytesInPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }

                            // Upload
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(.blue)
                                    Text("Upload")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                Text(Units.formatNetworkRate(sample.totalBytesOutPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }

                        // Session totals
                        Text("Session: \(Units.formatBytes(sample.totalBytesIn, standard: byteStandard)) in · \(Units.formatBytes(sample.totalBytesOut, standard: byteStandard)) out")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    } else {
                        Text("Sampling network...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            // MARK: - Dual-Trace Rolling Sparkline (Down in Teal, Up in Blue)
            VStack(alignment: .leading, spacing: 4) {
                DualTraceRollingGraphView(
                    primaryValues: historyInRates,
                    secondaryValues: historyOutRates,
                    primaryColor: .teal,
                    secondaryColor: .blue,
                    primaryLabel: "In",
                    secondaryLabel: "Out",
                    height: 44,
                    capacity: 60
                )

                HStack {
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Circle().fill(Color.teal).frame(width: 5, height: 5)
                            Text("In")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(Color.blue).frame(width: 5, height: 5)
                            Text("Out")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    let peakIn = historyInRates.max() ?? 0
                    let peakOut = historyOutRates.max() ?? 0
                    let peak = max(peakIn, peakOut)
                    Text("peak " + Units.formatNetworkRate(peak, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 2)
            }

            // MARK: - Collapsible Diagnostics (Friendly Interface List)
            if let sample = sample, !sample.interfaces.isEmpty {
                let activeInterfaces = sample.interfaces.filter { $0.bytesInPerSec > 0 || $0.bytesOutPerSec > 0 || $0.totalBytesIn > 0 }
                CollapsibleSection(
                    title: "Interfaces",
                    count: activeInterfaces.count,
                    isExpanded: $isInterfacesExpanded
                ) {
                    interfacesList(interfaces: activeInterfaces)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - Interface Diagnostics List

    @ViewBuilder
    private func interfacesList(interfaces: [InterfaceThroughput]) -> some View {
        VStack(spacing: 3) {
            ForEach(interfaces, id: \.interfaceName) { iface in
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.teal)
                            .frame(width: 4.5, height: 4.5)

                        Text(friendlyInterfaceName(iface.interfaceName))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.primary)

                        Text("(\(iface.interfaceName))")
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("↓ " + Units.formatNetworkRate(iface.bytesInPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 0))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.teal)

                        Text("↑ " + Units.formatNetworkRate(iface.bytesOutPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 0))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 1.5)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.04))
                )
            }
        }
        .padding(.top, 4)
    }

    private func friendlyInterfaceName(_ raw: String) -> String {
        if raw == "en0" { return "Wi-Fi" }
        if raw == "en1" { return "Ethernet" }
        if raw.hasPrefix("utun") { return "VPN" }
        if raw.hasPrefix("bridge") { return "Thunderbolt Bridge" }
        if raw.hasPrefix("pdp_ip") { return "Cellular" }
        return raw
    }
}
