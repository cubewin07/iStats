import AppKit
import iStatsCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var menuBarController: MenuBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce activation policy according to settings (default: .accessory via LSUIElement).
        DockIconManager.shared.applyCurrentPolicy()

        // Install the menu bar item and detail popover.
        menuBarController = MenuBarController()
    }
}

