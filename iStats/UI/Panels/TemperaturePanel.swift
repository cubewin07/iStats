import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Temperature Instrument Panel (Task 8.8d / ADR 0009 / Blueprint §6.4).
/// Features the signature Thermal Spectrum bar, collision-free marker placement,
/// sorted group meters, and collapsible copyable sensors.
public struct TemperaturePanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var expandedGroups: Set<MetricSource> = Set(MetricSource.allCases)

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
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private var componentSources: [MetricSource] {
        MetricSource.allCases.filter { $0 != .battery || hasBattery }
    }

    public var body: some View {
        let sample = coordinator.latestThermal?.value
        let glance = deriveGlance(sample: sample)
        let availability = coordinator.categoryAvailability[.thermal]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)
        let status = deriveStatus(sample: sample)
        let ribbon = deriveRibbon(sample: sample)

        PanelScaffold(
            category: .thermal,
            glance: glance,
            status: status,
            ribbon: ribbon,
            pages: PopoverTab.supportedTabs(for: .thermal),
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
                HistoryPage(category: .thermal, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .thermal)
            }
        }
    }

    // MARK: - Glance Derivation

    private func deriveGlance(sample: ThermalSample?) -> PanelGlance {
        let peakC = sample?.peakTemperatureCelsius ?? 0.0
        let unit = preferences.temperatureUnit
        let peakValue = unit == .fahrenheit ? Units.celsiusToFahrenheit(peakC) : peakC

        let cpuPeak = sample.flatMap { ThermalSensorClassifier.peakCelsius(in: $0, for: .cpu) }
        let gpuPeak = sample.flatMap { ThermalSensorClassifier.peakCelsius(in: $0, for: .gpu) }
        let headline = PanelHeadline.thermal(sample: sample, cpuTemp: cpuPeak, gpuTemp: gpuPeak)

        let peakHistoryC = coordinator.scalarHistory(for: .thermalPeakCelsius, duration: 60)
        let peakHistory = peakHistoryC.map { unit == .fahrenheit ? Units.celsiusToFahrenheit($0) : $0 }
        let insight = InsightEngine.insights(series: peakHistoryC, interval: 1.0, unit: .celsius, thresholds: .thermalCelsius()).first?.text

        let chartMode = LiveChartMode.single(
            values: peakHistory,
            color: CategoryPalette.tint(for: .thermal),
            deepColor: CategoryPalette.tintDeep(for: .thermal)
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

    // MARK: - Now Page (Thermal Spectrum & Group Meters)

    @ViewBuilder
    private func nowPage(sample: ThermalSample?) -> some View {
        if let s = sample {
            VStack(alignment: .leading, spacing: Instrument.Space.l) {
                spectrumBarModule(sample: s)
                groupsModule(sample: s)
            }
        }
    }

    @ViewBuilder
    private func spectrumBarModule(sample: ThermalSample) -> some View {
        let markers = buildMarkers(sample: sample)
        let barWidth: Double = Double(Instrument.Size.panelWidth - 2 * Instrument.Space.xl - 2 * Instrument.Space.modulePadding)
        let placed = SpectrumLayout.place(markers: markers, width: barWidth, minSpacing: 16.0)
        let maxTier = placed.map(\.tier).max() ?? 0
        let topPadding = CGFloat(maxTier) * 16.0

        Module(eyebrow: "Thermal Spectrum (30°–110°C)") {
            VStack(alignment: .leading, spacing: 8) {
                // Spectrum Bar with Stacking Markers
                ZStack(alignment: .topLeading) {
                    // Base Spectrum Bar
                    Capsule()
                        .fill(ThermalRamp.linearGradient)
                        .frame(width: CGFloat(barWidth), height: 10)
                        .padding(.top, topPadding + 6)

                    // Placed Marker Dots and Labels
                    ForEach(placed) { marker in
                        let dotX = CGFloat(marker.x)
                        let dotY = topPadding + 11 - CGFloat(marker.tier) * 16.0
                        let dotColor = ThermalRamp.color(celsius: marker.value)

                        VStack(spacing: 2) {
                            Text(marker.label)
                                .font(Instrument.Typography.micro)
                                .foregroundColor(Color.primary)

                            Circle()
                                .fill(dotColor)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.4), lineWidth: 1)
                                )
                        }
                        .offset(x: dotX - 12, y: dotY - 20)
                    }
                }
                .frame(width: CGFloat(barWidth), height: topPadding + 28)

                // Range Bounds Footnotes
                HStack {
                    Text(Units.formatTemperature(30.0, unit: preferences.temperatureUnit, fractionDigits: 0))
                        .font(Instrument.Typography.caption)
                        .foregroundColor(Color.secondary)
                    Spacer()
                    Text(Units.formatTemperature(110.0, unit: preferences.temperatureUnit, fractionDigits: 0))
                        .font(Instrument.Typography.caption)
                        .foregroundColor(Color.secondary)
                }
                .frame(width: CGFloat(barWidth))
            }
        }
    }

    private func buildMarkers(sample: ThermalSample) -> [SpectrumMarker] {
        var markers: [SpectrumMarker] = []
        for src in componentSources where src != .peak {
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

    @ViewBuilder
    private func groupsModule(sample: ThermalSample) -> some View {
        let activeSources: [(source: MetricSource, peak: Double)] = componentSources
            .compactMap { src in
                guard let peak = ThermalSensorClassifier.peakCelsius(in: sample, for: src) else { return nil }
                return (source: src, peak: peak)
            }
            .sorted(by: { $0.peak > $1.peak })

        Module(eyebrow: "Thermal Groups") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(activeSources, id: \.source.id) { item in
                    let fraction = max(0.0, min(1.0, (item.peak - 30.0) / 80.0))
                    let color = ThermalRamp.color(celsius: item.peak)
                    let formatted = Units.formatTemperature(item.peak, unit: preferences.temperatureUnit, fractionDigits: 0)

                    HStack(spacing: Instrument.Space.s) {
                        Text(item.source.displayName)
                            .font(Instrument.Typography.body)
                            .foregroundColor(Color.primary)
                            .frame(width: 80, alignment: .leading)

                        Meter(
                            progress: fraction,
                            height: .small,
                            tint: color,
                            deepTint: color.opacity(0.8)
                        )

                        Text(formatted)
                            .font(Instrument.Typography.value)
                            .foregroundColor(Color.primary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Detail Page (Sensors)

    @ViewBuilder
    private func detailPage(sample: ThermalSample?) -> some View {
        if let s = sample {
            let unit = preferences.temperatureUnit
            let groupedSensors = groupSensors(sensors: s.sensors)

            VStack(alignment: .leading, spacing: Instrument.Space.l) {
                ForEach(groupedSensors, id: \.source.id) { group in
                    let isExpanded = expandedGroups.contains(group.source)
                    Module(
                        eyebrow: "\(group.source.displayName) Sensors (\(group.sensors.count))",
                        trailing: {
                            Button {
                                withAnimation(Motion.snappy) {
                                    if isExpanded {
                                        expandedGroups.remove(group.source)
                                    } else {
                                        expandedGroups.insert(group.source)
                                    }
                                }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    ) {
                        if isExpanded {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(group.sensors, id: \.name) { sensor in
                                    let formatted = Units.formatTemperature(sensor.celsius, unit: unit, fractionDigits: 1)
                                    let dotColor = ThermalRamp.color(celsius: sensor.celsius)

                                    HStack {
                                        Circle()
                                            .fill(dotColor)
                                            .frame(width: 6, height: 6)

                                        Text(sensor.name)
                                            .font(Instrument.Typography.body)
                                            .foregroundColor(Color.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(formatted)
                                            .font(Instrument.Typography.value)
                                            .foregroundColor(Color.primary)
                                    }
                                    .padding(.vertical, 2)
                                    .copyable(text: "\(sensor.name): \(formatted)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func groupSensors(sensors: [SensorReading]) -> [(source: MetricSource, sensors: [SensorReading])] {
        var groups: [MetricSource: [SensorReading]] = [:]
        for sensor in sensors {
            let cat = ThermalSensorClassifier.classify(sensor) ?? .peak
            groups[cat, default: []].append(sensor)
        }

        return componentSources
            .compactMap { src in
                guard let list = groups[src], !list.isEmpty else { return nil }
                let sorted = list.sorted(by: { $0.celsius > $1.celsius })
                return (source: src, sensors: sorted)
            }
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
