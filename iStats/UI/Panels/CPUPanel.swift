import SwiftUI
import AppKit
import iStatsCore

/// Dedicated CPU Instrument Panel (Task 8.8a / ADR 0009 / Blueprint §6.1).
/// Features the signature Core Map, Load Average dot-plot, per-core telemetry, and breakdown capsule.
public struct CPUPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var hoveredCoreInfo: String?

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
        let supported = PopoverTab.supportedTabs(for: .cpu)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    public var body: some View {
        let sample = coordinator.latestCPU?.value
        let glance = deriveGlance(sample: sample)
        let availability = coordinator.categoryAvailability[.cpu]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)
        let status = deriveStatus(sample: sample)
        let ribbon = deriveRibbon(sample: sample)

        PanelScaffold(
            category: .cpu,
            glance: glance,
            status: status,
            ribbon: ribbon,
            pages: PopoverTab.supportedTabs(for: .cpu),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: .cpu)
            },
            isPinned: PanelController.shared.isPinned(for: .cpu)
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample)
            case .detail:
                detailPage(sample: sample)
            case .history:
                HistoryPage(category: .cpu, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .cpu)
            }
        }
        .onAppear {
            coordinator.startProcessDemand()
        }
        .onDisappear {
            coordinator.stopProcessDemand()
        }
    }

    // MARK: - Glance Derivation

    private func deriveGlance(sample: CPUSample?) -> PanelGlance {
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
            chartMode: chartMode,
            scrubFormat: { String(format: "%.1f%%", $0) }
        )
    }

    private func deriveStatus(sample: CPUSample?) -> StatusLevel {
        guard let s = sample else { return .fine }
        if s.totalUsage >= 90.0 { return .critical }
        if s.totalUsage >= 75.0 { return .elevated }
        if let load = s.loadAverage?.oneMinute, s.perCore.count > 0, load > Double(s.perCore.count) * 1.5 {
            return .warning
        }
        return .fine
    }

    private func deriveRibbon(sample: CPUSample?) -> String? {
        guard let s = sample else { return nil }
        if s.totalUsage >= 90.0 { return "Sustained high CPU load" }
        if s.totalUsage >= 75.0 { return "Elevated processor demand" }
        if let load = s.loadAverage?.oneMinute, s.perCore.count > 0, load > Double(s.perCore.count) * 1.5 {
            return "Load average (\(String(format: "%.1f", load))) exceeds core capacity (\(s.perCore.count))"
        }
        return nil
    }

    // MARK: - Now Page (Core Map + Top Consumers)

    @ViewBuilder
    private func nowPage(sample: CPUSample?) -> some View {
        if let s = sample {
            VStack(spacing: Instrument.Space.m) {
                // Signature Instrument: Core Map
                coreMapModule(sample: s)

                // Top Consumers (Task 8.9)
                topConsumersModule
            }
        }
    }

    @ViewBuilder
    private var topConsumersModule: some View {
        let processSample = coordinator.latestProcesses?.value
        TopConsumersModule(
            criterion: .cpu,
            processes: processSample?.topCPU ?? [],
            skippedCount: processSample?.skippedCount ?? 0,
            sparklines: coordinator.processCPUHistory,
            standard: preferences.byteUnitStandard
        )
    }

    private func coreMapModule(sample: CPUSample) -> some View {
        let pCount = sample.performanceCoreCount ?? 0
        let eCount = sample.efficiencyCoreCount ?? 0
        let hasTopology = (pCount > 0 || eCount > 0) && (pCount + eCount == sample.perCore.count)

        return Module(
            eyebrow: hoveredCoreInfo ?? "Core Map",
            trailing: {
                HStack(spacing: 8) {
                    if let load = sample.loadAverage?.oneMinute {
                        Text("Load 1m: \(String(format: "%.2f", load))")
                            .font(Instrument.Typography.micro)
                            .foregroundColor(.secondary)
                    }
                    if let freq = sample.frequencyHz, freq > 0 {
                        Text(Units.formatFrequencyHz(freq))
                            .font(Instrument.Typography.micro)
                            .foregroundColor(.secondary)
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if hasTopology {
                    // P Cluster (Performance Cores)
                    if pCount > 0 {
                        let pStart = eCount
                        let pUsage = sample.performanceUsage ?? 0.0
                        let pBars = (0..<pCount).map { i -> ClusterBarData in
                            let coreIdx = pStart + i
                            let val = coreIdx < sample.perCore.count ? sample.perCore[coreIdx] / 100.0 : 0.0
                            return ClusterBarData(
                                id: "p-\(coreIdx)",
                                index: coreIdx + 1,
                                utilization: val,
                                color: CategoryPalette.tint(for: .cpu),
                                label: "Core \(coreIdx + 1) (P): \(Int(val * 100))%"
                            )
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("P · \(Int(pUsage))%")
                                .font(Instrument.Typography.micro)
                                .foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)

                            ClusterStrip(
                                bars: pBars,
                                barWidth: pCount > 12 ? 6 : 8,
                                barHeight: 28,
                                onHover: { idx, bar in
                                    if let b = bar {
                                        hoveredCoreInfo = "Core \(b.index) (P) · \(Int(b.utilization * 100))%"
                                    } else {
                                        hoveredCoreInfo = nil
                                    }
                                }
                            )
                        }
                    }

                    // E Cluster (Efficiency Cores)
                    if eCount > 0 {
                        let eUsage = sample.efficiencyUsage ?? 0.0
                        let eBars = (0..<eCount).map { i -> ClusterBarData in
                            let val = i < sample.perCore.count ? sample.perCore[i] / 100.0 : 0.0
                            return ClusterBarData(
                                id: "e-\(i)",
                                index: i + 1,
                                utilization: val,
                                color: CategoryPalette.color(for: .fan), // Glacier tint
                                label: "Core \(i + 1) (E): \(Int(val * 100))%"
                            )
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("E · \(Int(eUsage))%")
                                .font(Instrument.Typography.micro)
                                .foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)

                            ClusterStrip(
                                bars: eBars,
                                barWidth: eCount > 12 ? 6 : 8,
                                barHeight: 28,
                                onHover: { idx, bar in
                                    if let b = bar {
                                        hoveredCoreInfo = "Core \(b.index) (E) · \(Int(b.utilization * 100))%"
                                    } else {
                                        hoveredCoreInfo = nil
                                    }
                                }
                            )
                        }
                    }
                } else {
                    // Unified Cores Strip (Intel / Unknown Topology)
                    let bars = sample.perCore.enumerated().map { i, val in
                        ClusterBarData(
                            id: "u-\(i)",
                            index: i + 1,
                            utilization: val / 100.0,
                            color: CategoryPalette.tint(for: .cpu),
                            label: "Core \(i + 1): \(Int(val))%"
                        )
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Text("\(sample.perCore.count) Cores")
                            .font(Instrument.Typography.micro)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)

                        ClusterStrip(
                            bars: bars,
                            barWidth: sample.perCore.count > 16 ? 5 : 8,
                            barHeight: 28,
                            onHover: { idx, bar in
                                if let b = bar {
                                    hoveredCoreInfo = "Core \(b.index) · \(Int(b.utilization * 100))%"
                                } else {
                                    hoveredCoreInfo = nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func loadAverageModule(sample: CPUSample) -> some View {
        let load = sample.loadAverage
        let coreCount = sample.perCore.count
        let oneMin = load?.oneMinute ?? 0.0
        let fiveMin = load?.fiveMinute ?? 0.0
        let fifteenMin = load?.fifteenMinute ?? 0.0
        let isElevated = coreCount > 0 && oneMin > Double(coreCount)

        return Module(eyebrow: "Load Average") {
            MetricRow(
                label: "1m · 5m · 15m",
                valueText: String(format: "%.2f  ·  %.2f  ·  %.2f", oneMin, fiveMin, fifteenMin),
                statusLevel: isElevated ? .elevated : .fine,
                isCopyable: true
            )
        }
    }

    // MARK: - Detail Page (Cores + Split Breakdown + Uptime)

    @ViewBuilder
    private func detailPage(sample: CPUSample?) -> some View {
        if let s = sample {
            VStack(spacing: Instrument.Space.m) {
                // Signature Instrument: Load Average Dot Plot
                loadAverageModule(sample: s)

                // User / System / Idle Split Capsule
                Module(eyebrow: "Composition") {
                    VStack(alignment: .leading, spacing: 8) {
                        SplitCapsule(
                            segments: [
                                CapsuleSegment(value: s.user, color: CategoryPalette.tint(for: .cpu), label: "User"),
                                CapsuleSegment(value: s.system, color: CategoryPalette.Series.cpuSystem, label: "System"),
                                CapsuleSegment(value: s.idle, color: Instrument.Surface.inset, label: "Idle")
                            ],
                            height: 10
                        )

                        HStack {
                            Text("User \(Int(round(s.user)))%")
                                .font(Instrument.Typography.micro)
                                .foregroundColor(CategoryPalette.tint(for: .cpu))
                            Spacer()
                            Text("System \(Int(round(s.system)))%")
                                .font(Instrument.Typography.micro)
                                .foregroundColor(CategoryPalette.Series.cpuSystem)
                            Spacer()
                            Text("Idle \(Int(round(s.idle)))%")
                                .font(Instrument.Typography.micro)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Per-Core Detailed Tiles with 60-Sample Micro-Sparklines
                Module(eyebrow: "Per-Core Detail (\(s.perCore.count) Cores)") {
                    VStack(spacing: 4) {
                        ForEach(Array(s.perCore.enumerated()), id: \.offset) { idx, usage in
                            let history = coordinator.coreHistory[idx] ?? [usage]
                            MetricRow(
                                label: coreLabel(index: idx, sample: s),
                                valueText: "\(Int(round(usage)))",
                                unit: "%",
                                sparklineHistory: history,
                                sparklineColor: CategoryPalette.tint(for: .cpu),
                                statusLevel: usage >= 90.0 ? .critical : (usage >= 75.0 ? .elevated : .fine)
                            )
                        }
                    }
                }

                // System Uptime
                if let uptime = s.loadAverage != nil ? ProcessInfo.processInfo.systemUptime : nil {
                    Module(eyebrow: "System") {
                        MetricRow(
                            label: "System Uptime",
                            valueText: Units.formatUptime(uptime)
                        )
                    }
                }
            }
        }
    }

    private func coreLabel(index: Int, sample: CPUSample) -> String {
        let eCount = sample.efficiencyCoreCount ?? 0
        let pCount = sample.performanceCoreCount ?? 0
        if eCount > 0 && index < eCount {
            return "Core \(index + 1) (E)"
        } else if pCount > 0 && index >= eCount && index < (eCount + pCount) {
            return "Core \(index + 1) (P)"
        } else {
            return "Core \(index + 1)"
        }
    }

    // MARK: - History Page


}
