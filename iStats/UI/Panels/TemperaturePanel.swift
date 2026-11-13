import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Temperature Instrument Panel (Task 8.5.8d / ADR 0009 / ADR 0010).
/// Features domain-floored threshold-shaded hero telemetry, a unified Thermal Spectrum + Ranked Subsystems card,
/// and collapsible subsystem sensor tables with the hottest group expanded by default.
public struct TemperaturePanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @Environment(\.motionPolicy) private var motionPolicy
    @State private var selectedTab: PopoverTab
    @State private var expandedGroups: Set<MetricSource>
    @State private var hasInitializedDefaultExpansion: Bool
    @State private var derivedMemo = DerivedMemo()

    private static let spectrumMinCelsius: Double = 30.0
    private static let spectrumMaxCelsius: Double = 110.0
    private static let warningCelsius: Double = 85.0
    private static let criticalCelsius: Double = 98.0
    private static let spectrumBarWidth: Double = Double(Instrument.Size.panelWidth - 2 * Instrument.Space.xl - 2 * Instrument.Space.modulePadding)

    private struct MemoKey: Equatable {
        let sampleTimestamp: Date?
        let hasSample: Bool
        let temperatureUnit: Units.TemperatureUnit
        let refreshInterval: Double
        let hasBattery: Bool
    }

    private struct SensorGroup: Identifiable {
        let source: MetricSource
        let peak: Double
        let sensors: [SensorReading]

        var id: String { source.id }
    }

    private struct SubsystemPeak: Identifiable {
        let source: MetricSource
        let peak: Double

        var id: String { source.id }
    }

    private struct DerivedState {
        let glance: PanelGlance
        let status: StatusLevel
        let ribbon: String?
        let placedMarkers: [PlacedMarker]
        let rankedSources: [SubsystemPeak]
        let groupedSensors: [SensorGroup]
    }

    private final class DerivedMemo {
        var key: MemoKey?
        var state: DerivedState?
    }

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
        let supported = PopoverTab.supportedTabs(for: .thermal)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)

        let hasBattery = coordinator.latestPower?.value.hasBattery ?? true
        if let initialSample = coordinator.latestThermal?.value,
           let hottest = Self.buildSensorGroups(from: initialSample, hasBattery: hasBattery).first?.source {
            self._expandedGroups = State(initialValue: [hottest])
            self._hasInitializedDefaultExpansion = State(initialValue: true)
        } else {
            self._expandedGroups = State(initialValue: [])
            self._hasInitializedDefaultExpansion = State(initialValue: false)
        }
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private static func componentSources(hasBattery: Bool) -> [MetricSource] {
        MetricSource.allCases.filter { $0 != .battery || hasBattery }
    }

    public var body: some View {
        let sampleWrapper = coordinator.latestThermal
        let sample = sampleWrapper?.value
        let derived = resolveDerivedState(sampleWrapper: sampleWrapper)
        let availability = coordinator.categoryAvailability[.thermal]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            category: .thermal,
            glance: derived.glance,
            status: derived.status,
            ribbon: derived.ribbon,
            pages: PopoverTab.supportedTabs(for: .thermal),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: .thermal)
            },
            isPinned: PanelController.shared.isPinned(for: .thermal)
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample, derived: derived)
            case .detail:
                detailPage(sample: sample, groups: derived.groupedSensors)
            case .history:
                HistoryPage(category: .thermal, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .thermal)
            }
        }
        .onChange(of: sampleWrapper?.timestamp) { _ in
            if !hasInitializedDefaultExpansion, let hottest = derived.groupedSensors.first?.source {
                expandedGroups = [hottest]
                hasInitializedDefaultExpansion = true
            }
        }
    }

    // MARK: - Memoised Glance & State Derivation (B8 + B14 + A9)

    private func resolveDerivedState(sampleWrapper: Sample<ThermalSample>?) -> DerivedState {
        let currentHasBattery = hasBattery
        let unit = preferences.temperatureUnit
        let key = MemoKey(
            sampleTimestamp: sampleWrapper?.timestamp,
            hasSample: sampleWrapper != nil,
            temperatureUnit: unit,
            refreshInterval: preferences.refreshInterval,
            hasBattery: currentHasBattery
        )

        if derivedMemo.key == key, let cached = derivedMemo.state {
            return cached
        }

        let sample = sampleWrapper?.value
        let referenceDate = sampleWrapper?.timestamp ?? Date()
        let glance = deriveGlance(sample: sample, unit: unit, referenceDate: referenceDate)
        let status = deriveStatus(sample: sample)
        let ribbon = deriveRibbon(sample: sample)

        let placedMarkers: [PlacedMarker]
        let rankedSources: [SubsystemPeak]
        let groupedSensors: [SensorGroup]

        if let s = sample {
            let markers = Self.buildMarkers(sample: s, hasBattery: currentHasBattery)
            placedMarkers = SpectrumLayout.place(
                markers: markers,
                width: Self.spectrumBarWidth,
                minSpacing: 36.0
            )
            rankedSources = Self.buildRankedSources(sample: s, hasBattery: currentHasBattery)
            groupedSensors = Self.buildSensorGroups(from: s, hasBattery: currentHasBattery)
        } else {
            placedMarkers = []
            rankedSources = []
            groupedSensors = []
        }

        let state = DerivedState(
            glance: glance,
            status: status,
            ribbon: ribbon,
            placedMarkers: placedMarkers,
            rankedSources: rankedSources,
            groupedSensors: groupedSensors
        )
        derivedMemo.key = key
        derivedMemo.state = state
        return state
    }

    private func deriveGlance(
        sample: ThermalSample?,
        unit: Units.TemperatureUnit,
        referenceDate: Date
    ) -> PanelGlance {
        let peakC = sample?.peakTemperatureCelsius ?? 0.0
        let peakValue = unit == .fahrenheit ? Units.celsiusToFahrenheit(peakC) : peakC

        let cpuPeak = sample.flatMap { ThermalSensorClassifier.peakCelsius(in: $0, for: .cpu) }
        let gpuPeak = sample.flatMap { ThermalSensorClassifier.peakCelsius(in: $0, for: .gpu) }
        let headline = PanelHeadline.thermal(sample: sample, cpuTemp: cpuPeak, gpuTemp: gpuPeak, unit: unit)

        let peakPointsC = coordinator.timedScalarHistory(
            for: .thermalPeakCelsius,
            duration: 60,
            referenceDate: referenceDate
        )
        let peakPoints = peakPointsC.map { point in
            let converted = unit == .fahrenheit ? Units.celsiusToFahrenheit(point.value) : point.value
            return ChartPoint(timestamp: point.timestamp, value: converted)
        }

        let peakValues = peakPoints.map(\.value)
        let insightUnit: InsightEngine.InsightUnit = unit == .fahrenheit ? .fahrenheit : .celsius
        let insight = InsightEngine.insights(
            series: peakValues,
            interval: preferences.refreshInterval,
            unit: insightUnit,
            thresholds: .thermal(unit: unit)
        ).first?.text

        let visibleMin = peakValues.min() ?? peakValue
        let visibleMax = peakValues.max() ?? peakValue
        let dynamicFloor = ChartScale.domainFloor(for: .thermal, visibleMin: visibleMin)
        let projectedCeiling = ChartScale.niceCeiling(
            for: visibleMax,
            floorVal: dynamicFloor,
            minSpan: 1.0
        ).ceiling

        let warningThreshold = unit == .fahrenheit
            ? Units.celsiusToFahrenheit(Self.warningCelsius)
            : Self.warningCelsius
        let criticalThreshold = unit == .fahrenheit
            ? Units.celsiusToFahrenheit(Self.criticalCelsius)
            : Self.criticalCelsius

        let allBands = [
            ChartBand(
                threshold: warningThreshold,
                color: CategoryPalette.statusColor(for: .warning),
                label: "Warning"
            ),
            ChartBand(
                threshold: criticalThreshold,
                color: CategoryPalette.statusColor(for: .critical),
                label: "Critical"
            )
        ]
        let visibleBands = allBands.filter { $0.threshold <= projectedCeiling }

        let chartMode = LiveChartMode.banded(
            points: peakPoints,
            bands: visibleBands,
            domainFloor: nil
        )

        return PanelGlance(
            value: peakValue,
            format: "%.0f",
            unit: unit.symbol,
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            scrubFormat: { Units.formatTemperature($0, unit: unit, fractionDigits: 1) }
        )
    }

    private func deriveStatus(sample: ThermalSample?) -> StatusLevel {
        guard let pressure = sample?.pressure else { return .fine }
        switch pressure {
        case .critical: return .critical
        case .serious: return .warning
        case .fair: return .elevated
        case .nominal: return .fine
        }
    }

    private func deriveRibbon(sample: ThermalSample?) -> String? {
        guard let pressure = sample?.pressure, pressure != .nominal else { return nil }
        switch pressure {
        case .critical:
            return "Thermal Pressure: Critical. Hardware throttling active."
        case .serious:
            return "Thermal Pressure: Serious. Cooling and performance constrained."
        case .fair:
            return "Thermal Pressure: Fair. Mac is running warm."
        case .nominal:
            return nil
        }
    }

    // MARK: - Now Page (1 Unified Thermal Spectrum Section)

    @ViewBuilder
    private func nowPage(sample: ThermalSample?, derived: DerivedState) -> some View {
        if let s = sample {
            unifiedThermalSpectrumSection(sample: s, derived: derived)
        }
    }

    private func unifiedThermalSpectrumSection(sample: ThermalSample, derived: DerivedState) -> some View {
        let unit = preferences.temperatureUnit
        let barWidth = CGFloat(Self.spectrumBarWidth)
        let placed = derived.placedMarkers
        let maxTier = placed.map(\.tier).max() ?? 0
        let tierSpacing: CGFloat = 18.0
        let topPadding = CGFloat(maxTier) * tierSpacing + 14.0
        let barCenterY = topPadding + 10.0
        let minLabel = Units.formatTemperature(Self.spectrumMinCelsius, unit: unit, fractionDigits: 0)
        let maxLabel = Units.formatTemperature(Self.spectrumMaxCelsius, unit: unit, fractionDigits: 0)

        return Section(
            "Thermal Spectrum",
            trailing: {
                Text("\(minLabel)–\(maxLabel)")
                    .font(Instrument.Typography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        ) {
            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                // Top: 8 pt continuous thermal ramp (30°–110°C) with 10° tick marks and SpectrumLayout sensor pins
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        Capsule()
                            .fill(ThermalRamp.linearGradient)
                            .frame(width: barWidth, height: 8)
                            .position(x: barWidth / 2.0, y: barCenterY)

                        ForEach(Array(stride(from: Self.spectrumMinCelsius, through: Self.spectrumMaxCelsius, by: 10.0)), id: \.self) { deg in
                            let fraction = (deg - Self.spectrumMinCelsius) / (Self.spectrumMaxCelsius - Self.spectrumMinCelsius)
                            let tickX = min(max(0.5, CGFloat(fraction) * barWidth), barWidth - 0.5)
                            Rectangle()
                                .fill(Color.primary.opacity(0.22))
                                .frame(width: 1, height: 4)
                                .position(x: tickX, y: barCenterY + 7.0)
                        }

                        ForEach(placed) { marker in
                            let dotX = CGFloat(marker.x)
                            let dotCenterY = barCenterY - CGFloat(marker.tier) * tierSpacing
                            let labelX = min(max(dotX, 18.0), barWidth - 18.0)
                            let dotColor = ThermalRamp.color(celsius: marker.value)

                            if marker.tier > 0 {
                                let stemHeight = CGFloat(marker.tier) * tierSpacing
                                Rectangle()
                                    .fill(dotColor.opacity(0.65))
                                    .frame(width: 1, height: stemHeight)
                                    .position(x: dotX, y: (dotCenterY + barCenterY) / 2.0)
                            }

                            Circle()
                                .fill(dotColor)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(Instrument.Surface.panel, lineWidth: 1.5)
                                )
                                .position(x: dotX, y: dotCenterY)

                            Text(marker.label)
                                .font(Instrument.Typography.micro)
                                .foregroundStyle(.primary)
                                .fixedSize()
                                .position(x: labelX, y: dotCenterY - 11.0)
                        }
                    }
                    .frame(width: barWidth, height: barCenterY + 10.0)

                    HStack {
                        ForEach([30.0, 50.0, 70.0, 90.0, 110.0], id: \.self) { deg in
                            let displayDeg = unit == .fahrenheit ? Units.celsiusToFahrenheit(deg) : deg
                            Text("\(Int(round(displayDeg)))°")
                                .font(Instrument.Typography.micro)
                                .foregroundStyle(.tertiary)
                            if deg < 110.0 {
                                Spacer()
                            }
                        }
                    }
                    .frame(width: barWidth)
                }

                Rectangle()
                    .fill(Instrument.Surface.hairline)
                    .frame(height: 0.5)

                // Bottom: Ranked subsystem rows with thermal-colored mini meters & tabular temperatures
                if derived.rankedSources.isEmpty {
                    MetricRow(
                        label: "Thermal Pressure",
                        valueText: sample.pressure?.displayName ?? "Nominal"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(derived.rankedSources.enumerated()), id: \.element.id) { index, item in
                            let fraction = max(
                                0.0,
                                min(1.0, (item.peak - Self.spectrumMinCelsius) / (Self.spectrumMaxCelsius - Self.spectrumMinCelsius))
                            )
                            let color = ThermalRamp.color(celsius: item.peak)
                            let formatted = Units.formatTemperature(item.peak, unit: unit, fractionDigits: 1)

                            HStack(spacing: Instrument.Space.s) {
                                Text(item.source.displayName)
                                    .font(Instrument.Typography.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 68, alignment: .leading)
                                    .lineLimit(1)

                                Meter(
                                    progress: fraction,
                                    height: .small,
                                    tint: color,
                                    deepTint: color.opacity(0.8),
                                    interval: preferences.refreshInterval
                                )

                                Text(formatted)
                                    .font(Instrument.Typography.value)
                                    .foregroundStyle(.primary)
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .frame(height: 26)
                            .padding(.horizontal, 4)
                            .overlay(alignment: .bottom) {
                                if index < derived.rankedSources.count - 1 {
                                    Rectangle()
                                        .fill(Instrument.Surface.hairline)
                                        .frame(height: 0.5)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func buildMarkers(sample: ThermalSample, hasBattery: Bool) -> [SpectrumMarker] {
        var markers: [SpectrumMarker] = []
        for src in componentSources(hasBattery: hasBattery) where src != .peak {
            if let peak = ThermalSensorClassifier.peakCelsius(in: sample, for: src) {
                markers.append(SpectrumMarker(
                    id: src.id,
                    value: peak,
                    label: src.shortLabel
                ))
            }
        }
        return markers
    }

    private static func buildRankedSources(sample: ThermalSample, hasBattery: Bool) -> [SubsystemPeak] {
        let subsystems: [SubsystemPeak] = componentSources(hasBattery: hasBattery)
            .filter { $0 != .peak }
            .compactMap { src in
                guard let peak = ThermalSensorClassifier.peakCelsius(in: sample, for: src) else { return nil }
                return SubsystemPeak(source: src, peak: peak)
            }
            .sorted(by: { $0.peak > $1.peak })

        if !subsystems.isEmpty {
            return subsystems
        }
        if let peak = sample.peakTemperatureCelsius {
            return [SubsystemPeak(source: .peak, peak: peak)]
        }
        return []
    }

    // MARK: - Detail Page (Collapsible Sensor Groups)

    @ViewBuilder
    private func detailPage(sample: ThermalSample?, groups: [SensorGroup]) -> some View {
        if sample != nil {
            let unit = preferences.temperatureUnit

            if groups.isEmpty {
                InsetEmptyState(
                    systemImage: "thermometer.medium",
                    title: "No Individual Sensors",
                    reason: "Thermal pressure telemetry is active, but per-sensor channels are unavailable."
                )
            } else {
                VStack(alignment: .leading, spacing: Instrument.Space.m) {
                    ForEach(groups) { group in
                        collapsibleSensorGroupSection(group: group, unit: unit)
                    }
                }
            }
        }
    }

    private func collapsibleSensorGroupSection(group: SensorGroup, unit: Units.TemperatureUnit) -> some View {
        let isExpanded = expandedGroups.contains(group.source)
        let peakFormatted = Units.formatTemperature(group.peak, unit: unit, fractionDigits: 1)

        return Section {
            Button {
                withAnimation(motionPolicy == .frozen ? nil : Motion.snappy) {
                    if isExpanded {
                        expandedGroups.remove(group.source)
                    } else {
                        expandedGroups.insert(group.source)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.m) {
                    Text(group.source.displayName)
                        .font(Instrument.Typography.sectionTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: Instrument.Space.m)

                    HStack(spacing: Instrument.Space.s) {
                        Text("\(group.sensors.count) · \(peakFormatted)")
                            .font(Instrument.Typography.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.source.displayName), \(group.sensors.count) sensors, peak \(peakFormatted)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.sensors.enumerated()), id: \.element.name) { index, sensor in
                        let formatted = Units.formatTemperature(sensor.celsius, unit: unit, fractionDigits: 1)
                        let dotColor = ThermalRamp.color(celsius: sensor.celsius)

                        HStack(spacing: Instrument.Space.m) {
                            Circle()
                                .fill(dotColor)
                                .frame(width: 6, height: 6)

                            Text(sensor.name)
                                .font(Instrument.Typography.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Text(formatted)
                                .font(Instrument.Typography.value)
                                .foregroundStyle(.primary)
                        }
                        .frame(height: 26)
                        .padding(.horizontal, 4)
                        .overlay(alignment: .bottom) {
                            if index < group.sensors.count - 1 {
                                Rectangle()
                                    .fill(Instrument.Surface.hairline)
                                    .frame(height: 0.5)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(sensor.name)
                        .accessibilityValue(formatted)
                    }
                }
            }
        }
    }

    private static func buildSensorGroups(from sample: ThermalSample, hasBattery: Bool) -> [SensorGroup] {
        var groups: [MetricSource: [SensorReading]] = [:]
        for sensor in sample.sensors {
            let cat = ThermalSensorClassifier.classify(sensor) ?? .peak
            groups[cat, default: []].append(sensor)
        }

        return componentSources(hasBattery: hasBattery)
            .compactMap { src in
                guard let list = groups[src], !list.isEmpty else { return nil }
                let sorted = list.sorted(by: { $0.celsius > $1.celsius })
                guard let peak = sorted.first?.celsius else { return nil }
                return SensorGroup(source: src, peak: peak, sensors: sorted)
            }
            .sorted(by: { $0.peak > $1.peak })
    }
}

#if DEBUG
struct TemperaturePanel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TemperaturePanel(
                initialTab: .overview,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Thermal Overview")

            TemperaturePanel(
                initialTab: .detail,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Sensors Detail")
        }
        .frame(width: 352)
        .background(Instrument.Surface.panel)
    }
}
#endif
