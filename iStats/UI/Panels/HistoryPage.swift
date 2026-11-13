import SwiftUI
import AppKit
import iStatsCore

/// Instrument-grade History Page used across all 8 category panels (Task 8.5.5 / ADR 0009 / ADR 0010).
/// Features:
/// 1. Unified `SegmentedControl` for 1m · 5m · 15m (initialized from preferences in `init`, fixing B10)
/// 2. Unified `FilterChip` bar for channel isolation, thermal sources, and Power Watts/Charge filtering
/// 3. Scalar-only queries (B8): `timedScalarHistory` for 1m, `bucketedScalarHistory` (2.5s / 7.5s) envelopes for 5m / 15m
/// 4. 140 pt `LiveChart` + 14 pt relative bottom time axis (`9.5 pt` tertiary tabular text)
/// 5. Decluttered annotations (avg line / peak marker revealed on `AVG` / `MAX` stat-cell hover or pin)
/// 6. Timestamp-pinned stat-cell scrub (B10) and Glance header routing via `Environment(\.chartScrubAction)`
public struct HistoryPage: View {
    public let category: MetricCategory
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedRange: HistoryTimeRange
    @State private var isolatedChannel: Int? = nil
    @State private var selectedThermalSource: MetricSource = .peak
    @State private var selectedPowerSeries: PowerSeriesFilter = .watts
    @State private var pinnedScrub: PinnedScrub? = nil
    @State private var hoveredStatCell: StatCellKind? = nil
    @State private var hoverScrub: HoverScrubReadout? = nil

    @Environment(\.motionPolicy) private var motionPolicy
    @Environment(\.chartScrubAction) private var chartScrubAction
    @Environment(\.historyPageProbeEnabled) private var probeEnabled

    internal enum PowerSeriesFilter: String, CaseIterable, Hashable {
        case watts = "Watts"
        case charge = "Charge %"
    }

    internal enum StatCellKind: String, Equatable, Hashable {
        case min = "MIN"
        case avg = "AVG"
        case max = "MAX"
        case now = "NOW"
    }

    internal struct PinnedScrub: Equatable {
        let timestamp: Date
        let kind: StatCellKind
    }

    private struct HoverScrubReadout: Equatable {
        let index: Int?
        let state: ChartScrubState?
    }

    internal struct TimeAxisTick: Equatable {
        let label: String
        let fraction: Double
    }

    internal struct StatTarget: Equatable {
        let index: Int?
        let timestamp: Date?
    }

    public init(
        category: MetricCategory,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self.category = category
        self.coordinator = coordinator
        self.preferences = preferences
        self._selectedRange = State(initialValue: preferences.historyRange(for: category))
    }

    internal var currentSelectedRange: HistoryTimeRange {
        selectedRange
    }

