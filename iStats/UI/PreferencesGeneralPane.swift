import SwiftUI
import AppKit
import iStatsCore

/// Modern, organized General & Units preferences pane.
/// Consolidates sampling intervals, battery saving controls, unit formatting,
/// and startup/Dock behaviors into clean, scannable settings cards.
public struct PreferencesGeneralPane: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    private let presetIntervals: [(label: String, seconds: TimeInterval, note: String)] = [
        ("0.5s", 0.5, "Realtime · High energy"),
        ("1s", 1.0, "Responsive"),
        ("2s", 2.0, "Balanced · Recommended"),
        ("5s", 5.0, "Energy Saver"),
        ("10s", 10.0, "Low Power"),
        ("30s", 30.0, "Extended"),
        ("60s", 60.0, "Minimal")
    ]

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.store = store
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - 1. Performance & Energy Card
                performanceCard

                // MARK: - 2. Display Units Card
                unitsCard

                // MARK: - 3. App Behavior Card
                appBehaviorCard
            }
            .padding(24)
            .frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Performance & Energy Card

    private var performanceCard: some View {
        SettingsCard(
            title: "Performance & Energy",
            subtitle: "Optimize background hardware sampling overhead and battery consumption."
        ) {
            // Battery Saver / Pause Sampling
            SettingsRow(
                leading: {
                    SettingsBadge(
                        icon: store.isSamplingPaused ? "pause.circle.fill" : "leaf.circle.fill",
                        color: store.isSamplingPaused ? .orange : .green
                    )
                },
                title: "Pause Sampling (Save Battery)",
                subtitle: store.isSamplingPaused
                    ? "Sampling is stopped. A minimal icon is shown in the menu bar."
                    : "Stop all background hardware samplers and collapse the menu bar to a minimal icon."
            ) {
                HStack(spacing: 8) {
                    if store.isSamplingPaused {
                        Text("PAUSED")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Toggle("", isOn: $store.isSamplingPaused)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            Divider().padding(.horizontal, 14)

            // Auto-Pause in macOS Low Power Mode
            SettingsRow(
                leading: {
                    SettingsBadge(
                        icon: "battery.50",
                        color: coordinator.isLowPowerModeActive ? .orange : .secondary
                    )
                },
                title: "Auto-Pause in Low Power Mode",
                subtitle: "Automatically pauses sampling whenever macOS enters Low Power Mode."
            ) {
                HStack(spacing: 8) {
                    if coordinator.isLowPowerModeActive {
                        Text("LOW POWER ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Toggle("", isOn: $store.autoPauseOnLowPowerMode)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }

            Divider().padding(.horizontal, 14)

            // Discrete Refresh Interval Bar
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sampling Refresh Rate")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(currentIntervalProfileNote)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(store.isSamplingPaused ? "Paused" : String(format: "%.1f s", store.refreshInterval))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(store.isSamplingPaused ? .orange : .accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // 7-Stop Interval Segmented Controls
                HStack(spacing: 4) {
                    ForEach(presetIntervals, id: \.seconds) { preset in
                        let isSelected = abs(store.refreshInterval - preset.seconds) < 0.01
                        Button(action: {
                            store.refreshInterval = preset.seconds
                        }) {
                            Text(preset.label)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
                                .foregroundColor(isSelected ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Live History Readout
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("History graphs display the last \(Units.formatHistoryDuration(sampleCount: 60, interval: store.refreshInterval)) of telemetry (60 samples).")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .disabled(store.isSamplingPaused)
            .opacity(store.isSamplingPaused ? 0.5 : 1.0)
        }
    }

    private var currentIntervalProfileNote: String {
        for preset in presetIntervals where abs(store.refreshInterval - preset.seconds) < 0.01 {
            return preset.note
        }
        return "Custom interval"
    }

    // MARK: - Display Units Card

    private var unitsCard: some View {
        SettingsCard(
            title: "Display & Units",
            subtitle: "Global formatting preferences across all menu bar items and popovers."
        ) {
            // Temperature Unit
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "thermometer.medium", color: .orange)
                },
                title: "Temperature Unit",
                subtitle: "Applies to CPU, GPU, memory, SSD, and battery temperature readings."
            ) {
                HStack(spacing: 10) {
                    Picker("", selection: $store.temperatureUnit) {
                        ForEach(Units.TemperatureUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Text(Units.formatTemperature(48.5, unit: store.temperatureUnit))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 55, alignment: .trailing)
                }
            }

            Divider().padding(.horizontal, 14)

            // Network Unit
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "network", color: .teal)
                },
                title: "Network Rate Unit",
                subtitle: "Choose between byte throughput (B/s, MB/s) and bit rate (bps, Mbps)."
            ) {
                HStack(spacing: 10) {
                    Picker("", selection: $store.networkUnit) {
                        ForEach(Units.NetworkUnit.allCases) { unit in
                            Text(unit == .bytesPerSecond ? "Bytes/s" : "Bits/s").tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Text(Units.formatNetworkRate(1024 * 1024 * 12.5, unit: store.networkUnit, standard: store.byteUnitStandard, fractionDigits: 1))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 75, alignment: .trailing)
                }
            }

            Divider().padding(.horizontal, 14)

            // Data Size Standard
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "internaldrive", color: .indigo)
                },
                title: "Data Size Standard",
                subtitle: "Standard base for disk capacities and RAM totals."
            ) {
                HStack(spacing: 10) {
                    Picker("", selection: $store.byteUnitStandard) {
                        ForEach(Units.ByteUnitStandard.allCases) { standard in
                            Text(standard == .iec ? "IEC (1024 B)" : "SI (1000 B)").tag(standard)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Text(Units.formatBytes(16 * 1024 * 1024 * 1024, standard: store.byteUnitStandard, fractionDigits: 0))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 75, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - App Behavior Card

    private var appBehaviorCard: some View {
        SettingsCard(
            title: "App & System Integration",
            subtitle: "Configure macOS launch items and Dock presence."
        ) {
            // Launch at Login
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "arrow.up.forward.app", color: .blue)
                },
                title: "Launch at Login",
                subtitle: "Automatically start iStats in the background when logging into macOS."
            ) {
                HStack(spacing: 8) {
                    if launchManager.status == .requiresApproval {
                        Button("Approve in Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Toggle("", isOn: $store.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: store.launchAtLogin) { newValue in
                            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
                        }
                }
            }

            Divider().padding(.horizontal, 14)

            // Show Dock Icon
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "dock.rectangle", color: .purple)
                },
                title: "Show Dock Icon",
                subtitle: "When disabled, iStats runs as a lightweight menu bar accessory without a Dock icon."
            ) {
                Toggle("", isOn: $store.showDockIcon)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: store.showDockIcon) { newValue in
                        DockIconManager.shared.setDockIconVisible(newValue)
                    }
            }
        }
    }
}

