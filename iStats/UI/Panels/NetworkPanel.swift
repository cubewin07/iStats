import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Network Instrument Panel (Task 8.8f / ADR 0009 / Blueprint §6.6).
/// Features the signature Mirrored Waveform + Link Card, dual LiveNumber tickers,
/// animated 4-bar signal glyph, copyable network addresses, and per-interface telemetry.
public struct NetworkPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var showAllInterfaces: Bool = false

    public init(
        initialTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self.initialTab = initialTab
        self.rememberLastTab = rememberLastTab
        self.focusSource = focusSource
        self.coordinator = coordinator
        self.preferences = preferences
        let supported = PopoverTab.supportedTabs(for: .network)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    private var sample: NetworkSample? {
        coordinator.latestNetwork?.value
    }

    private var activeInterfaces: [InterfaceThroughput] {
        guard let net = sample else { return [] }
        let primaryName = net.primaryInterface ?? net.interfaces.first(where: { $0.bytesInPerSec > 0 || $0.bytesOutPerSec > 0 })?.interfaceName ?? net.interfaces.first?.interfaceName
        let active = net.interfaces.filter { iface in
            iface.bytesInPerSec > 0 || iface.bytesOutPerSec > 0 || iface.interfaceName == primaryName
        }
        if active.isEmpty, let first = net.interfaces.first {
            return [first]
        }
        return active
    }

    private var displayedInterfaces: [InterfaceThroughput] {
        guard let net = sample else { return [] }
        if showAllInterfaces {
            let active = activeInterfaces
            let activeNames = Set(active.map(\.interfaceName))
            let others = net.interfaces.filter { !activeNames.contains($0.interfaceName) }
                .sorted { $0.interfaceName < $1.interfaceName }
            return active + others
        } else {
            return activeInterfaces
        }
    }

    public var body: some View {
        let glance = deriveGlance(sample: sample)
        let (status, ribbon) = deriveStatusAndRibbon(sample: sample)
        let availability = coordinator.categoryAvailability[.network]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            category: .network,
            glance: glance,
            status: status,
            ribbon: ribbon,
            pages: PopoverTab.supportedTabs(for: .network),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: .network)
            },
            isPinned: PanelController.shared.isPinned(for: .network)
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample)
            case .detail:
                connectionPage(sample: sample)
            case .history:
                HistoryPage(category: .network, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .network)
            }
        }
    }

    // MARK: - Glance Derivation

    private func deriveGlance(sample: NetworkSample?) -> PanelGlance {
        let downBytes = sample?.totalBytesInPerSec ?? 0.0
        let upBytes = sample?.totalBytesOutPerSec ?? 0.0
        let unit = preferences.networkUnit
        let std = preferences.byteUnitStandard

        let downParts = Units.rateComponents(downBytes, unit: unit, standard: std)
        let upParts = Units.rateComponents(upBytes, unit: unit, standard: std)

        let headline = PanelHeadline.network(sample: sample)

        let inHistory = coordinator.networkHistory.map { $0.value.totalBytesInPerSec }
        let outHistory = coordinator.networkHistory.map { $0.value.totalBytesOutPerSec }

        let insight = InsightEngine.best(
            series: inHistory,
            interval: preferences.refreshInterval,
            unit: .bytesPerSecond
        )?.text

        let chartMode = LiveChartMode.mirrored(
            top: inHistory,
            bottom: outHistory,
            topColor: CategoryPalette.color(for: .network),
            bottomColor: CategoryPalette.Series.networkUpload,
            topLabel: "↓",
            bottomLabel: "↑"
        )

        return PanelGlance(
            value: downParts.value,
            format: downParts.format,
            unit: downParts.unit,
            secondaryGlance: (
                value: upParts.value,
                unit: upParts.unit,
                color: CategoryPalette.Series.networkUpload
            ),
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            chartHeight: 56,
            scrubFormat: { Units.formatNetworkRate($0, unit: unit, standard: std) }
        )
    }

    private func deriveStatusAndRibbon(sample: NetworkSample?) -> (StatusLevel, String?) {
        guard let s = sample else { return (.fine, nil) }

        if let wifi = s.wifiDetails {
            if wifi.qualityRating == "Weak" || (wifi.signalPercent != nil && wifi.signalPercent! < 30) {
                let pct = wifi.signalPercent ?? 0
                return (.warning, "Weak Wi-Fi signal (\(pct)%)")
            }
        }

        if s.interfaces.isEmpty || (s.interfaces.allSatisfy { $0.bytesInPerSec == 0 && $0.bytesOutPerSec == 0 } && s.localIPv4 == nil) {
            return (.warning, "No active network connection")
        }

        return (.fine, nil)
    }

    // MARK: - Now Page (Overview)

    @ViewBuilder
    private func nowPage(sample: NetworkSample?) -> some View {
        if let net = sample {
            let std = preferences.byteUnitStandard

            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                // Link Card Module
                linkCardModule(net: net)

                // Network Routing & Addresses Module
                if net.localIPv4 != nil || net.gatewayIPv4 != nil || net.primaryDNS != nil {
                    Module(eyebrow: "Routing & Configuration") {
                        VStack(spacing: 6) {
                            if let ip = net.localIPv4 {
                                MetricRow(label: "Local IPv4", valueText: ip, isCopyable: true)
                            }
                            if let gw = net.gatewayIPv4 {
                                MetricRow(label: "Gateway IPv4", valueText: gw, isCopyable: true)
                            }
                            if let dns = net.primaryDNS {
                                MetricRow(label: "Primary DNS", valueText: dns, isCopyable: true)
                            }
                        }
                    }
                }

                // Session Totals Module
                Module(eyebrow: "Session Totals") {
                    VStack(spacing: 6) {
                        MetricRow(
                            label: "Total Downloaded",
                            valueText: Units.formatBytes(net.totalBytesIn, standard: std),
                            isCopyable: true
                        )
                        MetricRow(
                            label: "Total Uploaded",
                            valueText: Units.formatBytes(net.totalBytesOut, standard: std),
                            isCopyable: true
                        )
                    }
                }
            }
        } else {
            InsetEmptyState(
                systemImage: "network.slash",
                title: "No Network Data",
                reason: "Network interface metrics are currently unavailable."
            )
        }
    }

    // MARK: - Link Card Module

    @ViewBuilder
    private func linkCardModule(net: NetworkSample) -> some View {
        Module(eyebrow: "Link Connection") {
            if let wifi = net.wifiDetails {
                VStack(alignment: .leading, spacing: Instrument.Space.s) {
                    HStack(alignment: .center, spacing: Instrument.Space.s) {
                        SignalBarsView(signalPercent: wifi.signalPercent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(wifi.ssid ?? "Wi-Fi Network")
                                .font(Instrument.Typography.headline)
                                .foregroundColor(.primary)

                            let bandText = wifi.band
                            let channelText = wifi.channel.map { "Ch \($0)" }
                            let detailText = [bandText, channelText].compactMap { $0 }.joined(separator: " · ")
                            if !detailText.isEmpty {
                                Text(detailText)
                                    .font(Instrument.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Text(wifi.qualityRating ?? "Connected")
                            .font(Instrument.Typography.caption)
                            .foregroundColor(CategoryPalette.color(for: .network))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(CategoryPalette.color(for: .network).opacity(0.12))
                            )
                    }
                }
            } else {
                let primaryName = net.primaryInterface ?? net.interfaces.first?.interfaceName ?? "en0"
                let primaryType = net.primaryType ?? net.interfaces.first?.type ?? .ethernet

                HStack(alignment: .center, spacing: Instrument.Space.s) {
                    Image(systemName: primaryType.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CategoryPalette.color(for: .network))
                        .frame(width: 20)

                    Text(primaryName)
                        .font(Instrument.Typography.mono)
                        .foregroundColor(.primary)

                    Spacer()

                    Text(primaryType.displayName)
                        .font(Instrument.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Connection Detail Page

    @ViewBuilder
    private func connectionPage(sample: NetworkSample?) -> some View {
        if let net = sample {
            let unit = preferences.networkUnit
            let std = preferences.byteUnitStandard

            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                // Interfaces Module
                Module(
                    eyebrow: "Interfaces (\(net.interfaces.count))",
                    trailing: {
                        if net.interfaces.count > activeInterfaces.count {
                            Button {
                                withAnimation(Motion.smooth) {
                                    showAllInterfaces.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(showAllInterfaces ? "Show active only" : "Show all (\(net.interfaces.count))")
                                        .font(Instrument.Typography.caption)
                                    Image(systemName: showAllInterfaces ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                ) {
                    let list = displayedInterfaces
                    VStack(spacing: 6) {
                        ForEach(list, id: \.interfaceName) { iface in
                            HStack(spacing: 6) {
                                Image(systemName: iface.type.iconName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(CategoryPalette.color(for: .network))
                                    .frame(width: 14)

                                Text(iface.interfaceName)
                                    .font(Instrument.Typography.body)
                                    .foregroundColor(.primary)

                                Spacer()

                                HStack(spacing: 8) {
                                    Text("↓ \(Units.formatCompactRate(iface.bytesInPerSec, unit: unit, standard: std))")
                                        .font(Instrument.Typography.mono)
                                        .foregroundColor(CategoryPalette.color(for: .network))

                                    Text("↑ \(Units.formatCompactRate(iface.bytesOutPerSec, unit: unit, standard: std))")
                                        .font(Instrument.Typography.mono)
                                        .foregroundColor(CategoryPalette.Series.networkUpload)
                                }
                            }
                        }
                    }
                }

                // Wi-Fi Telemetry Module
                if let wifi = net.wifiDetails {
                    Module(eyebrow: "Wi-Fi Telemetry") {
                        VStack(spacing: 6) {
                            if let ssid = wifi.ssid {
                                MetricRow(label: "Network (SSID)", valueText: ssid, isCopyable: true)
                            }
                            if let p = wifi.signalPercent {
                                let qual = wifi.qualityRating ?? "Good"
                                MetricRow(label: "Signal Quality", valueText: "\(p)% (\(qual))", isCopyable: false)
                            }
                            if let rssi = wifi.rssi {
                                MetricRow(label: "Signal (RSSI)", valueText: "\(rssi) dBm", isCopyable: false)
                            }
                            if let noise = wifi.noise {
                                MetricRow(label: "Noise Floor", valueText: "\(noise) dBm", isCopyable: false)
                            }
                            if let snr = wifi.snr {
                                MetricRow(label: "Signal-to-Noise (SNR)", valueText: "\(snr) dB", isCopyable: false)
                            }
                            if let tx = wifi.txRate {
                                MetricRow(label: "Transmit Rate", valueText: String(format: "%.0f Mbps", tx), isCopyable: false)
                            }
                        }
                    }
                }
            }
        } else {
            InsetEmptyState(
                systemImage: "network.slash",
                title: "No Connection Details",
                reason: "No interface details available."
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
struct NetworkPanel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Wi-Fi Strong
            NetworkPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: NetworkSample(
                        interfaces: [
                            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1_250_000, bytesOutPerSec: 180_000, totalBytesIn: 12_400_000, totalBytesOut: 2_100_000, ipv4Address: "192.168.1.104", type: .wifi)
                        ],
                        primaryInterface: "en0",
                        primaryType: .wifi,
                        localIPv4: "192.168.1.104",
                        gatewayIPv4: "192.168.1.1",
                        primaryDNS: "1.1.1.1",
                        wifiDetails: WiFiLinkTelemetry(
                            ssid: "Studio-5G",
                            rssi: -58,
                            noise: -92,
                            txRate: 650.0,
                            channel: 44,
                            band: "5 GHz"
                        )
                    )
                )
            )
            .previewDisplayName("Wi-Fi Strong")

            // Wi-Fi Weak (triggers ribbon)
            NetworkPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: NetworkSample(
                        interfaces: [
                            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 15_000, bytesOutPerSec: 5_000, totalBytesIn: 100_000, totalBytesOut: 50_000, ipv4Address: "192.168.1.104", type: .wifi)
                        ],
                        primaryInterface: "en0",
                        primaryType: .wifi,
                        localIPv4: "192.168.1.104",
                        gatewayIPv4: "192.168.1.1",
                        primaryDNS: "1.1.1.1",
                        wifiDetails: WiFiLinkTelemetry(
                            ssid: "Studio-5G",
                            rssi: -89,
                            noise: -90,
                            txRate: 12.0,
                            channel: 44,
                            band: "5 GHz"
                        )
                    )
                )
            )
            .previewDisplayName("Wi-Fi Weak")

            // Ethernet
            NetworkPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: NetworkSample(
                        interfaces: [
                            InterfaceThroughput(interfaceName: "en1", bytesInPerSec: 45_000_000, bytesOutPerSec: 12_000_000, totalBytesIn: 500_000_000, totalBytesOut: 120_000_000, ipv4Address: "10.0.0.15", type: .ethernet)
                        ],
                        primaryInterface: "en1",
                        primaryType: .ethernet,
                        localIPv4: "10.0.0.15",
                        gatewayIPv4: "10.0.0.1",
                        primaryDNS: "8.8.8.8",
                        wifiDetails: nil
                    )
                )
            )
            .previewDisplayName("Ethernet")

            // Offline
            NetworkPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: NetworkSample(
                        interfaces: [],
                        primaryInterface: nil,
                        primaryType: nil,
                        localIPv4: nil,
                        gatewayIPv4: nil,
                        primaryDNS: nil,
                        wifiDetails: nil
                    )
                )
            )
            .previewDisplayName("Offline")
        }
        .padding()
        .background(Color.black)
    }

    private static func makeMockCoordinator(sample: NetworkSample) -> MetricsCoordinator {
        let coordinator = MetricsCoordinator.shared
        coordinator.handleReading(.network(Sample(value: sample)))
        return coordinator
    }
}
#endif
