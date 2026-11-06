import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Memory Instrument Panel (Task 8.8b / ADR 0009 / Blueprint §6.2).
/// Features the signature Pressure Arc, Composition Capsule, and swap telemetry.
public struct MemoryPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var hoveredSegmentSummary: String?

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
        let supported = PopoverTab.supportedTabs(for: .memory)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    public var body: some View {
        let sample = coordinator.latestMemory?.value
        let glance = deriveGlance(sample: sample)
        let availability = coordinator.categoryAvailability[.memory]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)
        let status = deriveStatus(sample: sample)
        let ribbon = deriveRibbon(sample: sample)

        PanelScaffold(
            category: .memory,
            glance: glance,
            status: status,
            ribbon: ribbon,
            pages: PopoverTab.supportedTabs(for: .memory),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin()
            },
            isPinned: PanelController.shared.activePanel?.isPinned ?? false
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample)
            case .detail:
                detailPage(sample: sample)
            case .history:
                HistoryPage(category: .memory, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .memory)
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

    private func deriveGlance(sample: MemorySample?) -> PanelGlance {
        let usedGB = sample.map { Double($0.used) / 1_073_741_824.0 } ?? 0.0
        let totalFormatted = sample.map { Units.formatBytes(UInt64($0.total), standard: preferences.byteUnitStandard) } ?? "16 GB"
        let headline = PanelHeadline.memory(sample: sample)
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
            chartMode: chartMode,
            scrubFormat: { "\(Int(round($0)))% used" }
        )
    }

    private func deriveStatus(sample: MemorySample?) -> StatusLevel {
        guard let s = sample else { return .fine }
        switch s.pressure {
        case .normal:
            return .fine
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }

    private func deriveRibbon(sample: MemorySample?) -> String? {
        guard let s = sample else { return nil }
        switch s.pressure {
        case .critical:
            return "Memory pressure critical: system may page heavily"
        case .warning:
            return "Elevated memory pressure: swap active"
        case .normal:
            if s.swapUsed > 1_000_000_000 {
                return "Significant swap usage: \(Units.formatBytesIEC(Int64(s.swapUsed), fractionDigits: 1))"
            }
            return nil
        }
    }

    // MARK: - Now Page (Pressure Arc + Composition Capsule)

    @ViewBuilder
    private func nowPage(sample: MemorySample?) -> some View {
        if let s = sample {
            VStack(spacing: Instrument.Space.m) {
                // Signature Instrument 1: Pressure Arc Gauge & Trailing Stats
                pressureArcModule(sample: s)

                // Signature Instrument 2: Composition Capsule
                compositionModule(sample: s)

                // Top Consumers (Task 8.9)
                topConsumersModule
            }
        }
    }

    @ViewBuilder
    private var topConsumersModule: some View {
        let processSample = coordinator.latestProcesses?.value
        TopConsumersModule(
            criterion: .memory,
            processes: processSample?.topMemory ?? [],
            skippedCount: processSample?.skippedCount ?? 0,
            sparklines: [:],
            standard: preferences.byteUnitStandard
        )
    }

    private func pressureArcModule(sample: MemorySample) -> some View {
        let pressureVal: Double
        let pressureText: String
        let pressureColor: Color

        switch sample.pressure {
        case .normal:
            pressureVal = 25.0
            pressureText = "Normal"
            pressureColor = CategoryPalette.tint(for: .memory)
        case .warning:
            pressureVal = 65.0
            pressureText = "Warning"
            pressureColor = Color(red: 0.95, green: 0.5, blue: 0.15) // Amber
        case .critical:
            pressureVal = 95.0
            pressureText = "Critical"
            pressureColor = Color(red: 0.9, green: 0.25, blue: 0.25) // Red
        }

        let zones = [
            GaugeZone(upToFraction: 0.50, color: CategoryPalette.tint(for: .memory)),
            GaugeZone(upToFraction: 0.80, color: Color(red: 0.95, green: 0.5, blue: 0.15)),
            GaugeZone(upToFraction: 1.00, color: Color(red: 0.9, green: 0.25, blue: 0.25))
        ]

        return Module(eyebrow: "Pressure & Memory Metrics") {
            HStack(spacing: 16) {
                // 120 pt 200° ArcGauge
                ArcGauge(
                    value: pressureVal,
                    range: 0...100,
                    sweep: 200.0,
                    zones: zones,
                    tint: pressureColor,
                    size: 110,
                    centerTitle: pressureText,
                    centerSubtitle: "PRESSURE"
                )
                .frame(width: 110, height: 110)

                // Trailing Column of MetricRows
                VStack(spacing: 4) {
                    if let app = sample.appMemory {
                        MetricRow(
                            label: "App Memory",
                            valueText: Units.formatBytes(UInt64(app), standard: preferences.byteUnitStandard)
                        )
                    }

                    MetricRow(
                        label: "Wired",
                        valueText: Units.formatBytes(UInt64(sample.wired), standard: preferences.byteUnitStandard)
                    )

                    MetricRow(
                        label: "Compressed",
                        valueText: Units.formatBytes(UInt64(sample.compressed), standard: preferences.byteUnitStandard)
                    )
                }
            }
        }
    }

    private func compositionModule(sample: MemorySample) -> some View {
        var segments: [CapsuleSegment] = []

        if let app = sample.appMemory, app > 0 {
            segments.append(CapsuleSegment(
                value: Double(app),
                color: CategoryPalette.tint(for: .memory),
                label: "App"
            ))
        }

        if sample.wired > 0 {
            segments.append(CapsuleSegment(
                value: Double(sample.wired),
                color: CategoryPalette.tintDeep(for: .memory),
                label: "Wired"
            ))
        }

        if sample.compressed > 0 {
            segments.append(CapsuleSegment(
                value: Double(sample.compressed),
                color: CategoryPalette.tint(for: .memory).opacity(0.55),
                label: "Compressed"
            ))
        }

        if sample.cached > 0 {
            segments.append(CapsuleSegment(
                value: Double(sample.cached),
                color: CategoryPalette.tint(for: .memory).opacity(0.28),
                label: "Cached"
            ))
        }

        if sample.free > 0 {
            segments.append(CapsuleSegment(
                value: Double(sample.free),
                color: Instrument.Surface.inset,
                label: "Free"
            ))
        }

        return Module(
            eyebrow: "Memory Composition",
            trailing: {
                Text(Units.formatBytes(UInt64(sample.total), standard: preferences.byteUnitStandard))
                    .font(Instrument.Typography.micro)
                    .foregroundColor(.secondary)
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SplitCapsule(
                    segments: segments,
                    height: 12,
                    minVisibleWidth: 4,
                    gap: 1,
                    onHoverSegment: { seg in
                        if let s = seg {
                            let pct = Int(round(s.value / Double(max(1, sample.total)) * 100.0))
                            hoveredSegmentSummary = "\(s.label): \(Units.formatBytes(UInt64(s.value), standard: preferences.byteUnitStandard)) (\(pct)%)"
                        } else {
                            hoveredSegmentSummary = nil
                        }
                    }
                )

                // Segment labels legend
                HStack(spacing: 8) {
                    ForEach(segments) { seg in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(seg.color)
                                .frame(width: 5, height: 5)
                            Text(seg.label)
                                .font(Instrument.Typography.micro)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Composition Footer: hovered segment or Swap status
                HStack {
                    Text(hoveredSegmentSummary ?? (sample.swapUsed > 0 ? "Swap: \(Units.formatBytes(UInt64(sample.swapUsed), standard: preferences.byteUnitStandard)) used" : "Swap unused"))
                        .font(Instrument.Typography.micro)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Detail Page (Pressure Trends & Swap Meter)

    @ViewBuilder
    private func detailPage(sample: MemorySample?) -> some View {
        if let s = sample {
            VStack(spacing: Instrument.Space.m) {
                // Banded Pressure Trends Chart
                Module(eyebrow: "Pressure History (Banded)") {
                    let history = coordinator.scalarHistory(for: .memoryUsedPercent, duration: 60)
                    let bands = [
                        ChartBand(threshold: 60.0, color: Color(red: 0.95, green: 0.5, blue: 0.15), label: "Warning"),
                        ChartBand(threshold: 80.0, color: Color(red: 0.9, green: 0.25, blue: 0.25), label: "Critical")
                    ]
                    LiveChart(
                        category: .memory,
                        mode: .banded(values: history, bands: bands, fixedMax: 100.0),
                        height: 72
                    )
                    .frame(height: 72)
                }

                // Swap Detail Meter
                if let totalSwap = s.swapTotal, totalSwap > 0 {
                    let swapUsed = Double(s.swapUsed)
                    let swapFraction = swapUsed / Double(totalSwap)
                    Module(eyebrow: "Swap Allocation") {
                        VStack(alignment: .leading, spacing: 6) {
                            Meter(
                                progress: swapFraction,
                                height: .medium,
                                tint: CategoryPalette.tint(for: .memory),
                                deepTint: Color(red: 0.95, green: 0.5, blue: 0.15)
                            )

                            HStack {
                                Text("Used: \(Units.formatBytes(UInt64(s.swapUsed), standard: preferences.byteUnitStandard))")
                                    .font(Instrument.Typography.micro)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Total: \(Units.formatBytes(UInt64(totalSwap), standard: preferences.byteUnitStandard))")
                                    .font(Instrument.Typography.micro)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Active / Inactive Pages
                Module(eyebrow: "Virtual Memory Pages") {
                    VStack(spacing: 4) {
                        if let act = s.active {
                            MetricRow(
                                label: "Active Pages",
                                valueText: Units.formatBytes(UInt64(act), standard: preferences.byteUnitStandard)
                            )
                        }
                        if let inact = s.inactive {
                            MetricRow(
                                label: "Inactive Pages",
                                valueText: Units.formatBytes(UInt64(inact), standard: preferences.byteUnitStandard)
                            )
                        }
                        MetricRow(
                            label: "Free Memory",
                            valueText: Units.formatBytes(UInt64(s.free), standard: preferences.byteUnitStandard)
                        )
                    }
                }
            }
        }
    }


}
