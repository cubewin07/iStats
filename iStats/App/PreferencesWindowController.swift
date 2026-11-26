import AppKit
import Combine
import SwiftUI
import iStatsCore

/// Manages the single Settings window lifecycle and deep-link navigation.
///
/// Ensures the Settings window can be opened, focused, and switched to any
/// `SettingsSection` even when the application is running in `.accessory` /
/// `LSUIElement` mode without a Dock icon.
@MainActor
public final class PreferencesWindowController: NSObject, NSWindowDelegate {
    public static let shared = PreferencesWindowController()

    private let store: PreferencesStore
    private let coordinator: MetricsCoordinator
    private let frameAutosaveName: String?
    public let navigation: SettingsNavigationModel

    public private(set) var window: NSWindow?
    private var deepLinkCancellable: AnyCancellable?

    public var currentSection: SettingsSection {
        navigation.selection
    }

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared,
        notificationCenter: NotificationCenter = .default,
        frameAutosaveName: String? = "iStatsSettingsWindowV1"
    ) {
        self.store = store
        self.coordinator = coordinator
        self.frameAutosaveName = frameAutosaveName
        self.navigation = SettingsNavigationModel(store: store)
        super.init()
        observeDeepLinks(on: notificationCenter)
    }

    /// Displays the Settings window on the last selected section.
    /// Kept for existing callers; delegates to `show(section: nil)`.
    public func showPreferences() {
        show(section: nil)
    }

    /// Displays the single Settings window, optionally switching to `section`.
    /// When `section` is `nil`, restores `PreferencesStore.lastSettingsSection`
    /// (falling back to `.general` if missing or stale) when first shown, or keeps
    /// the currently selected section if the window already exists.
    public func show(section: SettingsSection?) {
        if let section {
            navigation.select(section)
        } else if window == nil {
            navigation.select(storageKey: store.lastSettingsSection)
        }

        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp?.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            store: store,
            coordinator: coordinator,
            navigation: navigation
        )
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.minSize = NSSize(width: 900, height: 560)
        newWindow.toolbarStyle = .unified
        newWindow.title = "iStats Settings"
        newWindow.center()
        if let frameAutosaveName {
            newWindow.setFrameAutosaveName(frameAutosaveName)
        }
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp?.activate(ignoringOtherApps: true)
    }

    /// Closes the Settings window if open.
    public func close() {
        window?.close()
    }

    // MARK: - Deep-link Observer

    private func observeDeepLinks(on center: NotificationCenter) {
        deepLinkCancellable = center
            .publisher(for: SettingsSection.openNotificationName)
            .sink { [weak self] notification in
                let sectionKey = notification.userInfo?[SettingsSection.deepLinkUserInfoKey] as? String
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        self?.handleOpenNotification(sectionKey: sectionKey)
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.handleOpenNotification(sectionKey: sectionKey)
                    }
                }
            }
    }

    private func handleOpenNotification(sectionKey: String?) {
        if let sectionKey {
            show(section: SettingsSection.resolved(storageKey: sectionKey))
        } else {
            show(section: nil)
        }
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        // Keep window reference retained so it can be re-shown rapidly.
    }
}
