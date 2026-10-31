import SwiftUI
import iStatsCore

/// Purpose-driven Network popover (ADR 0008, Task 7.4f).
/// Structure: Overview · Connection · History.
/// Answers: "What is my current bandwidth? Am I connected?"
public struct NetworkPopover: View {
    @State public var selectedTab: PopoverTab
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    public init(
        initialTab: PopoverTab = .overview,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self._selectedTab = State(initialValue: initialTab)
        self.coordinator = coordinator
        self.preferences = preferences
    }

    private var sample: NetworkSample? {
        coordinator.latestNetwork?.value
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateNetwork(
            sample,
            unit: preferences.networkUnit,
            standard: preferences.byteUnitStandard
        )
    }

    public var body: some View {
        PopoverScaffold(
            category: .network,
            verdict: verdict,
            tabs: [.overview, .detail, .history],
            selectedTab: $selectedTab,
            isLoading: coordinator.latestNetwork == nil,
            unavailableReason: coordinator.categoryAvailability[.network]?.unavailableReason,
            preferences: preferences,
            coordinator: coordinator
        ) {
            switch selectedTab {
            case .overview:
                overviewTab
            case .detail:
                connectionTab
            case .history:
                HistoryTab(category: .network, coordinator: coordinator, preferences: preferences)
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let net = sample {
            let inRate = net.totalBytesInPerSec
            let outRate = net.totalBytesOutPerSec
            let unit = preferences.networkUnit
            let std = preferences.byteUnitStandard

            VStack(alignment: .leading, spacing: Tokens.md) {
                // Dual Hero Metrics (Download & Upload)
                HStack(spacing: Tokens.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("↓ Download")
                                .font(Tokens.sectionTitle)
                                .foregroundColor(CategoryPalette.network)
                        }
                        Text(Units.formatCompactRate(inRate, unit: unit, standard: std))
                            .font(Tokens.heroValue)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("↑ Upload")
                                .font(Tokens.sectionTitle)
                                .foregroundColor(Color.pink)
                        }
                        Text(Units.formatCompactRate(outRate, unit: unit, standard: std))
                            .font(Tokens.heroValue)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Mirrored Duplex Sparkline
                let inHistory = coordinator.networkHistory.map { $0.value.totalBytesInPerSec }
                let outHistory = coordinator.networkHistory.map { $0.value.totalBytesOutPerSec }
                TrendChart(
                    mode: .mirrored(
                        top: inHistory,
                        bottom: outHistory,
                        topColor: CategoryPalette.network,
                        bottomColor: Color.pink.opacity(0.85),
                        topLabel: "↓",
                        bottomLabel: "↑"
                    ),
                    height: 52,
                    sampleIntervalSeconds: preferences.refreshInterval
                )

                // Active Interfaces List
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Interfaces")
                        .font(Tokens.sectionTitle)
                        .foregroundColor(.secondary)

                    ForEach(net.interfaces, id: \.interfaceName) { iface in
                        HStack {
                            Text(iface.interfaceName)
                                .font(Tokens.bodyLabel)
                                .foregroundColor(.primary)

                            Spacer()

                            HStack(spacing: 8) {
                                Text("↓ \(Units.formatCompactRate(iface.bytesInPerSec, unit: unit, standard: std))")
                                    .font(Tokens.monoValue)
                                    .foregroundColor(CategoryPalette.network)

                                Text("↑ \(Units.formatCompactRate(iface.bytesOutPerSec, unit: unit, standard: std))")
                                    .font(Tokens.monoValue)
                                    .foregroundColor(Color.pink)
                            }
                        }
                    }
                }
                .padding(10)
                .cardBackground()
            }
        }
    }

    // MARK: - Connection Tab

    @ViewBuilder
    private var connectionTab: some View {
        if let net = sample {
            let primary = net.interfaces.first(where: { $0.bytesInPerSec > 0 || $0.bytesOutPerSec > 0 }) ?? net.interfaces.first
            let std = preferences.byteUnitStandard

            VStack(alignment: .leading, spacing: Tokens.md) {
                Text("Interface Configuration")
                    .font(Tokens.sectionTitle)
                    .foregroundColor(.secondary)

                VStack(spacing: 6) {
                    if let iface = primary {
                        StatRow(label: "Primary Interface", value: iface.interfaceName)

                        if let ip = iface.ipv4Address ?? net.localIPv4 {
                            CopyableValue(label: "Local IPv4", value: ip)
                        }

                        if let gateway = net.gatewayIPv4 {
                            CopyableValue(label: "Gateway IPv4", value: gateway)
                        }

                        if let dns = net.primaryDNS {
                            CopyableValue(label: "DNS Server", value: dns)
                        }

                        StatRow(label: "Type", value: iface.type.displayName)

                        if let wifi = net.wifiDetails, let ssid = wifi.ssid {
                            StatRow(label: "Wi-Fi Network", value: ssid)
                        }

                        Divider()

                        StatRow(
                            label: "Total Session Received",
                            value: Units.formatBytes(iface.totalBytesIn, standard: std)
                        )
                        StatRow(
                            label: "Total Session Sent",
                            value: Units.formatBytes(iface.totalBytesOut, standard: std)
                        )
                    }
                }
                .padding(10)
                .cardBackground()

                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Zero external network calls (ADR 0006). All IP data is local.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
