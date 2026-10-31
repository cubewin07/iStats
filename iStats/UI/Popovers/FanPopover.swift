import SwiftUI
import iStatsCore

/// Purpose-driven Fans popover (ADR 0008, Task 7.4e).
/// Structure: Overview · History (2 tabs).
/// Answers: "Are my fans running loud? How fast are they spinning?"
public struct FanPopover: View {
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

    private var sample: FanSample? {
        coordinator.latestFan?.value
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateFan(sample)
    }

    private var isFanless: Bool {
        sample?.isFanless == true || (sample != nil && sample!.fans.isEmpty)
    }

    public var body: some View {
        PopoverScaffold(
            category: .fan,
            verdict: verdict,
            tabs: [.overview, .history],
            selectedTab: $selectedTab,
            isLoading: coordinator.latestFan == nil,
            unavailableReason: coordinator.categoryAvailability[.fan]?.unavailableReason,
            preferences: preferences,
            coordinator: coordinator
        ) {
            switch selectedTab {
            case .overview, .detail:
                overviewTab
            case .history:
                HistoryTab(category: .fan, coordinator: coordinator, preferences: preferences)
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if isFanless {
            VStack(spacing: 12) {
                Image(systemName: "fan.slash")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)

                VStack(spacing: 4) {
                    Text("Passive Cooling")
                        .font(.system(size: 14, weight: .semibold))
                    Text("This Mac has no physical fans. Heat dissipation is completely silent via chassis conduction.")
                        .font(Tokens.bodyLabel)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        } else if let fan = sample {
            let fans = fan.fans

            VStack(alignment: .leading, spacing: Tokens.md) {
                // Hero Metric + Sparkline
                HStack(alignment: .top, spacing: Tokens.md) {
                    let maxRPM = fans.map(\.rpm).max() ?? 0
                    HeroMetric(
                        primaryValue: Units.formatRPM(maxRPM),
                        unit: "",
                        contextLine: "\(fans.count) active \(fans.count == 1 ? "fan" : "fans")"
                    )
                    .frame(width: 130, alignment: .leading)

                    let fanHistory = coordinator.fanHistory.map { s -> Double in
                        Double(s.value.fans.map(\.rpm).max() ?? 0)
                    }
                    TrendChart(
                        mode: .single(
                            values: fanHistory,
                            color: CategoryPalette.fan,
                            fillGradient: true
                        ),
                        height: 52,
                        sampleIntervalSeconds: preferences.refreshInterval
                    )
                    .frame(maxWidth: .infinity)
                }

                // Per-Fan RPM Range Bars
                VStack(spacing: 10) {
                    ForEach(fans, id: \.name) { fanReading in
                        let minR = Double(fanReading.minRPM ?? 1200)
                        let maxR = Double(fanReading.maxRPM ?? 6000)
                        let curR = Double(fanReading.rpm)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(fanReading.name)
                                    .font(Tokens.bodyLabel)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(Units.formatRPM(fanReading.rpm))
                                    .font(Tokens.monoValue)
                                    .foregroundColor(CategoryPalette.fan)
                            }

                            RangeBar(
                                value: curR,
                                min: minR,
                                max: maxR,
                                tintColor: CategoryPalette.fan
                            )
                        }
                    }
                }
                .padding(10)
                .cardBackground()

                // Firmware Safety & Operating Policy
                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "shield.checkerboard")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Controlled")
                            .font(.system(size: 11, weight: .semibold))
                        Text(FanControlPolicy.readOnlyExplanation)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
