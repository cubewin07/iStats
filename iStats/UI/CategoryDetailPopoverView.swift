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
            // Header Bar
            HStack(spacing: 10) {
                // Category Icon Badge with subtle tint glow
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(categoryAccentColor(for: category).opacity(0.16))
                        .frame(width: 26, height: 26)

                    Image(systemName: iconName(for: category))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(categoryAccentColor(for: category))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(categoryHeaderTitle(for: category))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)

                    Text(categorySubtitle(for: category))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Live status pulsing badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)

                    Text(statusBadgeText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(statusDotColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(statusDotColor.opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(.bottom, 2)

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

    private var statusBadgeText: String {
        if let avail = coordinator.categoryAvailability[category], !avail.isAvailable {
            return "Unavailable"
        }

        switch category {
        case .thermal:
            if let thermal = coordinator.latestThermal?.value, let pressure = thermal.pressure, pressure.isElevated {
                return pressure.displayName
            }
        case .memory:
            if let memory = coordinator.latestMemory?.value, memory.pressure.isElevated {
                return memory.pressure.displayName
            }
        case .power:
            if let power = coordinator.latestPower?.value, let state = power.state {
                return state == .charging ? "Charging" : (power.hasBattery ? "Battery" : "AC")
            }
        default:
            break
        }

        if !coordinator.isRunning {
            return "Ready"
        }
        return coordinator.categoryAvailability[category] != nil ? "Live" : "Sampling..."
    }

    private var statusDotColor: Color {
        if let avail = coordinator.categoryAvailability[category], !avail.isAvailable {
            return .secondary
        }

        switch category {
        case .thermal:
            if let thermal = coordinator.latestThermal?.value, let pressure = thermal.pressure {
                switch pressure {
                case .nominal: return .green
                case .fair: return .yellow
                case .serious: return .orange
                case .critical: return .red
                }
            }
        case .memory:
            if let memory = coordinator.latestMemory?.value {
                switch memory.pressure {
                case .normal: return .green
                case .warning: return .orange
                case .critical: return .red
                }
            }
        case .power:
            if let power = coordinator.latestPower?.value, let charge = power.charge {
                if charge <= 15 { return .red }
                if charge <= 30 { return .orange }
                return .green
            }
        default:
            break
        }

        if !coordinator.isRunning {
            return .secondary
        }
        return coordinator.categoryAvailability[category] != nil ? .green : .blue
    }

    private func categoryHeaderTitle(for category: MetricCategory) -> String {
        switch category {
        case .cpu: return "CPU & Processor"
        case .memory: return "Memory & Swap"
        case .gpu: return "GPU & Graphics"
        case .thermal: return "Thermals & Sensors"
        case .fan: return "Fans & Cooling"
        case .network: return "Network & Traffic"
        case .disk: return "Disks & Storage"
        case .power: return "Battery & Power"
        }
    }

    private func categorySubtitle(for category: MetricCategory) -> String {
        switch category {
        case .cpu:
            if let load = coordinator.latestCPU?.value.loadAverage {
                return String(format: "Load: %.2f, %.2f, %.2f", load.oneMinute, load.fiveMinute, load.fifteenMinute)
            }
            return "System Load & Performance"
        case .memory:
            if let mem = coordinator.latestMemory?.value {
                return "\(Units.formatBytes(mem.used, standard: preferences.byteUnitStandard)) used of \(Units.formatBytes(mem.total, standard: preferences.byteUnitStandard))"
            }
            return "RAM Allocation & Pressure"
        case .gpu:
            return "Renderer & Compute Activity"
        case .thermal:
            return "Internal Hardware Temperature"
        case .fan:
            if let fan = coordinator.latestFan?.value {
                return fan.fans.isEmpty ? "Passive Cooling (Fanless)" : "\(fan.fans.count) Active \(fan.fans.count == 1 ? "Fan" : "Fans")"
            }
            return "Cooling Subsystem"
        case .network:
            if let net = coordinator.latestNetwork?.value {
                return "\(net.interfaces.count) Interfaces Monitored"
            }
            return "Bandwidth & Active Interfaces"
        case .disk:
            if let disk = coordinator.latestDisk?.value {
                return "\(disk.volumes.count) Volumes Mounted"
            }
            return "I/O Activity & Storage"
        case .power:
            if let power = coordinator.latestPower?.value {
                if power.hasBattery {
                    let pct = power.charge != nil ? String(format: "%.0f%%", power.charge!) : "Battery"
                    return "\(pct) • \(power.adapterWatts != nil ? "\(Int(power.adapterWatts!))W Connected" : "On Battery")"
                }
                return "AC Powered Desktop Mac"
            }
            return "Power & Energy Telemetry"
        }
    }

    private func categoryAccentColor(for category: MetricCategory) -> Color {
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

