import SwiftUI
import AppKit
import iStatsCore

/// Factory for instantiating Instrument Panels (ADR 0009 / Task 8.6).
@MainActor
public enum PanelFactory {

    /// Instantiates the panel view for a given menu bar item configuration.
    @ViewBuilder
    public static func makePanelView(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        let popConfig = config.resolvedPopoverConfig
        let openingTab = (popConfig.rememberLastTab ? preferences.lastSelectedTab(for: config.category) : nil) ?? popConfig.openingTab
        let focusSource = config.source ?? popConfig.focusSource

        makeCategoryPanelView(
            category: config.category,
            initialTab: openingTab,
            rememberLastTab: popConfig.rememberLastTab,
            focusSource: focusSource,
            coordinator: coordinator,
            preferences: preferences
        )
    }

    /// Instantiates the panel view for a specific metric category.
    @ViewBuilder
    public static func makeCategoryPanelView(
        category: MetricCategory,
        initialTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        switch category {
        case .cpu:
            CPUPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .memory:
            MemoryPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .gpu:
            GPUPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .thermal:
            TemperaturePanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .fan:
            FanPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .network:
            NetworkPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .disk:
            DiskPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .power:
            PowerPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        }
    }
}

/// Dynamic host view bridging MetricsCoordinator live state to PanelScaffold.
public struct PanelHostView: View {
    public let category: MetricCategory
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var selectedTab: PopoverTab

