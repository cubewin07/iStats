import SwiftUI
import iStatsCore

/// Purpose-driven GPU popover (ADR 0008, Task 7.4c).
/// Structure: Overview · Engines · History.
/// Answers: "Is my GPU throttling or maxed out?"
public struct GPUPopover: View {
    @State public var selectedTab: PopoverTab
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    public let rememberLastTab: Bool

    public init(
        initialTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self._selectedTab = State(initialValue: initialTab)
        self.rememberLastTab = rememberLastTab
        self.coordinator = coordinator
        self.preferences = preferences
    }

    private var sample: GPUSample? {
        coordinator.latestGPU?.value
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateGPU(sample)
    }

    private var hasDetailedEngines: Bool {
        sample?.rendererUtilization != nil || sample?.tilerUtilization != nil
    }

    public var body: some View {
        PopoverScaffold(
            category: .gpu,
            verdict: verdict,
            tabs: [.overview, .detail, .history],
            selectedTab: $selectedTab,
            hasDetailedGPUEngines: hasDetailedEngines,
            rememberLastTab: rememberLastTab,
            isLoading: coordinator.latestGPU == nil,
            unavailableReason: coordinator.categoryAvailability[.gpu]?.unavailableReason,
            preferences: preferences,
            coordinator: coordinator
        ) {
            switch selectedTab {
            case .overview:
                overviewTab
            case .detail:
                enginesTab
            case .history:
                HistoryTab(category: .gpu, coordinator: coordinator, preferences: preferences)
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let gpu = sample {
            let util = gpu.utilization ?? 0.0

            VStack(alignment: .leading, spacing: Tokens.md) {
                // Hero Metric + Sparkline
                HStack(alignment: .top, spacing: Tokens.md) {
                    let tempStr = gpu.tempCelsius.map { " · \(Units.formatTemperature($0, unit: preferences.temperatureUnit, fractionDigits: 0))" } ?? ""
                    HeroMetric(
                        primaryValue: String(format: "%.0f", util),
                        unit: "%",
                        contextLine: "GPU Utilization\(tempStr)"
                    )
                    .frame(width: 130, alignment: .leading)

                    let utils = coordinator.gpuHistory.compactMap { $0.value.utilization }
                    TrendChart(
                        mode: .single(
                            values: utils,
                            color: CategoryPalette.gpu,
                            fillGradient: true
                        ),
                        fixedMax: 100.0,
                        height: 52,
                        sampleIntervalSeconds: preferences.refreshInterval
                    )
                    .frame(maxWidth: .infinity)
                }

                // Load Progress Bar
                SegmentedBar(segments: [
                    .init(value: util, color: CategoryPalette.gpu, label: "Active"),
                    .init(value: max(0, 100.0 - util), color: Color.secondary.opacity(0.2), label: "Idle")
                ])

                // Subsystem Stats Grid
                VStack(spacing: 6) {
                    if let watts = gpu.powerWatts {
                        StatRow(
                            label: "Power Consumption",
                            value: String(format: "%.1f W", watts)
                        )
                    }

                    if let temp = gpu.tempCelsius {
                        let level = StatusThresholds.temperature(celsius: temp, source: .gpu)
                        StatRow(
                            label: "GPU Die Temperature",
                            value: Units.formatTemperature(temp, unit: preferences.temperatureUnit, fractionDigits: 1),
                            statusLevel: level
                        )
                    }

                    if let allocated = gpu.allocatedMemory, let maxMem = gpu.recommendedMaxMemory, maxMem > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("VRAM Working Set")
                                    .font(Tokens.bodyLabel)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Units.formatBytes(allocated, standard: preferences.byteUnitStandard)) / \(Units.formatBytes(maxMem, standard: preferences.byteUnitStandard))")
                                    .font(Tokens.monoValue)
                                    .foregroundColor(.primary)
                            }
                            RangeBar(
                                value: Double(allocated),
                                min: 0,
                                max: Double(maxMem),
                                tintColor: CategoryPalette.gpu
                            )
                        }
                        .padding(.top, 2)
                    } else if let memUsed = gpu.memoryUsed {
                        StatRow(
                            label: "Graphics Working Set",
                            value: Units.formatBytes(memUsed, standard: preferences.byteUnitStandard)
                        )
                    }
                }
                .padding(10)
                .cardBackground()
            }
        }
    }

    // MARK: - Engines Tab

    @ViewBuilder
    private var enginesTab: some View {
        if let gpu = sample {
            VStack(alignment: .leading, spacing: Tokens.md) {
                Text("Graphics Subsystem Details")
                    .font(Tokens.sectionTitle)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    if let renderer = gpu.rendererUtilization {
                        engineProgressRow(label: "3D Renderer Engine", percentage: renderer)
                    }

                    if let tiler = gpu.tilerUtilization {
                        engineProgressRow(label: "Geometry / Tiler Engine", percentage: tiler)
                    }

                    if let coreCount = gpu.coreCount {
                        StatRow(label: "GPU Core Count", value: "\(coreCount) Cores")
                    }

                    if let deviceName = gpu.deviceName, !deviceName.isEmpty {
                        StatRow(label: "Metal Device", value: deviceName)
                    }

                    if let unified = gpu.isUnifiedMemory {
                        StatRow(label: "Memory Architecture", value: unified ? "Unified Memory" : "Discrete VRAM")
                    }

                    if let metal = gpu.metalFeatureSet, !metal.isEmpty {
                        StatRow(label: "Metal Architecture", value: metal)
                    }

                    if let ray = gpu.supportsRaytracing {
                        StatRow(label: "Hardware Ray Tracing", value: ray ? "Supported" : "Not Supported")
                    }

                    if let displays = gpu.displayDescriptions, !displays.isEmpty {
                        StatRow(label: "Connected Displays", value: displays.joined(separator: ", "))
                    }
                }
                .padding(10)
                .cardBackground()

                if let recoveries = gpu.recoveryCount, recoveries > 0 {
                    StatusBanner(
                        iconName: "exclamationmark.triangle.fill",
                        message: "Driver recovery events: \(recoveries) GPU resets detected.",
                        level: .warning
                    )
                }

                if gpu.rendererUtilization == nil && gpu.tilerUtilization == nil {
                    Text("Per-engine hardware telemetry is synthesized via IOKit on this architecture.")
                        .font(Tokens.bodyLabel)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func engineProgressRow(label: String, percentage: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(Tokens.bodyLabel)
                    .foregroundColor(.primary)
                Spacer()
                Text(String(format: "%.0f%%", percentage))
                    .font(Tokens.monoValue)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(CategoryPalette.gpu)
                        .frame(width: max(0, geo.size.width * CGFloat(percentage / 100.0)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

