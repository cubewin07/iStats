import SwiftUI
import iStatsCore

/// Purpose-driven Temperature popover (ADR 0008, Task 7.4d).
/// Structure: Overview · Sensors · History.
/// Answers: "Is my Mac running hot? Which component is heating up?"
public struct TemperaturePopover: View {
    @State public var selectedTab: PopoverTab
    public let focusSource: MetricSource?
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    public init(
        initialTab: PopoverTab = .overview,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self._selectedTab = State(initialValue: initialTab)
        self.focusSource = focusSource
        self.coordinator = coordinator
        self.preferences = preferences
    }

    private var sample: ThermalSample? {
        coordinator.latestThermal?.value
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateThermal(sample, unit: preferences.temperatureUnit)
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private var componentSources: [MetricSource] {
        MetricSource.allCases.filter { $0 != .battery || hasBattery }
    }

    public var body: some View {
        PopoverScaffold(
            category: .thermal,
            verdict: verdict,
            tabs: [.overview, .detail, .history],
            selectedTab: $selectedTab,
            isLoading: coordinator.latestThermal == nil,
            unavailableReason: coordinator.categoryAvailability[.thermal]?.unavailableReason,
            preferences: preferences,
            coordinator: coordinator
        ) {
            switch selectedTab {
            case .overview:
                overviewTab
            case .detail:
                sensorsTab
            case .history:
                HistoryTab(category: .thermal, coordinator: coordinator, preferences: preferences)
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let th = sample {
            let peakC = th.peakTemperatureCelsius ?? 0.0
            let unit = preferences.temperatureUnit
            let formattedPeak = Units.formatTemperature(peakC, unit: unit, fractionDigits: 0)

            VStack(alignment: .leading, spacing: Tokens.md) {
                // Hero Metric + Sparkline
                HStack(alignment: .top, spacing: Tokens.md) {
                    HeroMetric(
                        primaryValue: formattedPeak,
                        unit: "",
                        contextLine: "Peak Sensor Temperature"
                    )
                    .frame(width: 130, alignment: .leading)

                    let peakHistory = coordinator.thermalHistory.map { s -> Double in
                        let c = s.value.peakTemperatureCelsius ?? 0.0
                        return unit == .fahrenheit ? Units.celsiusToFahrenheit(c) : c
                    }
                    TrendChart(
                        mode: .single(
                            values: peakHistory,
                            color: CategoryPalette.thermal,
                            fillGradient: true
                        ),
                        height: 52,
                        sampleIntervalSeconds: preferences.refreshInterval
                    )
                    .frame(maxWidth: .infinity)
                }

                // Subcomponent Temperature Rows (CPU, GPU, Memory, SSD, Battery)
                VStack(spacing: 6) {
                    ForEach(componentSources, id: \.self) { src in
                        componentRow(for: src, in: th)
                    }
                }
                .padding(10)
                .cardBackground()

                // Thermal Pressure Banner if Elevated
                if let pressure = th.pressure, pressure != .nominal {
                    let level = StatusThresholds.thermalPressure(pressure)
                    StatusBanner(
                        iconName: "flame.fill",
                        message: "Thermal Pressure: \(pressure.rawValue.capitalized). macOS may throttle clock speeds to manage heat.",
                        level: level
                    )
                }
            }
        }
    }

    private func componentRow(for source: MetricSource, in thermal: ThermalSample) -> some View {
        let matching = ThermalSensorClassifier.sensors(in: thermal, for: source)
        let maxSensor = matching.max(by: { $0.celsius < $1.celsius })
        let tempC = maxSensor?.celsius ?? (source == .peak ? thermal.peakTemperatureCelsius : nil)
        let isFocused = (focusSource != nil && focusSource == source)
        let level = tempC.map { StatusThresholds.temperature(celsius: $0, source: source) } ?? .fine

        return HStack {
            HStack(spacing: 6) {
                Text(source.displayName)
                    .font(.system(size: 11, weight: isFocused ? .bold : .medium))
                    .foregroundColor(isFocused ? .primary : .secondary)

                if isFocused {
                    Text("Focus")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(CategoryPalette.thermal)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(CategoryPalette.thermal.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if let c = tempC {
                HStack(spacing: 6) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 6, height: 6)

                    Text(Units.formatTemperature(c, unit: preferences.temperatureUnit, fractionDigits: 0))
                        .font(Tokens.monoValue)
                        .foregroundColor(level.color)
                }
            } else {
                Text("—")
                    .font(Tokens.monoValue)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Sensors Tab

    @ViewBuilder
    private var sensorsTab: some View {
        if let th = sample {
            let unit = preferences.temperatureUnit
            let sensors = th.sensors.sorted(by: { $0.celsius > $1.celsius })

            VStack(alignment: .leading, spacing: Tokens.sm) {
                HStack {
                    Text("Hardware Sensors (\(sensors.count))")
                        .font(Tokens.sectionTitle)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Highest to lowest")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(sensors, id: \.name) { sensor in
                            let cat = ThermalSensorClassifier.classify(sensor) ?? .peak
                            let level = StatusThresholds.temperature(celsius: sensor.celsius, source: cat)

                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(sensor.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text(cat.displayName)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(level.color)
                                        .frame(width: 5, height: 5)

                                    Text(Units.formatTemperature(sensor.celsius, unit: unit, fractionDigits: 1))
                                        .font(Tokens.monoValue)
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }
}
