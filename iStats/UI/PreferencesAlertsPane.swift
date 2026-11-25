import SwiftUI
import AppKit
import iStatsCore

/// Per-metric alert thresholds, hosted by the Notifications Settings page until 9.10 replaces it.
/// (The master switch, permission banner, cooldown and test alert live in `NotificationsSettingsPage`.)
/// Features non-intrusive permission alerts, anti-spam debounce controls,
/// live telemetry context, and stable slider rows without layout jumping.
public struct PreferencesAlertsPane: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject private var notificationManager = NotificationManager.shared
    private let embedded: Bool

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared,
        embedded: Bool = false
    ) {
        self.store = store
        self.coordinator = coordinator
        self.embedded = embedded
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    public var body: some View {
        if embedded {
            thresholdRows
                .disabled(!store.notificationsEnabled)
                .opacity(store.notificationsEnabled ? 1.0 : 0.5)
        } else {
            ScrollView {
                HStack(spacing: 0) {
                    Spacer(minLength: 20)
                    VStack(alignment: .leading, spacing: 20) {
                        thresholdsCard
                    }
                    .frame(maxWidth: 640)
                    Spacer(minLength: 20)
                }
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Thresholds Card

    private var thresholdsCard: some View {
        SettingsCard(title: "Alert Thresholds") {
            thresholdRows
        }
        .disabled(!store.notificationsEnabled)
        .opacity(store.notificationsEnabled ? 1.0 : 0.5)
    }

    @ViewBuilder
    private var thresholdRows: some View {
        // CPU Alert
        cpuAlertSection

        Divider().padding(.horizontal, 14)

        // Memory Alert
        memoryAlertSection

        Divider().padding(.horizontal, 14)

        // Thermal Alert
        thermalAlertSection

        Divider().padding(.horizontal, 14)

        // Disk Alert
        diskAlertSection

        if hasBattery {
            Divider().padding(.horizontal, 14)

            // Battery Alert
            batteryAlertSection
        }
    }

    // MARK: - Metric Threshold Sections (Stable layout, no height jumping)

    private var cpuAlertSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                SettingsBadge(category: .cpu)

                HStack(spacing: 6) {
                    Text("CPU Usage")
                        .font(.system(size: 12.5, weight: .medium))

                    if let cpu = coordinator.latestCPU?.value {
                        Text("· \(Int(round(cpu.totalUsage)))% now")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.cpuAlertEnabled },
                    set: { newValue in
                        updateAlertToggle(newValue: newValue) { store.cpuAlertEnabled = $0 }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("CPU usage alert")
            }

            HStack(spacing: 12) {
                Slider(value: $store.cpuAlertThreshold, in: 50.0...100.0, step: 5.0)
                Text("\(Int(store.cpuAlertThreshold))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.leading, 38)
            .opacity(store.cpuAlertEnabled ? 1.0 : 0.35)
            .disabled(!store.cpuAlertEnabled)

            if !store.isCategoryEnabled(.cpu) {
                samplerWarning(for: .cpu)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var memoryAlertSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                SettingsBadge(category: .memory)

                HStack(spacing: 6) {
                    Text("Memory Pressure")
                        .font(.system(size: 12.5, weight: .medium))

                    if let mem = coordinator.latestMemory?.value, mem.total > 0 {
                        let usedPct = (Double(mem.used) / Double(mem.total)) * 100.0
                        Text("· \(Int(round(usedPct)))% now")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.memoryAlertEnabled },
                    set: { newValue in
                        updateAlertToggle(newValue: newValue) { store.memoryAlertEnabled = $0 }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Memory pressure alert")
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Notify on Critical Pressure only", isOn: $store.memoryAlertCriticalPressureOnly)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Notify on critical memory pressure only")

                if !store.memoryAlertCriticalPressureOnly {
                    HStack(spacing: 12) {
                        Slider(value: $store.memoryAlertThreshold, in: 50.0...100.0, step: 5.0)
                        Text("\(Int(store.memoryAlertThreshold))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(.leading, 38)
            .opacity(store.memoryAlertEnabled ? 1.0 : 0.35)
            .disabled(!store.memoryAlertEnabled)

            if !store.isCategoryEnabled(.memory) {
                samplerWarning(for: .memory)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var thermalAlertSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                SettingsBadge(category: .thermal)

                HStack(spacing: 6) {
                    Text("High Temperature")
                        .font(.system(size: 12.5, weight: .medium))

                    if let th = coordinator.latestThermal?.value,
                       let peak = th.sensors.map(\.celsius).max() {
                        Text("· \(Units.formatTemperature(peak, unit: store.temperatureUnit, fractionDigits: 0)) now")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.thermalAlertEnabled },
                    set: { newValue in
                        updateAlertToggle(newValue: newValue) { store.thermalAlertEnabled = $0 }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("High temperature alert")
            }

            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: {
                            TemperatureThresholdScale.displayValue(
                                celsius: store.thermalAlertThreshold, unit: store.temperatureUnit
                            )
                        },
                        set: { display in
                            store.thermalAlertThreshold = TemperatureThresholdScale.celsius(
                                fromDisplay: display, unit: store.temperatureUnit
                            )
                        }
                    ),
                    in: TemperatureThresholdScale.range(unit: store.temperatureUnit),
                    step: TemperatureThresholdScale.step(unit: store.temperatureUnit)
                )
                Text(Units.formatTemperature(store.thermalAlertThreshold, unit: store.temperatureUnit))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.leading, 38)
            .opacity(store.thermalAlertEnabled ? 1.0 : 0.35)
            .disabled(!store.thermalAlertEnabled)

            if !store.isCategoryEnabled(.thermal) {
                samplerWarning(for: .thermal)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var diskAlertSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                SettingsBadge(category: .disk)

                HStack(spacing: 6) {
                    Text("Low Disk Space")
                        .font(.system(size: 12.5, weight: .medium))

                    if let disk = coordinator.latestDisk?.value,
                       let vol = disk.volumes.first(where: { $0.mountPoint == "/" }) ?? disk.volumes.first,
                       vol.total > 0 {
                        let usedPct = (Double(vol.used) / Double(vol.total)) * 100.0
                        Text("· \(Int(round(usedPct)))% used now")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.diskAlertEnabled },
                    set: { newValue in
                        updateAlertToggle(newValue: newValue) { store.diskAlertEnabled = $0 }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Low disk space alert")
            }

            HStack(spacing: 12) {
                Slider(value: $store.diskAlertThreshold, in: 70.0...98.0, step: 2.0)
                Text("\(Int(store.diskAlertThreshold))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.leading, 38)
            .opacity(store.diskAlertEnabled ? 1.0 : 0.35)
            .disabled(!store.diskAlertEnabled)

            if !store.isCategoryEnabled(.disk) {
                samplerWarning(for: .disk)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var batteryAlertSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Low Battery Alert
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    SettingsBadge(category: .power, symbol: CategoryIdentity(.power).liveSymbol(LiveSymbolState(batteryChargePercent: 25)))

                    HStack(spacing: 6) {
                        Text("Low Battery Warning")
                            .font(.system(size: 12.5, weight: .medium))

                        if let pwr = coordinator.latestPower?.value, let charge = pwr.charge {
                            Text("· \(Int(round(charge)))% now")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { store.batteryLowAlertEnabled },
                        set: { newValue in
                            updateAlertToggle(newValue: newValue) { store.batteryLowAlertEnabled = $0 }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Low battery alert")
                }

                HStack(spacing: 12) {
                    Slider(value: Binding(
                        get: { Double(store.batteryLowThreshold) },
                        set: { store.batteryLowThreshold = Int($0) }
                    ), in: 5.0...50.0, step: 5.0)
                    Text("\(store.batteryLowThreshold)%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.leading, 38)
                .opacity(store.batteryLowAlertEnabled ? 1.0 : 0.35)
                .disabled(!store.batteryLowAlertEnabled)
            }

            Divider().padding(.leading, 38)

            // Fully Charged Alert
            HStack(spacing: 12) {
                SettingsBadge(category: .power, symbol: CategoryIdentity(.power).liveSymbol(LiveSymbolState(batteryChargePercent: 100, isCharging: true)))

                Text("Battery Fully Charged (100%)")
                    .font(.system(size: 12.5, weight: .medium))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.batteryFullAlertEnabled },
                    set: { newValue in
                        updateAlertToggle(newValue: newValue) { store.batteryFullAlertEnabled = $0 }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Battery fully charged alert")
            }

            if !store.isCategoryEnabled(.power) {
                samplerWarning(for: .power)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Sampler Off Warning

    @ViewBuilder
    private func samplerWarning(for category: MetricCategory) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .font(.system(size: 10))

            Text("\(category.displayName) background sampler is turned off.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)

            Spacer()

            Button("Enable Sampler") {
                store.setCategory(category, isEnabled: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Alert Toggle Handler

    private func updateAlertToggle(
        newValue: Bool,
        apply: (Bool) -> Void
    ) {
        apply(newValue)
        if newValue && notificationManager.authorizationStatus == .notDetermined {
            Task {
                await notificationManager.requestAuthorization()
            }
        }
    }
}
