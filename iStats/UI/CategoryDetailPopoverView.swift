import SwiftUI
import iStatsCore

/// A focused, dedicated popover view presenting metrics solely for a specific `MetricCategory` (ADR 0007).
/// All menu bar icons configured under the same category share this popover presentation.
public struct CategoryDetailPopoverView: View {
    public let category: MetricCategory
    @ObservedObject public var coordinator: MetricsCoordinator
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

    private var currentVerdict: MetricVerdict {
        switch category {
        case .cpu:
            return VerdictEvaluator.evaluateCPU(overrideCPUSample ?? coordinator.latestCPU?.value)
        case .memory:
            return VerdictEvaluator.evaluateMemory(overrideMemorySample ?? coordinator.latestMemory?.value, standard: preferences.byteUnitStandard)
        case .gpu:
            return VerdictEvaluator.evaluateGPU(overrideGPUSample ?? coordinator.latestGPU?.value)
        case .thermal:
            return VerdictEvaluator.evaluateThermal(overrideThermalSample ?? coordinator.latestThermal?.value, unit: preferences.temperatureUnit)
        case .fan:
            return VerdictEvaluator.evaluateFan(overrideFanSample ?? coordinator.latestFan?.value)
        case .network:
            return VerdictEvaluator.evaluateNetwork(overrideNetworkSample ?? coordinator.latestNetwork?.value, unit: preferences.networkUnit, standard: preferences.byteUnitStandard)
        case .disk:
            return VerdictEvaluator.evaluateDisk(overrideDiskSample ?? coordinator.latestDisk?.value, standard: preferences.byteUnitStandard)
        case .power:
            return VerdictEvaluator.evaluatePower(overridePowerSample ?? coordinator.latestPower?.value)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Standardized 3-tier Header
            PopoverHeaderView(
                category: category,
                verdict: currentVerdict
            )

            Divider()

            // Category-Specific Metric Content
            categoryContent
                .frame(maxWidth: .infinity)

            Divider()

            // Footer / System Actions
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
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning {
                coordinator.start()
            }
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch category {
        case .cpu:
            CPUSummaryView(
                sample: overrideCPUSample ?? coordinator.latestCPU?.value,
                history: coordinator.cpuHistory
            )
        case .memory:
            MemorySummaryView(
                sample: overrideMemorySample ?? coordinator.latestMemory?.value,
                history: coordinator.memoryHistory,
                byteStandard: preferences.byteUnitStandard
            )
        case .gpu:
            GPUSummaryView(
                sample: overrideGPUSample ?? coordinator.latestGPU?.value,
                history: coordinator.gpuHistory,
                temperatureUnit: preferences.temperatureUnit,
                byteStandard: preferences.byteUnitStandard
            )
        case .thermal:
            ThermalSummaryView(
                sample: overrideThermalSample ?? coordinator.latestThermal?.value,
                history: coordinator.thermalHistory,
                temperatureUnit: preferences.temperatureUnit
            )
        case .fan:
            FanSummaryView(
                sample: overrideFanSample ?? coordinator.latestFan?.value,
                history: coordinator.fanHistory
            )
        case .network:
            NetworkSummaryView(
                sample: overrideNetworkSample ?? coordinator.latestNetwork?.value,
                history: coordinator.networkHistory,
                networkUnit: preferences.networkUnit,
                byteStandard: preferences.byteUnitStandard
            )
        case .disk:
            DiskSummaryView(
                sample: overrideDiskSample ?? coordinator.latestDisk?.value,
                history: coordinator.diskHistory,
                byteStandard: preferences.byteUnitStandard
            )
        case .power:
            PowerSummaryView(
                sample: overridePowerSample ?? coordinator.latestPower?.value,
                history: coordinator.powerHistory
            )
        }
    }
}
