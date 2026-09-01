import AppKit
import iStatsCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var menuBarController: MenuBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce activation policy according to settings (default: .accessory via LSUIElement).
        DockIconManager.shared.applyCurrentPolicy()

        // Sync LaunchAtLogin registration if configured
        if PreferencesStore.shared.launchAtLogin {
            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: true)
        }

        // Register system notifications delegate and sync status
        NotificationManager.shared.register()

        // Start background metrics collection
        MetricsCoordinator.shared.start()

        // Start metric alert threshold monitor
        AlertCoordinator.shared.start()

        // Install the menu bar item and detail popover.
        menuBarController = MenuBarController()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PreferencesWindowController.shared.showPreferences()
        return true
    }
}

