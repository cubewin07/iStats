import SwiftUI
import iStatsCore

public struct DetailPopoverView: View {
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    // Optional overrides for testing / previews
    private let overrideCPUSample: CPUSample?
    private let overrideMemorySample: MemorySample?
    private let overrideGPUSample: GPUSample?
    private let overrideNetworkSample: NetworkSample?
    private let overrideDiskSample: DiskSample?
    private let overridePowerSample: PowerSample?
    private let overrideThermalSample: ThermalSample?
    private let overrideFanSample: FanSample?
    private let overrideCPUHistory: [Sample<CPUSample>]?
    private let overrideMemoryHistory: [Sample<MemorySample>]?
    private let overrideGPUHistory: [Sample<GPUSample>]?
    private let overrideNetworkHistory: [Sample<NetworkSample>]?
    private let overrideDiskHistory: [Sample<DiskSample>]?
    private let overridePowerHistory: [Sample<PowerSample>]?
    private let overrideThermalHistory: [Sample<ThermalSample>]?
    private let overrideFanHistory: [Sample<FanSample>]?

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        cpuSample: CPUSample? = nil,
        memorySample: MemorySample? = nil,
        gpuSample: GPUSample? = nil,
        networkSample: NetworkSample? = nil,
        diskSample: DiskSample? = nil,
        powerSample: PowerSample? = nil,
        thermalSample: ThermalSample? = nil,
        fanSample: FanSample? = nil,
        cpuHistory: [Sample<CPUSample>]? = nil,
        memoryHistory: [Sample<MemorySample>]? = nil,
        gpuHistory: [Sample<GPUSample>]? = nil,
        networkHistory: [Sample<NetworkSample>]? = nil,
        diskHistory: [Sample<DiskSample>]? = nil,
        powerHistory: [Sample<PowerSample>]? = nil,
        thermalHistory: [Sample<ThermalSample>]? = nil,
        fanHistory: [Sample<FanSample>]? = nil
    ) {
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
        self.overrideCPUHistory = cpuHistory
        self.overrideMemoryHistory = memoryHistory
        self.overrideGPUHistory = gpuHistory
        self.overrideNetworkHistory = networkHistory
        self.overrideDiskHistory = diskHistory
        self.overridePowerHistory = powerHistory
        self.overrideThermalHistory = thermalHistory
        self.overrideFanHistory = fanHistory
    }

    private var currentCPUSample: CPUSample? {
        overrideCPUSample ?? coordinator.latestCPU?.value
    }

    private var currentCPUHistory: [Sample<CPUSample>] {
        overrideCPUHistory ?? coordinator.cpuHistory
    }

    private var currentMemorySample: MemorySample? {
        overrideMemorySample ?? coordinator.latestMemory?.value
    }

    private var currentMemoryHistory: [Sample<MemorySample>] {
        overrideMemoryHistory ?? coordinator.memoryHistory
    }

    private var currentGPUSample: GPUSample? {
        overrideGPUSample ?? coordinator.latestGPU?.value
    }

    private var currentGPUHistory: [Sample<GPUSample>] {
        overrideGPUHistory ?? coordinator.gpuHistory
    }

    private var currentNetworkSample: NetworkSample? {
        overrideNetworkSample ?? coordinator.latestNetwork?.value
    }

    private var currentNetworkHistory: [Sample<NetworkSample>] {
        overrideNetworkHistory ?? coordinator.networkHistory
    }

    private var currentDiskSample: DiskSample? {
        overrideDiskSample ?? coordinator.latestDisk?.value
    }

    private var currentDiskHistory: [Sample<DiskSample>] {
        overrideDiskHistory ?? coordinator.diskHistory
    }

    private var currentPowerSample: PowerSample? {
        overridePowerSample ?? coordinator.latestPower?.value
    }

    private var currentPowerHistory: [Sample<PowerSample>] {
        overridePowerHistory ?? coordinator.powerHistory
    }

    private var currentThermalSample: ThermalSample? {
        overrideThermalSample ?? coordinator.latestThermal?.value
    }

    private var currentThermalHistory: [Sample<ThermalSample>] {
        overrideThermalHistory ?? coordinator.thermalHistory
    }

    private var currentFanSample: FanSample? {
        overrideFanSample ?? coordinator.latestFan?.value
    }

    private var currentFanHistory: [Sample<FanSample>] {
        overrideFanHistory ?? coordinator.fanHistory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("iStats")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("v0.1.0")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)

            Divider()

            // Metrics Scroll Area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // CPU Monitoring Section (Requirements 10.1, 10.2, 10.3)
                    if preferences.isCategoryEnabled(.cpu) {
                        CPUSummaryView(
                            sample: currentCPUSample,
                            history: currentCPUHistory
                        )
                    }

                    // Memory Monitoring Section (Requirements 10.1, 10.2, 10.3)
                    if preferences.isCategoryEnabled(.memory) {
                        MemorySummaryView(
                            sample: currentMemorySample,
                            history: currentMemoryHistory,
                            byteStandard: preferences.byteUnitStandard
                        )
                    }

                    // GPU Monitoring Section (Requirements 5.1, 5.2, 5.3, 10.1)
                    if preferences.isCategoryEnabled(.gpu) {
                        GPUSummaryView(
                            sample: currentGPUSample,
                            history: currentGPUHistory,
                            temperatureUnit: preferences.temperatureUnit,
                            byteStandard: preferences.byteUnitStandard
                        )
                    }

                    // Thermal Monitoring Section (Requirements 3.1-3.4, 10.1, 11.3)
                    if preferences.isCategoryEnabled(.thermal) {
                        ThermalSummaryView(
                            sample: currentThermalSample,
                            history: currentThermalHistory,
                            temperatureUnit: preferences.temperatureUnit
                        )
                    }

                    // Fans & Cooling Section (Requirements 4.1-4.4, 10.1)
                    if preferences.isCategoryEnabled(.fan) {
                        FanSummaryView(
                            sample: currentFanSample,
                            history: currentFanHistory
                        )
                    }

                    // Network Monitoring Section (Requirements 6.1-6.4, 10.1, 11.3)
                    if preferences.isCategoryEnabled(.network) {
                        NetworkSummaryView(
                            sample: currentNetworkSample,
                            history: currentNetworkHistory,
                            networkUnit: preferences.networkUnit,
                            byteStandard: preferences.byteUnitStandard
                        )
                    }

                    // Disk Monitoring Section (Requirements 7.1-7.3, 10.1, 11.3)
                    if preferences.isCategoryEnabled(.disk) {
                        DiskSummaryView(
                            sample: currentDiskSample,
                            history: currentDiskHistory,
                            byteStandard: preferences.byteUnitStandard
                        )
                    }

                    // Battery & Power Monitoring Section (Requirements 8.1-8.4, 10.1)
                    if preferences.isCategoryEnabled(.power) {
                        PowerSummaryView(
                            sample: currentPowerSample,
                            history: currentPowerHistory
                        )
                    }
                }
            }
            .frame(maxHeight: 520)

            Divider()

            // Footer / Actions
            HStack {
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 9))
                        Text("Activity Monitor")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

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
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning && overrideCPUSample == nil && overrideMemorySample == nil && overrideGPUSample == nil && overrideNetworkSample == nil && overrideDiskSample == nil && overridePowerSample == nil && overrideThermalSample == nil && overrideFanSample == nil {
                coordinator.start()
            }
        }
    }

    private var statusFooterText: String {
        if let thermal = currentThermalSample, let pressure = thermal.pressure, pressure.isElevated {
            return "Thermal Pressure: \(pressure.displayName)"
        } else if let memory = currentMemorySample {
            return "Pressure: \(memory.pressure.displayName)"
        } else if coordinator.isRunning {
            return "Sampling..."
        } else {
            return "Status: Ready"
        }
    }
}
