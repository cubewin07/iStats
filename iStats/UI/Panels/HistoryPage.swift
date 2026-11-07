import SwiftUI
import AppKit
import iStatsCore

/// Instrument-grade History Page used across all 8 category panels (Task 8.10 / ADR 0009).
/// Features:
/// 1. Glass segmented range control: 1m · 5m · 15m (persists per category)
/// 2. 140 pt vector LiveChart with niceTicks y-axis, avg dashed line, ▲ peak marker with value, and relative-time lens
/// 3. Stats strip (Min · Avg · Max · Now) driven by LiveNumber with interactive tap-to-scrub
/// 4. Channel isolation chips for dual-series categories (CPU, Network, Disk) dimming the non-selected series to 15%
/// 5. Matched-geometry morphing under full motion
/// 6. Calm empty state when fewer than 10 samples have been collected.
public struct HistoryPage: View {
    public let category: MetricCategory
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedRange: HistoryTimeRange = .oneMinute
    @State private var isolatedChannel: Int? = nil
    @State private var scrubIndex: Int? = nil
    @State private var scrubSummary: String? = nil
    @State private var selectedThermalSource: MetricSource = .peak

    @Environment(\.motionPolicy) private var motionPolicy
    @Environment(\.chartNamespace) private var chartNamespace

