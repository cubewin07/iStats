import SwiftUI
import AppKit
import iStatsCore

/// Modern, clean About pane for iStats.
/// Highlights system architecture guarantees, version info, and macOS system shortcuts
/// without exposing internal engineering jargon.
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
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "macOS Universal"
        #endif
    }

    public var body: some View {
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 20)
                VStack(spacing: 20) {
                    headerCard
                    architectureTrustCard
                    diagnosticToolsCard
                }
                .frame(maxWidth: 580)
                Spacer(minLength: 20)
            }
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header Branding Card

    private var headerCard: some View {
        SettingsCard {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: Color.blue.opacity(0.25), radius: 6, x: 0, y: 3)

                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("iStats")
                            .font(.system(size: 17, weight: .bold))

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
            .padding(14)
        }
    }

    // MARK: - Architecture & Privacy Guarantees

    private var architectureTrustCard: some View {
        SettingsCard(title: "Privacy & Architecture") {
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "lock.shield.fill", color: .green)
                },
                title: "100% On-Device & Private",
                subtitle: "Metrics stay strictly in volatile memory. No telemetry is logged to disk or network."
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
                title: "Background Kernel Sampling",
                subtitle: "Hardware queries execute off the main thread to ensure smooth UI performance."
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
                title: "Modular Menu Bar Studio",
                subtitle: "Decoupled popovers, reorderable items, and interactive menu bar hover-scrubbing."
            ) {
                Text("Native")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Quick System Tools

    private var diagnosticToolsCard: some View {
        SettingsCard(title: "System Shortcuts") {
            SettingsRow(
                leading: {
                    SettingsBadge(icon: "chart.line.uptrend.xyaxis", color: .blue)
                },
                title: "Activity Monitor",
                subtitle: "Inspect running macOS processes and resource usage"
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
                title: "macOS Notification Settings",
                subtitle: "Configure banner styles, sounds, and Focus filters"
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
}
