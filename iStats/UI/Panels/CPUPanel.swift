import SwiftUI
import AppKit
import iStatsCore

/// Dedicated CPU Instrument Panel (Task 8.8a / Task 8.5.8a / ADR 0009 / Blueprint §6.1).
/// Features the signature Core Map, Load Average dot-plot, per-core 2-column grid, and breakdown capsule.
public struct CPUPanel: View {
    private enum ClusterGroup: Equatable {
        case performance
        case efficiency
        case unified
    }

    private final class DerivedStateCache {
        struct DerivedState {
            let glance: PanelGlance
            let status: StatusLevel
            let ribbon: String?
        }

        private var coordinatorID: ObjectIdentifier?
        private var cachedTimestamp: Date?
        private var cachedHasSample: Bool = false
        private var cachedSample: CPUSample?
        private var cachedState: DerivedState?
        private(set) var derivationCount: Int = 0

        func resolve(
            coordinator: MetricsCoordinator,
            reading: Sample<CPUSample>?,
            builder: () -> DerivedState
        ) -> DerivedState {
            let coordID = ObjectIdentifier(coordinator)
            let timestamp = reading?.timestamp
            let sample = reading?.value
            let hasSample = (sample != nil)

            if let cachedState,
               coordinatorID == coordID,
               cachedTimestamp == timestamp,
               cachedHasSample == hasSample,
               cachedSample == sample {
                return cachedState
            }

            let next = builder()
            self.coordinatorID = coordID
            self.cachedTimestamp = timestamp
            self.cachedHasSample = hasSample
            self.cachedSample = sample
            self.cachedState = next
            self.derivationCount += 1
            return next
        }
    }

    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var hoveredCoreInfo: String?
    @State private var hoveredCluster: ClusterGroup?
    @State private var derivedCache = DerivedStateCache()

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
        let reading = coordinator.latestCPU
        let sample = reading?.value
        let derived = derivedCache.resolve(coordinator: coordinator, reading: reading) {
            DerivedStateCache.DerivedState(
                glance: deriveGlance(sample: sample),
                status: deriveStatus(sample: sample),
                ribbon: deriveRibbon(sample: sample)
            )
        }
        let availability = coordinator.categoryAvailability[.cpu]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            category: .cpu,
            glance: derived.glance,
            status: derived.status,
            ribbon: derived.ribbon,
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
        let dualPoints = coordinator.timedDualScalarHistory(
            primary: .cpuUser,
            secondary: .cpuSystem,
            duration: 60
        )
        let combined = dualPoints.map { $0.primary + $0.secondary }
        let insight = InsightEngine.insights(series: combined, interval: 1.0, unit: .percent).first?.text
        let chartMode = LiveChartMode.stacked(
            points: dualPoints,
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

    // MARK: - Now Page (Cores + Top Apps, Max 3 Sections)

    @ViewBuilder
    private func nowPage(sample: CPUSample?) -> some View {
        if let s = sample {
            VStack(spacing: Instrument.Space.m) {
                coreMapModule(sample: s)
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

        return Section(
            hoveredCoreInfo ?? "Cores",
            trailing: {
                HStack(spacing: 8) {
                    if let load = sample.loadAverage?.oneMinute {
                        Text("Load \(String(format: "%.2f", load))")
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
            if hasTopology {
                let pStrip = pCount > 0 ? makePerformanceClusterStrip(sample: sample, eCount: eCount, pCount: pCount) : nil
                let eStrip = eCount > 0 ? makeEfficiencyClusterStrip(sample: sample, eCount: eCount) : nil

                if (pCount + eCount) <= 14, let pStrip, let eStrip {
                    HStack(alignment: .top, spacing: Instrument.Space.xl) {
                        pStrip
                        Spacer(minLength: 0)
                        eStrip
                    }
                } else {
                    VStack(alignment: .leading, spacing: Instrument.Space.m) {
                        if let pStrip { pStrip }
                        if let eStrip { eStrip }
                    }
                }
            } else {
                let bars = sample.perCore.enumerated().map { i, val in
                    ClusterBarData(
                        id: "u-\(i)",
                        index: i + 1,
                        utilization: val / 100.0,
                        color: CategoryPalette.tint(for: .cpu),
                        label: "Core \(i + 1): \(Int(round(val)))%"
                    )
                }

                ClusterStrip(
                    title: "\(sample.perCore.count) Cores · \(Int(round(sample.totalUsage)))%",
                    bars: bars,
                    barWidth: sample.perCore.count > 20 ? 8 : 10,
                    barHeight: 36,
                    onHover: { _, bar in
                        if let b = bar {
                            hoveredCluster = .unified
                            hoveredCoreInfo = "Core \(b.index) · \(Int(round(b.utilization * 100)))%"
                        } else if hoveredCluster == .unified {
                            hoveredCluster = nil
                            hoveredCoreInfo = nil
                        }
                    }
                )
            }
        }
    }

    private func makePerformanceClusterStrip(sample: CPUSample, eCount: Int, pCount: Int) -> ClusterStrip {
        let pUsage = sample.performanceUsage ?? 0.0
        let pBars = (0..<pCount).map { i -> ClusterBarData in
            let coreIdx = eCount + i
            let val = coreIdx < sample.perCore.count ? sample.perCore[coreIdx] / 100.0 : 0.0
            return ClusterBarData(
                id: "p-\(coreIdx)",
                index: coreIdx + 1,
                utilization: val,
                color: CategoryPalette.tint(for: .cpu),
                label: "Core \(coreIdx + 1) (P): \(Int(round(val * 100)))%"
            )
        }

        return ClusterStrip(
            title: "Performance · \(Int(round(pUsage)))%",
            bars: pBars,
            barWidth: pCount > 20 ? 8 : 10,
            barHeight: 36,
            onHover: { _, bar in
                if let b = bar {
                    hoveredCluster = .performance
                    hoveredCoreInfo = "Core \(b.index) (P) · \(Int(round(b.utilization * 100)))%"
                } else if hoveredCluster == .performance {
                    hoveredCluster = nil
                    hoveredCoreInfo = nil
                }
            }
        )
    }

    private func makeEfficiencyClusterStrip(sample: CPUSample, eCount: Int) -> ClusterStrip {
        let eUsage = sample.efficiencyUsage ?? 0.0
        let eBars = (0..<eCount).map { i -> ClusterBarData in
            let val = i < sample.perCore.count ? sample.perCore[i] / 100.0 : 0.0
            return ClusterBarData(
                id: "e-\(i)",
                index: i + 1,
                utilization: val,
                color: CategoryPalette.Series.cpuEfficiency,
                label: "Core \(i + 1) (E): \(Int(round(val * 100)))%"
            )
        }

        return ClusterStrip(
            title: "Efficiency · \(Int(round(eUsage)))%",
            bars: eBars,
            barWidth: eCount > 20 ? 8 : 10,
            barHeight: 36,
            onHover: { _, bar in
                if let b = bar {
                    hoveredCluster = .efficiency
                    hoveredCoreInfo = "Core \(b.index) (E) · \(Int(round(b.utilization * 100)))%"
                } else if hoveredCluster == .efficiency {
                    hoveredCluster = nil
                    hoveredCoreInfo = nil
                }
            }
        )
    }

    // MARK: - Detail Page (Load Average Dot Plot + Composition + 2-Col Per-Core Grid)

    @ViewBuilder
    private func detailPage(sample: CPUSample?) -> some View {
        if let s = sample {
            VStack(spacing: Instrument.Space.m) {
                loadAverageModule(sample: s)
                compositionModule(sample: s)
                perCoreGridModule(sample: s)
            }
        }
    }

    private func loadAverageModule(sample: CPUSample) -> some View {
        let load = sample.loadAverage
        let coreCount = sample.perCore.count
        let oneMin = load?.oneMinute ?? 0.0
        let fiveMin = load?.fiveMinute ?? 0.0
        let fifteenMin = load?.fifteenMinute ?? 0.0
        let maxLoad = max(oneMin, max(fiveMin, fifteenMin))
        let capacity = Double(max(1, coreCount))
        let scaleMax = max(1.0, max(capacity * 1.5, maxLoad * 1.1))
        let isElevated = coreCount > 0 && oneMin > Double(coreCount)

        let oneMinColor = isElevated ? CategoryPalette.statusColor(for: .elevated) : CategoryPalette.tint(for: .cpu)
        let fiveMinColor = CategoryPalette.Series.cpuEfficiency
        let fifteenMinColor = Color.secondary

        return Section(
            "Load Average",
            trailing: {
                if coreCount > 0 {
                    Text("Capacity: \(coreCount)")
                        .font(Instrument.Typography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { proxy in
                    let totalWidth = max(1.0, proxy.size.width)
                    let inset: CGFloat = 6.0
                    let usableWidth = max(1.0, totalWidth - inset * 2.0)

                    let xForValue: (Double) -> CGFloat = { value in
                        let clamped = min(1.0, max(0.0, value / scaleMax))
                        return inset + usableWidth * CGFloat(clamped)
                    }

                    let capX = coreCount > 0 ? xForValue(Double(coreCount)) : nil

                    ZStack(alignment: .leading) {
                        // Horizontal track
                        Capsule()
                            .fill(Instrument.Surface.inset)
                            .frame(height: 6)
                            .padding(.horizontal, inset)

                        // Threshold tick at coreCount
                        if let capX {
                            Rectangle()
                                .fill(Color.primary.opacity(0.35))
                                .frame(width: 1.5, height: 14)
                                .position(x: capX, y: 10)
                        }

                        // Plotted markers (15m, 5m, 1m back-to-front)
                        if load != nil {
                            dotMarker(color: fifteenMinColor, size: 7)
                                .position(x: xForValue(fifteenMin), y: 10)
                            dotMarker(color: fiveMinColor, size: 8)
                                .position(x: xForValue(fiveMin), y: 10)
                            dotMarker(color: oneMinColor, size: 9.5)
                                .position(x: xForValue(oneMin), y: 10)
                        }
                    }
                    .frame(height: 20)
                }
                .frame(height: 20)

                HStack(spacing: 10) {
                    Text("0")
                        .font(Instrument.Typography.micro)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    HStack(spacing: 8) {
                        dotLegendItem(label: "1m", color: oneMinColor)
                        dotLegendItem(label: "5m", color: fiveMinColor)
                        dotLegendItem(label: "15m", color: fifteenMinColor)
                    }

                    Spacer()

                    Text(String(format: "%.1f", scaleMax))
                        .font(Instrument.Typography.micro)
                        .foregroundStyle(.tertiary)
                }

                MetricRow(
                    label: "1m · 5m · 15m",
                    valueText: load != nil
                        ? String(format: "%.2f · %.2f · %.2f", oneMin, fiveMin, fifteenMin)
                        : "Unavailable",
                    statusLevel: isElevated ? .elevated : .fine,
                    isCopyable: load != nil
                )
            }
        }
    }

    private func dotMarker(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Instrument.Surface.panel, lineWidth: 1.25)
            )
    }

    private func dotLegendItem(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(Instrument.Typography.micro)
                .foregroundStyle(.secondary)
        }
    }

    private func compositionModule(sample: CPUSample) -> some View {
        Section(
            "Composition",
            trailing: {
                Text("Uptime \(Units.formatUptime(ProcessInfo.processInfo.systemUptime))")
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SplitCapsule(
                    segments: [
                        CapsuleSegment(value: sample.user, color: CategoryPalette.tint(for: .cpu), label: "User"),
                        CapsuleSegment(value: sample.system, color: CategoryPalette.Series.cpuSystem, label: "System"),
                        CapsuleSegment(value: sample.idle, color: Instrument.Surface.inset, label: "Idle")
                    ],
                    height: 10
                )

                HStack {
                    Text("User \(Int(round(sample.user)))%")
                        .font(Instrument.Typography.micro)
                        .foregroundColor(CategoryPalette.tint(for: .cpu))
                    Spacer()
                    Text("System \(Int(round(sample.system)))%")
                        .font(Instrument.Typography.micro)
                        .foregroundColor(CategoryPalette.Series.cpuSystem)
                    Spacer()
                    Text("Idle \(Int(round(sample.idle)))%")
                        .font(Instrument.Typography.micro)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func perCoreGridModule(sample: CPUSample) -> some View {
        let columns = [
            GridItem(.flexible(minimum: 0), spacing: Instrument.Space.m),
            GridItem(.flexible(minimum: 0), spacing: Instrument.Space.m)
        ]

        return Section("Per-Core Detail (\(sample.perCore.count) Cores)") {
            LazyVGrid(columns: columns, spacing: Instrument.Space.s) {
                ForEach(Array(sample.perCore.enumerated()), id: \.offset) { idx, usage in
                    let history = coordinator.coreHistory[idx] ?? [usage]
                    coreGridTile(
                        label: coreLabel(index: idx, sample: sample),
                        usage: usage,
                        history: history,
                        color: coreColor(index: idx, sample: sample)
                    )
                }
            }
        }
    }

    private func coreGridTile(
        label: String,
        usage: Double,
        history: [Double],
        color: Color
    ) -> some View {
        let status: StatusLevel = usage >= 90.0 ? .critical : (usage >= 75.0 ? .elevated : .fine)

        return HStack(spacing: 4) {
            Text(label)
                .font(Instrument.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 2)

            coreSparkline(history: history, color: color)
                .frame(width: 32, height: 12)

            Text("\(Int(round(usage)))%")
                .font(Instrument.Typography.value)
                .foregroundColor(status.isQuiet ? .primary : status.color)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Instrument.Surface.inset.opacity(0.6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(round(usage)))%")
    }

    private func coreSparkline(history: [Double], color: Color) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let maxBound = max(10.0, LiveChartMath.computeMaxBound(values: history))
            guard history.count >= 2, maxBound > 0 else {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: h - 1))
                baseline.addLine(to: CGPoint(x: w, y: h - 1))
                context.stroke(baseline, with: .color(color.opacity(0.25)), lineWidth: 1.0)
                return
            }

            let dx = w / CGFloat(history.count - 1)
            let points = history.enumerated().map { i, v in
                LiveChartMath.Point2D(
                    x: Double(CGFloat(i) * dx),
                    y: Double(h * (1.0 - CGFloat(max(0.0, min(maxBound, v)) / maxBound)))
                )
            }
            let segments = LiveChartMath.smoothSegments(points: points)

            var path = Path()
            if let first = segments.first {
                path.move(to: CGPoint(x: first.start.x, y: first.start.y))
                for seg in segments {
                    path.addCurve(
                        to: CGPoint(x: seg.end.x, y: seg.end.y),
                        control1: CGPoint(x: seg.control1.x, y: seg.control1.y),
                        control2: CGPoint(x: seg.control2.x, y: seg.control2.y)
                    )
                }
            }
            context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1.0)
        }
    }

    private func coreColor(index: Int, sample: CPUSample) -> Color {
        switch sample.coreType(at: index) {
        case .efficiency:
            return CategoryPalette.Series.cpuEfficiency
        case .performance, .standard:
            return CategoryPalette.tint(for: .cpu)
        }
    }

    private func coreLabel(index: Int, sample: CPUSample) -> String {
        switch sample.coreType(at: index) {
        case .efficiency:
            return "Core \(index + 1) (E)"
        case .performance:
            return "Core \(index + 1) (P)"
        case .standard:
            return "Core \(index + 1)"
        }
    }
}
