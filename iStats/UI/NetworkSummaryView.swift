import SwiftUI
import iStatsCore

/// A Network metrics card view:
/// 1. Dynamic Dual Flow Pipes Illustration (Down in Teal, Up in Blue)
/// 2. Active Connection Pill & Dual Hero Down/Up Rates + Session transfer totals
/// 3. Connectivity & Link Telemetry Grid (Local IP, Gateway, Primary DNS, Wi-Fi / Link Speed & Signal)
/// 4. Dual-trace rolling sparkline with Down & Up peak throughput callouts
/// 5. Collapsible interface diagnostics with interface type icons, IP addresses, and throughput.
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
        VStack(alignment: .leading, spacing: 9) {
            // MARK: - Hero Row: Dynamic Pipes + Connection Pill & Dual Hero Rates
            HStack(alignment: .center, spacing: 12) {
                // Live Dynamic Flow Pipes Illustration
                NetworkPipesIllustrationView(sample: sample, size: CGSize(width: 40, height: 62))

                // Connection Pill, Rates & Session Totals
                VStack(alignment: .leading, spacing: 3) {
                    if let sample = sample {
                        // Connection Pill / Header
                        HStack(spacing: 4.5) {
                            let connType = sample.primaryType ?? .other
                            Image(systemName: connType.iconName)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(connType == .wifi ? .teal : (connType == .ethernet ? .blue : .secondary))

                            Text(primaryConnectionLabel(sample))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if let ifName = sample.primaryInterface {
                                Text("(\(ifName))")
                                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Spacer(minLength: 2)

                            if let wifi = sample.wifiDetails, let quality = wifi.qualityRating {
                                Text(quality)
                                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.teal)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.teal.opacity(0.12)))
                            }
                        }

                        // Dual Hero Rates Side-by-Side
                        HStack(spacing: 14) {
                            // Download
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(.teal)
                                    Text("Download")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                Text(Units.formatNetworkRate(sample.totalBytesInPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }

                            // Upload
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(.blue)
                                    Text("Upload")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                Text(Units.formatNetworkRate(sample.totalBytesOutPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 1))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.top, 1)

                        // Session totals
                        Text("Session: \(Units.formatBytes(sample.totalBytesIn, standard: byteStandard)) in · \(Units.formatBytes(sample.totalBytesOut, standard: byteStandard)) out")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Sampling network...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            // MARK: - Connectivity & Routing Telemetry Grid
            if let sample = sample, hasConnectivityDetails(sample) {
                connectivityGrid(sample: sample)
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
                    height: 40,
                    capacity: 60
                )

                HStack {
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Circle().fill(Color.teal).frame(width: 5, height: 5)
                            Text("In")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(Color.blue).frame(width: 5, height: 5)
                            Text("Out")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    let peakIn = historyInRates.max() ?? 0
                    let peakOut = historyOutRates.max() ?? 0
                    HStack(spacing: 5) {
                        Text("Peak:")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("↓" + Units.formatNetworkRate(peakIn, unit: networkUnit, standard: byteStandard, fractionDigits: 0))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.teal)
                        Text("↑" + Units.formatNetworkRate(peakOut, unit: networkUnit, standard: byteStandard, fractionDigits: 0))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 2)
            }

            // MARK: - Collapsible Diagnostics (Enriched Interface List)
            if let sample = sample, !sample.interfaces.isEmpty {
                let activeInterfaces = sample.interfaces.filter { $0.bytesInPerSec > 0 || $0.bytesOutPerSec > 0 || $0.totalBytesIn > 0 }
                CollapsibleSection(
                    title: "Interfaces",
                    count: activeInterfaces.count,
                    isExpanded: $isInterfacesExpanded
                ) {
                    interfacesList(interfaces: activeInterfaces)
                }
                .padding(.horizontal, 2)
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

    // MARK: - Connectivity Grid

    private func hasConnectivityDetails(_ sample: NetworkSample) -> Bool {
        sample.localIPv4 != nil || sample.gatewayIPv4 != nil || sample.primaryDNS != nil || sample.wifiDetails != nil
    }

    @ViewBuilder
    private func connectivityGrid(sample: NetworkSample) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
            // Local IP
            detailTile(
                label: "Local IPv4",
                value: sample.localIPv4 ?? "—",
                icon: "laptopcomputer",
                color: .teal
            )

            // Router / Gateway
            detailTile(
                label: "Gateway IP",
                value: sample.gatewayIPv4 ?? "—",
                icon: "server.rack",
                color: .blue
            )

            // DNS
            detailTile(
                label: "Primary DNS",
                value: sample.primaryDNS ?? "—",
                icon: "globe",
                color: .indigo
            )

            // Wi-Fi Link or Primary Link
            if let wifi = sample.wifiDetails {
                detailTile(
                    label: wifiLinkLabel(wifi),
                    value: wifiLinkValue(wifi),
                    icon: "wifi",
                    color: .teal
                )
            } else if sample.primaryType == .ethernet {
                detailTile(
                    label: "Ethernet Link",
                    value: sample.primaryInterface ?? "Active",
                    icon: "cable.connector",
                    color: .blue
                )
            } else {
                detailTile(
                    label: "Link Type",
                    value: (sample.primaryType ?? .other).displayName,
                    icon: (sample.primaryType ?? .other).iconName,
                    color: .secondary
                )
            }
        }
        .padding(.vertical, 2)
    }

    private func detailTile(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
                .foregroundColor(color)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(label)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
    }

    private func wifiLinkLabel(_ wifi: WiFiLinkTelemetry) -> String {
        if let band = wifi.band {
            return "Wi-Fi (\(band))"
        }
        return "Wi-Fi Link"
    }

    private func wifiLinkValue(_ wifi: WiFiLinkTelemetry) -> String {
        var parts: [String] = []
        if let tx = wifi.txRate, tx > 0 {
            parts.append("\(Int(round(tx))) Mbps")
        }
        if let rssi = wifi.rssi {
            parts.append("\(rssi) dBm")
        } else if let pct = wifi.signalPercent {
            parts.append("\(pct)%")
        }
        if parts.isEmpty {
            return wifi.qualityRating ?? "Connected"
        }
        return parts.joined(separator: " · ")
    }

    private func primaryConnectionLabel(_ sample: NetworkSample) -> String {
        if let ssid = sample.wifiDetails?.ssid, !ssid.isEmpty {
            return ssid
        }
        if let primaryType = sample.primaryType {
            return primaryType.displayName
        }
        return "Connected"
    }

    // MARK: - Interface Diagnostics List

    @ViewBuilder
    private func interfacesList(interfaces: [InterfaceThroughput]) -> some View {
        VStack(spacing: 3) {
            ForEach(interfaces, id: \.interfaceName) { iface in
                HStack {
                    HStack(spacing: 4.5) {
                        Image(systemName: iface.type.iconName)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(iface.type == .wifi ? .teal : (iface.type == .ethernet ? .blue : .secondary))
                            .frame(width: 11)

                        Text(friendlyInterfaceName(iface))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.primary)

                        Text("(\(iface.interfaceName))")
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let ip = iface.ipv4Address {
                            Text(ip)
                                .font(.system(size: 7.5, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 0.5)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.08)))
                        }
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 6) {
                        Text("↓ " + Units.formatNetworkRate(iface.bytesInPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 0))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.teal)

                        Text("↑ " + Units.formatNetworkRate(iface.bytesOutPerSec, unit: networkUnit, standard: byteStandard, fractionDigits: 0))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.04))
                )
            }
        }
        .padding(.top, 4)
    }

    private func friendlyInterfaceName(_ iface: InterfaceThroughput) -> String {
        switch iface.type {
        case .wifi:
            return "Wi-Fi"
        case .ethernet:
            return "Ethernet"
        case .vpn:
            return "VPN"
        case .thunderbolt:
            return "Thunderbolt"
        case .cellular:
            return "Cellular"
        case .other:
            return iface.interfaceName
        }
    }
}
