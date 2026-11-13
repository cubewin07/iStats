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
        private var cachedState: DerivedState?
        private(set) var derivationCount: Int = 0

        func resolve(
            coordinator: MetricsCoordinator,
            reading: Sample<MemorySample>?,
            byteUnitStandard: Units.ByteUnitStandard,
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
               cachedStandard == byteUnitStandard {
                return cachedState
            }

            let next = builder()
            self.coordinatorID = coordID
            self.cachedTimestamp = timestamp
            self.cachedHasSample = hasSample
            self.cachedSample = sample
            self.cachedStandard = byteUnitStandard
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
        let derived = derivedCache.resolve(
            coordinator: coordinator,
            reading: reading,
            byteUnitStandard: standard
        ) {
            DerivedStateCache.DerivedState(
                glance: deriveGlance(sample: sample, standard: standard),
                status: deriveStatus(sample: sample),
                ribbon: deriveRibbon(sample: sample)
            )
        }
        let availability = coordinator.categoryAvailability[.memory]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            category: .memory,
            glance: derived.glance,
            status: derived.status,
            ribbon: derived.ribbon,
            pages: PopoverTab.supportedTabs(for: .memory),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: .memory)
            },
            isPinned: PanelController.shared.isPinned(for: .memory)
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

    private func deriveGlance(sample: MemorySample?, standard: Units.ByteUnitStandard) -> PanelGlance {
        let usedGB = sample.map { Double($0.used) / 1_073_741_824.0 } ?? 0.0
        let headline: String
        if let s = sample {
            let totalStr = formatTotalBytes(s.total, standard: standard)
            let baseHeadline = PanelHeadline.memory(sample: s, standard: standard)
            headline = "of \(totalStr) · \(baseHeadline)"
        } else {
            headline = PanelHeadline.memory(sample: nil, standard: standard)
        }

        let usedPoints = coordinator.timedScalarHistory(for: .memoryUsedPercent, duration: 60)
        let insight = InsightEngine.insights(series: usedPoints.map(\.value), interval: 1.0, unit: .percent).first?.text
        let bands = [
            ChartBand(threshold: 60.0, color: CategoryPalette.statusColor(for: .warning), label: "Warning"),
            ChartBand(threshold: 80.0, color: CategoryPalette.statusColor(for: .critical), label: "Critical")
        ]
        let chartMode = LiveChartMode.banded(
            points: usedPoints,
            bands: bands,
            fixedMax: 100.0
        )
        return PanelGlance(
            value: usedGB,
            format: "%.1f",
            unit: "GB",
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            scrubFormat: { "\(Int(round($0)))% used" }
        )
    }

    private func formatTotalBytes(_ bytes: UInt64, standard: Units.ByteUnitStandard) -> String {
        let isWholeGiB = (standard == .iec && bytes >= 1_073_741_824 && bytes % 1_073_741_824 == 0)
        return Units.formatBytes(bytes, standard: standard, fractionDigits: isWholeGiB ? 0 : 1)
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

    // MARK: - Now Page (Memory Allocation + Top Apps, Max 2 Sections)

    @ViewBuilder
    private func nowPage(sample: MemorySample?) -> some View {
        if let s = sample {
            VStack(spacing: Instrument.Space.m) {
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
            ("free", "Free", sample.free, Instrument.Surface.inset)
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
            GridItem(.flexible(minimum: 0), spacing: Instrument.Space.m),
            GridItem(.flexible(minimum: 0), spacing: Instrument.Space.m)
        ]

        return Section(
            "Memory Allocation",
            trailing: {
                Text(hoveredSegmentSummary ?? formatTotalBytes(sample.total, standard: standard))
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                        HStack(spacing: 4) {
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
                                .minimumScaleFactor(0.85)

                            Spacer(minLength: 2)

                            Text(item.formattedBytes)
                                .font(Instrument.Typography.caption.monospacedDigit())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            Text("\(item.percent)%")
                                .font(Instrument.Typography.micro)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 24, alignment: .trailing)
                        }
                    }
                }

                Rectangle()
                    .fill(Instrument.Surface.hairline)
                    .frame(height: 0.5)

                HStack(alignment: .center, spacing: Instrument.Space.m) {
                    pressurePill(active: sample.pressure)

                    Spacer(minLength: 4)

                    Text(
                        sample.swapUsed > 0
                            ? "Swap \(Units.formatBytes(sample.swapUsed, standard: standard, fractionDigits: 1))"
                            : "Swap 0 B"
                    )
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }

    private func pressurePill(active: MemoryPressure) -> some View {
        let levels: [MemoryPressure] = [.normal, .warning, .critical]

        return HStack(spacing: 2) {
            ForEach(levels, id: \.self) { level in
                let isActive = (level == active)
                let tint = pressureTint(for: level)

                Text(level.displayName)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? tint : .secondary.opacity(0.65))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(tint.opacity(0.16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(tint.opacity(0.45), lineWidth: 0.5)
                                )
                        }
                    }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
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
            VStack(spacing: Instrument.Space.m) {
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

    private func virtualMemoryPagesModule(sample: MemorySample) -> some View {
        let standard = preferences.byteUnitStandard
        let appBytes: UInt64 = sample.appMemory
            ?? (sample.used > sample.wired + sample.compressed
                ? sample.used - sample.wired - sample.compressed
                : 0)

        var rows: [(label: String, value: String)] = [
            ("App Memory", Units.formatBytes(appBytes, standard: standard)),
            ("Wired", Units.formatBytes(sample.wired, standard: standard)),
            ("Compressed", Units.formatBytes(sample.compressed, standard: standard)),
            ("Cached", Units.formatBytes(sample.cached, standard: standard))
        ]
        if let active = sample.active {
            rows.append(("Active Pages", Units.formatBytes(active, standard: standard)))
        }
        if let inactive = sample.inactive {
            rows.append(("Inactive Pages", Units.formatBytes(inactive, standard: standard)))
        }
        rows.append(("Free", Units.formatBytes(sample.free, standard: standard)))

        return Section("Virtual Memory Pages") {
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
