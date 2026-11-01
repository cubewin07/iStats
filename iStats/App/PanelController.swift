import AppKit
import SwiftUI
import iStatsCore

/// Coordinates presentation, placement, dismissal, tracking, and pinning of the Glass Panel (ADR 0009 / Task 8.3).
@MainActor
public final class PanelController: NSObject {
    public static let shared = PanelController()

    public private(set) var activePanel: MetricPanel?
    public private(set) var currentCategory: MetricCategory?
    public private(set) var currentButton: NSStatusBarButton?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var spaceChangeObserver: Any?
    private var resignActiveObserver: Any?

    private var preferencesStore: PreferencesStore?

    public override init() {
        super.init()
    }

    public func configure(preferences: PreferencesStore) {
        self.preferencesStore = preferences
    }

    // MARK: - Presentation & Toggling

    public func toggle<V: View>(
        category: MetricCategory,
        relativeTo button: NSStatusBarButton,
        content: () -> V
    ) {
        if isPanelOpen(for: category) {
            close()
        } else {
            show(category: category, relativeTo: button, content: content)
        }
    }

    public func show<V: View>(
        category: MetricCategory,
        relativeTo button: NSStatusBarButton,
        content: () -> V
    ) {
        let isSwitching = activePanel != nil && currentCategory != category

        let panel: MetricPanel
        if let existing = activePanel {
            panel = existing
        } else {
            panel = MetricPanel()
            panel.onCloseRequested = { [weak self] in
                self?.close()
            }
            panel.onUnpinRequested = { [weak self] in
                self?.togglePin()
            }
            activePanel = panel
        }

        currentCategory = category
        currentButton = button

        let pinned = (preferencesStore?.pinnedOrigin(for: category) != nil)
        panel.isPinned = pinned

        // Inject content
        panel.setSwiftUIContent(content())

        // Compute layout and placement
        reposition(panel: panel, relativeTo: button, animated: isSwitching)

        if !panel.isVisible {
            panel.alphaValue = 0.0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        }

        installDismissalMonitorsIfNeeded()
    }

    public func close() {
        guard let panel = activePanel else { return }

        removeDismissalMonitors()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                panel.orderOut(nil)
                self.activePanel = nil
                self.currentCategory = nil
                self.currentButton = nil
            }
        })
    }

    public func isPanelOpen(for category: MetricCategory) -> Bool {
        activePanel?.isVisible == true && currentCategory == category
    }

    // MARK: - Menu Tracking (F2)

    /// Instantly switches panels when the user hovers over another status item while a panel is open.
    public func handleStatusItemHover<V: View>(
        category: MetricCategory,
        button: NSStatusBarButton,
        content: () -> V
    ) {
        guard let panel = activePanel, panel.isVisible, !panel.isPinned else { return }
        guard currentCategory != category else { return }

        // Switch category with swift crossfade
        show(category: category, relativeTo: button, content: content)
    }

    // MARK: - Pinning & Detaching (F3)

    public func togglePin() {
        guard let panel = activePanel, let category = currentCategory else { return }

        panel.isPinned.toggle()

        if panel.isPinned {
            preferencesStore?.setPinnedOrigin(panel.frame.origin, for: category)
            removeDismissalMonitors()
        } else {
            preferencesStore?.setPinnedOrigin(nil, for: category)
            installDismissalMonitorsIfNeeded()
            if let button = currentButton {
                reposition(panel: panel, relativeTo: button, animated: true)
            }
        }
    }

    // MARK: - Placement Math

    private func reposition(panel: MetricPanel, relativeTo button: NSStatusBarButton, animated: Bool) {
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return }

        let buttonRectOnScreen = window.convertToScreen(button.bounds)

        // If pinned and has a stored origin, use the pinned origin
        if panel.isPinned, let category = currentCategory, let savedOrigin = preferencesStore?.pinnedOrigin(for: category) {
            var frame = panel.frame
            frame.origin = savedOrigin
            panel.setFrame(frame, display: true, animate: animated)
            return
        }

        // Measure content
        let targetSize = CGSize(
            width: Instrument.Size.panelWidth,
            height: min(panel.contentView?.fittingSize.height ?? 400, Instrument.Size.maxHeight)
        )

        let targetFrame = PanelPlacement.frame(
            for: buttonRectOnScreen,
            panelSize: targetSize,
            visibleFrame: screen.visibleFrame,
            gap: 6.0,
            margin: 8.0
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    // MARK: - Dismissal Monitors

    private func installDismissalMonitorsIfNeeded() {
        guard globalMouseMonitor == nil, let panel = activePanel, !panel.isPinned else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self, let activePanel = self.activePanel, !activePanel.isPinned else { return }

                let clickLocation = NSEvent.mouseLocation
                let buttonRect = self.currentButton?.window?.convertToScreen(self.currentButton?.bounds ?? .zero) ?? .zero

                if !activePanel.frame.contains(clickLocation) && !buttonRect.contains(clickLocation) {
                    self.close()
                }
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self, let activePanel = self.activePanel, !activePanel.isPinned else { return }

                if let eventWindow = event.window, eventWindow != activePanel {
                    let clickLocation = NSEvent.mouseLocation
                    let buttonRect = self.currentButton?.window?.convertToScreen(self.currentButton?.bounds ?? .zero) ?? .zero

                    if !activePanel.frame.contains(clickLocation) && !buttonRect.contains(clickLocation) {
                        self.close()
                    }
                }
            }
            return event
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let panel = self.activePanel, !panel.isPinned else { return }
                self.close()
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let panel = self.activePanel, !panel.isPinned else { return }
                self.close()
            }
        }
    }

    private func removeDismissalMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            resignActiveObserver = nil
        }
    }

    isolated deinit {
        removeDismissalMonitors()
    }
}
