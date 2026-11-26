import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Memory Instrument Panel (Task 8.8b / Task 8.5.8b / ADR 0009 / Blueprint §6.2).
/// Features the banded memory hero chart, 5-segment allocation capsule with 2-column legend,
/// 3-step pressure pill, swap meter, and virtual memory page table.
public struct MemoryPanel: View {
    private struct AllocationLegendItem: Identifiable {
        let id: String
        let label: String
        let bytes: UInt64
        let color: Color
        let formattedBytes: String
        let percent: Int
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
        private var cachedSample: MemorySample?
        private var cachedStandard: Units.ByteUnitStandard?
        private var cachedRefreshInterval: TimeInterval?
        private var cachedState: DerivedState?
        private(set) var derivationCount: Int = 0

        func resolve(
            coordinator: MetricsCoordinator,
            reading: Sample<MemorySample>?,
            byteUnitStandard: Units.ByteUnitStandard,
            refreshInterval: TimeInterval,
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
               cachedSample == sample,
               cachedStandard == byteUnitStandard,
               cachedRefreshInterval == refreshInterval {
                return cachedState
            }

            let next = builder()
            self.coordinatorID = coordID
            self.cachedTimestamp = timestamp
            self.cachedHasSample = hasSample
            self.cachedSample = sample
            self.cachedStandard = byteUnitStandard
            self.cachedRefreshInterval = refreshInterval
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
    @State private var hoveredSegmentSummary: String?
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
        let supported = PopoverTab.supportedTabs(for: .memory)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    public var body: some View {
        let reading = coordinator.latestMemory
        let sample = reading?.value
        let standard = preferences.byteUnitStandard
        let referenceDate = reading?.timestamp ?? Date()
        let refreshInterval = preferences.refreshInterval
        let derived = derivedCache.resolve(
            coordinator: coordinator,
            reading: reading,
            byteUnitStandard: standard,
            refreshInterval: refreshInterval
        ) {
            DerivedStateCache.DerivedState(
                glance: deriveGlance(
                    sample: sample,
                    standard: standard,
                    referenceDate: referenceDate,
                    refreshInterval: refreshInterval
                ),
                status: deriveStatus(sample: sample),
                // Pressure is shown once (pill on Now, chip in the header); no ribbon copy.
                ribbon: nil
            )
        }
        let availability = coordinator.categoryAvailability[.memory]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            chrome: PanelChrome(
                category: .memory,
                status: derived.status,
                ribbon: derived.ribbon,
                availability: availability,
                isLoading: isLoading,
                isPaused: coordinator.isSamplingPaused,
                isLowPowerModeActive: coordinator.isLowPowerModeActive,
                isPinned: PanelController.shared.isPinned(for: .memory),
                hasBattery: coordinator.latestPower?.value.hasBattery ?? true,
                refreshInterval: preferences.refreshInterval,
                enabledCategories: preferences.enabledCategories,
                onTogglePause: {
                    coordinator.toggleSamplingPaused()
                },
                onPinToggle: {
                    PanelController.shared.togglePin(for: .memory)
                }
            ),
            glance: derived.glance,
            pages: PopoverTab.supportedTabs(for: .memory),
            selection: $selectedTab
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

    internal func deriveGlance(
        sample: MemorySample?,
        standard: Units.ByteUnitStandard,
        referenceDate: Date,
        refreshInterval: TimeInterval
    ) -> PanelGlance {
        let (divisor, unitLabel) = MemoryPageContent.heroUnit(standard: standard)
        let totalBytes = sample?.total ?? 0
        let usedValue = sample.map { Double($0.used) / divisor } ?? 0.0
        let headline = MemoryPageContent.headline(sample: sample, standard: standard)

        let usedPoints = coordinator.timedScalarHistory(
            for: .memoryUsedPercent,
            duration: 60,
            referenceDate: referenceDate
        )
        let insight = InsightEngine.insights(series: usedPoints.map(\.value), interval: refreshInterval, unit: .percent).first?.text
        let bands = [
            ChartBand(threshold: StatusThresholds.memoryChartWarningPercent, color: CategoryPalette.statusColor(for: .warning), label: "Warning"),
            ChartBand(threshold: StatusThresholds.memoryChartCriticalPercent, color: CategoryPalette.statusColor(for: .critical), label: "Critical")
        ]
        let chartMode = LiveChartMode.banded(
            points: usedPoints,
            bands: bands,
            fixedMax: 100.0
        )
        return PanelGlance(
            value: usedValue,
            format: "%.1f",
            unit: unitLabel,
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            scrubFormat: { MemoryPageContent.scrubReadout(percentUsed: $0, totalBytes: totalBytes, standard: standard) }
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

    // MARK: - Now Page (Memory Allocation + Top Apps, Max 2 Sections)

    @ViewBuilder
    private func nowPage(sample: MemorySample?) -> some View {
        if let s = sample {
            VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
                allocationModule(sample: s)
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

    private func allocationModule(sample: MemorySample) -> some View {
        let standard = preferences.byteUnitStandard
        let appBytes: UInt64 = sample.appMemory
            ?? (sample.used > sample.wired + sample.compressed
                ? sample.used - sample.wired - sample.compressed
                : 0)
        let totalDenom = Double(max(1, sample.total))

        let specs: [(id: String, label: String, bytes: UInt64, color: Color)] = [
            ("app", "App", appBytes, CategoryPalette.tint(for: .memory)),
            ("wired", "Wired", sample.wired, CategoryPalette.Series.memoryWired),
            ("compressed", "Compressed", sample.compressed, CategoryPalette.Series.memoryCompressed),
            ("cached", "Cached", sample.cached, CategoryPalette.Series.memoryCached),
            ("free", "Free", sample.free, Color.secondary.opacity(0.24))
        ]

        let legendItems: [AllocationLegendItem] = specs.map { spec in
            let pct = Int(round((Double(spec.bytes) / totalDenom) * 100.0))
            let formatted = Units.formatBytes(spec.bytes, standard: standard, fractionDigits: 1)
            return AllocationLegendItem(
                id: spec.id,
                label: spec.label,
                bytes: spec.bytes,
                color: spec.color,
                formattedBytes: formatted,
                percent: pct
            )
        }

        let segments: [CapsuleSegment] = legendItems.compactMap { item in
            guard item.bytes > 0 else { return nil }
            return CapsuleSegment(
                id: item.id,
                value: Double(item.bytes),
                color: item.color,
                label: item.label,
                formattedValue: "\(item.label): \(item.formattedBytes) (\(item.percent)%)"
            )
        }

        let legendColumns = [
            GridItem(.flexible(minimum: 0), spacing: Instrument.Space.s),
            GridItem(.flexible(minimum: 0), spacing: Instrument.Space.s)
        ]

        return Section(
            "Memory Allocation",
            trailing: {
                if let hovered = hoveredSegmentSummary {
                    Text(hovered)
                        .font(Instrument.Typography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                SplitCapsule(
                    segments: segments,
                    height: 14,
                    minVisibleWidth: 4,
                    gap: 1,
                    onHoverSegment: { seg in
                        if let s = seg {
                            let pct = Int(round(s.value / totalDenom * 100.0))
                            hoveredSegmentSummary = "\(s.label): \(Units.formatBytes(UInt64(s.value), standard: standard, fractionDigits: 1)) (\(pct)%)"
                        } else {
                            hoveredSegmentSummary = nil
                        }
                    }
                )

                // 2-column tabular legend: swatch · label · bytes · %
                LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 5) {
                    ForEach(legendItems) { item in
                        HStack(spacing: Instrument.Space.xxs) {
                            Circle()
                                .fill(item.color)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                                )
                                .frame(width: 6, height: 6)

                            Text(item.label)
                                .font(Instrument.Typography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            if item.id == "wired" {
                                InfoButton(term: .wired)
                            } else if item.id == "compressed" {
                                InfoButton(term: .compressed)
                            }

                            Spacer(minLength: 2)

                            Text(item.formattedBytes)
                                .font(Instrument.Typography.caption.monospacedDigit())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("\(item.percent)%")
                                .font(Instrument.Typography.micro)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 22, alignment: .trailing)
                        }
                    }
                }

                Rectangle()
                    .fill(Instrument.Surface.hairline)
                    .frame(height: 0.5)

                HStack(alignment: .center, spacing: Instrument.Space.s) {
                    pressurePill(active: sample.pressure)
                    InfoButton(term: .memoryPressure)
                }
            }
        }
    }

    private func pressurePill(active: MemoryPressure) -> some View {
        let levels: [MemoryPressure] = [.normal, .warning, .critical]

        return HStack(spacing: Instrument.Space.xxs) {
            ForEach(levels, id: \.self) { level in
                let isActive = (level == active)
                let tint = pressureTint(for: level)

                Text(level.displayName)
                    .font(isActive ? Instrument.Typography.eyebrow : Instrument.Typography.micro)
                    .foregroundColor(isActive ? tint : .secondary.opacity(0.65))
                    .padding(.horizontal, Instrument.Space.s)
                    .padding(.vertical, 2.5)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: Instrument.Radius.chip, style: .continuous)
                                .fill(tint.opacity(0.16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Instrument.Radius.chip, style: .continuous)
                                        .strokeBorder(tint.opacity(0.45), lineWidth: 0.5)
                                )
                        }
                    }
            }
        }
        .padding(Instrument.Space.xxs)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.chip, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memory Pressure")
        .accessibilityValue(active.displayName)
    }

    private func pressureTint(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal:
            return CategoryPalette.tint(for: .memory)
        case .warning:
            return CategoryPalette.statusColor(for: .warning)
        case .critical:
            return CategoryPalette.statusColor(for: .critical)
        }
    }

    // MARK: - Detail Page (Swap Allocation + Virtual Memory Pages, Max 2 Sections)

    @ViewBuilder
    private func detailPage(sample: MemorySample?) -> some View {
        if let s = sample {
            VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
                swapAllocationModule(sample: s)
                virtualMemoryPagesModule(sample: s)
            }
        }
    }

    private func swapAllocationModule(sample: MemorySample) -> some View {
        let standard = preferences.byteUnitStandard
        let totalSwap = sample.swapTotal ?? 0
        let freeSwap = sample.swapFree ?? (totalSwap > sample.swapUsed ? totalSwap - sample.swapUsed : 0)
        let swapFraction = totalSwap > 0 ? min(1.0, max(0.0, Double(sample.swapUsed) / Double(totalSwap))) : 0.0

        return Section(
            "Swap Allocation",
            glossaryKey: .swap,
            trailing: {
                Text(totalSwap > 0 ? "\(Int(round(swapFraction * 100)))%" : "Inactive")
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        ) {
            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                Meter(
                    progress: swapFraction,
                    height: .medium,
                    tint: CategoryPalette.tint(for: .memory),
                    deepTint: CategoryPalette.statusColor(for: .warning)
                )

                VStack(spacing: 0) {
                    MetricRow(
                        label: "Used",
                        valueText: Units.formatBytes(sample.swapUsed, standard: standard),
                        glossaryKey: .swap,
                        showHairline: true
                    )
                    MetricRow(
                        label: "Total",
                        valueText: Units.formatBytes(totalSwap, standard: standard),
                        showHairline: true
                    )
                    MetricRow(
                        label: "Free",
                        valueText: Units.formatBytes(freeSwap, standard: standard),
                        showHairline: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func virtualMemoryPagesModule(sample: MemorySample) -> some View {
        let standard = preferences.byteUnitStandard
        let rows = MemoryPageContent.virtualMemoryRows(sample: sample, standard: standard)
        // Page-ins/outs, faults and compressions are not sampled yet; only the
        // page classes absent from the Now page appear here.
        if !rows.isEmpty {
            Section("Virtual Memory") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        MetricRow(
                            label: row.label,
                            valueText: row.value,
                            showHairline: index < rows.count - 1
                        )
                    }
                }
            }
        }
    }
}

/// Pure content rules for the Memory panel (Task 9.5), kept testable without rendering.
enum MemoryPageContent {
    /// Hero value divisor and unit label (single source for hero and scrub readout).
    static func heroUnit(standard: Units.ByteUnitStandard) -> (divisor: Double, label: String) {
        standard == .si ? (1_000_000_000.0, "GB") : (1_073_741_824.0, "GiB")
    }

    /// Scrub readout in the same unit and precision as the hero numeral.
    static func scrubReadout(percentUsed: Double, totalBytes: UInt64, standard: Units.ByteUnitStandard) -> String {
        let unit = heroUnit(standard: standard)
        let used = percentUsed / 100.0 * Double(totalBytes) / unit.divisor
        return String(format: "%.1f %@", used, unit.label)
    }

    /// "of 16 GiB" plus swap when active. Pressure and compression live in the
    /// pill and legend on Now, so the headline does not repeat them.
    static func headline(sample: MemorySample?, standard: Units.ByteUnitStandard) -> String {
        guard let s = sample else { return PanelHeadline.memory(sample: nil, standard: standard) }
        let isWholeGiB = (standard == .iec && s.total >= 1_073_741_824 && s.total % 1_073_741_824 == 0)
        var text = "of \(Units.formatBytes(s.total, standard: standard, fractionDigits: isWholeGiB ? 0 : 1))"
        if s.swapUsed > 0 {
            text += " · \(Units.formatBytes(s.swapUsed, standard: standard, fractionDigits: 1)) swap"
        }
        return text
    }

    /// Details rows that the Now allocation legend does not already show.
    static func virtualMemoryRows(sample: MemorySample, standard: Units.ByteUnitStandard) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let active = sample.active {
            rows.append(("Active Pages", Units.formatBytes(active, standard: standard)))
        }
        if let inactive = sample.inactive {
            rows.append(("Inactive Pages", Units.formatBytes(inactive, standard: standard)))
        }
        return rows
    }
}
