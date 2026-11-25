import AppKit
import SwiftUI
import iStatsCore

@main
struct iStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main UI is presented via MenuBarController in the menu bar.
        // Settings uses the single AppKit window managed by PreferencesWindowController;
        // this stub wires the standard Cmd+, menu item to it without creating a second window.
        Settings {
            SettingsSceneForwarder()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    PreferencesWindowController.shared.showPreferences()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Closes any SwiftUI-created Settings window immediately and opens the canonical Settings window.
private struct SettingsSceneForwarder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ForwardingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ForwardingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let swiftUIWindow = window else { return }
            Task { @MainActor in
                swiftUIWindow.orderOut(nil)
                swiftUIWindow.close()
                PreferencesWindowController.shared.showPreferences()
            }
        }
    }
}
