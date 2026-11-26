import AppKit
import Combine
import SwiftUI
import iStatsCore

/// Manages the first-run Welcome onboarding window and `"Show Welcome Again"` replay (Task 9.11).
@MainActor
public final class WelcomeWindow: NSObject, NSWindowDelegate {
    public static let shared = WelcomeWindow()

    private let store: PreferencesStore
    private let coordinator: MetricsCoordinator
    private var showWelcomeCancellable: AnyCancellable?

    public private(set) var window: NSWindow?
    public private(set) var activeModel: WelcomeFlowModel?

    public var isPresented: Bool {
        window?.isVisible == true
    }

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.coordinator = coordinator
        super.init()
        observeReplayRequests(on: notificationCenter)
    }

    /// Returns `true` only for fresh users who have not yet completed (or migrated past) onboarding.
    public static func shouldShowOnLaunch(store: PreferencesStore) -> Bool {
        !store.hasCompletedOnboarding
    }

    /// Presents the Welcome window on launch ONLY when `hasCompletedOnboarding == false`.
    public func showIfNeeded() {
        guard Self.shouldShowOnLaunch(store: store) else { return }
        show()
    }

    /// Presents or focuses the Welcome window.
    public func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp?.activate(ignoringOtherApps: true)
            return
        }

        let model = WelcomeFlowModel(
            store: store,
            coordinator: coordinator,
            onComplete: { [weak self] in
                self?.close()
            }
        )
        self.activeModel = model

        let hostingController = NSHostingController(rootView: WelcomeView(model: model))
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Welcome to iStats"
        newWindow.center()
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp?.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.close()
    }

    private func observeReplayRequests(on center: NotificationCenter) {
        showWelcomeCancellable = center
            .publisher(for: SettingsSection.showWelcomeNotificationName)
            .sink { [weak self] _ in
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        self?.show()
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.show()
                    }
                }
            }
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        // Closing before completing first-run setup behaves like Skip so Welcome is shown only once.
        if !store.hasCompletedOnboarding {
            let hasBattery = activeModel?.hasBattery ?? (coordinator.latestPower?.value.hasBattery ?? true)
            let hasFans = activeModel?.hasFans ?? (coordinator.latestFan.map { !$0.value.isFanless && !$0.value.fans.isEmpty } ?? true)
            store.skipOnboarding(hasBattery: hasBattery, hasFans: hasFans)
        }
        activeModel = nil
        window = nil
    }
}