    private var isFanless: Bool {
        category == .fan && (coordinator.latestFan?.value.fans.isEmpty ?? true)
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private var availableThermalSources: [MetricSource] {
        MetricSource.allCases.filter { $0 != .battery || hasBattery }
    }

    public var body: some View {
        let seriesData = buildSeriesData()
        let resolvedPinnedIndex = pinnedScrub.flatMap {
            Self.resolveTimestampIndex(for: $0.timestamp, in: seriesData.timestamps)
        }
        let stats = (!isFanless && seriesData.activeValues.count >= 2)
            ? LiveChartMath.computeStats(for: seriesData.activeValues)
            : nil
        let activeFourthCell = resolveFourthCell(
            stats: stats,
            seriesData: seriesData,
            resolvedPinnedIndex: resolvedPinnedIndex
        )
        let pinnedGlanceState = buildPinnedGlanceState(
            resolvedPinnedIndex: resolvedPinnedIndex,
            seriesData: seriesData
        )
        let showAverageLine = (hoveredStatCell == .avg || pinnedScrub?.kind == .avg)
        let showPeakMarker = (hoveredStatCell == .max || pinnedScrub?.kind == .max)
        let hasSufficientData = seriesData.rawSampleCount >= 10 && seriesData.activeValues.count >= 2

        VStack(spacing: Instrument.Space.l) {
            // Top Controls Bar (Unified FilterChips + SegmentedControl)
            HStack(spacing: 8) {
                leadingChips(seriesData: seriesData)
                Spacer(minLength: 4)
                rangeControl
            }

            // Chart Zone (140 pt plot + 14 pt relative time axis)
            if isFanless {
                InsetEmptyState(
                    systemImage: "fan.slash",
                    title: "Passive Cooling",
                    reason: "Fanless system — no cooling telemetry to record."
                )
                .frame(height: Instrument.Size.historyChartHeight)
            } else if !hasSufficientData {
                InsetEmptyState(
                    systemImage: "waveform.path.ecg",
                    title: "Collecting History",
                    reason: "History fills while iStats runs (in-memory only)."
                )
                .frame(height: Instrument.Size.historyChartHeight)
            } else {
                VStack(spacing: 0) {
                    chartContainer(
                        seriesData: seriesData,
                        resolvedScrubIndex: resolvedPinnedIndex,
                        showAverageLine: showAverageLine,
                        showPeakMarker: showPeakMarker
                    )
                    .frame(height: Instrument.Size.historyChartHeight)

                    timeAxis
                }
            }

            // Stats Strip (Min · Avg · Max · Now / AT -<time>)
            if let stats, hasSufficientData {
                statsStrip(
                    stats: stats,
                    seriesData: seriesData,
                    fourthCellLabel: activeFourthCell.label,
                    fourthCellValue: activeFourthCell.value,
                    isScrubbing: activeFourthCell.isScrubbing
                )
            }
        }
        .padding(.vertical, 2)
        .onChange(of: resolvedPinnedIndex) { newIdx in
            if newIdx == nil && pinnedScrub != nil {
                pinnedScrub = nil
                if hoverScrub?.state == nil {
                    chartScrubAction?(nil)
                }
            }
        }
        .onChange(of: pinnedGlanceState) { newState in
            guard hoverScrub?.state == nil else { return }
            chartScrubAction?(newState)
        }
        .onDisappear {
            if pinnedScrub != nil || hoverScrub != nil {
                pinnedScrub = nil
                hoverScrub = nil
                chartScrubAction?(nil)
            }
        }
        .preference(
            key: HistoryPageProbeKey.self,
            value: probeEnabled
                ? HistoryPageProbeSnapshot(
                    selectedRange: selectedRange,
                    fourthCellLabel: activeFourthCell.label,
                    fourthCellValue: activeFourthCell.value,
                    showAverageLine: showAverageLine,
                    showPeakMarker: showPeakMarker,
                    resolvedScrubIndex: resolvedPinnedIndex,
                    timeAxisLabels: Self.timeAxisTicks(for: selectedRange).map(\.label)
                )
                : HistoryPageProbeSnapshot()
        )
    }

    // MARK: - Leading Filter Chips

    @ViewBuilder
    private func leadingChips(seriesData: SeriesData) -> some View {
        if category == .thermal {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(availableThermalSources, id: \.self) { src in
                        let isSelected = (selectedThermalSource == src)
                        FilterChip(
                            title: src.shortLabel,
                            isSelected: isSelected,
                            tint: CategoryPalette.tint(for: .thermal),
                            fontSize: 10.5
                        ) {
                            selectedThermalSource = src
                            if selectedRange != .oneMinute && src != .peak {
                                selectedRange = .oneMinute
                                preferences.setHistoryRange(.oneMinute, for: category)
                            }
                            clearScrubState()
                        }
                    }
                }
            }
        } else if category == .power && hasBattery {
            HStack(spacing: 6) {
                ForEach(PowerSeriesFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: selectedPowerSeries == filter,
                        tint: CategoryPalette.tint(for: .power),
                        fontSize: 10.5
                    ) {
                        selectedPowerSeries = filter
                        clearScrubState()
                    }
                }
            }
        } else if let chA = seriesData.channelA, let chB = seriesData.channelB,
                  let colA = seriesData.channelAColor, let colB = seriesData.channelBColor {
            HStack(spacing: 6) {
                channelChip(label: chA, color: colA, channelIndex: 0)
                channelChip(label: chB, color: colB, channelIndex: 1)
            }
        } else {
            HStack(spacing: 5) {
                Circle()
                    .fill(CategoryPalette.tint(for: category))
                    .frame(width: 5, height: 5)
                Text("\(category.displayName) Trend")
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func channelChip(label: String, color: Color, channelIndex: Int) -> some View {
        let isSelected = (isolatedChannel == channelIndex)
        let isDimmed = (isolatedChannel != nil && !isSelected)
        return FilterChip(
            title: label,
            isSelected: isSelected,
            isDimmed: isDimmed,
            dotColor: color,
            tint: color,
            fontSize: 10.5
        ) {
            if isolatedChannel == channelIndex {
                isolatedChannel = nil
            } else {
                isolatedChannel = channelIndex
            }
            clearScrubState()
        }
        .help("Click to isolate \(label) (dims other series)")
    }

    // MARK: - Segmented Range Control

    private var rangeControl: some View {
        let selectionBinding = Binding<HistoryTimeRange>(
            get: { selectedRange },
            set: { newRange in
                selectedRange = newRange
                preferences.setHistoryRange(newRange, for: category)
                if category == .thermal && newRange != .oneMinute && selectedThermalSource != .peak {
                    selectedThermalSource = .peak
                }
                clearScrubState()
            }
        )

        return SegmentedControl(
            options: HistoryTimeRange.allCases,
            selection: selectionBinding,
            fontSize: 10.5,
            horizontalPadding: 7,
            verticalPadding: 3,
            accessibilityLabel: { range in
                switch range {
                case .oneMinute: return "1 minute history"
                case .fiveMinutes: return "5 minutes history"
                case .fifteenMinutes: return "15 minutes history"
                }
            }
        ) { range in
            range.rawValue
        }
    }

    // MARK: - Chart Container & Bottom Time Axis

    private func chartContainer(
        seriesData: SeriesData,
        resolvedScrubIndex: Int?,
        showAverageLine: Bool,
        showPeakMarker: Bool
    ) -> some View {
        LiveChart(
            category: category,
            mode: seriesData.mode,
            height: Instrument.Size.historyChartHeight,
            sampleIntervalSeconds: seriesData.sampleInterval,
            windowDuration: selectedRange.durationSeconds,
            showAverageLine: showAverageLine,
            showPeakMarker: showPeakMarker,
            showAxisTicks: true,
            valueFormatter: seriesData.valueFormatter,
            isolatedChannel: isolatedChannel,
            scrubIndex: resolvedScrubIndex,
            onScrub: { idx, _, _ in
                if let idx {
                    hoverScrub = HoverScrubReadout(index: idx, state: hoverScrub?.state)
                } else {
                    hoverScrub = nil
                }
            },
            onScrubStateChange: { newState in
                if let newState {
                    hoverScrub = HoverScrubReadout(index: hoverScrub?.index, state: newState)
                } else {
                    hoverScrub = nil
                }
            }
        )
    }

    private var timeAxis: some View {
        let ticks = Self.timeAxisTicks(for: selectedRange)
        return GeometryReader { proxy in
            let plotWidth = max(1.0, proxy.size.width - 5.0)
            ZStack(alignment: .leading) {
                ForEach(Array(ticks.enumerated()), id: \.offset) { idx, tick in
                    let label = Text(tick.label)
                        .font(.system(size: 9.5, weight: .regular).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()

                    if idx == 0 {
                        label
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if idx == ticks.count - 1 {
                        label
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        label
                            .position(x: plotWidth * tick.fraction, y: proxy.size.height / 2.0)
                    }
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    // MARK: - Stats Strip (Min · Avg · Max · Now / AT -<time>)

    private func statsStrip(
        stats: LiveChartMath.Stats,
        seriesData: SeriesData,
        fourthCellLabel: String,
        fourthCellValue: Double,
        isScrubbing: Bool
    ) -> some View {
        let targets = Self.statTargets(stats: stats, seriesData: seriesData)

        return HStack(spacing: 6) {
            statCell(
                kind: .min,
                label: StatCellKind.min.rawValue,
                value: stats.min,
                targetTimestamp: targets.min.timestamp,
                seriesData: seriesData
            )
            statCell(
                kind: .avg,
                label: StatCellKind.avg.rawValue,
                value: stats.avg,
                targetTimestamp: targets.avg.timestamp,
                seriesData: seriesData
            )
            statCell(
                kind: .max,
                label: StatCellKind.max.rawValue,
                value: stats.max,
                targetTimestamp: targets.max.timestamp,
                seriesData: seriesData
            )
            statCell(
                kind: .now,
                label: fourthCellLabel,
                value: fourthCellValue,
                targetTimestamp: targets.now.timestamp,
                seriesData: seriesData,
                isScrubDisplay: isScrubbing
            )
        }
        .padding(.top, 2)
    }

    private func statCell(
        kind: StatCellKind,
        label: String,
        value: Double,
        targetTimestamp: Date?,
        seriesData: SeriesData,
        isScrubDisplay: Bool = false
    ) -> some View {
        let isPinned = (pinnedScrub?.kind == kind)
        let isHighlighted = isPinned || (isScrubDisplay && kind == .now)
        let tint = CategoryPalette.tint(for: category)

        return Button {
            guard let targetTs = targetTimestamp else { return }
            let anim: Animation? = (motionPolicy == .full) ? Motion.snappy : nil
            withAnimation(anim) {
                if pinnedScrub?.kind == kind {
                    pinnedScrub = nil
                } else {
                    pinnedScrub = PinnedScrub(timestamp: targetTs, kind: kind)
                }
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Instrument.Typography.eyebrow)
                    .foregroundColor(isHighlighted ? tint : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                LiveNumber(
                    value: value,
                    format: seriesData.formatLiveNumber,
                    font: Instrument.Typography.value,
                    unit: seriesData.unit.isEmpty ? nil : seriesData.unit
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Instrument.Radius.control)
                    .fill(isHighlighted ? tint.opacity(0.14) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: Instrument.Radius.control)
                            .stroke(isHighlighted ? tint.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Instrument.Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredStatCell = kind
            } else if hoveredStatCell == kind {
                hoveredStatCell = nil
            }
        }
        .help(kind == .now && isScrubDisplay ? "Pinned / scrubbed sample" : "Click to pin crosshair to \(kind.rawValue)")
    }

    // MARK: - Scrub State Helpers

    private func clearScrubState() {
        pinnedScrub = nil
        hoverScrub = nil
        chartScrubAction?(nil)
    }

    private func resolveFourthCell(
        stats: LiveChartMath.Stats?,
        seriesData: SeriesData,
        resolvedPinnedIndex: Int?
    ) -> (label: String, value: Double, isScrubbing: Bool) {
        let timestamps = seriesData.timestamps
        let values = seriesData.activeValues
        let latestTs = timestamps.last ?? 0.0

        if let hoverState = hoverScrub?.state {
            let idx: Int?
            if let explicitIdx = hoverScrub?.index, explicitIdx >= 0, explicitIdx < values.count {
                idx = explicitIdx
            } else if let ts = hoverState.timestamp {
                idx = Self.resolveTimestampIndex(for: Date(timeIntervalSince1970: ts), in: timestamps)
            } else {
                idx = nil
            }

            if let idx, idx < values.count, idx < timestamps.count {
                let secAgo = max(0.0, latestTs - timestamps[idx])
                return (Self.formatScrubAxisLabel(secondsAgo: secAgo), values[idx], true)
            }
        }

        if let pinnedIdx = resolvedPinnedIndex, pinnedIdx < values.count, pinnedIdx < timestamps.count {
            let secAgo = max(0.0, latestTs - timestamps[pinnedIdx])
            return (Self.formatScrubAxisLabel(secondsAgo: secAgo), values[pinnedIdx], true)
        }

        return (StatCellKind.now.rawValue, stats?.now ?? 0.0, false)
    }

    internal func buildPinnedGlanceState(
        resolvedPinnedIndex: Int?,
        seriesData: SeriesData
    ) -> ChartScrubState? {
        guard let idx = resolvedPinnedIndex,
              idx >= 0,
              idx < seriesData.timestamps.count else {
            return nil
        }

        let timestamp = seriesData.timestamps[idx]
        let latestTimestamp = seriesData.timestamps.last ?? timestamp

        switch seriesData.mode.payload {
        case .mirrored(let pts, _, let botColor, let topLbl, let botLbl, _, _, _):
            guard idx < pts.count else { return nil }
            if isolatedChannel == 0 {
                return ChartScrubState.make(
                    primaryValue: pts[idx].primary,
                    primaryLabel: topLbl,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: seriesData.valueFormatter
                )
            } else if isolatedChannel == 1 {
                return ChartScrubState.make(
                    primaryValue: pts[idx].secondary,
                    primaryLabel: botLbl,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: seriesData.valueFormatter
                )
            } else {
                return ChartScrubState.make(
                    primaryValue: pts[idx].primary,
                    secondaryValue: pts[idx].secondary,
                    primaryLabel: topLbl,
                    secondaryLabel: botLbl,
                    secondaryColor: botColor,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: seriesData.valueFormatter
                )
            }

        case .mirroredEnvelope(let top, let bot, _, let botColor, let topLbl, let botLbl, _, _):
            guard idx < top.count else { return nil }
            if isolatedChannel == 0 {
                return ChartScrubState.make(
                    primaryValue: top[idx].mean,
                    primaryLabel: topLbl,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: seriesData.valueFormatter
                )
            } else if isolatedChannel == 1 {
                let botVal = idx < bot.count ? bot[idx].mean : top[idx].mean
                return ChartScrubState.make(
                    primaryValue: botVal,
                    primaryLabel: botLbl,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: seriesData.valueFormatter
                )
            } else {
                let botVal = idx < bot.count ? bot[idx].mean : nil
                return ChartScrubState.make(
                    primaryValue: top[idx].mean,
                    secondaryValue: botVal,
                    primaryLabel: topLbl,
                    secondaryLabel: botLbl,
                    secondaryColor: botColor,
                    timestamp: timestamp,
                    latestTimestamp: latestTimestamp,
                    valueFormatter: seriesData.valueFormatter
                )
            }

        default:
            guard idx < seriesData.activeValues.count else { return nil }
            return ChartScrubState.make(
                primaryValue: seriesData.activeValues[idx],
                timestamp: timestamp,
                latestTimestamp: latestTimestamp,
                valueFormatter: seriesData.valueFormatter
            )
        }
    }

    // MARK: - Telemetry Series Construction

    internal struct SeriesData {
        let mode: LiveChartMode
        let activeValues: [Double]
        let timestamps: [TimeInterval]
        let rawSampleCount: Int
        let sampleInterval: Double
        let unit: String
        let valueFormatter: @Sendable (Double) -> String
        let formatLiveNumber: @Sendable (Double) -> String
        let channelA: String?
        let channelB: String?
        let channelAColor: Color?
        let channelBColor: Color?
    }

    internal static func bucketWidth(for range: HistoryTimeRange) -> TimeInterval? {
        switch range {
        case .oneMinute: return nil
        case .fiveMinutes: return 2.5
        case .fifteenMinutes: return 7.5
        }
    }

    internal static func timeAxisTicks(for range: HistoryTimeRange) -> [TimeAxisTick] {
        switch range {
        case .oneMinute:
            return [
                TimeAxisTick(label: "-60s", fraction: 0.0),
                TimeAxisTick(label: "-40s", fraction: 1.0 / 3.0),
                TimeAxisTick(label: "-20s", fraction: 2.0 / 3.0),
                TimeAxisTick(label: "now", fraction: 1.0)
            ]
        case .fiveMinutes:
            return [
                TimeAxisTick(label: "-5m", fraction: 0.0),
                TimeAxisTick(label: "-3m", fraction: 0.4),
                TimeAxisTick(label: "-1m", fraction: 0.8),
                TimeAxisTick(label: "now", fraction: 1.0)
            ]
        case .fifteenMinutes:
            return [
                TimeAxisTick(label: "-15m", fraction: 0.0),
                TimeAxisTick(label: "-10m", fraction: 1.0 / 3.0),
                TimeAxisTick(label: "-5m", fraction: 2.0 / 3.0),
                TimeAxisTick(label: "now", fraction: 1.0)
            ]
        }
    }

    internal static func formatScrubAxisLabel(secondsAgo: Double) -> String {
        guard secondsAgo.isFinite else { return "AT -0s" }
        let sec = max(0, Int(secondsAgo.rounded()))
        if sec < 60 {
            return "AT -\(sec)s"
        }
        let m = sec / 60
        let s = sec % 60
        return s == 0 ? "AT -\(m)m" : "AT -\(m)m\(s)s"
    }

    internal static func resolveTimestampIndex(
        for timestamp: Date,
        in timestamps: [TimeInterval],
        tolerance: TimeInterval = 1e-3
    ) -> Int? {
        guard !timestamps.isEmpty else { return nil }
        let target = timestamp.timeIntervalSince1970
        var bestIndex: Int? = nil
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        for (idx, ts) in timestamps.enumerated() {
            let dist = abs(ts - target)
            if dist <= tolerance && dist < bestDistance {
                bestDistance = dist
                bestIndex = idx
            }
        }
        return bestIndex
    }

    internal static func statTargets(
        stats: LiveChartMath.Stats,
        seriesData: SeriesData
    ) -> (min: StatTarget, avg: StatTarget, max: StatTarget, now: StatTarget) {
        let values = seriesData.activeValues
        let timestamps = seriesData.timestamps
        guard !values.isEmpty, values.count == timestamps.count else {
            return (
                StatTarget(index: nil, timestamp: nil),
                StatTarget(index: nil, timestamp: nil),
                StatTarget(index: nil, timestamp: nil),
                StatTarget(index: nil, timestamp: nil)
            )
        }

        let minIdx = values.enumerated().min(by: { $0.element < $1.element })?.offset
        let avgIdx = values.enumerated().min(by: { abs($0.element - stats.avg) < abs($1.element - stats.avg) })?.offset
        let maxIdx = LiveChartMath.peakIndex(values: values)
        let nowIdx = values.count - 1

        func target(at idx: Int?) -> StatTarget {
            guard let idx, idx >= 0, idx < timestamps.count else {
                return StatTarget(index: nil, timestamp: nil)
            }
            return StatTarget(index: idx, timestamp: Date(timeIntervalSince1970: timestamps[idx]))
        }

        return (target(at: minIdx), target(at: avgIdx), target(at: maxIdx), target(at: nowIdx))
    }

    internal func buildSeriesData(referenceDate: Date = Date()) -> SeriesData {
        let duration = selectedRange.durationSeconds
        let bucketWidth = Self.bucketWidth(for: selectedRange)
        let sampleInterval = bucketWidth ?? preferences.refreshInterval

        switch category {
        case .cpu:
            if let bucketWidth {
                let dual = coordinator.bucketedDualScalarHistory(
                    primary: .cpuUser,
                    secondary: .cpuSystem,
                    duration: duration,
                    bucketWidth: bucketWidth,
                    referenceDate: referenceDate
                )
                let rawCount = coordinator.timedScalarHistory(
                    for: .cpuUser,
                    duration: duration,
                    referenceDate: referenceDate
                ).count
                let totalBuckets = zip(dual.primary, dual.secondary).map { u, s in
                    BucketPoint(
                        timestamp: u.timestamp,
                        min: min(100.0, u.min + s.min),
                        max: min(100.0, u.max + s.max),
                        mean: min(100.0, u.mean + s.mean)
                    )
                }
                let activeBuckets: [BucketPoint]
                let seriesColor: Color
                if isolatedChannel == 0 {
                    activeBuckets = dual.primary
                    seriesColor = CategoryPalette.tint(for: .cpu)
                } else if isolatedChannel == 1 {
                    activeBuckets = dual.secondary
                    seriesColor = CategoryPalette.Series.cpuSystem
                } else {
                    activeBuckets = totalBuckets
                    seriesColor = CategoryPalette.tint(for: .cpu)
                }
                return SeriesData(
                    mode: .envelope(buckets: activeBuckets, color: seriesColor, fixedMax: 100.0),
                    activeValues: activeBuckets.map(\.mean),
                    timestamps: activeBuckets.map(\.timestamp),
                    rawSampleCount: rawCount,
                    sampleInterval: sampleInterval,
                    unit: "%",
                    valueFormatter: { String(format: "%.0f%%", $0) },
                    formatLiveNumber: { String(format: "%.0f", $0) },
                    channelA: "User",
                    channelB: "System",
                    channelAColor: CategoryPalette.tint(for: .cpu),
                    channelBColor: CategoryPalette.Series.cpuSystem
                )
            } else {
                let dualPoints = coordinator.timedDualScalarHistory(
                    primary: .cpuUser,
                    secondary: .cpuSystem,
                    duration: duration,
                    referenceDate: referenceDate
                )
                let active: [Double]
                if isolatedChannel == 0 {
                    active = dualPoints.map(\.primary)
                } else if isolatedChannel == 1 {
                    active = dualPoints.map(\.secondary)
                } else {
                    active = dualPoints.map { $0.primary + $0.secondary }
                }
                return SeriesData(
                    mode: .stacked(
                        points: dualPoints,
                        primaryColor: CategoryPalette.tint(for: .cpu),
                        secondaryColor: CategoryPalette.Series.cpuSystem,
                        fixedMax: 100.0
                    ),
                    activeValues: active,
                    timestamps: dualPoints.map(\.timestamp),
                    rawSampleCount: dualPoints.count,
                    sampleInterval: sampleInterval,
                    unit: "%",
                    valueFormatter: { String(format: "%.0f%%", $0) },
                    formatLiveNumber: { String(format: "%.0f", $0) },
                    channelA: "User",
                    channelB: "System",
                    channelAColor: CategoryPalette.tint(for: .cpu),
                    channelBColor: CategoryPalette.Series.cpuSystem
                )
            }

        case .memory:
            return buildSingleScalarSeries(
                key: .memoryUsedPercent,
                duration: duration,
                bucketWidth: bucketWidth,
                sampleInterval: sampleInterval,
                referenceDate: referenceDate,
                color: CategoryPalette.tint(for: .memory),
                deepColor: CategoryPalette.tintDeep(for: .memory),
                fixedMax: 100.0,
                unit: "%",
                valueFormatter: { String(format: "%.0f%%", $0) },
                formatLiveNumber: { String(format: "%.0f", $0) }
            )

        case .gpu:
            return buildSingleScalarSeries(
                key: .gpuUtilization,
                duration: duration,
                bucketWidth: bucketWidth,
                sampleInterval: sampleInterval,
                referenceDate: referenceDate,
                color: CategoryPalette.tint(for: .gpu),
                deepColor: CategoryPalette.tintDeep(for: .gpu),
                fixedMax: 100.0,
                unit: "%",
                valueFormatter: { String(format: "%.0f%%", $0) },
                formatLiveNumber: { String(format: "%.0f", $0) }
            )

        case .thermal:
            let tempUnit = preferences.temperatureUnit
            let sym = tempUnit.symbol
            let convertTemp: @Sendable (Double) -> Double = { celsius in
                tempUnit == .fahrenheit ? Units.celsiusToFahrenheit(celsius) : celsius
            }

            if let bucketWidth {
                let rawBuckets = coordinator.bucketedScalarHistory(
                    for: .thermalPeakCelsius,
                    duration: duration,
                    bucketWidth: bucketWidth,
                    referenceDate: referenceDate
                )
                let buckets = rawBuckets.map { b in
                    BucketPoint(
                        timestamp: b.timestamp,
                        min: convertTemp(b.min),
                        max: convertTemp(b.max),
                        mean: convertTemp(b.mean)
                    )
                }
                let rawCount = coordinator.timedScalarHistory(
                    for: .thermalPeakCelsius,
                    duration: duration,
                    referenceDate: referenceDate
                ).count
                return SeriesData(
                    mode: .envelope(
                        buckets: buckets,
                        color: CategoryPalette.tint(for: .thermal),
                        deepColor: CategoryPalette.tintDeep(for: .thermal)
                    ),
                    activeValues: buckets.map(\.mean),
                    timestamps: buckets.map(\.timestamp),
                    rawSampleCount: rawCount,
                    sampleInterval: sampleInterval,
                    unit: sym,
                    valueFormatter: { String(format: "%.0f\(sym)", $0) },
                    formatLiveNumber: { String(format: "%.0f", $0) },
                    channelA: nil,
                    channelB: nil,
                    channelAColor: nil,
                    channelBColor: nil
                )
            } else if selectedThermalSource == .peak {
                let points = coordinator.timedScalarHistory(
                    for: .thermalPeakCelsius,
                    duration: duration,
                    referenceDate: referenceDate
                ).map { ChartPoint(timestamp: $0.timestamp, value: convertTemp($0.value)) }
                return SeriesData(
                    mode: .single(
                        points: points,
                        color: CategoryPalette.tint(for: .thermal),
                        deepColor: CategoryPalette.tintDeep(for: .thermal)
                    ),
                    activeValues: points.map(\.value),
                    timestamps: points.map(\.timestamp),
                    rawSampleCount: points.count,
                    sampleInterval: sampleInterval,
                    unit: sym,
                    valueFormatter: { String(format: "%.0f\(sym)", $0) },
                    formatLiveNumber: { String(format: "%.0f", $0) },
                    channelA: nil,
                    channelB: nil,
                    channelAColor: nil,
                    channelBColor: nil
                )
            } else {
                let refEpoch = referenceDate.timeIntervalSince1970
                let cutoff = refEpoch - duration
                let source = selectedThermalSource
                let points: [ChartPoint] = coordinator.thermalHistory.compactMap { sample in
                    let t = sample.timestamp.timeIntervalSince1970
                    guard t > cutoff, t <= refEpoch else { return nil }
                    let matching = ThermalSensorClassifier.sensors(in: sample.value, for: source)
                    let celsius = matching.map(\.celsius).max() ?? sample.value.peakTemperatureCelsius ?? 0.0
                    return ChartPoint(timestamp: t, value: convertTemp(celsius))
                }
                return SeriesData(
                    mode: .single(
                        points: points,
                        color: CategoryPalette.tint(for: .thermal),
                        deepColor: CategoryPalette.tintDeep(for: .thermal)
                    ),
                    activeValues: points.map(\.value),
                    timestamps: points.map(\.timestamp),
                    rawSampleCount: points.count,
                    sampleInterval: sampleInterval,
                    unit: sym,
                    valueFormatter: { String(format: "%.0f\(sym)", $0) },
                    formatLiveNumber: { String(format: "%.0f", $0) },
                    channelA: nil,
                    channelB: nil,
                    channelAColor: nil,
                    channelBColor: nil
                )
            }

        case .fan:
            return buildSingleScalarSeries(
                key: .fanMaxRPM,
                duration: duration,
                bucketWidth: bucketWidth,
                sampleInterval: sampleInterval,
                referenceDate: referenceDate,
                color: CategoryPalette.tint(for: .fan),
                deepColor: CategoryPalette.tintDeep(for: .fan),
                fixedMax: nil,
                unit: "RPM",
                valueFormatter: { Units.formatRPM(Int($0)) },
                formatLiveNumber: { String(format: "%.0f", $0) }
            )

        case .network:
            let netUnit = preferences.networkUnit
            let byteStandard = preferences.byteUnitStandard
            let formatter: @Sendable (Double) -> String = {
                Units.formatCompactRate($0, unit: netUnit, standard: byteStandard)
            }
            return buildMirroredScalarSeries(
                primaryKey: .networkInBytesPerSec,
                secondaryKey: .networkOutBytesPerSec,
                duration: duration,
                bucketWidth: bucketWidth,
                sampleInterval: sampleInterval,
                referenceDate: referenceDate,
                topColor: CategoryPalette.tint(for: .network),
                bottomColor: CategoryPalette.Series.networkUpload,
                topLabel: "↓",
                bottomLabel: "↑",
                channelA: "Download ↓",
                channelB: "Upload ↑",
                valueFormatter: formatter,
                formatLiveNumber: formatter
            )

        case .disk:
            let byteStandard = preferences.byteUnitStandard
            let formatter: @Sendable (Double) -> String = {
                Units.formatDiskRate($0, standard: byteStandard)
            }
            return buildMirroredScalarSeries(
                primaryKey: .diskReadBytesPerSec,
                secondaryKey: .diskWriteBytesPerSec,
                duration: duration,
                bucketWidth: bucketWidth,
                sampleInterval: sampleInterval,
                referenceDate: referenceDate,
                topColor: CategoryPalette.tint(for: .disk),
                bottomColor: CategoryPalette.Series.diskWrite,
                topLabel: "R",
                bottomLabel: "W",
                channelA: "Read",
                channelB: "Write",
                valueFormatter: formatter,
                formatLiveNumber: formatter
            )

        case .power:
            let useCharge = (hasBattery && selectedPowerSeries == .charge)
            if useCharge {
                return buildSingleScalarSeries(
                    key: .powerChargePercent,
                    duration: duration,
                    bucketWidth: bucketWidth,
                    sampleInterval: sampleInterval,
                    referenceDate: referenceDate,
                    color: CategoryPalette.tint(for: .power),
                    deepColor: CategoryPalette.tintDeep(for: .power),
                    fixedMax: 100.0,
                    unit: "%",
                    valueFormatter: { String(format: "%.0f%%", $0) },
                    formatLiveNumber: { String(format: "%.0f", $0) }
                )
            } else {
                return buildSingleScalarSeries(
                    key: .powerWatts,
                    duration: duration,
                    bucketWidth: bucketWidth,
                    sampleInterval: sampleInterval,
                    referenceDate: referenceDate,
                    color: CategoryPalette.tint(for: .power),
                    deepColor: CategoryPalette.tintDeep(for: .power),
                    fixedMax: nil,
                    unit: "W",
                    valueFormatter: { String(format: "%.1f W", $0) },
                    formatLiveNumber: { String(format: "%.1f", $0) }
                )
            }
        }
    }

    private func buildSingleScalarSeries(
        key: ScalarSeriesKey,
        duration: TimeInterval,
        bucketWidth: TimeInterval?,
        sampleInterval: Double,
        referenceDate: Date,
        color: Color,
        deepColor: Color,
        fixedMax: Double?,
        unit: String,
        valueFormatter: @escaping @Sendable (Double) -> String,
        formatLiveNumber: @escaping @Sendable (Double) -> String
    ) -> SeriesData {
        if let bucketWidth {
            let buckets = coordinator.bucketedScalarHistory(
                for: key,
                duration: duration,
                bucketWidth: bucketWidth,
                referenceDate: referenceDate
            )
            let rawCount = coordinator.timedScalarHistory(
                for: key,
                duration: duration,
                referenceDate: referenceDate
            ).count
            return SeriesData(
                mode: .envelope(buckets: buckets, color: color, deepColor: deepColor, fixedMax: fixedMax),
                activeValues: buckets.map(\.mean),
                timestamps: buckets.map(\.timestamp),
                rawSampleCount: rawCount,
                sampleInterval: sampleInterval,
                unit: unit,
                valueFormatter: valueFormatter,
                formatLiveNumber: formatLiveNumber,
                channelA: nil,
                channelB: nil,
                channelAColor: nil,
                channelBColor: nil
            )
        } else {
            let points = coordinator.timedScalarHistory(
                for: key,
                duration: duration,
                referenceDate: referenceDate
            )
            return SeriesData(
                mode: .single(points: points, color: color, deepColor: deepColor, fixedMax: fixedMax),
                activeValues: points.map(\.value),
                timestamps: points.map(\.timestamp),
                rawSampleCount: points.count,
                sampleInterval: sampleInterval,
                unit: unit,
                valueFormatter: valueFormatter,
                formatLiveNumber: formatLiveNumber,
                channelA: nil,
                channelB: nil,
                channelAColor: nil,
                channelBColor: nil
            )
        }
    }

    private func buildMirroredScalarSeries(
        primaryKey: ScalarSeriesKey,
        secondaryKey: ScalarSeriesKey,
        duration: TimeInterval,
        bucketWidth: TimeInterval?,
        sampleInterval: Double,
        referenceDate: Date,
        topColor: Color,
        bottomColor: Color,
        topLabel: String,
        bottomLabel: String,
        channelA: String,
        channelB: String,
        valueFormatter: @escaping @Sendable (Double) -> String,
        formatLiveNumber: @escaping @Sendable (Double) -> String
    ) -> SeriesData {
        if let bucketWidth {
            let dual = coordinator.bucketedDualScalarHistory(
                primary: primaryKey,
                secondary: secondaryKey,
                duration: duration,
                bucketWidth: bucketWidth,
                referenceDate: referenceDate
            )
            let rawCount = coordinator.timedScalarHistory(
                for: primaryKey,
                duration: duration,
                referenceDate: referenceDate
            ).count
            let active: [Double]
            if isolatedChannel == 0 {
                active = dual.primary.map(\.mean)
            } else if isolatedChannel == 1 {
                active = dual.secondary.map(\.mean)
            } else {
                active = zip(dual.primary, dual.secondary).map { $0.mean + $1.mean }
            }
            return SeriesData(
                mode: .mirroredEnvelope(
                    top: dual.primary,
                    bottom: dual.secondary,
                    topColor: topColor,
                    bottomColor: bottomColor,
                    topLabel: topLabel,
                    bottomLabel: bottomLabel
                ),
                activeValues: active,
                timestamps: dual.primary.map(\.timestamp),
                rawSampleCount: rawCount,
                sampleInterval: sampleInterval,
                unit: "",
                valueFormatter: valueFormatter,
                formatLiveNumber: formatLiveNumber,
                channelA: channelA,
                channelB: channelB,
                channelAColor: topColor,
                channelBColor: bottomColor
            )
        } else {
            let dualPoints = coordinator.timedDualScalarHistory(
                primary: primaryKey,
                secondary: secondaryKey,
                duration: duration,
                referenceDate: referenceDate
            )
            let active: [Double]
            if isolatedChannel == 0 {
                active = dualPoints.map(\.primary)
            } else if isolatedChannel == 1 {
                active = dualPoints.map(\.secondary)
            } else {
                active = dualPoints.map { $0.primary + $0.secondary }
            }
            return SeriesData(
                mode: .mirrored(
                    points: dualPoints,
                    topColor: topColor,
                    bottomColor: bottomColor,
                    topLabel: topLabel,
                    bottomLabel: bottomLabel
                ),
                activeValues: active,
                timestamps: dualPoints.map(\.timestamp),
                rawSampleCount: dualPoints.count,
                sampleInterval: sampleInterval,
                unit: "",
                valueFormatter: valueFormatter,
                formatLiveNumber: formatLiveNumber,
                channelA: channelA,
                channelB: channelB,
                channelAColor: topColor,
                channelBColor: bottomColor
            )
        }
    }
}

// MARK: - Test Probe Environment & Preference

private struct HistoryPageProbeEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    internal var historyPageProbeEnabled: Bool {
        get { self[HistoryPageProbeEnabledKey.self] }
        set { self[HistoryPageProbeEnabledKey.self] = newValue }
    }
}

internal struct HistoryPageProbeSnapshot: Equatable, Sendable {
    var selectedRange: HistoryTimeRange?
    var fourthCellLabel: String?
    var fourthCellValue: Double?
    var showAverageLine: Bool?
    var showPeakMarker: Bool?
    var resolvedScrubIndex: Int?
    var timeAxisLabels: [String]?
}

internal struct HistoryPageProbeKey: PreferenceKey {
    static let defaultValue = HistoryPageProbeSnapshot()
    static func reduce(value: inout HistoryPageProbeSnapshot, nextValue: () -> HistoryPageProbeSnapshot) {
        let next = nextValue()
        if let r = next.selectedRange { value.selectedRange = r }
        if let l = next.fourthCellLabel { value.fourthCellLabel = l }
        if let v = next.fourthCellValue { value.fourthCellValue = v }
        if let a = next.showAverageLine { value.showAverageLine = a }
        if let p = next.showPeakMarker { value.showPeakMarker = p }
        if let i = next.resolvedScrubIndex { value.resolvedScrubIndex = i }
        if let t = next.timeAxisLabels { value.timeAxisLabels = t }
    }
}
