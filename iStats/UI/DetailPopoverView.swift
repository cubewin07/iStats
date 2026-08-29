import SwiftUI
import iStatsCore

/// The All-In-One system monitor popover redesigned as an 8-Row Instrument Cluster.
/// Displays glanceable thumbnails, human status verdicts, and precise primary metrics per row,
/// with smooth in-place progressive disclosure expansion on click.
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

    // Expanded category rows in the instrument cluster
    @State private var expandedCategory: MetricCategory? = nil

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

    private var currentCPUSample: CPUSample? { overrideCPUSample ?? coordinator.latestCPU?.value }
    private var currentMemorySample: MemorySample? { overrideMemorySample ?? coordinator.latestMemory?.value }
    private var currentGPUSample: GPUSample? { overrideGPUSample ?? coordinator.latestGPU?.value }
    private var currentNetworkSample: NetworkSample? { overrideNetworkSample ?? coordinator.latestNetwork?.value }
    private var currentDiskSample: DiskSample? { overrideDiskSample ?? coordinator.latestDisk?.value }
    private var currentPowerSample: PowerSample? { overridePowerSample ?? coordinator.latestPower?.value }
    private var currentThermalSample: ThermalSample? { overrideThermalSample ?? coordinator.latestThermal?.value }
    private var currentFanSample: FanSample? { overrideFanSample ?? coordinator.latestFan?.value }

    private var currentCPUHistory: [Sample<CPUSample>] { overrideCPUHistory ?? coordinator.cpuHistory }
    private var currentMemoryHistory: [Sample<MemorySample>] { overrideMemoryHistory ?? coordinator.memoryHistory }
    private var currentGPUHistory: [Sample<GPUSample>] { overrideGPUHistory ?? coordinator.gpuHistory }
    private var currentNetworkHistory: [Sample<NetworkSample>] { overrideNetworkHistory ?? coordinator.networkHistory }
    private var currentDiskHistory: [Sample<DiskSample>] { overrideDiskHistory ?? coordinator.diskHistory }
    private var currentPowerHistory: [Sample<PowerSample>] { overridePowerHistory ?? coordinator.powerHistory }
    private var currentThermalHistory: [Sample<ThermalSample>] { overrideThermalHistory ?? coordinator.thermalHistory }
    private var currentFanHistory: [Sample<FanSample>] { overrideFanHistory ?? coordinator.fanHistory }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("iStats")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("Instrument Cluster")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)

            Divider()

            // 8-Row Instrument Cluster
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    if preferences.isCategoryEnabled(.cpu) {
                        instrumentRow(
                            category: .cpu,
                            title: "CPU",
                            verdict: VerdictEvaluator.evaluateCPU(currentCPUSample)
                        ) {
                            CPUSummaryView(sample: currentCPUSample, history: currentCPUHistory)
                        }
                    }

                    if preferences.isCategoryEnabled(.memory) {
                        instrumentRow(
                            category: .memory,
                            title: "Memory",
                            verdict: VerdictEvaluator.evaluateMemory(currentMemorySample, standard: preferences.byteUnitStandard)
                        ) {
                            MemorySummaryView(sample: currentMemorySample, history: currentMemoryHistory, byteStandard: preferences.byteUnitStandard)
                        }
                    }

                    if preferences.isCategoryEnabled(.gpu) {
                        instrumentRow(
                            category: .gpu,
                            title: "GPU",
                            verdict: VerdictEvaluator.evaluateGPU(currentGPUSample)
                        ) {
                            GPUSummaryView(sample: currentGPUSample, history: currentGPUHistory, temperatureUnit: preferences.temperatureUnit, byteStandard: preferences.byteUnitStandard)
                        }
                    }

                    if preferences.isCategoryEnabled(.thermal) {
                        instrumentRow(
                            category: .thermal,
                            title: "Heat",
                            verdict: VerdictEvaluator.evaluateThermal(currentThermalSample, unit: preferences.temperatureUnit)
                        ) {
                            ThermalSummaryView(sample: currentThermalSample, history: currentThermalHistory, temperatureUnit: preferences.temperatureUnit)
                        }
                    }

                    if preferences.isCategoryEnabled(.fan) {
                        instrumentRow(
                            category: .fan,
                            title: "Fans",
                            verdict: VerdictEvaluator.evaluateFan(currentFanSample)
                        ) {
                            FanSummaryView(sample: currentFanSample, history: currentFanHistory)
                        }
                    }

                    if preferences.isCategoryEnabled(.network) {
                        instrumentRow(
                            category: .network,
                            title: "Net",
                            verdict: VerdictEvaluator.evaluateNetwork(currentNetworkSample, unit: preferences.networkUnit, standard: preferences.byteUnitStandard)
                        ) {
                            NetworkSummaryView(sample: currentNetworkSample, history: currentNetworkHistory, networkUnit: preferences.networkUnit, byteStandard: preferences.byteUnitStandard)
                        }
                    }

                    if preferences.isCategoryEnabled(.disk) {
                        instrumentRow(
                            category: .disk,
                            title: "Disk",
                            verdict: VerdictEvaluator.evaluateDisk(currentDiskSample, standard: preferences.byteUnitStandard)
                        ) {
                            DiskSummaryView(sample: currentDiskSample, history: currentDiskHistory, byteStandard: preferences.byteUnitStandard)
                        }
                    }

                    if preferences.isCategoryEnabled(.power) {
                        instrumentRow(
                            category: .power,
                            title: "Power",
                            verdict: VerdictEvaluator.evaluatePower(currentPowerSample)
                        ) {
                            PowerSummaryView(sample: currentPowerSample, history: currentPowerHistory)
                        }
                    }
                }
            }
            .frame(maxHeight: 520)

            Divider()

            // Footer / Actions
            HStack(spacing: 6) {
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }) {
                    Label("Activity Monitor", systemImage: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

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

    // MARK: - Instrument Cluster Row

    private func instrumentRow<DetailContent: View>(
        category: MetricCategory,
        title: String,
        verdict: MetricVerdict,
        @ViewBuilder detailContent: @escaping () -> DetailContent
    ) -> some View {
        let isExpanded = expandedCategory == category

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if expandedCategory == category {
                        expandedCategory = nil
                    } else {
                        expandedCategory = category
                    }
                }
            }) {
                HStack(spacing: 8) {
                    // Category Thumbnail Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(categoryColor(for: category).opacity(0.15))
                            .frame(width: 22, height: 22)

                        Image(systemName: iconName(for: category))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(categoryColor(for: category))
                    }

                    // Category Name
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 48, alignment: .leading)

                    // Status Verdict Badge (Green, Yellow, Orange, Red)
                    HStack(spacing: 3) {
                        Circle()
                            .fill(verdict.level.color)
                            .frame(width: 5, height: 5)

                        Text(verdict.badgeText)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(verdict.level.color)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(verdict.level.color.opacity(0.1))
                    .clipShape(Capsule())

                    Spacer()

                    // Primary Metric Value
                    Text(verdict.primaryValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)

                    // Expansion Chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isExpanded ? Color.secondary.opacity(0.1) : Color.secondary.opacity(0.04))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // In-place Expanded Detail View
            if isExpanded {
                detailContent()
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func categoryColor(for category: MetricCategory) -> Color {
        switch category {
        case .cpu: return .blue
        case .memory: return .green
        case .gpu: return .purple
        case .thermal: return .orange
        case .fan: return .cyan
        case .network: return .teal
        case .disk: return .indigo
        case .power: return .green
        }
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
