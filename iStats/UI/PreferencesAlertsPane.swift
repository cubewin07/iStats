import SwiftUI
import AppKit
import iStatsCore

/// Modern, calibrated Notifications & Alerts preferences pane.
/// Features a compact permission bar, anti-spam debounce controls, live current telemetry
/// indicators next to sliders, and guardrails for desktop Macs and disabled samplers.
public struct PreferencesAlertsPane: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject private var notificationManager = NotificationManager.shared

    private let cooldownOptions: [(label: String, seconds: TimeInterval)] = [
        ("1 minute", 60.0),
        ("5 minutes", 300.0),
        ("15 minutes", 900.0),
        ("30 minutes", 1800.0),
        ("1 hour", 3600.0)
    ]

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.store = store
        self.coordinator = coordinator
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - 1. System Permission Status
                permissionStatusCard

                // MARK: - 2. Master Alerts & Timing Card
                masterAlertsCard

                // MARK: - 3. Metric Thresholds
                thresholdsCard
            }
            .padding(24)
            .frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Permission Status Card

    private var permissionStatusCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                if notificationManager.isAuthorized {
                    SettingsBadge(icon: "checkmark.circle.fill", color: .green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications Authorized")
                            .font(.system(size: 13, weight: .semibold))
                        Text("iStats has permission to post alert banners in macOS Notification Center.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Send Test Alert") {
                        Task {
                            await AlertCoordinator.shared.sendTestNotification()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if notificationManager.authorizationStatus == .denied {
                    SettingsBadge(icon: "exclamationmark.triangle.fill", color: .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications Disabled in System Settings")
                            .font(.system(size: 13, weight: .semibold))
                        Text("macOS has blocked notifications for iStats. Please allow them in System Settings.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    SettingsBadge(icon: "bell.badge", color: .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notification Permission Needed")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Authorization is required to display alert banners when thresholds are crossed.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Request Permission") {
                        Task {
                            await notificationManager.requestAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Master Alerts Card

    private var masterAlertsCard: some View {
        SettingsCard(
            title: "Notification Settings",
            subtitle: "Global delivery and anti-spam debouncing options."
        ) {
            // Master Switch
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "bell.fill", color: store.notificationsEnabled ? .blue : .secondary)
                },
                title: "Enable System Alert Notifications",
                subtitle: "Sends macOS banner alerts when hardware metrics exceed configured limits."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.notificationsEnabled && notificationManager.isAuthorized },
                    set: { newValue in
                        updatePermissionGuardedSetting(newValue: newValue) { granted in
                            store.notificationsEnabled = granted
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider().padding(.horizontal, 14)

            // Anti-Spam Cooldown
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "clock.arrow.circlepath", color: .purple)
                },
                title: "Alert Cooldown Period",
                subtitle: "Minimum wait interval before sending another alert for the same metric category."
            ) {
                Picker("", selection: $store.alertCooldownInterval) {
                    ForEach(cooldownOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .frame(width: 130)
                .disabled(!store.notificationsEnabled || !notificationManager.isAuthorized)
            }
        }
    }

    // MARK: - Metric Alert Thresholds Card

    private var thresholdsCard: some View {
        SettingsCard(
            title: "Metric Alert Thresholds",
            subtitle: "Calibrate alert triggers against live hardware metrics."
        ) {
            // CPU Alert
            cpuAlertRow

            Divider().padding(.horizontal, 14)

            // Memory Alert
            memoryAlertRow

            Divider().padding(.horizontal, 14)

            // Thermal Alert
            thermalAlertRow

            Divider().padding(.horizontal, 14)

            // Disk Alert
            diskAlertRow

            if hasBattery {
                Divider().padding(.horizontal, 14)

                // Battery Alert
                batteryAlertRow
            }
        }
        .disabled(!store.notificationsEnabled || !notificationManager.isAuthorized)
        .opacity((!store.notificationsEnabled || !notificationManager.isAuthorized) ? 0.55 : 1.0)
    }

    // MARK: - Threshold Rows

    private var cpuAlertRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "cpu", color: .blue)
                },
                title: "High CPU Usage Alert",
                subtitle: "Triggers when total CPU utilization exceeds threshold."
            ) {
                HStack(spacing: 8) {
                    currentCPUReadingBadge

                    Toggle("", isOn: Binding(
                        get: { store.cpuAlertEnabled },
                        set: { newValue in
                            updatePermissionGuardedSetting(newValue: newValue) { granted in
                                store.cpuAlertEnabled = granted
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            if store.cpuAlertEnabled {
                HStack(spacing: 12) {
                    Slider(value: $store.cpuAlertThreshold, in: 50.0...100.0, step: 5.0)
                    Text("\(Int(store.cpuAlertThreshold))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

                samplerWarning(for: .cpu)
            }
        }
    }

    private var memoryAlertRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "memorychip", color: .green)
                },
                title: "Memory Pressure Alert",
                subtitle: "Triggers on elevated system memory exhaustion or paging pressure."
            ) {
                HStack(spacing: 8) {
                    currentMemoryReadingBadge

                    Toggle("", isOn: Binding(
                        get: { store.memoryAlertEnabled },
                        set: { newValue in
                            updatePermissionGuardedSetting(newValue: newValue) { granted in
                                store.memoryAlertEnabled = granted
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            if store.memoryAlertEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Notify on Critical Pressure only (recommended)", isOn: $store.memoryAlertCriticalPressureOnly)
                        .font(.system(size: 11))
                        .padding(.horizontal, 18)

                    if !store.memoryAlertCriticalPressureOnly {
                        HStack(spacing: 12) {
                            Text("Threshold:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Slider(value: $store.memoryAlertThreshold, in: 50.0...100.0, step: 5.0)
                            Text("\(Int(store.memoryAlertThreshold))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .frame(width: 44, alignment: .trailing)
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .padding(.bottom, 6)

                samplerWarning(for: .memory)
            }
        }
    }

    private var thermalAlertRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "thermometer.high", color: .orange)
                },
                title: "High Temperature Alert",
                subtitle: "Triggers when peak hardware sensor exceeds temperature threshold."
            ) {
                HStack(spacing: 8) {
                    currentThermalReadingBadge

                    Toggle("", isOn: Binding(
                        get: { store.thermalAlertEnabled },
                        set: { newValue in
                            updatePermissionGuardedSetting(newValue: newValue) { granted in
                                store.thermalAlertEnabled = granted
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            if store.thermalAlertEnabled {
                HStack(spacing: 12) {
                    Slider(value: $store.thermalAlertThreshold, in: 60.0...105.0, step: 5.0)
                    Text(Units.formatTemperature(store.thermalAlertThreshold, unit: store.temperatureUnit))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 65, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

                samplerWarning(for: .thermal)
            }
        }
    }

    private var diskAlertRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "internaldrive", color: .indigo)
                },
                title: "Low Disk Space Alert",
                subtitle: "Triggers when primary startup disk exceeds storage threshold."
            ) {
                HStack(spacing: 8) {
                    currentDiskReadingBadge

                    Toggle("", isOn: Binding(
                        get: { store.diskAlertEnabled },
                        set: { newValue in
                            updatePermissionGuardedSetting(newValue: newValue) { granted in
                                store.diskAlertEnabled = granted
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            if store.diskAlertEnabled {
                HStack(spacing: 12) {
                    Slider(value: $store.diskAlertThreshold, in: 70.0...98.0, step: 2.0)
                    Text("\(Int(store.diskAlertThreshold))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

                samplerWarning(for: .disk)
            }
        }
    }

    private var batteryAlertRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "battery.25", color: .mint)
                },
                title: "Low Battery Alert",
                subtitle: "Triggers when discharging and battery falls below percentage."
            ) {
                HStack(spacing: 8) {
                    currentBatteryReadingBadge

                    Toggle("", isOn: Binding(
                        get: { store.batteryLowAlertEnabled },
                        set: { newValue in
                            updatePermissionGuardedSetting(newValue: newValue) { granted in
                                store.batteryLowAlertEnabled = granted
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            if store.batteryLowAlertEnabled {
                HStack(spacing: 12) {
                    Slider(value: Binding(
                        get: { Double(store.batteryLowThreshold) },
                        set: { store.batteryLowThreshold = Int($0) }
                    ), in: 5.0...50.0, step: 5.0)
                    Text("\(store.batteryLowThreshold)%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
            }

            // Full Battery Alert Row
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "battery.100.bolt", color: .green)
                },
                title: "Battery Fully Charged Alert (100%)",
                subtitle: "Sends a notification when battery reaches 100% capacity."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.batteryFullAlertEnabled },
                    set: { newValue in
                        updatePermissionGuardedSetting(newValue: newValue) { granted in
                            store.batteryFullAlertEnabled = granted
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if store.batteryLowAlertEnabled || store.batteryFullAlertEnabled {
                samplerWarning(for: .power)
            }
        }
    }

    // MARK: - Live Calibration Badges

    @ViewBuilder
    private var currentCPUReadingBadge: some View {
        if let cpu = coordinator.latestCPU?.value {
            Text("Now: \(Int(round(cpu.totalUsage)))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var currentMemoryReadingBadge: some View {
        if let mem = coordinator.latestMemory?.value, mem.total > 0 {
            let usedPct = (Double(mem.used) / Double(mem.total)) * 100.0
            Text("Now: \(Int(round(usedPct)))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var currentThermalReadingBadge: some View {
        if let th = coordinator.latestThermal?.value,
           let peak = th.sensors.map(\.celsius).max() {
            Text("Now: \(Units.formatTemperature(peak, unit: store.temperatureUnit, fractionDigits: 0))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var currentDiskReadingBadge: some View {
        if let disk = coordinator.latestDisk?.value,
           let vol = disk.volumes.first(where: { $0.mountPoint == "/" }) ?? disk.volumes.first,
           vol.total > 0 {
            let usedPct = (Double(vol.used) / Double(vol.total)) * 100.0
            Text("Now: \(Int(round(usedPct)))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var currentBatteryReadingBadge: some View {
        if let pwr = coordinator.latestPower?.value, let charge = pwr.charge {
            Text("Now: \(Int(round(charge)))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    // MARK: - Sampler Off Warning

    @ViewBuilder
    private func samplerWarning(for category: MetricCategory) -> some View {
        if !store.isCategoryEnabled(category) {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Permission Guard Handler

    private func updatePermissionGuardedSetting(
        newValue: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        if newValue {
            if notificationManager.isAuthorized {
                completion(true)
                store.notificationsEnabled = true
            } else {
                Task {
                    let granted = await notificationManager.requestAuthorization()
                    if granted {
                        completion(true)
                        store.notificationsEnabled = true
                    } else {
                        completion(false)
                        store.notificationsEnabled = false
                    }
                }
            }
        } else {
            completion(false)
        }
    }
}