    public init(
        category: MetricCategory,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self.category = category
        self.coordinator = coordinator
        self.preferences = preferences
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

        VStack(spacing: Instrument.Space.l) {
            // Top Controls Bar (Channel Isolation / Source Chips + Glass Range Segment)
            HStack(spacing: 8) {
                // Leading: Channel Chips or Title
                leadingChips(seriesData: seriesData)

                Spacer()

                if let summary = scrubSummary {
                    Text(summary)
                        .font(Instrument.Typography.caption)
                        .foregroundColor(.primary)
                }

                // Trailing: Glass Segmented Range Control
                rangeControl
            }

            // Chart Zone (140 pt)
            if isFanless {
                InsetEmptyState(
                    systemImage: "fan.slash",
                    title: "Passive Cooling",
                    reason: "Fanless system — no cooling telemetry to record."
                )
                .frame(height: 140)
            } else if seriesData.activeValues.count < 10 {
                InsetEmptyState(
                    systemImage: "waveform.path.ecg",
                    title: "Collecting History",
                    reason: "History fills while iStats runs (in-memory only)."
                )
                .frame(height: 140)
            } else {
                chartContainer(seriesData: seriesData)
                    .frame(height: 140)
            }

            // Stats Strip (Min · Avg · Max · Now)
            if !isFanless && seriesData.activeValues.count >= 2, let stats = LiveChartMath.computeStats(for: seriesData.activeValues) {
                statsStrip(stats: stats, seriesData: seriesData)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            selectedRange = preferences.historyRange(for: category)
        }
    }

    // MARK: - Leading Chips

    @ViewBuilder
    private func leadingChips(seriesData: SeriesData) -> some View {
        if category == .thermal {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(availableThermalSources, id: \.self) { src in
                        let isSelected = selectedThermalSource == src
                        Button {
                            withAnimation(Motion.snappy) {
                                selectedThermalSource = src
                                if selectedRange != .oneMinute && src != .peak {
                                    selectedRange = .oneMinute
                                    preferences.setHistoryRange(.oneMinute, for: category)
                                }
                                scrubIndex = nil
                            }
                        } label: {
                            Text(src.shortLabel)
                                .font(Instrument.Typography.micro)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? CategoryPalette.tint(for: .thermal).opacity(0.18) : Color.primary.opacity(0.06))
                                        .overlay(
                                            Capsule()
                                                .stroke(isSelected ? CategoryPalette.tint(for: .thermal).opacity(0.6) : Color.clear, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
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
        return Button {
            withAnimation(Motion.snappy) {
                if isolatedChannel == channelIndex {
                    isolatedChannel = nil
                } else {
                    isolatedChannel = channelIndex
                }
                scrubIndex = nil
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(Instrument.Typography.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .primary : (isDimmed ? .secondary.opacity(0.4) : .secondary))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Instrument.Radius.control)
                    .fill(isSelected ? color.opacity(0.16) : Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: Instrument.Radius.control)
                            .stroke(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
            .opacity(isDimmed ? 0.35 : 1.0)
        }
        .buttonStyle(.plain)
        .help("Click to isolate \(label) (dims other series)")
    }

    // MARK: - Glass Segmented Range Control

    private var rangeControl: some View {
        HStack(spacing: 2) {
            ForEach(HistoryTimeRange.allCases) { range in
                let isSelected = (selectedRange == range)
                Button {
                    withAnimation(Motion.snappy) {
                        selectedRange = range
                        preferences.setHistoryRange(range, for: category)
                        if category == .thermal && range != .oneMinute && selectedThermalSource != .peak {
                            selectedThermalSource = .peak
                        }
                        scrubIndex = nil
                    }
                } label: {
                    Text(range.rawValue)
                        .font(Instrument.Typography.micro)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
    }

    // MARK: - Chart Container

    @ViewBuilder
    private func chartContainer(seriesData: SeriesData) -> some View {
        let chart = LiveChart(
            category: category,
            mode: seriesData.mode,
            height: 140,
            sampleIntervalSeconds: seriesData.interval,
            showAverageLine: true,
            showPeakMarker: true,
            showAxisTicks: true,
            valueFormatter: seriesData.valueFormatter,
            isolatedChannel: isolatedChannel,
            scrubIndex: scrubIndex,
            onScrub: { idx, val, secAgo in
                if let val = val, let secAgo = secAgo {
                    let ago = formatRelativeTime(secAgo)
                    scrubSummary = "\(ago) · \(seriesData.valueFormatter(val))"
                } else {
                    scrubSummary = nil
                }
            }
        )

        if let ns = chartNamespace, motionPolicy == .full {
            chart
                .matchedGeometryEffect(id: "panelChart-\(category.rawValue)", in: ns)
        } else {
            chart
        }
    }

    // MARK: - Stats Strip (Min · Avg · Max · Now)

    private func statsStrip(stats: LiveChartMath.Stats, seriesData: SeriesData) -> some View {
        let values = seriesData.activeValues
        let minIdx = values.enumerated().min(by: { $0.element < $1.element })?.offset
        let peakIdx = LiveChartMath.peakIndex(values: values)
        let nowIdx = max(0, values.count - 1)

        // Find index closest to average
        let avgIdx = values.enumerated().min(by: { abs($0.element - stats.avg) < abs($1.element - stats.avg) })?.offset

        return HStack(spacing: 6) {
            statCell(label: "MIN", value: stats.min, targetIndex: minIdx, seriesData: seriesData)
            statCell(label: "AVG", value: stats.avg, targetIndex: avgIdx, seriesData: seriesData)
            statCell(label: "MAX", value: stats.max, targetIndex: peakIdx, seriesData: seriesData)
            statCell(label: "NOW", value: stats.now, targetIndex: nowIdx, seriesData: seriesData)
        }
        .padding(.top, 2)
    }

    private func statCell(
        label: String,
        value: Double,
        targetIndex: Int?,
        seriesData: SeriesData
    ) -> some View {
        let isHighlighted = (scrubIndex != nil && scrubIndex == targetIndex)
        return Button {
            if let target = targetIndex {
                withAnimation(Motion.snappy) {
                    if scrubIndex == target {
                        scrubIndex = nil
                    } else {
                        scrubIndex = target
                    }
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Instrument.Typography.eyebrow)
                    .foregroundColor(.secondary)

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
                    .fill(isHighlighted ? CategoryPalette.tint(for: category).opacity(0.14) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: Instrument.Radius.control)
                            .stroke(isHighlighted ? CategoryPalette.tint(for: category).opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Click to jump crosshair to \(label)")
    }

    // MARK: - Telemetry Series Construction

    struct SeriesData {
        let mode: LiveChartMode
        let activeValues: [Double]
        let interval: Double
        let unit: String
        let valueFormatter: (Double) -> String
        let formatLiveNumber: (Double) -> String
        let channelA: String?
        let channelB: String?
        let channelAColor: Color?
        let channelBColor: Color?
    }

    private func buildSeriesData() -> SeriesData {
        let isExtended = selectedRange != .oneMinute
        let duration = selectedRange.durationSeconds

        switch category {
        case .cpu:
            let user: [Double]
            let system: [Double]
            if isExtended {
                user = coordinator.scalarHistory(for: .cpuUser, duration: duration)
                system = coordinator.scalarHistory(for: .cpuSystem, duration: duration)
            } else {
                let samples = coordinator.cpuHistory
                user = samples.map { $0.value.user }
                system = samples.map { $0.value.system }
            }
            let active: [Double]
            if isolatedChannel == 0 {
                active = user
            } else if isolatedChannel == 1 {
                active = system
            } else {
                active = zip(user, system).map(+)
            }
            let interval = effectiveInterval(for: max(user.count, system.count), duration: duration, isExtended: isExtended, key: .cpuUser)
            return SeriesData(
                mode: .stacked(
                    primary: user,
                    secondary: system,
                    primaryColor: CategoryPalette.tint(for: .cpu),
                    secondaryColor: Color(red: 1.0, green: 0.42, blue: 0.37),
                    fixedMax: 100.0
                ),
                activeValues: active,
                interval: interval,
                unit: "%",
                valueFormatter: { String(format: "%.0f%%", $0) },
                formatLiveNumber: { String(format: "%.0f", $0) },
                channelA: "User",
                channelB: "System",
                channelAColor: CategoryPalette.tint(for: .cpu),
                channelBColor: Color(red: 1.0, green: 0.42, blue: 0.37)
            )

        case .memory:
            let ratios: [Double]
            if isExtended {
                ratios = coordinator.scalarHistory(for: .memoryUsedPercent, duration: duration)
            } else {
                let samples = coordinator.memoryHistory
                ratios = samples.map { sample -> Double in
                    let mem = sample.value
                    guard mem.total > 0 else { return 0.0 }
                    return (Double(mem.used) / Double(mem.total)) * 100.0
                }
            }
            let interval = effectiveInterval(for: ratios.count, duration: duration, isExtended: isExtended, key: .memoryUsedPercent)
            return SeriesData(
                mode: .single(
                    values: ratios,
                    color: CategoryPalette.tint(for: .memory),
                    deepColor: CategoryPalette.tintDeep(for: .memory),
                    fixedMax: 100.0
                ),
                activeValues: ratios,
                interval: interval,
                unit: "%",
                valueFormatter: { String(format: "%.0f%%", $0) },
                formatLiveNumber: { String(format: "%.0f", $0) },
                channelA: nil, channelB: nil, channelAColor: nil, channelBColor: nil
            )

        case .gpu:
            let utils: [Double]
            if isExtended {
                utils = coordinator.scalarHistory(for: .gpuUtilization, duration: duration)
            } else {
                let samples = coordinator.gpuHistory
                utils = samples.compactMap { $0.value.utilization }
            }
            let interval = effectiveInterval(for: utils.count, duration: duration, isExtended: isExtended, key: .gpuUtilization)
            return SeriesData(
                mode: .single(
                    values: utils,
                    color: CategoryPalette.tint(for: .gpu),
                    deepColor: CategoryPalette.tintDeep(for: .gpu),
                    fixedMax: 100.0
                ),
                activeValues: utils,
                interval: interval,
                unit: "%",
                valueFormatter: { String(format: "%.0f%%", $0) },
                formatLiveNumber: { String(format: "%.0f", $0) },
                channelA: nil, channelB: nil, channelAColor: nil, channelBColor: nil
            )

        case .thermal:
            let temps: [Double]
            if isExtended {
                let raw = coordinator.scalarHistory(for: .thermalPeakCelsius, duration: duration)
                temps = raw.map { preferences.temperatureUnit == .fahrenheit ? Units.celsiusToFahrenheit($0) : $0 }
            } else {
                let samples = coordinator.thermalHistory
                temps = samples.map { sample -> Double in
                    let matching = ThermalSensorClassifier.sensors(in: sample.value, for: selectedThermalSource)
                    let c = matching.map(\.celsius).max() ?? sample.value.peakTemperatureCelsius ?? 0.0
                    return preferences.temperatureUnit == .fahrenheit ? Units.celsiusToFahrenheit(c) : c
                }
            }
            let interval = effectiveInterval(for: temps.count, duration: duration, isExtended: isExtended, key: .thermalPeakCelsius)
            let sym = preferences.temperatureUnit.symbol
            return SeriesData(
                mode: .single(
                    values: temps,
                    color: CategoryPalette.tint(for: .thermal),
                    deepColor: CategoryPalette.tintDeep(for: .thermal)
                ),
                activeValues: temps,
                interval: interval,
                unit: sym,
                valueFormatter: { String(format: "%.0f\(sym)", $0) },
                formatLiveNumber: { String(format: "%.0f", $0) },
                channelA: nil, channelB: nil, channelAColor: nil, channelBColor: nil
            )

        case .fan:
            let maxRPMs: [Double]
            if isExtended {
                maxRPMs = coordinator.scalarHistory(for: .fanMaxRPM, duration: duration)
            } else {
                let samples = coordinator.fanHistory
                maxRPMs = samples.map { sample -> Double in
                    Double(sample.value.fans.map(\.rpm).max() ?? 0)
                }
            }
            let interval = effectiveInterval(for: maxRPMs.count, duration: duration, isExtended: isExtended, key: .fanMaxRPM)
            return SeriesData(
                mode: .single(
                    values: maxRPMs,
                    color: CategoryPalette.tint(for: .fan),
                    deepColor: CategoryPalette.tintDeep(for: .fan)
                ),
                activeValues: maxRPMs,
                interval: interval,
                unit: "RPM",
                valueFormatter: { Units.formatRPM(Int($0)) },
                formatLiveNumber: { String(format: "%.0f", $0) },
                channelA: nil, channelB: nil, channelAColor: nil, channelBColor: nil
            )

        case .network:
            let inRates: [Double]
            let outRates: [Double]
            if isExtended {
                inRates = coordinator.scalarHistory(for: .networkInBytesPerSec, duration: duration)
                outRates = coordinator.scalarHistory(for: .networkOutBytesPerSec, duration: duration)
            } else {
                let samples = coordinator.networkHistory
                inRates = samples.map { $0.value.totalBytesInPerSec }
                outRates = samples.map { $0.value.totalBytesOutPerSec }
            }
            let active: [Double]
            if isolatedChannel == 0 {
                active = inRates
            } else if isolatedChannel == 1 {
                active = outRates
            } else {
                active = zip(inRates, outRates).map(+)
            }
            let interval = effectiveInterval(for: max(inRates.count, outRates.count), duration: duration, isExtended: isExtended, key: .networkInBytesPerSec)
            return SeriesData(
                mode: .mirrored(
                    top: inRates,
                    bottom: outRates,
                    topColor: CategoryPalette.tint(for: .network),
                    bottomColor: Color(red: 1.0, green: 0.54, blue: 0.36),
                    topLabel: "↓",
                    bottomLabel: "↑"
                ),
                activeValues: active,
                interval: interval,
                unit: "",
                valueFormatter: { Units.formatCompactRate($0, unit: self.preferences.networkUnit, standard: self.preferences.byteUnitStandard) },
                formatLiveNumber: { Units.formatCompactRate($0, unit: self.preferences.networkUnit, standard: self.preferences.byteUnitStandard) },
                channelA: "Download ↓",
                channelB: "Upload ↑",
                channelAColor: CategoryPalette.tint(for: .network),
                channelBColor: Color(red: 1.0, green: 0.54, blue: 0.36)
            )

        case .disk:
            let readRates: [Double]
            let writeRates: [Double]
            if isExtended {
                readRates = coordinator.scalarHistory(for: .diskReadBytesPerSec, duration: duration)
                writeRates = coordinator.scalarHistory(for: .diskWriteBytesPerSec, duration: duration)
            } else {
                let samples = coordinator.diskHistory
                readRates = samples.map { $0.value.io?.bytesReadPerSec ?? 0.0 }
                writeRates = samples.map { $0.value.io?.bytesWrittenPerSec ?? 0.0 }
            }
            let active: [Double]
            if isolatedChannel == 0 {
                active = readRates
            } else if isolatedChannel == 1 {
                active = writeRates
            } else {
                active = zip(readRates, writeRates).map(+)
            }
            let interval = effectiveInterval(for: max(readRates.count, writeRates.count), duration: duration, isExtended: isExtended, key: .diskReadBytesPerSec)
            return SeriesData(
                mode: .mirrored(
                    top: readRates,
                    bottom: writeRates,
                    topColor: CategoryPalette.tint(for: .disk),
                    bottomColor: Color(red: 0.96, green: 0.72, blue: 0.24),
                    topLabel: "R",
                    bottomLabel: "W"
                ),
                activeValues: active,
                interval: interval,
                unit: "",
                valueFormatter: { Units.formatDiskRate($0, standard: self.preferences.byteUnitStandard) },
                formatLiveNumber: { Units.formatDiskRate($0, standard: self.preferences.byteUnitStandard) },
                channelA: "Read",
                channelB: "Write",
                channelAColor: CategoryPalette.tint(for: .disk),
                channelBColor: Color(red: 0.96, green: 0.72, blue: 0.24)
            )

        case .power:
            let watts: [Double]
            if isExtended {
                watts = coordinator.scalarHistory(for: .powerWatts, duration: duration)
            } else {
                let samples = coordinator.powerHistory
                watts = samples.map { $0.value.powerDrawWatts ?? 0.0 }
            }
            let interval = effectiveInterval(for: watts.count, duration: duration, isExtended: isExtended, key: .powerWatts)
            return SeriesData(
                mode: .single(
                    values: watts,
                    color: CategoryPalette.tint(for: .power),
                    deepColor: CategoryPalette.tintDeep(for: .power)
                ),
                activeValues: watts,
                interval: interval,
                unit: "W",
                valueFormatter: { String(format: "%.1f W", $0) },
                formatLiveNumber: { String(format: "%.1f", $0) },
                channelA: nil, channelB: nil, channelAColor: nil, channelBColor: nil
            )
        }
    }

    private func effectiveInterval(for count: Int, duration: Double, isExtended: Bool, key: ScalarSeriesKey? = nil) -> Double {
        if isExtended && count > 1 {
            if let key = key {
                let actualSpan = coordinator.scalarTimeSpan(for: key, duration: duration)
                if actualSpan > 0 {
                    return min(duration, actualSpan) / Double(count - 1)
                }
            }
            return duration / Double(count - 1)
        } else {
            return preferences.refreshInterval
        }
    }

    private func formatRelativeTime(_ seconds: Double) -> String {
        let sec = Int(seconds.rounded())
        if sec <= 0 {
            return "now"
        } else if sec < 60 {
            return "\(sec)s ago"
        } else {
            let m = sec / 60
            let s = sec % 60
            return s == 0 ? "\(m)m ago" : "\(m)m \(s)s ago"
        }
    }
}
