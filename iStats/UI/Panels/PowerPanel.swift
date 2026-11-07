import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Power Instrument Panel (Task 8.8h / ADR 0009 / Blueprint §6.8).
/// Features the signature Battery Glyph, 3-node animated Power Flow diagram,
/// ArcGauge desktop power meter, and battery health telemetry.
public struct PowerPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab

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

        let hasBattery = coordinator.latestPower?.value.hasBattery ?? true
        let supported = PopoverTab.supportedTabs(for: .power, hasBattery: hasBattery)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    private var sample: PowerSample? {
        coordinator.latestPower?.value
    }

    private var hasBattery: Bool {
        sample?.hasBattery ?? true
    }

    private var supportedPages: [PopoverTab] {
        PopoverTab.supportedTabs(for: .power, hasBattery: hasBattery)
    }

    public var body: some View {
        let glance = deriveGlance(sample: sample)
        let (status, ribbon) = deriveStatusAndRibbon(sample: sample)
        let availability = coordinator.categoryAvailability[.power]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            category: .power,
            glance: glance,
            status: status,
            ribbon: ribbon,
            pages: supportedPages,
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: .power)
            },
            isPinned: PanelController.shared.isPinned(for: .power)
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample)
            case .detail:
                healthPage(sample: sample)
            case .history:
                HistoryPage(category: .power, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .power)
            }
        }
    }

    // MARK: - Glance Derivation

    private func deriveGlance(sample: PowerSample?) -> PanelGlance {
        let headline = PanelHeadline.power(sample: sample)

        if hasBattery {
            let charge = sample?.charge ?? 0.0
            let history = coordinator.powerHistory.compactMap { $0.value.charge }
            let series = history.isEmpty ? [charge] : history

            let insight = InsightEngine.best(
                series: series,
                interval: preferences.refreshInterval,
                unit: .percent
            )?.text

            let chartMode = LiveChartMode.single(
                values: series,
                color: CategoryPalette.color(for: .power),
                fixedMax: 100
            )

            return PanelGlance(
                value: charge,
                format: "%.0f",
                unit: "%",
                headline: headline,
                insight: insight,
                chartMode: chartMode,
                chartHeight: 56,
                scrubFormat: { "\(Int(round($0)))%" }
            )
        } else {
            // Desktop Mac
            let watts = sample?.powerDrawWatts ?? 0.0
            let history = coordinator.powerHistory.compactMap { $0.value.powerDrawWatts }
            let series = history.isEmpty ? [watts] : history

            let insight = InsightEngine.best(
                series: series,
                interval: preferences.refreshInterval,
                unit: .watts
            )?.text

            let chartMode = LiveChartMode.single(
                values: series,
                color: CategoryPalette.color(for: .power),
                fixedMax: 150
            )

            return PanelGlance(
                value: watts,
                format: "%.1f",
                unit: "W",
                headline: headline,
                insight: insight,
                chartMode: chartMode,
                chartHeight: 56,
                scrubFormat: { String(format: "%.1f W", $0) }
            )
        }
    }

    private func deriveStatusAndRibbon(sample: PowerSample?) -> (StatusLevel, String?) {
        guard let s = sample else { return (.fine, nil) }

        if s.isPowerDeficit {
            return (.warning, "Power draw exceeds adapter rating: battery assisting")
        }

        if s.isOnHold {
            return (.fine, "Charging on hold (Optimized Battery Charging)")
        }

        if s.isLowBattery, let charge = s.charge {
            if charge <= 10.0 {
                return (.critical, "Battery critically low: connect charger immediately")
            } else {
                return (.warning, "Battery low: connect power soon")
            }
        }

        return (.fine, nil)
    }

    // MARK: - Now Page (Overview)

    @ViewBuilder
    private func nowPage(sample: PowerSample?) -> some View {
        if let s = sample {
            if s.hasBattery {
                batteryNowPage(sample: s)
            } else {
                desktopNowPage(sample: s)
            }
        } else {
            InsetEmptyState(
                systemImage: "bolt.slash",
                title: "No Power Data",
                reason: "Power and battery diagnostics are currently unavailable."
            )
        }
    }

    @ViewBuilder
    private func batteryNowPage(sample: PowerSample) -> some View {
        let (status, _) = deriveStatusAndRibbon(sample: sample)

        VStack(alignment: .leading, spacing: Instrument.Space.m) {
            // Hero Battery Glyph Card
            Module(eyebrow: "Battery State") {
                HStack(alignment: .center, spacing: Instrument.Space.l) {
                    BatteryGlyph(
                        charge: sample.charge,
                        isCharging: sample.state == .charging,
                        statusLevel: status
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(sample.variant.displayName)
                            .font(Instrument.Typography.headline)
                            .foregroundColor(.primary)

                        if let secs = sample.timeRemaining, secs > 0 {
                            let mins = Int(secs / 60)
                            let h = mins / 60
                            let m = mins % 60
                            let suffix = sample.state == .charging ? "to full" : "remaining"
                            Text("\(h > 0 ? "\(h)h " : "")\(m)m \(suffix)")
                                .font(Instrument.Typography.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(sample.condition ?? "Normal Condition")
                                .font(Instrument.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Power Flow Diagram
            let flow = PowerFlowMath.calculateFlow(
                hasBattery: sample.hasBattery,
                state: sample.state,
                adapterWatts: sample.adapterWatts,
                powerDrawWatts: sample.powerDrawWatts,
                voltageVolts: sample.voltageVolts,
                amperageMilliAmps: sample.amperageMilliAmps
            )

            Module(eyebrow: "Power Flow Topology") {
                PowerFlowView(flow: flow, variant: sample.variant)
                    .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func desktopNowPage(sample: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: Instrument.Space.m) {
            Module(eyebrow: "System Power Draw") {
                HStack(alignment: .center, spacing: Instrument.Space.l) {
                    ArcGauge(
                        value: sample.powerDrawWatts ?? 0,
                        range: 0...150,
                        tint: CategoryPalette.color(for: .power),
                        size: 60
                    )
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(sample.adapterName ?? "Connected to AC Power")
                            .font(Instrument.Typography.headline)
                            .foregroundColor(.primary)

                        if let adapterW = sample.adapterWatts, adapterW > 0 {
                            Text("Power supply rated at \(Int(adapterW)) W")
                                .font(Instrument.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Health Page (Battery Macs)

    @ViewBuilder
    private func healthPage(sample: PowerSample?) -> some View {
        if let s = sample, s.hasBattery {
            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                // Health Rings & Cycles
                Module(eyebrow: "Battery Health & Capacity") {
                    HStack(spacing: Instrument.Space.l) {
                        let health = s.healthPercentage
                        if let h = health {
                            RingStack(
                                rings: [
                                    RingData(
                                        fraction: h / 100.0,
                                        color: CategoryPalette.color(for: .power),
                                        label: "Health"
                                    )
                                ],
                                size: 72,
                                ringWidth: 7
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            if let h = health {
                                Text("\(Int(round(h)))% Maximum Capacity")
                                    .font(Instrument.Typography.headline)
                                    .foregroundColor(.primary)
                            } else {
                                Text("Health Capacity Unavailable")
                                    .font(Instrument.Typography.headline)
                                    .foregroundColor(.secondary)
                            }

                            if let cycles = s.cycleCount {
                                let designCycles = s.designCycleCount ?? 1000
                                Text("\(cycles) of \(designCycles) charge cycles")
                                    .font(Instrument.Typography.caption)
                                    .foregroundColor(.secondary)

                                let cycleProgress = Double(cycles) / Double(max(1, designCycles))
                                Meter(
                                    progress: cycleProgress,
                                    height: .small,
                                    tint: CategoryPalette.color(for: .power)
                                )
                            } else {
                                Text("Cycle Count Unavailable")
                                    .font(Instrument.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Diagnostics Rows
                Module(eyebrow: "Hardware Diagnostics") {
                    VStack(spacing: 6) {
                        MetricRow(
                            label: "Condition",
                            valueText: s.condition ?? "Normal",
                            isCopyable: false
                        )

                        if let cur = s.currentMaxCapacity {
                            MetricRow(
                                label: "Current Max Capacity",
                                valueText: "\(cur) mAh",
                                isCopyable: true
                            )
                        }

                        if let des = s.designCapacity {
                            MetricRow(
                                label: "Design Capacity",
                                valueText: "\(des) mAh",
                                isCopyable: true
                            )
                        }

                        if let adapter = s.adapterName {
                            let wText = s.adapterWatts.map { " (\(Int($0)) W)" } ?? ""
                            MetricRow(
                                label: "Power Adapter",
                                valueText: "\(adapter)\(wText)",
                                isCopyable: true
                            )
                        }
                    }
                }
            }
        } else {
            InsetEmptyState(
                systemImage: "battery.slash",
                title: "No Battery Installed",
                reason: "This Mac operates on direct AC power and has no internal battery."
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
struct PowerPanel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Charging
            PowerPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: PowerSample(
                        hasBattery: true,
                        charge: 68.0,
                        state: .charging,
                        timeRemaining: 2700,
                        cycleCount: 142,
                        condition: "Normal",
                        designCapacity: 5103,
                        currentMaxCapacity: 5020,
                        powerDrawWatts: 18.5,
                        adapterWatts: 67.0,
                        voltageVolts: 12.0,
                        amperageMilliAmps: 2500.0,
                        designCycleCount: 1000,
                        adapterName: "Apple 67W USB-C Power Adapter"
                    )
                )
            )
            .previewDisplayName("Charging")

            // Discharging
            PowerPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: PowerSample(
                        hasBattery: true,
                        charge: 84.0,
                        state: .discharging,
                        timeRemaining: 14400,
                        cycleCount: 142,
                        condition: "Normal",
                        designCapacity: 5103,
                        currentMaxCapacity: 5020,
                        powerDrawWatts: 12.0,
                        adapterWatts: nil,
                        voltageVolts: 11.8,
                        amperageMilliAmps: -1016.0,
                        designCycleCount: 1000,
                        adapterName: nil
                    )
                )
            )
            .previewDisplayName("Discharging")

            // Power Deficit
            PowerPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: PowerSample(
                        hasBattery: true,
                        charge: 45.0,
                        state: .acConnected,
                        timeRemaining: 3600,
                        cycleCount: 142,
                        condition: "Normal",
                        designCapacity: 5103,
                        currentMaxCapacity: 5020,
                        powerDrawWatts: 65.0,
                        adapterWatts: 30.0,
                        voltageVolts: 11.2,
                        amperageMilliAmps: -3125.0,
                        designCycleCount: 1000,
                        adapterName: "Apple 30W USB-C Power Adapter"
                    )
                )
            )
            .previewDisplayName("Power Deficit")

            // Desktop
            PowerPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: PowerSample(
                        hasBattery: false,
                        charge: nil,
                        state: nil,
                        timeRemaining: nil,
                        cycleCount: nil,
                        condition: nil,
                        designCapacity: nil,
                        currentMaxCapacity: nil,
                        powerDrawWatts: 38.5,
                        adapterWatts: 140.0,
                        voltageVolts: nil,
                        amperageMilliAmps: nil,
                        designCycleCount: nil,
                        adapterName: "Mac Studio Internal PSU"
                    )
                )
            )
            .previewDisplayName("Desktop Mac")
        }
        .padding()
        .background(Color.black)
    }

    private static func makeMockCoordinator(sample: PowerSample) -> MetricsCoordinator {
        let coordinator = MetricsCoordinator.shared
        coordinator.handleReading(.power(Sample(value: sample)))
        return coordinator
    }
}
#endif