    public init(
        category: MetricCategory,
        initialTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self.category = category
        self.rememberLastTab = rememberLastTab
        self.focusSource = focusSource
        self.coordinator = coordinator
        self.preferences = preferences
        let supported = PopoverTab.supportedTabs(for: category, hasBattery: coordinator.latestPower?.value.hasBattery ?? true)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    public var body: some View {
        let pages = PopoverTab.supportedTabs(
            for: category,
            hasBattery: coordinator.latestPower?.value.hasBattery ?? true
        )
        let glance = deriveGlance()
        let availability = coordinator.categoryAvailability[category]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)
        let status = deriveStatus()
        let ribbonMessage = deriveRibbonMessage()

        PanelScaffold(
            category: category,
            glance: glance,
            status: status,
            ribbon: ribbonMessage,
            pages: pages,
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: category)
            },
            isPinned: PanelController.shared.isPinned(for: category)
        ) { tab in
            pageBody(for: tab)
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: category)
            }
        }
    }

    // MARK: - Glance Derivation

    private func deriveGlance() -> PanelGlance {
        switch category {
        case .cpu:
            let sample = coordinator.latestCPU?.value
            let usage = sample?.totalUsage ?? 0.0
            let headline = PanelHeadline.cpu(sample: sample)
            let userHistory = coordinator.scalarHistory(for: .cpuUser, duration: 60)
            let sysHistory = coordinator.scalarHistory(for: .cpuSystem, duration: 60)
            let combined = zip(userHistory, sysHistory).map(+)
            let insight = InsightEngine.insights(series: combined, interval: 1.0, unit: .percent).first?.text
            let chartMode = LiveChartMode.stacked(
                primary: userHistory,
                secondary: sysHistory,
                primaryColor: CategoryPalette.tint(for: .cpu),
                secondaryColor: CategoryPalette.Series.cpuSystem,
                fixedMax: 100.0
            )
            return PanelGlance(
                value: usage,
                format: "%.0f",
                unit: "%",
                headline: headline,
                insight: insight,
                chartMode: chartMode
            )

        case .memory:
            let sample = coordinator.latestMemory?.value
            let usedGB = sample.map { Double($0.used) / 1_073_741_824.0 } ?? 0.0
            let totalFormatted = sample.map { Units.formatBytes($0.total, standard: preferences.byteUnitStandard) } ?? "16 GB"
            let headline = PanelHeadline.memory(sample: sample, standard: preferences.byteUnitStandard)
            let usedHistory = coordinator.scalarHistory(for: .memoryUsedPercent, duration: 60)
            let insight = InsightEngine.insights(series: usedHistory, interval: 1.0, unit: .percent).first?.text
            let chartMode = LiveChartMode.single(
                values: usedHistory,
                color: CategoryPalette.tint(for: .memory),
                deepColor: CategoryPalette.tintDeep(for: .memory),
                fixedMax: 100.0
            )
            return PanelGlance(
                value: usedGB,
                format: "%.1f",
                unit: "of \(totalFormatted)",
                headline: headline,
                insight: insight,
                chartMode: chartMode
            )

        case .gpu:
            let sample = coordinator.latestGPU?.value
            let util = sample?.utilization ?? 0.0
            let headline = PanelHeadline.gpu(sample: sample)
            let gpuHistory = coordinator.scalarHistory(for: .gpuUtilization, duration: 60)
            let insight = InsightEngine.insights(series: gpuHistory, interval: 1.0, unit: .percent).first?.text
            let chartMode = LiveChartMode.single(
                values: gpuHistory,
                color: CategoryPalette.tint(for: .gpu),
                deepColor: CategoryPalette.tintDeep(for: .gpu),
                fixedMax: 100.0
            )
            return PanelGlance(
                value: util,
                format: "%.0f",
                unit: "%",
                headline: headline,
                insight: insight,
                chartMode: chartMode
            )

        case .thermal:
            let sample = coordinator.latestThermal?.value
            let unit = preferences.temperatureUnit
            let peakC = sample?.peakTemperatureCelsius ?? 0.0
            let peak = unit == .fahrenheit ? Units.celsiusToFahrenheit(peakC) : peakC
            let headline = PanelHeadline.thermal(sample: sample, unit: unit)
            let thermalHistory = coordinator.scalarHistory(for: .thermalPeakCelsius, duration: 60)
                .map { unit == .fahrenheit ? Units.celsiusToFahrenheit($0) : $0 }
            let insight = InsightEngine.insights(
                series: thermalHistory,
                interval: 1.0,
                unit: unit == .fahrenheit ? .fahrenheit : .celsius,
                thresholds: .thermal(unit: unit)
            ).first?.text
            let chartMode = LiveChartMode.single(
                values: thermalHistory,
                color: CategoryPalette.tint(for: .thermal),
                deepColor: CategoryPalette.tintDeep(for: .thermal)
            )
            return PanelGlance(
                value: peak,
                format: "%.0f",
                unit: unit.symbol,
                headline: headline,
                insight: insight,
                chartMode: chartMode
            )

        case .fan:
            let sample = coordinator.latestFan?.value
            let maxRPM = Double(sample?.fans.map(\.rpm).max() ?? 0)
            let headline = PanelHeadline.fan(sample: sample)
            let fanHistory = coordinator.scalarHistory(for: .fanMaxRPM, duration: 60)
            let minRPM = Double(sample?.fans.compactMap(\.minRPM).min() ?? 1200)
            let maxSpecRPM = Double(sample?.fans.compactMap(\.maxRPM).max() ?? 6000)
            let insight = InsightEngine.insights(
                series: fanHistory,
                interval: 1.0,
                unit: .rpm,
                thresholds: .fanRPM(minRPM: minRPM, maxRPM: maxSpecRPM)
            ).first?.text
            let chartMode = LiveChartMode.single(
                values: fanHistory,
                color: CategoryPalette.tint(for: .fan),
                deepColor: CategoryPalette.tintDeep(for: .fan)
            )
            return PanelGlance(
                value: maxRPM,
                format: "%.0f",
                unit: "RPM",
                headline: headline,
                insight: insight,
                chartMode: chartMode
            )

        case .network:
            let sample = coordinator.latestNetwork?.value
            let std = preferences.byteUnitStandard
            let downMB = sample.map { Double($0.totalBytesInPerSec) / 1_000_000.0 } ?? 0.0
            let upMB = sample.map { Double($0.totalBytesOutPerSec) / 1_000_000.0 } ?? 0.0
            let headline = PanelHeadline.network(sample: sample, standard: std)
            let downHistory = coordinator.scalarHistory(for: .networkInBytesPerSec, duration: 60).map { $0 / 1_000_000.0 }
            let upHistory = coordinator.scalarHistory(for: .networkOutBytesPerSec, duration: 60).map { $0 / 1_000_000.0 }
            let insight = InsightEngine.insights(
                series: downHistory.map { $0 * 1_000_000.0 },
                interval: 1.0,
                unit: .bytesPerSecond(standard: std),
                thresholds: .throughputBytesPerSec()
            ).first?.text
            let chartMode = LiveChartMode.mirrored(
                top: downHistory,
                bottom: upHistory,
                topColor: CategoryPalette.tint(for: .network),
                bottomColor: CategoryPalette.Series.networkUpload,
                topLabel: "↓",
                bottomLabel: "↑"
            )
            return PanelGlance(
                value: downMB,
                format: "%.1f",
                unit: "MB/s",
                secondaryGlance: (value: upMB, unit: "MB/s", color: CategoryPalette.Series.networkUpload),
                headline: headline,
                insight: insight,
                chartMode: chartMode
            )

        case .disk:
            let sample = coordinator.latestDisk?.value
            let std = preferences.byteUnitStandard
            let freeGB = sample?.volumes.first.map { Double($0.free) / 1_000_000_000.0 } ?? 0.0
            let headline = PanelHeadline.disk(sample: sample, standard: std)
            let readHistory = coordinator.scalarHistory(for: .diskReadBytesPerSec, duration: 60).map { $0 / 1_000_000.0 }
            let writeHistory = coordinator.scalarHistory(for: .diskWriteBytesPerSec, duration: 60).map { $0 / 1_000_000.0 }
            let insight = InsightEngine.insights(
                series: readHistory.map { $0 * 1_000_000.0 },
                interval: 1.0,
                unit: .bytesPerSecond(standard: std),
                thresholds: .throughputBytesPerSec()
            ).first?.text
            let chartMode = LiveChartMode.mirrored(
                top: readHistory,
                bottom: writeHistory,
                topColor: CategoryPalette.tint(for: .disk),
                bottomColor: CategoryPalette.Series.diskWrite,
                topLabel: "R",
                bottomLabel: "W"
            )
            return PanelGlance(
                value: freeGB,
                format: "%.0f",
                unit: "GB free",
                headline: headline,
                insight: insight,
                chartMode: chartMode
            )

        case .power:
            let sample = coordinator.latestPower?.value
            let val = Double(sample?.charge ?? (sample?.powerDrawWatts ?? 0))
            let unit = (sample?.hasBattery == true) ? "%" : "W"
            let headline = PanelHeadline.power(sample: sample)
            let powerHistory = coordinator.scalarHistory(for: .powerWatts, duration: 60)
            let insight = InsightEngine.insights(
                series: powerHistory,
                interval: 1.0,
                unit: .watts,
                thresholds: .powerWatts
            ).first?.text
            let chartMode = LiveChartMode.single(
                values: powerHistory,
                color: CategoryPalette.tint(for: .power),
                deepColor: CategoryPalette.tintDeep(for: .power),
                fixedMax: (sample?.hasBattery == true) ? 100.0 : nil
            )
            return PanelGlance(
                value: val,
                format: "%.0f",
                unit: unit,
                headline: headline,
                insight: insight,
                chartMode: chartMode
            )
        }
    }

    private func deriveStatus() -> StatusLevel {
        switch category {
        case .cpu:
            let usage = coordinator.latestCPU?.value.totalUsage ?? 0
            if usage >= 90 { return .critical }
            if usage >= 75 { return .elevated }
            return .fine
        case .memory:
            let pressure = coordinator.latestMemory?.value.pressure ?? .normal
            switch pressure {
            case .normal: return .fine
            case .warning: return .warning
            case .critical: return .critical
            }
        case .gpu:
            let util = coordinator.latestGPU?.value.utilization ?? 0
            if util >= 95 { return .critical }
            if util >= 80 { return .elevated }
            return .fine
        case .thermal:
            let p = coordinator.latestThermal?.value.pressure ?? .nominal
            switch p {
            case .nominal: return .fine
            case .fair: return .elevated
            case .serious: return .warning
            case .critical: return .critical
            }
        case .fan:
            return .fine
        case .network, .disk:
            return .fine
        case .power:
            if let sample = coordinator.latestPower?.value {
                if sample.hasBattery && sample.state != .charging, let charge = sample.charge {
                    if charge <= 10 { return .critical }
                    if charge <= 20 { return .warning }
                }
            }
            return .fine
        }
    }

    private func deriveRibbonMessage() -> String? {
        switch category {
        case .cpu:
            let usage = coordinator.latestCPU?.value.totalUsage ?? 0
            if usage >= 90 { return "Sustained high CPU load" }
            if usage >= 75 { return "Elevated processor demand" }
            return nil
        case .memory:
            let pressure = coordinator.latestMemory?.value.pressure ?? .normal
            if pressure == .critical { return "Memory pressure critical: system may page heavily" }
            if pressure == .warning { return "Elevated memory pressure: swap active" }
            return nil
        case .gpu:
            let util = coordinator.latestGPU?.value.utilization ?? 0
            if util >= 95 { return "High GPU demand" }
            return nil
        case .thermal:
            let p = coordinator.latestThermal?.value.pressure ?? .nominal
            if p == .critical { return "Thermal throttling engaged" }
            if p == .serious { return "High operating temperature detected" }
            if p == .fair { return "Elevated temperature" }
            return nil
        case .fan:
            return nil
        case .network, .disk:
            return nil
        case .power:
            if let sample = coordinator.latestPower?.value {
                if sample.hasBattery && sample.state != .charging, let charge = sample.charge {
                    if charge <= 10 { return "Battery critically low: connect charger immediately" }
                    if charge <= 20 { return "Battery low: connect power soon" }
                }
            }
            return nil
        }
    }

    // MARK: - Page Body (Stub until 8.8)

    @ViewBuilder
    private func pageBody(for tab: PopoverTab) -> some View {
        switch tab {
        case .overview:
            Module(eyebrow: "Telemetry") {
                VStack(spacing: 8) {
                    MetricRow(
                        label: "\(category.displayName) Activity",
                        valueText: "\(Int(deriveGlance().value ?? 0))\(deriveGlance().unit)"
                    )
                }
            }
        case .detail:
            Module(eyebrow: "Details") {
                VStack(spacing: 8) {
                    MetricRow(
                        label: "Status",
                        valueText: deriveStatus() == .fine ? "Normal" : "\(deriveStatus())"
                    )
                }
            }
        case .history:
            HistoryPage(category: category, coordinator: coordinator, preferences: preferences)
        }
    }
}

/// The fallback panel view shown when no widgets are currently active in the menu bar.
public struct NoWidgetsActiveView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: Instrument.Space.l) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            VStack(spacing: Instrument.Space.xs) {
                Text("No Widgets Active")
                    .font(Instrument.Typography.title)
                Text("Enable metrics to display them in your menu bar.")
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Open Preferences...") {
                PreferencesWindowController.shared.showPreferences()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(Instrument.Space.xxl)
        .frame(width: Instrument.Size.panelWidth)
    }
}
