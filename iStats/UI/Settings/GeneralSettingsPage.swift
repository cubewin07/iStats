import SwiftUI
import AppKit
import iStatsCore

/// General: startup behavior, sampling cadence and energy, display units, reset.
struct GeneralSettingsPage: View {
    @ObservedObject var store: PreferencesStore
    @ObservedObject var coordinator: MetricsCoordinator
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    @State private var isShowingResetConfirmation = false

    private static let presetIntervals: [TimeInterval] = [0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]

    /// Presets plus the stored value, so a value set elsewhere is never silently replaced.
    private var intervalOptions: [TimeInterval] {
        var options = Self.presetIntervals
        if !options.contains(store.refreshInterval) {
            options.append(store.refreshInterval)
        }
        return options.sorted()
    }

    private func intervalLabel(_ interval: TimeInterval) -> String {
        interval < 1.0 ? String(format: "%.1f seconds", interval) : "\(Int(interval)) seconds"
    }

    var body: some View {
        Form {
            SwiftUI.Section("Startup") {
                Toggle("Open at login", isOn: $store.launchAtLogin)
                    .accessibilityLabel("Open iStats at login")
                    .onChange(of: store.launchAtLogin) { newValue in
                        LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
                    }

                if launchManager.status == .requiresApproval {
                    LabeledContent("macOS needs your approval") {
                        Button("Approve in System Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                Toggle("Show icon in the Dock", isOn: $store.showDockIcon)
                    .accessibilityLabel("Show iStats icon in the Dock")
                    .onChange(of: store.showDockIcon) { newValue in
                        DockIconManager.shared.setDockIconVisible(newValue)
                    }
            }

            SwiftUI.Section {
                Toggle("Pause sampling", isOn: $store.isSamplingPaused)
                    .accessibilityLabel("Pause sampling")

                Toggle("Pause automatically in Low Power Mode", isOn: $store.autoPauseOnLowPowerMode)
                    .accessibilityLabel("Pause sampling automatically in Low Power Mode")

                Picker("Refresh interval", selection: $store.refreshInterval) {
                    ForEach(intervalOptions, id: \.self) { interval in
                        Text(intervalLabel(interval)).tag(interval)
                    }
                }
                .disabled(store.isSamplingPaused)
            } header: {
                Text("Sampling")
            } footer: {
                Text(samplingFooter)
            }

            SwiftUI.Section("Units") {
                Picker("Temperature", selection: $store.temperatureUnit) {
                    Text("°C").tag(Units.TemperatureUnit.celsius)
                    Text("°F").tag(Units.TemperatureUnit.fahrenheit)
                }
                .pickerStyle(.segmented)

                Picker("Network rate", selection: $store.networkUnit) {
                    Text("MB/s").tag(Units.NetworkUnit.bytesPerSecond)
                    Text("Mbps").tag(Units.NetworkUnit.bitsPerSecond)
                }
                .pickerStyle(.segmented)

                Picker("Storage sizes", selection: $store.byteUnitStandard) {
                    Text("Binary (1024)").tag(Units.ByteUnitStandard.iec)
                    Text("Decimal (1000)").tag(Units.ByteUnitStandard.si)
                }
                .pickerStyle(.segmented)
            }

            SwiftUI.Section {
                Button("Reset All Settings…", role: .destructive) {
                    isShowingResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset all settings to their defaults?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the default refresh interval and units, resets the menu bar items, and turns alerts off.")
        }
    }

    private var samplingFooter: String {
        if store.isSamplingPaused {
            return "Sampling is paused. The menu bar shows a minimal icon until you resume."
        }
        if coordinator.isLowPowerModeActive && store.autoPauseOnLowPowerMode {
            return "Low Power Mode is on, so sampling is paused until it turns off."
        }
        let span = Units.formatHistoryDuration(sampleCount: 60, interval: store.refreshInterval)
        return "Charts keep 60 samples, which covers \(span) at this interval."
    }

    private func resetAll() {
        store.resetToDefaults()
        DockIconManager.shared.setDockIconVisible(store.showDockIcon)
        LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: store.launchAtLogin)
    }
}
