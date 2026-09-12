import SwiftUI
import iStatsCore

/// A focused, dedicated popover view presenting metrics solely for a specific `MetricCategory` (ADR 0007).
///
/// Performance optimization:
/// Instead of observing the entire `MetricsCoordinator` (which causes blanket re-renders whenever ANY
/// metric in the system ticks), `CategoryDetailPopoverView` delegates rendering to category-specific sections
/// that listen strictly to their own targeted `$latest<Category>` Combine publishers via `.onReceive`.
public struct CategoryDetailPopoverView: View {
    public let category: MetricCategory
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    // Optional sample overrides for previews / testing
    public let overrideCPUSample: CPUSample?
    public let overrideMemorySample: MemorySample?
    public let overrideGPUSample: GPUSample?
    public let overrideNetworkSample: NetworkSample?
    public let overrideDiskSample: DiskSample?
    public let overridePowerSample: PowerSample?
    public let overrideThermalSample: ThermalSample?
    public let overrideFanSample: FanSample?

    public init(
        category: MetricCategory,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        cpuSample: CPUSample? = nil,
        memorySample: MemorySample? = nil,
        gpuSample: GPUSample? = nil,
        networkSample: NetworkSample? = nil,
        diskSample: DiskSample? = nil,
        powerSample: PowerSample? = nil,
        thermalSample: ThermalSample? = nil,
        fanSample: FanSample? = nil
    ) {
        self.category = category
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideCPUSample = cpuSample
        self.overrideMemorySample = memorySample
        self.overrideGPUSample = gpuSample
        self.overrideNetworkSample = networkSample
        self.overrideDiskSample = diskSample
        self.overridePowerSample = powerSample
        self.overrideThermalSample = thermalSample
        self.overrideFanSample = fanSample
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category-Specific Metric Content (Isolated fine-grained publisher subscription)
            categorySection
                .frame(maxWidth: .infinity)

            Divider()

            // Footer / System Actions (Static, never re-renders on telemetry ticks)
            footerActions
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning {
                coordinator.start()
            }
        }
    }

    // MARK: - Category Sections (Fine-Grained Isolation)

    @ViewBuilder
    private var categorySection: some View {
        switch category {
        case .cpu:
            CPUCategorySection(
                coordinator: coordinator,
                overrideSample: overrideCPUSample
            )
        case .memory:
            MemoryCategorySection(
                coordinator: coordinator,
                preferences: preferences,
                overrideSample: overrideMemorySample
            )
        case .gpu:
            GPUCategorySection(
                coordinator: coordinator,
                preferences: preferences,
                overrideSample: overrideGPUSample
            )
        case .thermal:
            ThermalCategorySection(
                coordinator: coordinator,
                preferences: preferences,
                overrideSample: overrideThermalSample
            )
        case .fan:
            FanCategorySection(
                coordinator: coordinator,
                overrideSample: overrideFanSample
            )
        case .network:
            NetworkCategorySection(
                coordinator: coordinator,
                preferences: preferences,
                overrideSample: overrideNetworkSample
            )
        case .disk:
            DiskCategorySection(
                coordinator: coordinator,
                preferences: preferences,
                overrideSample: overrideDiskSample
            )
        case .power:
            PowerCategorySection(
                coordinator: coordinator,
                overrideSample: overridePowerSample
            )
        }
    }

    // MARK: - Static Footer Actions

    private var footerActions: some View {
        HStack(spacing: 6) {
            Button(action: {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }) {
                Label("Activity Monitor", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button(action: {
                PreferencesWindowController.shared.showPreferences()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("Preferences...")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Dedicated Category Subsections (Targeted Publisher Subscriptions)

private struct CPUCategorySection: View {
    let coordinator: MetricsCoordinator
    let overrideSample: CPUSample?
    @State private var sample: CPUSample?
    @State private var history: [Sample<CPUSample>]

    init(coordinator: MetricsCoordinator, overrideSample: CPUSample?) {
        self.coordinator = coordinator
        self.overrideSample = overrideSample
        _sample = State(initialValue: overrideSample ?? coordinator.latestCPU?.value)
        _history = State(initialValue: coordinator.cpuHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(category: .cpu, verdict: VerdictEvaluator.evaluateCPU(sample))
            Divider()
            CPUSummaryView(sample: sample, history: history)
        }
        .onReceive(coordinator.$latestCPU) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.cpuHistory
            }
        }
    }
}

private struct MemoryCategorySection: View {
    let coordinator: MetricsCoordinator
    @ObservedObject var preferences: PreferencesStore
    let overrideSample: MemorySample?
    @State private var sample: MemorySample?
    @State private var history: [Sample<MemorySample>]

    init(coordinator: MetricsCoordinator, preferences: PreferencesStore, overrideSample: MemorySample?) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = overrideSample
        _sample = State(initialValue: overrideSample ?? coordinator.latestMemory?.value)
        _history = State(initialValue: coordinator.memoryHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .memory,
                verdict: VerdictEvaluator.evaluateMemory(sample, standard: preferences.byteUnitStandard)
            )
            Divider()
            MemorySummaryView(
                sample: sample,
                history: history,
                byteStandard: preferences.byteUnitStandard
            )
        }
        .onReceive(coordinator.$latestMemory) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.memoryHistory
            }
        }
    }
}

