import SwiftUI
import AppKit
import UserNotifications
import iStatsCore

/// Notifications: the alerts master switch (your preference, separate from the macOS permission),
/// a banner when macOS blocks notifications, the default cooldown, a test alert, and the
/// per-metric thresholds (hosted from `PreferencesAlertsPane` until 9.10 replaces them).
struct NotificationsSettingsPage: View {
    @ObservedObject var store: PreferencesStore
    @ObservedObject var coordinator: MetricsCoordinator
    @ObservedObject private var notificationManager = NotificationManager.shared

    static let cooldownOptions: [(label: String, seconds: TimeInterval)] = [
        ("1 minute", 60.0),
        ("5 minutes", 300.0),
        ("15 minutes", 900.0),
        ("30 minutes", 1800.0),
        ("1 hour", 3600.0)
    ]

    private var status: UNAuthorizationStatus { notificationManager.authorizationStatus }

    private var cooldownChoices: [(label: String, seconds: TimeInterval)] {
        var choices = Self.cooldownOptions
        if !choices.contains(where: { $0.seconds == store.alertCooldownInterval }) {
            choices.append(("\(Int(store.alertCooldownInterval / 60)) minutes", store.alertCooldownInterval))
            choices.sort { $0.seconds < $1.seconds }
        }
        return choices
    }

    var body: some View {
        Form {
            if status == .denied {
                SwiftUI.Section {
                    permissionBanner(
                        message: "macOS is blocking notifications from iStats, so alerts cannot appear.",
                        buttonTitle: "Open System Settings"
                    ) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else if status == .notDetermined {
                SwiftUI.Section {
                    permissionBanner(
                        message: "iStats needs permission before it can show alert banners.",
                        buttonTitle: "Allow Notifications"
                    ) {
                        Task { await notificationManager.requestAuthorization() }
                    }
                }
            }

            SwiftUI.Section {
                Toggle("Hardware alerts", isOn: Binding(
                    get: { store.notificationsEnabled },
                    set: { newValue in
                        store.notificationsEnabled = newValue
                        if newValue && status == .notDetermined {
                            Task { await notificationManager.requestAuthorization() }
                        }
                    }
                ))
                .accessibilityLabel("Hardware alerts")

                Picker("Default cooldown", selection: $store.alertCooldownInterval) {
                    ForEach(cooldownChoices, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .disabled(!store.notificationsEnabled)

                LabeledContent("Test") {
                    Button("Send Test Alert") {
                        Task { await AlertCoordinator.shared.sendTestNotification() }
                    }
                    .disabled(!notificationManager.isAuthorized)
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("The cooldown is the shortest wait before the same alert can appear again.")
            }

            SwiftUI.Section("Alert Thresholds") {
                PreferencesAlertsPane(store: store, coordinator: coordinator, embedded: true)
            }
        }
        .formStyle(.grouped)
    }

    private func permissionBanner(
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
            Spacer()
            Button(buttonTitle, action: action)
        }
        .accessibilityElement(children: .contain)
    }
}
