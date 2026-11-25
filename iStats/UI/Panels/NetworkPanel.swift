import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Network Instrument Panel (Task 8.5.8f / B8, B11, B14 / ADR 0010).
/// Features a standard-height independent-scale mirrored LiveChart, consolidated Active Link + Routing & DNS
/// sections on Now (<= 2 sections), and ranked Network Interfaces + Wi-Fi Radio Telemetry on Details.
public struct NetworkPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var showAllInterfaces: Bool = false
    @StateObject private var memoCache = MemoCache()

    private final class MemoCache: ObservableObject {
        struct Key: Equatable {
            let timestamp: Date?
            let sample: NetworkSample?
            let networkUnit: Units.NetworkUnit
            let byteUnitStandard: Units.ByteUnitStandard
            let refreshInterval: TimeInterval
        }

        var key: Key?
        var glance: PanelGlance?
        var status: StatusLevel = .fine
        var ribbon: String?
    }

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

    private var latestSample: Sample<NetworkSample>? {
        coordinator.latestNetwork
    }

    private var sample: NetworkSample? {
        latestSample?.value
    }

    private func primaryInterfaceName(in net: NetworkSample) -> String? {
        if let explicit = net.primaryInterface {
            return explicit
        }
        if net.connectionHealth?.isPathSatisfied == false {
            return nil
        }
        return net.interfaces.first(where: { $0.bytesInPerSec > 0 || $0.bytesOutPerSec > 0 })?.interfaceName
            ?? net.interfaces.first?.interfaceName
    }

    private func isActiveInterface(_ iface: InterfaceThroughput, primaryName: String?) -> Bool {
        iface.bytesInPerSec > 0 || iface.bytesOutPerSec > 0 || iface.interfaceName == primaryName
    }

    private func rankedActiveInterfaces(in net: NetworkSample) -> [InterfaceThroughput] {
        let primaryName = primaryInterfaceName(in: net)
        let active = net.interfaces
            .filter { isActiveInterface($0, primaryName: primaryName) }
            .sorted { lhs, rhs in
                if lhs.interfaceName == primaryName, rhs.interfaceName != primaryName { return true }
                if rhs.interfaceName == primaryName, lhs.interfaceName != primaryName { return false }
                let lhsRate = lhs.bytesInPerSec + lhs.bytesOutPerSec
                let rhsRate = rhs.bytesInPerSec + rhs.bytesOutPerSec
                if lhsRate != rhsRate { return lhsRate > rhsRate }
                return lhs.interfaceName < rhs.interfaceName
            }
        if active.isEmpty, let first = net.interfaces.first {
            return [first]
        }
        return active
    }

    private func displayedInterfaces(in net: NetworkSample) -> [InterfaceThroughput] {
        let active = rankedActiveInterfaces(in: net)
        guard showAllInterfaces else { return active }
        let activeNames = Set(active.map(\.interfaceName))
        let others = net.interfaces
            .filter { !activeNames.contains($0.interfaceName) }
            .sorted { $0.interfaceName < $1.interfaceName }
        return active + others
    }

    public var body: some View {
        let derived = memoizedState(for: latestSample)
        let availability = coordinator.categoryAvailability[.network]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            category: .network,
            glance: derived.glance,
            status: derived.status,
            ribbon: derived.ribbon,
            pages: PopoverTab.supportedTabs(for: .network),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            isLowPowerModeActive: coordinator.isLowPowerModeActive,
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

    // MARK: - Memoised Glance & Status Derivation (B8 + B14)

    private func memoizedState(for latest: Sample<NetworkSample>?) -> (glance: PanelGlance, status: StatusLevel, ribbon: String?) {
        let key = MemoCache.Key(
            timestamp: latest?.timestamp,
            sample: latest?.value,
            networkUnit: preferences.networkUnit,
            byteUnitStandard: preferences.byteUnitStandard,
            refreshInterval: preferences.refreshInterval
        )
        if memoCache.key == key, let cachedGlance = memoCache.glance {
            return (cachedGlance, memoCache.status, memoCache.ribbon)
        }

        let glance = deriveGlance(latest: latest)
        let (status, ribbon) = deriveStatusAndRibbon(sample: latest?.value)
        memoCache.key = key
        memoCache.glance = glance
        memoCache.status = status
        memoCache.ribbon = ribbon
        return (glance, status, ribbon)
    }

    internal func deriveGlance(latest: Sample<NetworkSample>?) -> PanelGlance {
        let currentSample = latest?.value
        let downBytes = currentSample?.totalBytesInPerSec ?? 0.0
        let upBytes = currentSample?.totalBytesOutPerSec ?? 0.0
        let unit = preferences.networkUnit
        let std = preferences.byteUnitStandard

        let downParts = Units.rateComponents(downBytes, unit: unit, standard: std)
        let upParts = Units.rateComponents(upBytes, unit: unit, standard: std)

        let headline = PanelHeadline.network(sample: currentSample, standard: std)

        let refDate = latest?.timestamp ?? Date()
        let dualPoints = coordinator.timedDualScalarHistory(
            primary: .networkInBytesPerSec,
            secondary: .networkOutBytesPerSec,
            duration: 60,
            referenceDate: refDate
        )

        let insight = InsightEngine.best(
            series: dualPoints.map(\.primary),
            interval: preferences.refreshInterval,
            unit: .bytesPerSecond(standard: std),
            thresholds: .throughputBytesPerSec()
        )?.text

        let chartMode = LiveChartMode.mirrored(
            points: dualPoints,
            topColor: CategoryPalette.tint(for: .network),
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
            chartHeight: Instrument.Size.chartHeightStandard,
            scrubFormat: { Units.formatNetworkRate($0, unit: unit, standard: std) }
        )
    }

    private func deriveStatusAndRibbon(sample: NetworkSample?) -> (StatusLevel, String?) {
        guard let s = sample else { return (.fine, nil) }

        if let health = s.connectionHealth {
            if health.isProbing {
                return (.fine, nil)
            }
            switch health.status {
            case .disconnected:
                return (.critical, health.reason)
            case .degraded:
                return (.elevated, health.reason)
            case .connected:
                return (.fine, nil)
            }
        }

        if let wifi = s.wifiDetails {
            if wifi.qualityRating == "Weak" || (wifi.signalPercent != nil && wifi.signalPercent! < 30) {
                let pct = wifi.signalPercent ?? 0
                return (.elevated, "Weak Wi-Fi signal (\(pct)%)")
            }
        }

        if s.interfaces.isEmpty || (s.interfaces.allSatisfy { $0.bytesInPerSec == 0 && $0.bytesOutPerSec == 0 } && s.localIPv4 == nil) {
            return (.critical, "No active network connection")
        }

        return (.fine, nil)
    }

    // MARK: - Now Page (single Active Link section)

    @ViewBuilder
    private func nowPage(sample: NetworkSample?) -> some View {
        if let net = sample {
            let std = preferences.byteUnitStandard

            // One section: Active Link (interface, SSID + signal, IPv4, session totals).
            // Routing & DNS lives on Details.
            activeLinkSection(net: net, standard: std)
        } else {
            InsetEmptyState(
                systemImage: "network.slash",
                title: "No Network Data",
                reason: "Network interface metrics are currently unavailable."
            )
        }
    }

    @ViewBuilder
    private func activeLinkSection(net: NetworkSample, standard: Units.ByteUnitStandard) -> some View {
        let health = NetworkConnectionEvaluator.fallbackHealth(for: net)
        let primaryName = primaryInterfaceName(in: net)
        let primaryType = net.primaryType
            ?? net.interfaces.first(where: { $0.interfaceName == primaryName })?.type
            ?? (net.wifiDetails != nil ? .wifi : .other)
        let displayName = primaryName.map { "\(primaryType.displayName) (\($0))" } ?? "Offline"
        let pillTextColor: Color = health.isProbing ? .secondary : ConnectionStatusGridView.badgeTextColor(for: health.status)
        let linkSymbol = primaryName == nil || health.status == .disconnected
            ? "network.slash"
            : CategoryIdentity(.network).liveSymbol(LiveSymbolState(connectionType: primaryType))

        Section(
            "Active Link",
            trailing: {
                if let wifi = net.wifiDetails {
                    HStack(spacing: Instrument.Space.s) {
                        Text(wifi.ssid ?? "Wi-Fi")
                            .font(Instrument.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        SignalBarsView(signalPercent: wifi.signalPercent)
                    }
                } else if primaryName != nil {
                    Text(primaryType.displayName)
                        .font(Instrument.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Instrument.Space.s) {
                // Interface identity row
                HStack(alignment: .center, spacing: Instrument.Space.s) {
                    Image(systemName: linkSymbol)
                        .font(Instrument.Typography.icon(Instrument.Icon.medium, weight: .medium))
                        .foregroundColor(primaryName == nil ? .secondary : (health.status == .connected ? CategoryPalette.tint(for: .network) : pillTextColor))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName)
                            .font(Instrument.Typography.headline)
                            .foregroundColor(.primary)

                        if health.status != .connected && !health.isProbing {
                            Text(health.reason)
                                .font(Instrument.Typography.caption)
                                .foregroundColor(pillTextColor)
                                .lineLimit(1)
                        } else if let wifi = net.wifiDetails {
                            let channelText = wifi.channel.map { "Ch \($0)" }
                            let bandDetail = [wifi.band, channelText].compactMap { $0 }.joined(separator: " · ")
                            if !bandDetail.isEmpty {
                                Text(bandDetail)
                                    .font(Instrument.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()
                }

                // Local IPv4 (copyable hairline row)
                if let ip = net.localIPv4 {
                    MetricRow(
                        label: "Local IPv4",
                        valueText: ip,
                        isCopyable: true,
                        showHairline: true
                    )
                } else {
                    Rectangle()
                        .fill(Instrument.Surface.hairline)
                        .frame(height: 0.5)
                }

                // Bottom split row: Session Download (↓ Total) & Session Upload (↑ Total)
                HStack(spacing: Instrument.Space.m) {
                    sessionTotalCell(
                        label: "↓ Total",
                        bytesText: Units.formatBytes(net.totalBytesIn, standard: standard),
                        color: CategoryPalette.tint(for: .network)
                    )

                    Rectangle()
                        .fill(Instrument.Surface.hairline)
                        .frame(width: 0.5, height: 28)

                    sessionTotalCell(
                        label: "↑ Total",
                        bytesText: Units.formatBytes(net.totalBytesOut, standard: standard),
                        color: CategoryPalette.Series.networkUpload
                    )
                }
                .padding(.top, Instrument.Space.xxs)
            }
        }
    }

    @ViewBuilder
    private func sessionTotalCell(label: String, bytesText: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Instrument.Space.xxs) {
            Text(label)
                .font(Instrument.Typography.caption)
                .foregroundColor(color)

            Text(bytesText)
                .font(Instrument.Typography.titleNumeric)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(bytesText)
    }

    @ViewBuilder
    private func routingSection(net: NetworkSample) -> some View {
        let bsdName = primaryInterfaceName(in: net)
        let rows: [(label: String, value: String)] = [
            net.gatewayIPv4.map { ("Gateway IPv4", $0) },
            net.primaryDNS.map { ("Primary DNS", $0) },
            bsdName.map { ("BSD Interface", $0) }
        ].compactMap { $0 }

        if !rows.isEmpty {
            Section("Routing & DNS") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        MetricRow(
                            label: row.label,
                            valueText: row.value,
                            isCopyable: true,
                            showHairline: idx < rows.count - 1
                        )
                    }
                }
            }
        }
    }

    // MARK: - Details Page (Interfaces, Wi-Fi telemetry, Routing & DNS, connection status)

    @ViewBuilder
    private func connectionPage(sample: NetworkSample?) -> some View {
        if let net = sample {
            let unit = preferences.networkUnit
            let std = preferences.byteUnitStandard
            let activeCount = rankedActiveInterfaces(in: net).count
            let list = displayedInterfaces(in: net)
            let primaryName = primaryInterfaceName(in: net)
            let health = NetworkConnectionEvaluator.fallbackHealth(for: net)

            VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
                Section(
                    "Network Interfaces",
                    trailing: {
                        if net.interfaces.count > activeCount {
                            Button {
                                withAnimation(Motion.smooth) {
                                    showAllInterfaces.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(showAllInterfaces ? "Show active only" : "Show all (\(net.interfaces.count))")
                                        .font(Instrument.Typography.caption)
                                    Image(systemName: showAllInterfaces ? "chevron.up" : "chevron.down")
                                        .font(Instrument.Typography.icon(Instrument.Icon.small))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("\(net.interfaces.count)")
                                .font(Instrument.Typography.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                ) {
                    if list.isEmpty {
                        Text("No network interfaces detected")
                            .font(Instrument.Typography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.interfaceName) { idx, iface in
                                interfaceRow(
                                    iface: iface,
                                    isActive: isActiveInterface(iface, primaryName: primaryName),
                                    unit: unit,
                                    standard: std,
                                    showHairline: idx < list.count - 1
                                )
                            }
                        }
                    }
                }

                if let wifi = net.wifiDetails {
                    wifiTelemetrySection(wifi: wifi)
                }

                routingSection(net: net)

                ConnectionStatusGridView(
                    health: health,
                    history: coordinator.networkConnectionHistory,
                    primaryInterface: primaryName,
                    primaryType: net.primaryType,
                    wifiDetails: net.wifiDetails
                )
            }
        } else {
            InsetEmptyState(
                systemImage: "network.slash",
                title: "No Connection Details",
                reason: "No interface details available."
            )
        }
    }

    @ViewBuilder
    private func interfaceRow(
        iface: InterfaceThroughput,
        isActive: Bool,
        unit: Units.NetworkUnit,
        standard: Units.ByteUnitStandard,
        showHairline: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isActive ? CategoryPalette.tint(for: .network) : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)

            Image(systemName: iface.type.iconName)
                .font(Instrument.Typography.icon(Instrument.Icon.regular, weight: .medium))
                .foregroundColor(isActive ? CategoryPalette.tint(for: .network) : .secondary)
                .frame(width: 14)

            Text(iface.interfaceName)
                .font(Instrument.Typography.mono)
                .foregroundColor(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Instrument.Surface.inset)
                )

            Spacer()

            HStack(spacing: Instrument.Space.m) {
                Text("↓ \(Units.formatCompactRate(iface.bytesInPerSec, unit: unit, standard: standard))")
                    .font(Instrument.Typography.value)
                    .foregroundColor(CategoryPalette.tint(for: .network))

                Text("↑ \(Units.formatCompactRate(iface.bytesOutPerSec, unit: unit, standard: standard))")
                    .font(Instrument.Typography.value)
                    .foregroundColor(CategoryPalette.Series.networkUpload)
            }
        }
        .frame(height: 26)
        .overlay(alignment: .bottom) {
            if showHairline {
                Rectangle()
                    .fill(Instrument.Surface.hairline)
                    .frame(height: 0.5)
            }
        }
    }

    @ViewBuilder
    private func wifiTelemetrySection(wifi: WiFiLinkTelemetry) -> some View {
        let rows: [(label: String, value: String, copyable: Bool)] = [
            wifi.signalPercent.map { pct in
                let qual = wifi.qualityRating ?? "Good"
                return ("Signal Quality", "\(pct)% (\(qual))", false)
            },
            wifi.rssi.map { ("RSSI", "\($0) dBm", false) },
            wifi.noise.map { ("Noise Floor", "\($0) dBm", false) },
            wifi.snr.map { ("SNR", "\($0) dB", false) },
            wifi.txRate.map { ("Transmit Rate", String(format: "%.0f Mbps", $0), false) }
        ].compactMap { $0 }

        if !rows.isEmpty {
            Section("Wi-Fi Radio Telemetry") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        MetricRow(
                            label: row.label,
                            valueText: row.value,
                            isCopyable: row.copyable,
                            showHairline: idx < rows.count - 1
                        )
                    }
                }
            }
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
        let suiteName = "iStats.Preview.Network.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(preferencesStore: prefs)
        coordinator.handleReading(.network(Sample(value: sample)))
        return coordinator
    }
}
#endif
