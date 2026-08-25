import SwiftUI
import iStatsCore

@main
struct iStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar UI will be managed by MenuBarController in Task 1.2.
        // A minimal Settings scene satisfies the SwiftUI App protocol requirements.
        Settings {
            EmptyView()
        }
    }
}
