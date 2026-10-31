import SwiftUI
import iStatsCore

/// Purpose-driven CPU popover (ADR 0008, Task 7.4a).
/// Structure: Overview · Cores · History.
/// Answers: "Why is my Mac busy? Which cores are working?"
public struct CPUPopover: View {
    @State public var selectedTab: PopoverTab
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var hoveredCore: (index: Int, usage: Double)?

    public init(
        initialTab: PopoverTab = .overview,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self._selectedTab = State(initialValue: initialTab)
        self.coordinator = coordinator
        self.preferences = preferences
    }

    private var sample: CPUSample? {
        coordinator.latestCPU?.value
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateCPU(sample)
    }

    public var body: some View {
        PopoverScaffold(
            category: .cpu,
            verdict: verdict,
            tabs: [.overview, .detail, .history],
            selectedTab: $selectedTab,
            isLoading: coordinator.latestCPU == nil,
            unavailableReason: coordinator.categoryAvailability[.cpu]?.unavailableReason,
            preferences: preferences,
            coordinator: coordinator
        ) {
            switch selectedTab {
            case .overview:
                overviewTab
            case .detail:
                coresTab
            case .history:
                HistoryTab(category: .cpu, coordinator: coordinator, preferences: preferences)
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let cpu = sample {
            VStack(alignment: .leading, spacing: Tokens.md) {
                // Hero Metric + 60 pt Stacked User/System TrendChart
                HStack(alignment: .top, spacing: Tokens.md) {
                    let coreCount = cpu.perCore.count
                    let freqStr = cpu.frequencyHz.map { " · \(Units.formatFrequencyHz($0))" } ?? ""
                    HeroMetric(
                        primaryValue: String(format: "%.0f", cpu.totalUsage),
                        unit: "%",
                        contextLine: "on \(coreCount) cores\(freqStr)"
                    )
                    .frame(width: 120, alignment: .leading)

                    let userHistory = coordinator.cpuHistory.map { $0.value.user }
                    let systemHistory = coordinator.cpuHistory.map { $0.value.system }
                    TrendChart(
                        mode: .stacked(
                            primary: userHistory,
                            secondary: systemHistory,
                            primaryColor: CategoryPalette.cpu,
                            secondaryColor: Color.red.opacity(0.70)
                        ),
                        fixedMax: 100.0,
                        height: 52,
                        sampleIntervalSeconds: preferences.refreshInterval
                    )
                    .frame(maxWidth: .infinity)
                }

                // 3-Segment Usage Bar
                SegmentedBar(segments: [
                    .init(value: cpu.user, color: CategoryPalette.cpu, label: "User"),
                    .init(value: cpu.system, color: Color.red.opacity(0.85), label: "System"),
                    .init(value: max(0, 100.0 - cpu.user - cpu.system), color: Color.secondary.opacity(0.25), label: "Idle")
                ])

                // Breakdown Legend Rows
                VStack(spacing: 4) {
                    LegendRow(
                        color: CategoryPalette.cpu,
                        label: "User",
                        value: String(format: "%.1f%%", cpu.user)
                    )
                    LegendRow(
                        color: Color.red.opacity(0.85),
                        label: "System",
                        value: String(format: "%.1f%%", cpu.system)
                    )
                    LegendRow(
                        color: Color.secondary.opacity(0.4),
                        label: "Idle",
                        value: String(format: "%.1f%%", max(0, 100.0 - cpu.user - cpu.system))
                    )
                }

                // P / E Cluster Rows (if Apple Silicon / hybrid topology detected)
                if let pCount = cpu.performanceCoreCount, let eCount = cpu.efficiencyCoreCount, pCount > 0 || eCount > 0 {
                    Divider()

                    VStack(spacing: 6) {
                        if let pUsage = cpu.performanceUsage {
                            clusterRow(
                                title: "Performance (\(pCount) cores)",
                                percentage: pUsage,
                                color: CategoryPalette.cpu
                            )
                        }
                        if let eUsage = cpu.efficiencyUsage {
                            clusterRow(
                                title: "Efficiency (\(eCount) cores)",
                                percentage: eUsage,
                                color: CategoryPalette.cpu.opacity(0.7)
                            )
                        }
                    }
                }

                // Load Averages & Uptime Strip
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    if let load = cpu.loadAverage {
                        let cores = Double(max(1, cpu.perCore.count))
                        let hint = load.oneMinute <= cores ? "no thread queueing" : "threads queueing"
                        StatRow(
                            label: "Load Average (1 · 5 · 15m)",
                            value: String(format: "%.2f · %.2f · %.2f (%@)", load.oneMinute, load.fiveMinute, load.fifteenMinute, hint),
                            statusLevel: load.oneMinute > cores ? .elevated : .fine
                        )
                    }

                    StatRow(
                        label: "System Uptime",
                        value: Units.formatUptime(ProcessInfo.processInfo.systemUptime)
                    )
                }
            }
        }
    }

    private func clusterRow(title: String, percentage: Double, color: Color) -> some View {
        HStack {
            Text(title)
                .font(Tokens.bodyLabel)
                .foregroundColor(.secondary)

            Spacer()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(percentage / 100.0)), height: 6)
                }
            }
            .frame(width: 80, height: 6)

            Text(String(format: "%.0f%%", percentage))
                .font(Tokens.monoValue)
                .foregroundColor(.primary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Cores Tab

    @ViewBuilder
    private var coresTab: some View {
        if let cpu = sample {
            let cores = cpu.perCore
            let pCount = cpu.performanceCoreCount ?? 0
            let eCount = cpu.efficiencyCoreCount ?? 0

            VStack(alignment: .leading, spacing: Tokens.sm) {
                // Header with Hovered Core Reading
                HStack {
                    Text("Per-Core Utilization (\(cores.count) Cores)")
                        .font(Tokens.sectionTitle)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let hovered = hoveredCore {
                        Text("Core \(hovered.index + 1): \(String(format: "%.0f%%", hovered.usage))")
                            .font(Tokens.monoValue)
                            .foregroundColor(.primary)
                    }
                }

                // Grid of vertical per-core bars (P cores first, then E cores)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Tokens.md) {
                        if pCount > 0 && eCount > 0 && pCount + eCount <= cores.count {
                            // Grouped P and E Clusters
                            coreClusterGroup(
                                label: "Performance Cores (\(pCount))",
                                coreIndices: Array(0..<pCount),
                                coreLoads: cores,
                                tint: CategoryPalette.cpu
                            )

                            coreClusterGroup(
                                label: "Efficiency Cores (\(eCount))",
                                coreIndices: Array(pCount..<(pCount + eCount)),
                                coreLoads: cores,
                                tint: CategoryPalette.cpu.opacity(0.75)
                            )
                        } else {
                            // Uniform Core Cluster
                            coreClusterGroup(
                                label: "Logical Cores",
                                coreIndices: Array(0..<cores.count),
                                coreLoads: cores,
                                tint: CategoryPalette.cpu
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private func coreClusterGroup(
        label: String,
        coreIndices: [Int],
        coreLoads: [Double],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let groupLoads = coreIndices.compactMap { $0 < coreLoads.count ? coreLoads[$0] : nil }
            let avg = groupLoads.isEmpty ? 0.0 : groupLoads.reduce(0, +) / Double(groupLoads.count)

            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Avg \(String(format: "%.0f%%", avg))")
                    .font(Tokens.monoValue)
                    .foregroundColor(.secondary)
            }

            // Adaptive Columns (up to 12 cores per row)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 16, maximum: 24), spacing: 6), count: min(coreIndices.count, 12)), spacing: 6) {
                ForEach(coreIndices, id: \.self) { idx in
                    let load = idx < coreLoads.count ? coreLoads[idx] : 0.0
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.08))

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(tint)
                                    .frame(height: max(2, geo.size.height * CGFloat(min(max(load, 0.0), 100.0) / 100.0)))
                            }
                        }
                        .frame(height: 54)

                        Text("\(idx + 1)")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            hoveredCore = (index: idx, usage: load)
                        } else if hoveredCore?.index == idx {
                            hoveredCore = nil
                        }
                    }
                }
            }
        }
        .padding(10)
        .cardBackground()
    }
}
