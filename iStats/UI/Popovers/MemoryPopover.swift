import SwiftUI
import iStatsCore

/// Purpose-driven Memory popover (ADR 0008, Task 7.4b).
/// Structure: Overview · Pressure · History.
/// Answers: "Am I running out of RAM? Is memory pressure elevating?"
public struct MemoryPopover: View {
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

    private var sample: MemorySample? {
        coordinator.latestMemory?.value
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateMemory(sample, standard: preferences.byteUnitStandard)
    }

    public var body: some View {
        PopoverScaffold(
            category: .memory,
            verdict: verdict,
            tabs: [.overview, .detail, .history],
            selectedTab: $selectedTab,
            isLoading: coordinator.latestMemory == nil,
            unavailableReason: coordinator.categoryAvailability[.memory]?.unavailableReason,
            preferences: preferences,
            coordinator: coordinator
        ) {
            switch selectedTab {
            case .overview:
                overviewTab
            case .detail:
                pressureTab
            case .history:
                HistoryTab(category: .memory, coordinator: coordinator, preferences: preferences)
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let mem = sample {
            let total = Double(mem.total)
            let usedPct = total > 0 ? (Double(mem.used) / total) * 100.0 : 0.0
            let std = preferences.byteUnitStandard

            let appBytes = Double(mem.appMemory ?? mem.active ?? (mem.used - min(mem.used, mem.wired + mem.compressed)))
            let wiredBytes = Double(mem.wired)
            let compBytes = Double(mem.compressed)
            let freeBytes = Double(mem.free)

            VStack(alignment: .leading, spacing: Tokens.md) {
                // Hero Metric + Sparkline
                HStack(alignment: .top, spacing: Tokens.md) {
                    HeroMetric(
                        primaryValue: String(format: "%.0f", usedPct),
                        unit: "%",
                        contextLine: "\(Units.formatBytes(mem.used, standard: std)) of \(Units.formatBytes(mem.total, standard: std))"
                    )
                    .frame(width: 130, alignment: .leading)

                    let memHistory = coordinator.memoryHistory.map { s -> Double in
                        guard s.value.total > 0 else { return 0.0 }
                        return (Double(s.value.used) / Double(s.value.total)) * 100.0
                    }
                    TrendChart(
                        mode: .single(
                            values: memHistory,
                            color: CategoryPalette.memory,
                            fillGradient: true
                        ),
                        fixedMax: 100.0,
                        height: 52,
                        sampleIntervalSeconds: preferences.refreshInterval
                    )
                    .frame(maxWidth: .infinity)
                }

                // 4-Segment Memory Allocation Bar
                SegmentedBar(segments: [
                    .init(value: appBytes, color: CategoryPalette.memory, label: "App"),
                    .init(value: wiredBytes, color: Color.orange, label: "Wired"),
                    .init(value: compBytes, color: Color.purple, label: "Compressed"),
                    .init(value: freeBytes, color: Color.secondary.opacity(0.25), label: "Free")
                ])

                // Breakdown Legend Rows
                VStack(spacing: 4) {
                    LegendRow(
                        color: CategoryPalette.memory,
                        label: "App Memory",
                        value: Units.formatBytes(UInt64(appBytes), standard: std),
                        shareText: total > 0 ? String(format: "%.0f%%", (appBytes / total) * 100.0) : nil
                    )
                    LegendRow(
                        color: Color.orange,
                        label: "Wired Memory",
                        value: Units.formatBytes(UInt64(wiredBytes), standard: std),
                        shareText: total > 0 ? String(format: "%.0f%%", (wiredBytes / total) * 100.0) : nil
                    )
                    LegendRow(
                        color: Color.purple,
                        label: "Compressed",
                        value: Units.formatBytes(UInt64(compBytes), standard: std),
                        shareText: total > 0 ? String(format: "%.0f%%", (compBytes / total) * 100.0) : nil
                    )
                    LegendRow(
                        color: Color.secondary.opacity(0.4),
                        label: "Cached Files / Free",
                        value: Units.formatBytes(UInt64(freeBytes + Double(mem.cached)), standard: std),
                        shareText: total > 0 ? String(format: "%.0f%%", ((freeBytes + Double(mem.cached)) / total) * 100.0) : nil
                    )
                }

                // Swap Strip
                Divider()

                HStack {
                    Text("Swap Memory Used")
                        .font(Tokens.bodyLabel)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Units.formatBytes(mem.swapUsed, standard: std))
                        .font(Tokens.monoValue)
                        .foregroundColor(mem.swapUsed > 0 ? .orange : .primary)
                }
            }
        }
    }

    // MARK: - Pressure Tab

    @ViewBuilder
    private var pressureTab: some View {
        if let mem = sample {
            let std = preferences.byteUnitStandard
            let level = StatusThresholds.memory(sample: mem)

            VStack(alignment: .leading, spacing: Tokens.md) {
                // Pressure Status Card
                HStack(spacing: 12) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kernel Memory Pressure: \(mem.pressure.rawValue.capitalized)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(pressureExplanation(mem.pressure))
                            .font(Tokens.bodyLabel)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .cardBackground()

                if level != .fine {
                    StatusBanner(
                        iconName: "exclamationmark.triangle.fill",
                        message: "macOS is actively compressing memory pages and may write to disk swap if pressure increases.",
                        level: level
                    )
                }

                // Swap Details Grid
                VStack(alignment: .leading, spacing: 6) {
                    Text("Virtual Memory & Paging")
                        .font(Tokens.sectionTitle)
                        .foregroundColor(.secondary)

                    StatRow(
                        label: "Swap Used",
                        value: Units.formatBytes(mem.swapUsed, standard: std),
                        statusLevel: mem.swapUsed > 0 ? .elevated : .fine
                    )

                    if let totalSwap = mem.swapTotal {
                        StatRow(
                            label: "Swap Allocated",
                            value: Units.formatBytes(totalSwap, standard: std)
                        )
                    }

                    if let cached = mem.cached as UInt64? {
                        StatRow(
                            label: "Purgeable File Cache",
                            value: Units.formatBytes(cached, standard: std)
                        )
                    }
                }
                .padding(10)
                .cardBackground()
            }
        }
    }

    private func pressureExplanation(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal:
            return "RAM availability is healthy. Apps have plenty of free address space."
        case .warning:
            return "Memory is congested. Background pages are being compressed to reclaim space."
        case .critical:
            return "Severe memory pressure. Performance degradation and paging may occur."
        }
    }
}

