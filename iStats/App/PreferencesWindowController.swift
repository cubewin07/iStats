import AppKit
import SwiftUI
import iStatsCore

/// Manages the standalone preferences/settings window lifecycle.
///
/// Ensures the preferences window can be opened and focused even when
/// the application is running in `.accessory` / `LSUIElement` mode without a Dock icon.
@MainActor
public final class PreferencesWindowController: NSObject, NSWindowDelegate {
    public static let shared = PreferencesWindowController()

    private var window: NSWindow?

    public override init() {
        super.init()
    }

    /// Displays the preferences window, bringing it to the front and making it key.
    public func showPreferences() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let preferencesView = PreferencesView(store: .shared)
        let hostingController = NSHostingController(rootView: preferencesView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.minSize = NSSize(width: 880, height: 580)
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.toolbarStyle = .unified

        newWindow.center()
        newWindow.setFrameAutosaveName("iStatsPreferencesWindowV2")
        newWindow.title = "iStats Settings"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        // Keep window reference retained so it can be re-shown rapidly.
    }
}
