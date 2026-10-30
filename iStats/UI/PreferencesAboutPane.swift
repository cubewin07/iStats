import SwiftUI
import AppKit
import iStatsCore

/// Modern, informative About pane for iStats.
/// Highlights system architecture guarantees, version info, and quick system shortcuts.
public struct PreferencesAboutPane: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.store = store
        self.coordinator = coordinator
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }

    private var architectureName: String {
        #if arch(arm64)
        return "Apple Silicon (Native arm64e)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "macOS Universal"
        #endif
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Branding Card
                SettingsCard {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 58, height: 58)
                                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)

                            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("iStats")
                                    .font(.system(size: 18, weight: .bold))

                                Text(architectureName)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Capsule())
                            }

                            Text(appVersion)
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)

                            Text("Native macOS system monitor inspired by iStat Menus.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(16)
                }

                // Architecture & Privacy Guarantees Card
                SettingsCard(
                    title: "System & Architecture Guarantees",
                    subtitle: "Designed from first principles for performance and privacy."
                ) {
                    SettingsRow(
                        leading: {
                            SettingsBadge(icon: "lock.shield.fill", color: .green)
                        },
                        title: "Zero-Telemetry Persistence (ADR 0006)",
                        subtitle: "All hardware telemetry stays strictly in memory in ring buffers. No metric data is ever written to disk or sent over the network."
                    ) {
                        Text("Verified")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Divider().padding(.horizontal, 14)

                    SettingsRow(
                        leading: {
                            SettingsBadge(icon: "bolt.badge.clock.fill", color: .orange)
                        },
                        title: "Strict Background Scheduling (ADR 0002)",
                        subtitle: "All kernel, sysctl, Mach, and AppleSMC calls run on dedicated background actors to guarantee a zero-lag main thread."
                    ) {
                        Text("Off-Main")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Divider().padding(.horizontal, 14)

                    SettingsRow(
                        leading: {
                            SettingsBadge(icon: "menubar.rectangle", color: .purple)
                        },
                        title: "Modular Dynamic Menu Bar (ADR 0007)",
                        subtitle: "Supports multi-item widgets and decoupled popovers with drag reordering and instantaneous hover scrubbing."
                    ) {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // Quick System Tools Card
                SettingsCard(title: "Diagnostic Shortcuts") {
                    SettingsRow(
                        leading: {
                            SettingsBadge(icon: "chart.line.uptrend.xyaxis", color: .blue)
                        },
                        title: "Activity Monitor",
                        subtitle: "Launch macOS system activity and process diagnostics."
                    ) {
                        Button("Open") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider().padding(.horizontal, 14)

                    SettingsRow(
                        leading: {
                            SettingsBadge(icon: "bell.badge", color: .red)
                        },
                        title: "Notification Settings",
                        subtitle: "Manage macOS banner delivery, alert style, and sound permissions."
                    ) {
                        Button("Open") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

