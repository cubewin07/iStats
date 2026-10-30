import SwiftUI
import AppKit
import iStatsCore

/// Modern, streamlined General preferences pane.
/// Provides responsive, clean controls for sampling rates, energy management,
/// unit formatting, and system launch behaviors without text clutter.
public struct PreferencesGeneralPane: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    private let samplingIntervals: [TimeInterval] = [0.5, 1.0, 2.0, 5.0, 10.0]

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.store = store
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 20)
                VStack(alignment: .leading, spacing: 20) {
                    performanceCard
                    unitsCard
                    appBehaviorCard
                }
                .frame(maxWidth: 640)
                Spacer(minLength: 20)
            }
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Performance & Energy Card

    private var performanceCard: some View {
        SettingsCard(title: "Performance & Energy") {
            // Pause Sampling
            SettingsRow(
                leading: {
                    SettingsBadge(
                        icon: store.isSamplingPaused ? "pause.circle.fill" : "leaf.circle.fill",
                        color: store.isSamplingPaused ? .orange : .green
                    )
                },
                title: "Pause Sampling",
                subtitle: store.isSamplingPaused
                    ? "Sampling is paused · Minimal menu bar icon shown"
                    : "Temporarily stop hardware monitors to save battery"
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

            // Auto-Pause in Low Power Mode
            SettingsRow(
                leading: {
                    SettingsBadge(
                        icon: "battery.50",
                        color: coordinator.isLowPowerModeActive ? .orange : .secondary
                    )
                },
                title: "Auto-Pause in Low Power Mode",
                subtitle: "Pause monitors whenever macOS Low Power Mode is active"
            ) {
                HStack(spacing: 8) {
                    if coordinator.isLowPowerModeActive {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Toggle("", isOn: $store.autoPauseOnLowPowerMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            Divider().padding(.horizontal, 14)

            // Sampling Rate
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "speedometer", color: .blue)
                },
                title: "Sampling Rate",
                subtitle: "60 samples = \(Units.formatHistoryDuration(sampleCount: 60, interval: store.refreshInterval)) history"
            ) {
                Picker("", selection: Binding(
                    get: {
                        samplingIntervals.min(by: { abs($0 - store.refreshInterval) < abs($1 - store.refreshInterval) }) ?? 2.0
                    },
                    set: { store.refreshInterval = $0 }
                )) {
                    ForEach(samplingIntervals, id: \.self) { interval in
                        Text(interval < 1.0 ? String(format: "%.1fs", interval) : "\(Int(interval))s")
                            .tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(store.isSamplingPaused)
            }
        }
    }

    // MARK: - Display Units Card

    private var unitsCard: some View {
        SettingsCard(title: "Display Units") {
            // Temperature Unit
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "thermometer.medium", color: .orange)
                },
                title: "Temperature"
            ) {
                Picker("", selection: $store.temperatureUnit) {
                    Text("°C").tag(Units.TemperatureUnit.celsius)
                    Text("°F").tag(Units.TemperatureUnit.fahrenheit)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Divider().padding(.horizontal, 14)

            // Network Unit
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "network", color: .teal)
                },
                title: "Network Rate"
            ) {
                Picker("", selection: $store.networkUnit) {
                    Text("MB/s").tag(Units.NetworkUnit.bytesPerSecond)
                    Text("Mbps").tag(Units.NetworkUnit.bitsPerSecond)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Divider().padding(.horizontal, 14)

            // Data Size Standard
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "internaldrive", color: .indigo)
                },
                title: "Data Storage Standard",
                subtitle: "Base 2 (1024 B) or Base 10 (1000 B)"
            ) {
                Picker("", selection: $store.byteUnitStandard) {
                    Text("IEC (1024)").tag(Units.ByteUnitStandard.iec)
                    Text("SI (1000)").tag(Units.ByteUnitStandard.si)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
    }

    // MARK: - App Behavior Card

    private var appBehaviorCard: some View {
        SettingsCard(title: "Application") {
            // Launch at Login
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "arrow.up.forward.app", color: .blue)
                },
                title: "Start at Login",
                subtitle: "Launch iStats in the background on startup"
            ) {
                HStack(spacing: 8) {
                    if launchManager.status == .requiresApproval {
                        Button("Approve in Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
                title: "Show in Dock",
                subtitle: "Keep icon visible in Dock while running"
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
