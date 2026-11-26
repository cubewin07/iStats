import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Power Instrument Panel (Task 8.5.8h / ADR 0009 / ADR 0010).
/// Feeds timestamped `.powerWatts` scalar history (B8/B9) into a nice-ceiling hero LiveChart,
/// embeds BatteryGlyph + state summary in a calm-velocity Power Flow card, and organizes
/// battery health and electrical diagnostics into hairline tables.
public struct PowerPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var derivedCache = DerivedCache()

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

    private var sampleWrapper: Sample<PowerSample>? {
        coordinator.latestPower
    }

    private var sample: PowerSample? {
        sampleWrapper?.value
    }

    private var hasBattery: Bool {
        sample?.hasBattery ?? true
    }

    private var supportedPages: [PopoverTab] {
        PopoverTab.supportedTabs(for: .power, hasBattery: hasBattery)
    }

    public var body: some View {
        let derived = memoizedDerivedState()
        let availability = coordinator.categoryAvailability[.power]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            chrome: PanelChrome(
                category: .power,
                status: derived.status,
                ribbon: derived.ribbon,
                availability: availability,
                isLoading: isLoading,
                isPaused: coordinator.isSamplingPaused,
                isLowPowerModeActive: coordinator.isLowPowerModeActive,
                isPinned: PanelController.shared.isPinned(for: .power),
                hasBattery: hasBattery,
                refreshInterval: preferences.refreshInterval,
                enabledCategories: preferences.enabledCategories,
                onTogglePause: {
                    coordinator.toggleSamplingPaused()
                },
                onPinToggle: {
                    PanelController.shared.togglePin(for: .power)
                }
            ),
            glance: derived.glance,
            pages: supportedPages,
            selection: $selectedTab
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample, status: derived.status)
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

    // MARK: - Memoised Derived State (B8 + B9 + B14)

    private struct CacheKey: Equatable {
        let timestamp: Date?
        let sample: PowerSample?
        let refreshInterval: TimeInterval
    }

    private struct DerivedState {
        let glance: PanelGlance
        let status: StatusLevel
        let ribbon: String?
    }

    private final class DerivedCache {
        var key: CacheKey?
        var value: DerivedState?
    }

    private func memoizedDerivedState() -> DerivedState {
        let key = CacheKey(
            timestamp: sampleWrapper?.timestamp,
            sample: sample,
            refreshInterval: preferences.refreshInterval
        )
        if let cachedKey = derivedCache.key, cachedKey == key, let cached = derivedCache.value {
            return cached
        }

        let computed = computeDerivedState(sampleWrapper: sampleWrapper)
        derivedCache.key = key
        derivedCache.value = computed
        return computed
    }

    private func computeDerivedState(sampleWrapper: Sample<PowerSample>?) -> DerivedState {
        let currentSample = sampleWrapper?.value
        let showsBattery = currentSample?.hasBattery ?? true
        let headline = Self.headline(sample: currentSample)

        // Battery Macs plot charge % (matches the hero); desktops plot watts.
        let seriesKey: ScalarSeriesKey = showsBattery ? .powerChargePercent : .powerWatts
        let refDate = sampleWrapper?.timestamp ?? Date()
        let points = coordinator.timedScalarHistory(
            for: seriesKey,
            duration: 60.0,
            referenceDate: refDate
        )

        let insight = showsBattery
            ? nil
            : InsightEngine.best(
                series: points.map(\.value),
                interval: preferences.refreshInterval,
                unit: .watts,
                thresholds: .powerWatts
            )?.text

        let chartMode = LiveChartMode.single(
            points: points,
            color: CategoryPalette.color(for: .power),
            deepColor: CategoryPalette.tintDeep(for: .power),
            domainFloor: 0.0,
            fixedMax: showsBattery ? 100.0 : nil
        )

        let heroValue = showsBattery ? currentSample?.charge : currentSample?.powerDrawWatts
        let glance = Self.makeGlance(
            hasBattery: showsBattery,
            heroValue: heroValue,
            headline: headline,
            insight: insight,
            chartMode: chartMode
        )

        let (status, ribbon) = deriveStatusAndRibbon(sample: currentSample)
        return DerivedState(glance: glance, status: status, ribbon: ribbon)
    }

    /// One glance builder for battery and desktop. Hero unit and scrub unit always agree:
    /// battery Macs read percent, desktops read watts.
    static func makeGlance(
        hasBattery: Bool,
        heroValue: Double?,
        headline: String,
        insight: String?,
        chartMode: LiveChartMode?
    ) -> PanelGlance {
        let unit = hasBattery ? "%" : "W"
        let format = hasBattery ? "%.0f" : "%.1f"
        let scrubFormat: String = hasBattery ? "%.0f%%" : "%.1f W"
        let hasValue = heroValue != nil
        let formatted: String? = hasValue ? nil : "—"
        return PanelGlance(
            value: heroValue,
            formattedValue: formatted,
            format: format,
            unit: hasValue ? unit : "",
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            chartHeight: Instrument.Size.chartHeightCompact,
            scrubFormat: { String(format: scrubFormat, $0) }
        )
    }

    /// "Discharging 12.4 W · 3h 40m left". Watts live here and in Power Flow, not in the hero.
    static func headline(sample: PowerSample?) -> String {
        guard let s = sample else { return "Power telemetry unavailable" }
        let state: String
        var timeSuffix: String?
        switch s.variant {
        case .charging: state = "Charging"; timeSuffix = "to full"
        case .discharging: state = "Discharging"; timeSuffix = "left"
        case .lowBattery: state = "Low battery"; timeSuffix = "left"
        case .onHold: state = "Charging on hold"
        case .powerDeficit: state = "Power deficit"
        case .charged: state = "Fully charged"
        case .acDesktop: state = "On AC power"
        case .unavailable: state = "Power unmetered"
        }
        var parts = [state]
        if let watts = s.powerDrawWatts, watts > 0 {
            parts[0] += String(format: " %.1f W", watts)
        }
        if let secs = s.timeRemaining, secs > 0, let suffix = timeSuffix {
            parts.append("\(Self.formatDurationHM(seconds: secs)) \(suffix)")
        }
        return parts.joined(separator: " · ")
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
            if StatusThresholds.battery(chargePercent: charge, isCharging: false) == .critical {
                return (.critical, "Battery critically low: connect charger immediately")
            } else {
                return (.warning, "Battery low: connect power soon")
            }
        }

        return (.fine, nil)
    }

    // MARK: - Now Page (Max 2 Sections)

    @ViewBuilder
    private func nowPage(sample: PowerSample?, status: StatusLevel) -> some View {
        if let s = sample {
            if s.hasBattery {
                batteryNowPage(sample: s, status: status)
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
    private func batteryNowPage(sample: PowerSample, status: StatusLevel) -> some View {
        let flow = PowerFlowMath.calculateFlow(
            hasBattery: sample.hasBattery,
            state: sample.state,
            adapterWatts: sample.adapterWatts,
            powerDrawWatts: sample.powerDrawWatts,
            voltageVolts: sample.voltageVolts,
            amperageMilliAmps: sample.amperageMilliAmps
        )

        VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
            // Section 1: Power Flow with embedded BatteryGlyph + state summary header
            Section("Power Flow") {
                Text(sample.variant.displayName)
                    .font(Instrument.Typography.caption.weight(.medium))
                    .foregroundStyle(status.isQuiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(status.color))
            } content: {
                VStack(alignment: .leading, spacing: Instrument.Space.m) {
                    HStack(alignment: .center, spacing: Instrument.Space.l) {
                        BatteryGlyph(
                            charge: sample.charge,
                            isCharging: sample.state == .charging,
                            statusLevel: status
                        )

                        VStack(alignment: .leading, spacing: Instrument.Space.xxs) {
                            Text(batteryHeaderSummary(for: sample))
                                .font(Instrument.Typography.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if let detail = batteryHeaderDetail(for: sample) {
                                Text(detail)
                                    .font(Instrument.Typography.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, Instrument.Space.s)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Instrument.Surface.hairline)
                            .frame(height: 0.5)
                    }

                    PowerFlowView(flow: flow, variant: sample.variant)
                        .padding(.vertical, Instrument.Space.xxs)
                }
            }

            // Section 2: Time & Source
            Section("Time & Source") {
                VStack(spacing: 0) {
                    MetricRow(
                        label: sample.state == .charging ? "Time to Full" : "Time Remaining",
                        valueText: formattedTimeRemaining(for: sample),
                        showHairline: true
                    )

                    MetricRow(
                        label: "Adapter Wattage",
                        valueText: sample.adapterWatts.map { "\(Int(round($0))) W" } ?? "Not Connected",
                        showHairline: true
                    )

                    MetricRow(
                        label: "Power Source",
                        valueText: powerSourceLabel(for: sample),
                        showHairline: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func desktopNowPage(sample: PowerSample) -> some View {
        let drawWatts = sample.powerDrawWatts
        let ratedMax = max(100.0, sample.adapterWatts ?? 150.0, (drawWatts ?? 0.0) * 1.2)
        let scaleCeiling = ChartScale.niceCeiling(for: ratedMax, floorVal: 0.0, minSpan: 50.0).ceiling

        Section("System Power Draw") {
            if let drawWatts {
                Text(String(format: "%.1f W", drawWatts))
                    .font(Instrument.Typography.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.primary)
            } else {
                Text("AC Power")
                    .font(Instrument.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                if let drawWatts {
                    VStack(alignment: .leading, spacing: 5) {
                        Meter(
                            progress: min(1.0, max(0.0, drawWatts / scaleCeiling)),
                            height: .medium,
                            tint: CategoryPalette.color(for: .power),
                            deepTint: CategoryPalette.tintDeep(for: .power),
                            thresholdTick: sample.adapterWatts.map { min(1.0, $0 / scaleCeiling) }
                        )

                        HStack {
                            Text("0 W")
                            Spacer()
                            if let adapterW = sample.adapterWatts, adapterW > 0 {
                                Text("PSU \(Int(round(adapterW))) W")
                            } else {
                                Text("\(Int(round(scaleCeiling))) W scale")
                            }
                        }
                        .font(Instrument.Typography.micro)
                        .foregroundStyle(.tertiary)
                    }
                }

                VStack(spacing: 0) {
                    MetricRow(
                        label: "System Draw",
                        valueText: drawWatts.map { String(format: "%.1f W", $0) } ?? "Unavailable",
                        showHairline: true
                    )

                    MetricRow(
                        label: "Power Source",
                        valueText: "AC Power",
                        showHairline: sample.adapterName != nil || sample.adapterWatts != nil
                    )

                    if sample.adapterName != nil || sample.adapterWatts != nil {
                        MetricRow(
                            label: "Power Supply",
                            valueText: adapterDisplayText(for: sample),
                            isCopyable: sample.adapterName != nil,
                            showHairline: false
                        )
                    }
                }
            }
        }
    }

    /// Power Flow caption: live watts (also in the headline) with direction.
    private func batteryHeaderSummary(for sample: PowerSample) -> String {
        guard let watts = sample.powerDrawWatts, watts > 0 else { return sample.variant.displayName }
        return String(format: "%.1f W", watts)
    }

    private func batteryHeaderDetail(for sample: PowerSample) -> String? {
        switch sample.variant {
        case .charged: return "Connected to AC power"
        case .onHold: return "Optimized Battery Charging active"
        default: return nil
        }
    }

    private func formattedTimeRemaining(for sample: PowerSample) -> String {
        if let secs = sample.timeRemaining, secs > 0 {
            return Self.formatDurationHM(seconds: secs)
        }
        switch sample.variant {
        case .charged:
            return "Fully Charged"
        case .onHold:
            return "On Hold"
        case .charging, .discharging, .lowBattery:
            return "Calculating…"
        case .powerDeficit:
            return "Battery Assisting"
        case .acDesktop, .unavailable:
            return "Unavailable"
        }
    }

    private static func formatDurationHM(seconds: TimeInterval) -> String {
        let mins = max(1, Int(seconds / 60))
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func powerSourceLabel(for sample: PowerSample) -> String {
        if sample.isUsingBatteryPower || sample.state == .discharging {
            return "Internal Battery"
        }
        return "AC Power"
    }

    private func adapterDisplayText(for sample: PowerSample) -> String {
        switch (sample.adapterName, sample.adapterWatts) {
        case (let name?, let watts?) where watts > 0:
            return "\(name) (\(Int(round(watts))) W)"
        case (let name?, _):
            return name
        case (nil, let watts?) where watts > 0:
            return "\(Int(round(watts))) W Adapter"
        default:
            return "Not Connected"
        }
    }

    // MARK: - Details Page (Max 2 Sections)

    @ViewBuilder
    private func healthPage(sample: PowerSample?) -> some View {
        if let s = sample, s.hasBattery {
            let batteryTemp = coordinator.latestThermal.flatMap {
                ThermalSensorClassifier.peakCelsius(in: $0.value, for: .battery)
            }

            VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
                // Section 1: Battery Health & Cycle Life
                batteryHealthSection(sample: s)

                // Section 2: Electrical Diagnostics
                electricalDiagnosticsSection(sample: s, batteryTempCelsius: batteryTemp)
            }
        } else {
            InsetEmptyState(
                systemImage: "battery.slash",
                title: "No Battery Installed",
                reason: "This Mac operates on direct AC power and has no internal battery."
            )
        }
    }

    @ViewBuilder
    private func batteryHealthSection(sample: PowerSample) -> some View {
        let health = sample.healthPercentage
        let ringFraction = min(1.0, max(0.0, (health ?? 0.0) / 100.0))

        Section("Battery Health") {
            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                HStack(alignment: .center, spacing: Instrument.Space.l) {
                    ZStack {
                        RingStack(
                            rings: [
                                RingData(
                                    fraction: ringFraction,
                                    color: CategoryPalette.color(for: .power),
                                    label: "Health"
                                )
                            ],
                            size: 68,
                            ringWidth: 6
                        )

                        Text(health.map { "\(Int(round($0)))%" } ?? "—")
                            .font(Instrument.Typography.headline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(health != nil ? .primary : .secondary)
                    }

                    VStack(spacing: 0) {
                        MetricRow(
                            label: "Cycle Count",
                            valueText: sample.cycleCount.map { "\($0) / \(sample.designCycleCount ?? 1000)" } ?? "Unavailable",
                            glossaryKey: .cycleCount,
                            showHairline: true
                        )

                        MetricRow(
                            label: "Condition",
                            valueText: sample.condition ?? "Normal",
                            showHairline: false
                        )
                    }
                }

                // Design vs Current Capacity Meter
                if let cur = sample.currentMaxCapacity, let des = sample.designCapacity, des > 0 {
                    let capacityFraction = min(1.0, max(0.0, Double(cur) / Double(des)))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            HStack(spacing: Instrument.Space.xs) {
                                Text("Current vs Design Capacity")
                                    .font(Instrument.Typography.caption)
                                    .foregroundStyle(.secondary)
                                InfoButton(term: .maxCapacity)
                            }
                            Spacer()
                            Text("\(cur) / \(des) mAh")
                                .font(Instrument.Typography.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(.primary)
                        }

                        Meter(
                            progress: capacityFraction,
                            height: .small,
                            tint: CategoryPalette.color(for: .power),
                            deepTint: CategoryPalette.tintDeep(for: .power)
                        )
                    }
                    .padding(.top, Instrument.Space.xxs)
                } else {
                    MetricRow(
                        label: "Design vs Current",
                        valueText: "Unavailable",
                        showHairline: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func electricalDiagnosticsSection(
        sample: PowerSample,
        batteryTempCelsius: Double?
    ) -> some View {
        Section("Electrical Diagnostics") {
            VStack(spacing: 0) {
                MetricRow(
                    label: "Voltage",
                    valueText: sample.voltageVolts.map { String(format: "%.2f V", $0) } ?? "Unavailable",
                    showHairline: true
                )

                MetricRow(
                    label: "Amperage",
                    valueText: sample.amperageMilliAmps.map { String(format: "%+.0f mA", $0) } ?? "Unavailable",
                    showHairline: true
                )

                MetricRow(
                    label: "Temperature",
                    valueText: batteryTempCelsius.map {
                        Units.formatTemperature($0, unit: preferences.temperatureUnit, fractionDigits: 1)
                    } ?? "Unavailable",
                    showHairline: true
                )

                MetricRow(
                    label: "Charger ID",
                    valueText: adapterDisplayText(for: sample),
                    isCopyable: sample.adapterName != nil,
                    showHairline: false
                )
            }
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
        let suiteName = "iStats.Preview.Power.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(preferencesStore: prefs)
        coordinator.handleReading(.power(Sample(value: sample)))
        return coordinator
    }
}
#endif
