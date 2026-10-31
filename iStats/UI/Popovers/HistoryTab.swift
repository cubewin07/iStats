import SwiftUI
import iStatsCore

/// Selectable time range windows for history graphs (Task 7.5, Task 7.6).
public enum HistoryTimeRange: String, CaseIterable, Identifiable, Sendable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"

    public var id: String { rawValue }

    public var durationSeconds: Double {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        }
    }
}

/// Unified History tab view used across all 8 category popovers (ADR 0008, Task 7.5).
/// Features a time range selector, high-signal 140 pt vector TrendChart with hover scrubber,
/// and Min / Avg / Max / Now statistics.
public struct HistoryTab: View {
    public let category: MetricCategory
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedRange: HistoryTimeRange = .oneMinute
    @State private var selectedThermalSource: MetricSource = .peak

    public init(
        category: MetricCategory,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self.category = category
        self.coordinator = coordinator
        self.preferences = preferences
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private var availableThermalSources: [MetricSource] {
        MetricSource.allCases.filter { $0 != .battery || hasBattery }
    }

    public var body: some View {
        VStack(spacing: Tokens.md) {
            // Range Picker & Component Filter Header
            HStack {
                if category == .thermal {
                    // Thermal Filter Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(availableThermalSources, id: \.self) { src in
                                let isSelected = selectedThermalSource == src
                                Button {
                                    selectedThermalSource = src
                                } label: {
                                    Text(src.shortLabel)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? CategoryPalette.thermal : Color.primary.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Text("\(category.displayName) Trend")
                        .font(Tokens.sectionTitle)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 1m | 5m | 15m Segmented Range Picker
                Picker("", selection: $selectedRange) {
                    ForEach(HistoryTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 120)
            }

            // 140 pt Primary TrendChart
            chartContent
                .frame(height: 140)

            // Category-Specific Legend Subtext
            chartLegendSubtext
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var chartContent: some View {
        switch category {
        case .cpu:
            let samples = coordinator.cpuHistory
            let user = samples.map { $0.value.user }
            let system = samples.map { $0.value.system }
            TrendChart(
                mode: .stacked(
                    primary: user,
                    secondary: system,
                    primaryColor: CategoryPalette.cpu,
                    secondaryColor: Color.red.opacity(0.70)
                ),
                fixedMax: 100.0,
                height: 140,
                sampleIntervalSeconds: preferences.refreshInterval,
                showStatsStrip: true,
                formatter: { String(format: "%.0f%%", $0) }
            )

        case .memory:
            let samples = coordinator.memoryHistory
            let ratios = samples.map { sample -> Double in
                let mem = sample.value
                guard mem.total > 0 else { return 0.0 }
                return (Double(mem.used) / Double(mem.total)) * 100.0
            }
            TrendChart(
                mode: .single(
                    values: ratios,
                    color: CategoryPalette.memory,
                    fillGradient: true
                ),
                fixedMax: 100.0,
                height: 140,
                sampleIntervalSeconds: preferences.refreshInterval,
                showStatsStrip: true,
                formatter: { String(format: "%.0f%%", $0) }
            )

        case .gpu:
            let samples = coordinator.gpuHistory
            let utils = samples.compactMap { $0.value.utilization }
            TrendChart(
                mode: .single(
                    values: utils,
                    color: CategoryPalette.gpu,
                    fillGradient: true
                ),
                fixedMax: 100.0,
                height: 140,
                sampleIntervalSeconds: preferences.refreshInterval,
                showStatsStrip: true,
                formatter: { String(format: "%.0f%%", $0) }
            )

        case .thermal:
            let samples = coordinator.thermalHistory
            let temps = samples.map { sample -> Double in
                let matching = ThermalSensorClassifier.sensors(in: sample.value, for: selectedThermalSource)
                let c = matching.map(\.celsius).max() ?? sample.value.peakTemperatureCelsius ?? 0.0
                return preferences.temperatureUnit == .fahrenheit ? Units.celsiusToFahrenheit(c) : c
            }
            TrendChart(
                mode: .single(
                    values: temps,
                    color: CategoryPalette.thermal,
                    fillGradient: true
                ),
                height: 140,
                sampleIntervalSeconds: preferences.refreshInterval,
                showStatsStrip: true,
                formatter: { String(format: "%.0f°", $0) }
            )

        case .fan:
            let samples = coordinator.fanHistory
            let maxRPMs = samples.map { sample -> Double in
                Double(sample.value.fans.map(\.rpm).max() ?? 0)
            }
            TrendChart(
                mode: .single(
                    values: maxRPMs,
                    color: CategoryPalette.fan,
                    fillGradient: true
                ),
                height: 140,
                sampleIntervalSeconds: preferences.refreshInterval,
                showStatsStrip: true,
                formatter: { Units.formatRPM(Int($0)) }
            )

        case .network:
            let samples = coordinator.networkHistory
            let inRates = samples.map { $0.value.totalBytesInPerSec }
            let outRates = samples.map { $0.value.totalBytesOutPerSec }
            TrendChart(
                mode: .mirrored(
                    top: inRates,
                    bottom: outRates,
                    topColor: CategoryPalette.network,
                    bottomColor: Color.pink.opacity(0.85),
                    topLabel: "↓",
                    bottomLabel: "↑"
                ),
                height: 140,
                sampleIntervalSeconds: preferences.refreshInterval,
                showStatsStrip: true,
                formatter: {
                    Units.formatCompactRate($0, unit: self.preferences.networkUnit, standard: self.preferences.byteUnitStandard)
                }
            )

        case .disk:
            let samples = coordinator.diskHistory
            let readRates = samples.map { $0.value.io?.bytesReadPerSec ?? 0.0 }
            let writeRates = samples.map { $0.value.io?.bytesWrittenPerSec ?? 0.0 }
            TrendChart(
                mode: .mirrored(
                    top: readRates,
                    bottom: writeRates,
                    topColor: CategoryPalette.disk,
                    bottomColor: Color.orange.opacity(0.85),
                    topLabel: "R",
                    bottomLabel: "W"
                ),
                height: 140,
                sampleIntervalSeconds: preferences.refreshInterval,
                showStatsStrip: true,
                formatter: {
                    Units.formatDiskRate($0, standard: self.preferences.byteUnitStandard)
                }
            )

        case .power:
            let samples = coordinator.powerHistory
            let watts = samples.map { $0.value.powerDrawWatts ?? 0.0 }
            TrendChart(
                mode: .single(
                    values: watts,
                    color: CategoryPalette.power,
                    fillGradient: true
                ),
                height: 140,
                sampleIntervalSeconds: preferences.refreshInterval,
                showStatsStrip: true,
                formatter: { String(format: "%.1f W", $0) }
            )
        }
    }

    @ViewBuilder
    private var chartLegendSubtext: some View {
        HStack(spacing: Tokens.md) {
            switch category {
            case .cpu:
                HStack(spacing: 4) {
                    Circle().fill(CategoryPalette.cpu).frame(width: 6, height: 6)
                    Text("User").font(.system(size: 9.5)).foregroundColor(.secondary)
                    Circle().fill(Color.red.opacity(0.70)).frame(width: 6, height: 6).padding(.leading, 6)
                    Text("System").font(.system(size: 9.5)).foregroundColor(.secondary)
                }
            case .network:
                HStack(spacing: 4) {
                    Circle().fill(CategoryPalette.network).frame(width: 6, height: 6)
                    Text("Inbound (Download)").font(.system(size: 9.5)).foregroundColor(.secondary)
                    Circle().fill(Color.pink.opacity(0.85)).frame(width: 6, height: 6).padding(.leading, 6)
                    Text("Outbound (Upload)").font(.system(size: 9.5)).foregroundColor(.secondary)
                }
            case .disk:
                HStack(spacing: 4) {
                    Circle().fill(CategoryPalette.disk).frame(width: 6, height: 6)
                    Text("Disk Read").font(.system(size: 9.5)).foregroundColor(.secondary)
                    Circle().fill(Color.orange.opacity(0.85)).frame(width: 6, height: 6).padding(.leading, 6)
                    Text("Disk Write").font(.system(size: 9.5)).foregroundColor(.secondary)
                }
            case .memory:
                Text("RAM Utilization % over time").font(.system(size: 9.5)).foregroundColor(.secondary)
            case .gpu:
                Text("Graphics processor load over time").font(.system(size: 9.5)).foregroundColor(.secondary)
            case .thermal:
                Text("Peak sensor temperature (\(preferences.temperatureUnit.symbol))").font(.system(size: 9.5)).foregroundColor(.secondary)
            case .fan:
                Text("Maximum fan speed across all cooling units").font(.system(size: 9.5)).foregroundColor(.secondary)
            case .power:
                Text("System power draw in Watts").font(.system(size: 9.5)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}
