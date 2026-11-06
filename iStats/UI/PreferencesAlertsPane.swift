import SwiftUI
import AppKit
import iStatsCore

/// Modern, calibrated Notifications & Alerts preferences pane.
/// Features non-intrusive permission alerts, anti-spam debounce controls,
/// live telemetry context, and stable slider rows without layout jumping.
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
            HStack(spacing: 0) {
                Spacer(minLength: 20)
                VStack(alignment: .leading, spacing: 20) {
                    if !notificationManager.isAuthorized {
                        permissionBanner
                    }

                    masterAlertsCard
                    thresholdsCard
                }
                .frame(maxWidth: 640)
                Spacer(minLength: 20)
            }
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Permission Banner (Only shown if unauthorized)

    @ViewBuilder
    private var permissionBanner: some View {
        SettingsCard {
            HStack(spacing: 12) {
                if notificationManager.authorizationStatus == .denied {
                    SettingsBadge(icon: "exclamationmark.triangle.fill", color: .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications Disabled in System Settings")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("macOS has blocked notifications for iStats. Please enable them in System Settings.")
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
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Permission is required to display alert banners when thresholds are crossed.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Allow Notifications") {
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
        SettingsCard(title: "System Notifications") {
            // Master Switch
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "bell.fill", color: store.notificationsEnabled ? .blue : .secondary)
                },
                title: "Hardware Alerts",
                subtitle: "Post notification banners when thresholds are exceeded"
            ) {
                HStack(spacing: 10) {
                    if notificationManager.isAuthorized {
                        Button("Send Test Alert") {
                            Task {
                                await AlertCoordinator.shared.sendTestNotification()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

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
            }

            Divider().padding(.horizontal, 14)

            // Alert Cooldown
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "clock.arrow.circlepath", color: .purple)
                },
                title: "Alert Cooldown",
                subtitle: "Minimum wait before repeating an alert for the same category"
            ) {
                Picker("", selection: $store.alertCooldownInterval) {
                    ForEach(cooldownOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .frame(width: 120)
                .disabled(!store.notificationsEnabled || !notificationManager.isAuthorized)
            }
        }
    }

    // MARK: - Thresholds Card

    private var thresholdsCard: some View {
        SettingsCard(title: "Alert Thresholds") {
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
        .disabled(!store.notificationsEnabled || !notificationManager.isAuthorized)
        .opacity((!store.notificationsEnabled || !notificationManager.isAuthorized) ? 0.5 : 1.0)
    }

    // MARK: - Metric Threshold Sections (Stable layout, no height jumping)

    private var cpuAlertSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                SettingsBadge(icon: "cpu", color: .blue)

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
                        updatePermissionGuardedSetting(newValue: newValue) { granted in
                            store.cpuAlertEnabled = granted
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
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
                SettingsBadge(icon: "memorychip", color: .green)

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
                        updatePermissionGuardedSetting(newValue: newValue) { granted in
                            store.memoryAlertEnabled = granted
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Notify on Critical Pressure only", isOn: $store.memoryAlertCriticalPressureOnly)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

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
                SettingsBadge(icon: "thermometer.high", color: .orange)

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
                        updatePermissionGuardedSetting(newValue: newValue) { granted in
                            store.thermalAlertEnabled = granted
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            HStack(spacing: 12) {
                Slider(value: $store.thermalAlertThreshold, in: 60.0...105.0, step: 5.0)
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
                SettingsBadge(icon: "internaldrive", color: .indigo)

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
                        updatePermissionGuardedSetting(newValue: newValue) { granted in
                            store.diskAlertEnabled = granted
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
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
                    SettingsBadge(icon: "battery.25", color: .mint)

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
                            updatePermissionGuardedSetting(newValue: newValue) { granted in
                                store.batteryLowAlertEnabled = granted
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
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
                SettingsBadge(icon: "battery.100.bolt", color: .green)

                Text("Battery Fully Charged (100%)")
                    .font(.system(size: 12.5, weight: .medium))

                Spacer()

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