private struct GPUCategorySection: View {
    let coordinator: MetricsCoordinator
    @ObservedObject var preferences: PreferencesStore
    let overrideSample: GPUSample?
    @State private var sample: GPUSample?
    @State private var history: [Sample<GPUSample>]

    init(coordinator: MetricsCoordinator, preferences: PreferencesStore, overrideSample: GPUSample?) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = overrideSample
        _sample = State(initialValue: overrideSample ?? coordinator.latestGPU?.value)
        _history = State(initialValue: coordinator.gpuHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .gpu,
                verdict: VerdictEvaluator.evaluateGPU(sample)
            )
            Divider()
            GPUSummaryView(
                sample: sample,
                history: history,
                temperatureUnit: preferences.temperatureUnit,
                byteStandard: preferences.byteUnitStandard
            )
        }
        .onReceive(coordinator.$latestGPU) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.gpuHistory
            }
        }
    }
}

private struct ThermalCategorySection: View {
    let coordinator: MetricsCoordinator
    @ObservedObject var preferences: PreferencesStore
    let overrideSample: ThermalSample?
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    init(coordinator: MetricsCoordinator, preferences: PreferencesStore, overrideSample: ThermalSample?) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = overrideSample
        _sample = State(initialValue: overrideSample ?? coordinator.latestThermal?.value)
        _history = State(initialValue: coordinator.thermalHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                verdict: VerdictEvaluator.evaluateThermal(sample, unit: preferences.temperatureUnit)
            )
            Divider()
            ThermalSummaryView(
                sample: sample,
                history: history,
                temperatureUnit: preferences.temperatureUnit
            )
        }
        .onReceive(coordinator.$latestThermal) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.thermalHistory
            }
        }
    }
}

private struct FanCategorySection: View {
    let coordinator: MetricsCoordinator
    let overrideSample: FanSample?
    @State private var sample: FanSample?
    @State private var history: [Sample<FanSample>]

    init(coordinator: MetricsCoordinator, overrideSample: FanSample?) {
        self.coordinator = coordinator
        self.overrideSample = overrideSample
        _sample = State(initialValue: overrideSample ?? coordinator.latestFan?.value)
        _history = State(initialValue: coordinator.fanHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .fan,
                verdict: VerdictEvaluator.evaluateFan(sample)
            )
            Divider()
            FanSummaryView(
                sample: sample,
                history: history
            )
        }
        .onReceive(coordinator.$latestFan) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.fanHistory
            }
        }
    }
}

private struct NetworkCategorySection: View {
    let coordinator: MetricsCoordinator
    @ObservedObject var preferences: PreferencesStore
    let overrideSample: NetworkSample?
    @State private var sample: NetworkSample?
    @State private var history: [Sample<NetworkSample>]

    init(coordinator: MetricsCoordinator, preferences: PreferencesStore, overrideSample: NetworkSample?) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = overrideSample
        _sample = State(initialValue: overrideSample ?? coordinator.latestNetwork?.value)
        _history = State(initialValue: coordinator.networkHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .network,
                verdict: VerdictEvaluator.evaluateNetwork(
                    sample,
                    unit: preferences.networkUnit,
                    standard: preferences.byteUnitStandard
                )
            )
            Divider()
            NetworkSummaryView(
                sample: sample,
                history: history,
                networkUnit: preferences.networkUnit,
                byteStandard: preferences.byteUnitStandard
            )
        }
        .onReceive(coordinator.$latestNetwork) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.networkHistory
            }
        }
    }
}

private struct DiskCategorySection: View {
    let coordinator: MetricsCoordinator
    @ObservedObject var preferences: PreferencesStore
    let overrideSample: DiskSample?
    @State private var sample: DiskSample?
    @State private var history: [Sample<DiskSample>]

    init(coordinator: MetricsCoordinator, preferences: PreferencesStore, overrideSample: DiskSample?) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = overrideSample
        _sample = State(initialValue: overrideSample ?? coordinator.latestDisk?.value)
        _history = State(initialValue: coordinator.diskHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .disk,
                verdict: VerdictEvaluator.evaluateDisk(sample, standard: preferences.byteUnitStandard)
            )
            Divider()
            DiskSummaryView(
                sample: sample,
                history: history,
                byteStandard: preferences.byteUnitStandard
            )
        }
        .onReceive(coordinator.$latestDisk) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.diskHistory
            }
        }
    }
}

private struct PowerCategorySection: View {
    let coordinator: MetricsCoordinator
    let overrideSample: PowerSample?
    @State private var sample: PowerSample?
    @State private var history: [Sample<PowerSample>]

    init(coordinator: MetricsCoordinator, overrideSample: PowerSample?) {
        self.coordinator = coordinator
        self.overrideSample = overrideSample
        _sample = State(initialValue: overrideSample ?? coordinator.latestPower?.value)
        _history = State(initialValue: coordinator.powerHistory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .power,
                verdict: VerdictEvaluator.evaluatePower(sample)
            )
            Divider()
            PowerSummaryView(
                sample: sample,
                history: history
            )
        }
        .onReceive(coordinator.$latestPower) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.powerHistory
            }
        }
    }
}
