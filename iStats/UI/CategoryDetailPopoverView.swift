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

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: iconName(for: category))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("\(category.displayName) Metrics")
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                Text("iStats")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)

            Divider()

            // Category-Specific Metric Content
            categoryContent
                .frame(maxWidth: .infinity)

            Divider()

            // Footer / Actions
            HStack {
                Text(statusFooterText)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Preferences...") {
                    PreferencesWindowController.shared.showPreferences()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
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

    private var statusFooterText: String {
        switch category {
        case .thermal:
            if let thermal = coordinator.latestThermal?.value, let pressure = thermal.pressure, pressure.isElevated {
                return "Thermal Pressure: \(pressure.displayName)"
            }
        case .memory:
            if let memory = coordinator.latestMemory?.value {
                return "Pressure: \(memory.pressure.displayName)"
            }
        default:
            break
        }

        return coordinator.isRunning ? "Sampling Live" : "Ready"
    }

    private func iconName(for category: MetricCategory) -> String {
        switch category {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .fan: return "fan"
        case .gpu: return "display"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        }
    }
}
