import SwiftUI
import iStatsCore

/// Purpose-driven Battery & Power popover (ADR 0008, Task 7.4h).
/// Structure: Overview · Health · History (Laptop) or Overview · History (Desktop).
/// Answers: "How much battery is left? How much power am I drawing?"
public struct PowerPopover: View {
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

    private var sample: PowerSample? {
        coordinator.latestPower?.value
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluatePower(sample)
    }

    private var hasBattery: Bool {
        sample?.hasBattery ?? true
    }

    private var supportedTabs: [PopoverTab] {
        PopoverTab.supportedTabs(for: .power, hasBattery: hasBattery)
    }

    public var body: some View {
        PopoverScaffold(
            category: .power,
            verdict: verdict,
            tabs: supportedTabs,
            selectedTab: $selectedTab,
            isLoading: coordinator.latestPower == nil,
            unavailableReason: coordinator.categoryAvailability[.power]?.unavailableReason,
            preferences: preferences,
            coordinator: coordinator
        ) {
            switch selectedTab {
            case .overview:
                overviewTab
            case .detail:
                if hasBattery {
                    healthTab
                } else {
                    overviewTab
                }
            case .history:
                HistoryTab(category: .power, coordinator: coordinator, preferences: preferences)
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let pwr = sample {
            VStack(alignment: .leading, spacing: Tokens.md) {
                // Hero Metric + Sparkline
                HStack(alignment: .top, spacing: Tokens.md) {
                    if hasBattery {
                        let charge = pwr.charge ?? 0.0
                        let timeStr: String = {
                            if let sec = pwr.timeRemaining, sec > 0 {
                                let h = Int(sec) / 3600
                                let m = (Int(sec) % 3600) / 60
                                return "\(h)h \(m)m remaining"
                            }
                            return pwr.state?.rawValue.capitalized ?? "Battery"
                        }()

                        HeroMetric(
                            primaryValue: String(format: "%.0f", charge),
                            unit: "%",
                            contextLine: timeStr
                        )
                        .frame(width: 140, alignment: .leading)
                    } else {
                        let watts = pwr.powerDrawWatts ?? 0.0
                        HeroMetric(
                            primaryValue: String(format: "%.1f", watts),
                            unit: "W",
                            contextLine: "System Power Draw"
                        )
                        .frame(width: 140, alignment: .leading)
                    }

                    let powerHistory = coordinator.powerHistory.map { $0.value.powerDrawWatts ?? 0.0 }
                    TrendChart(
                        mode: .single(
                            values: powerHistory,
                            color: CategoryPalette.power,
                            fillGradient: true
                        ),
                        height: 52,
                        sampleIntervalSeconds: preferences.refreshInterval
                    )
                    .frame(maxWidth: .infinity)
                }

                // Battery Gauge Bar (if battery Mac)
                if hasBattery, let charge = pwr.charge {
                    let level = StatusThresholds.battery(chargePercent: charge, isCharging: pwr.state == .charging)
                    SegmentedBar(segments: [
                        .init(value: charge, color: level.color, label: "Charge"),
                        .init(value: max(0, 100.0 - charge), color: Color.secondary.opacity(0.2), label: "Depleted")
                    ])
                }

                // Numeric Power Flow Strip
                VStack(spacing: 6) {
                    if let draw = pwr.powerDrawWatts {
                        StatRow(
                            label: "Current Power Draw",
                            value: String(format: "%.2f W", draw)
                        )
                    }

                    if let adapter = pwr.adapterWatts, adapter > 0 {
                        StatRow(
                            label: "Power Adapter Connected",
                            value: "\(adapter) W"
                        )
                    }

                    StatRow(
                        label: "Power Source",
                        value: !pwr.isUsingBatteryPower ? "Power Adapter" : "Battery"
                    )
                }
                .padding(10)
                .cardBackground()
            }
        }
    }

    // MARK: - Health Tab

    @ViewBuilder
    private var healthTab: some View {
        if let pwr = sample {
            VStack(alignment: .leading, spacing: Tokens.md) {
                Text("Battery Health & Longevity")
                    .font(Tokens.sectionTitle)
                    .foregroundColor(.secondary)

                VStack(spacing: 6) {
                    if let cycles = pwr.cycleCount {
                        StatRow(
                            label: "Charge Cycle Count",
                            value: "\(cycles) cycles"
                        )
                    }

                    if let health = pwr.healthPercentage {
                        let level: StatusLevel = health >= 80 ? .fine : (health >= 70 ? .elevated : .warning)
                        StatRow(
                            label: "Maximum Capacity",
                            value: String(format: "%.0f%%", health),
                            statusLevel: level
                        )
                    }

                    if let cond = pwr.condition {
                        StatRow(
                            label: "Condition",
                            value: cond
                        )
                    }

                    let batTemp = coordinator.latestThermal?.value.sensors.first(where: {
                        $0.name.lowercased().contains("battery")
                    })?.celsius
                    if let temp = batTemp {
                        let level = StatusThresholds.temperature(celsius: temp, source: .battery)
                        StatRow(
                            label: "Battery Temperature",
                            value: Units.formatTemperature(temp, unit: preferences.temperatureUnit, fractionDigits: 1),
                            statusLevel: level
                        )
                    }
                }
                .padding(10)
                .cardBackground()
            }
        }
    }
}
