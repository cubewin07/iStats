import SwiftUI
import iStatsCore

@main
struct iStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main UI is presented via MenuBarController in the menu bar.
        // The Settings scene enables standard macOS Cmd+, shortcut for preferences.
        Settings {
            PreferencesView(store: .shared)
        }
    }
}
