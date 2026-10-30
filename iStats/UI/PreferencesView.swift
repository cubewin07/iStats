import SwiftUI
import AppKit
import iStatsCore

/// Modern, macOS System Settings-style preferences view (ADR 0007, Requirements 11.1-11.4).
/// Features a translucent sidebar navigation, live menu bar customization studio,
/// unified general/units controls, calibrated alert threshold setup, and safe reset confirmation.
public struct PreferencesView: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject private var notificationManager = NotificationManager.shared

    @State private var activeSection: PreferencesSection = .menuBar
    @State private var isShowingResetConfirmation: Bool = false

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.store = store
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar Navigation
            sidebarView
                .frame(width: 220)

            Divider()

            // MARK: - Detail Workspace
            VStack(spacing: 0) {
                // Section Title Bar
                workspaceTitleBar

                Divider()

                // Active Section Pane
                Group {
                    switch activeSection {
                    case .menuBar:
                        PreferencesMenuBarPane(store: store, coordinator: coordinator)
                    case .general:
                        PreferencesGeneralPane(store: store, coordinator: coordinator)
                    case .alerts:
                        PreferencesAlertsPane(store: store, coordinator: coordinator)
                    case .about:
                        PreferencesAboutPane(store: store, coordinator: coordinator)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 880, minHeight: 580)
        // Hidden keyboard shortcuts for Cmd+1 ... Cmd+4
        .background(
            ZStack {
                Button("") { activeSection = .menuBar }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { activeSection = .general }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { activeSection = .alerts }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { activeSection = .about }
                    .keyboardShortcut("4", modifiers: .command)
            }
            .opacity(0)
        )
        // Safe Reset Confirmation Dialog
        .confirmationDialog(
            "Reset All Preferences to Defaults?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) {
                resetAllPreferences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore default sampling rates, reset menu bar items to standard widgets, clear custom popover assignments, and disable alerts.")
        }
    }

    // MARK: - Sidebar View

    private var sidebarView: some View {
        ZStack {
            SidebarVisualEffectView()

            VStack(spacing: 0) {
                // App Branding Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)

                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("iStats")
                            .font(.system(size: 13, weight: .bold))
                        Text("Settings")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 12)

                Divider()

                // Navigation Items List
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(PreferencesSection.allCases) { section in
                            sidebarItem(for: section)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }

                Spacer()

                Divider()

                // Sidebar Footer (Safe Reset Action)
                HStack {
                    Button(action: {
                        isShowingResetConfirmation = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10.5))
                            Text("Reset Defaults…")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func sidebarItem(for section: PreferencesSection) -> some View {
        let isSelected = (activeSection == section)

        return Button(action: {
            activeSection = section
        }) {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 18)

                Text(section.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()

                // Context Badges
                sidebarBadge(for: section, isSelected: isSelected)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sidebarBadge(for section: PreferencesSection, isSelected: Bool) -> some View {
        switch section {
        case .menuBar:
            if store.isSamplingPaused {
                Text("Paused")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(isSelected ? .white : .orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                let count = store.activeMenuBarItems.count
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        case .general:
            if coordinator.isLowPowerModeActive {
                Text("Low Power")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isSelected ? .white : .orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }
        case .alerts:
            if !notificationManager.isAuthorized && store.notificationsEnabled {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            } else if store.notificationsEnabled {
                Circle()
                    .fill(isSelected ? Color.white : Color.green)
                    .frame(width: 6, height: 6)
            }
        case .about:
            EmptyView()
        }
    }

    // MARK: - Workspace Title Bar

    private var workspaceTitleBar: some View {
        HStack(spacing: 8) {
            Text(activeSection.title)
                .font(.system(size: 13, weight: .bold))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: - Reset Actions

    private func resetAllPreferences() {
        store.resetToDefaults()
        DockIconManager.shared.setDockIconVisible(store.showDockIcon)
        LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: store.launchAtLogin)
    }
}
