import AppKit
import SwiftUI
import iStatsCore

/// Coordinates presentation, placement, dismissal, tracking, and pinning of the Glass Panel (ADR 0009 / Task 8.3).
@MainActor
public final class PanelController: NSObject, ObservableObject {
    public static let shared = PanelController()

    public private(set) var transientPanel: MetricPanel?
    public private(set) var pinnedPanels: [MetricCategory: MetricPanel] = [:]
    @Published public private(set) var pinnedCategories: Set<MetricCategory> = []
    @Published public private(set) var isTransientVisible: Bool = false
    public private(set) var currentCategory: MetricCategory?
    public private(set) var currentItemID: String?
    public private(set) var currentButton: NSStatusBarButton?

    public var onTransientPanelClosed: (() -> Void)?

    public var activePanel: MetricPanel? {
        transientPanel ?? (currentCategory.flatMap { pinnedPanels[$0] })
    }

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var spaceChangeObserver: Any?
    private var resignActiveObserver: Any?
    private var pinnedMoveObservers: [MetricCategory: Any] = [:]

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
        itemID: String? = nil,
        relativeTo button: NSStatusBarButton,
        content: () -> V
    ) {
        if let pinned = pinnedPanels[category], pinned.isVisible {
            close()
            pinned.makeKeyAndOrderFront(nil)
            return
        }

        if isTransientPanelOpen(for: category) && (itemID == nil || currentItemID == itemID) {
            close()
        } else {
            show(category: category, itemID: itemID, relativeTo: button, content: content)
        }
    }

    public func show<V: View>(
        category: MetricCategory,
        itemID: String? = nil,
        relativeTo button: NSStatusBarButton,
        content: () -> V
    ) {
        let isSwitching = transientPanel != nil && currentCategory != category

        let panel: MetricPanel
        if let existing = transientPanel {
            panel = existing
        } else {
            panel = MetricPanel()
            panel.onCloseRequested = { [weak self] in
                self?.close()
            }
            panel.onUnpinRequested = { [weak self] in
                self?.togglePin()
            }
            transientPanel = panel
        }

        currentCategory = category
        currentItemID = itemID
        currentButton = button

        panel.category = category
        panel.isPinned = false

        // Inject content
        panel.setSwiftUIContent(content())

        // Compute layout and placement
        reposition(panel: panel, relativeTo: button, animated: isSwitching)

        if !panel.isVisible {
            panel.alphaValue = 0.0
            panel.makeKeyAndOrderFront(nil)
            let isRunningInTest = (NSClassFromString("XCTestCase") != nil)
            if isRunningInTest || NSAnimationContext.current.duration == 0 {
                panel.alphaValue = 1.0
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1.0
                }
            }
        }
        isTransientVisible = true

        installDismissalMonitorsIfNeeded()
    }

    public func close(immediately: Bool = false) {
        guard let panel = transientPanel else { return }

        removeDismissalMonitors()
        currentCategory = nil
        currentItemID = nil
        currentButton = nil
        isTransientVisible = false

        let teardown: @Sendable () -> Void = { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                panel?.orderOut(nil)
                if self.currentCategory == nil {
                    self.transientPanel = nil
                }
                self.onTransientPanelClosed?()
            }
        }

        let isRunningInTest = (NSClassFromString("XCTestCase") != nil)
        if immediately || isRunningInTest || NSAnimationContext.current.duration == 0 {
            panel.alphaValue = 0.0
            teardown()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: teardown)
    }

    public func isTransientPanelOpen(for category: MetricCategory? = nil) -> Bool {
        guard let panel = transientPanel, panel.isVisible else { return false }
        if let cat = category {
            return currentCategory == cat
        }
        return true
    }

    public func isPinned(for category: MetricCategory) -> Bool {
        pinnedCategories.contains(category) && (pinnedPanels[category]?.isVisible == true)
    }

    public func isPanelOpen(for category: MetricCategory) -> Bool {
        isTransientPanelOpen(for: category) || isPinned(for: category)
    }

    /// Swaps the active open panel to a different category (e.g. from Fanless state to Temperature).
    public func swapToCategory(_ category: MetricCategory) {
        guard let button = currentButton else { return }
        show(category: category, relativeTo: button) {
            PanelFactory.makeCategoryPanelView(category: category)
        }
    }

    // MARK: - Menu Tracking (F2)

    /// Instantly switches panels when the user hovers over another status item while a panel is open.
    public func handleStatusItemHover<V: View>(
        category: MetricCategory,
        itemID: String? = nil,
        button: NSStatusBarButton,
        content: () -> V
    ) {
        guard let panel = transientPanel, panel.isVisible, !panel.isPinned else { return }
        guard currentCategory != category || (itemID != nil && currentItemID != itemID) else { return }

        // Switch category with swift crossfade
        show(category: category, itemID: itemID, relativeTo: button, content: content)
    }

    // MARK: - Pinning & Detaching (F3)

    public func togglePin() {
        guard let category = currentCategory else { return }
        togglePin(for: category)
    }

    public func togglePin(for category: MetricCategory) {
        if pinnedPanels[category] != nil {
            unpin(category: category)
            return
        }

        guard let panel = transientPanel, currentCategory == category else { return }

        // Pinning the currently open transient panel into an independent floating HUD
        panel.category = category
        panel.isPinned = true
        removeDismissalMonitors()
        onTransientPanelClosed?()

        pinnedPanels[category] = panel
        pinnedCategories.insert(category)
        transientPanel = nil
        currentCategory = nil
        currentItemID = nil
        currentButton = nil
        isTransientVisible = false

        if let savedOrigin = preferencesStore?.pinnedOrigin(for: category) {
            var frame = panel.frame
            frame.origin = clampedPinnedOrigin(savedOrigin, for: frame.size)
            panel.setFrame(frame, display: true, animate: false)
        } else {
            preferencesStore?.setPinnedOrigin(panel.frame.origin, for: category)
        }

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self = self, let panel = panel else { return }
                self.preferencesStore?.setPinnedOrigin(panel.frame.origin, for: category)
            }
        }
        pinnedMoveObservers[category] = observer

        panel.onUnpinRequested = { [weak self] in
            self?.unpin(category: category)
        }
        panel.onCloseRequested = { [weak self] in
            self?.unpin(category: category)
        }
    }

    public func unpin(category: MetricCategory) {
        guard let panel = pinnedPanels[category] else { return }

        if let obs = pinnedMoveObservers[category] {
            NotificationCenter.default.removeObserver(obs)
            pinnedMoveObservers.removeValue(forKey: category)
        }
        pinnedPanels.removeValue(forKey: category)
        pinnedCategories.remove(category)

        panel.orderOut(nil)
    }

    public func unpinAll() {
        for category in Array(pinnedPanels.keys) {
            unpin(category: category)
        }
    }

    // MARK: - Placement & Dynamic Morphing

    public func updateFittingHeight(for category: MetricCategory? = nil, animated: Bool = true) {
        let targetPanel: MetricPanel?
        if let cat = category {
            if currentCategory == cat, let transient = transientPanel, transient.isVisible {
                targetPanel = transient
            } else {
                targetPanel = pinnedPanels[cat]
            }
        } else {
            targetPanel = activePanel
        }

        guard let panel = targetPanel, panel.isVisible else { return }

        panel.contentView?.layoutSubtreeIfNeeded()
        let newFittingHeight = panel.contentView?.fittingSize.height ?? panel.frame.height
        let targetHeight = min(max(newFittingHeight, 160.0), Instrument.Size.maxHeight)

        var targetFrame = panel.frame
        if abs(targetFrame.height - targetHeight) < 1.0 { return }

        // Top-anchored: keep targetFrame.maxY stationary!
        let delta = targetHeight - targetFrame.height
        targetFrame.size.height = targetHeight
        targetFrame.origin.y -= delta

        if let screen = panel.screen ?? NSScreen.main {
            let minY = screen.visibleFrame.minY + 8.0
            if targetFrame.minY < minY {
                targetFrame.origin.y = minY
                targetFrame.size.height = panel.frame.maxY - minY
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func reposition(panel: MetricPanel, relativeTo button: NSStatusBarButton, animated: Bool) {
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)

        // Measure content
        let targetSize = CGSize(
            width: Instrument.Size.panelWidth,
            height: min(max(panel.contentView?.fittingSize.height ?? 400, 160), Instrument.Size.maxHeight)
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

    private func clampedPinnedOrigin(_ origin: CGPoint, for size: CGSize) -> CGPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return origin }

        let targetRect = CGRect(origin: origin, size: size)
        for screen in screens {
            if screen.visibleFrame.intersects(targetRect) {
                return origin
            }
        }

        if let main = NSScreen.main {
            return CGPoint(
                x: main.visibleFrame.midX - size.width / 2.0,
                y: main.visibleFrame.midY - size.height / 2.0
            )
        }
        return origin
    }

    // MARK: - Dismissal Monitors

    private func installDismissalMonitorsIfNeeded() {
        guard globalMouseMonitor == nil, let panel = transientPanel, !panel.isPinned else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self, let activePanel = self.transientPanel, !activePanel.isPinned else { return }

                let clickLocation = NSEvent.mouseLocation
                let buttonRect = self.currentButton.flatMap { btn in
                    btn.window.map { $0.convertToScreen(btn.convert(btn.bounds, to: nil)) }
                } ?? .zero

                if !activePanel.frame.contains(clickLocation) && !buttonRect.contains(clickLocation) {
                    self.close()
                }
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self, let activePanel = self.transientPanel, !activePanel.isPinned else { return }

                if let eventWindow = event.window, eventWindow != activePanel {
                    let clickLocation = NSEvent.mouseLocation
                    let buttonRect = self.currentButton.flatMap { btn in
                        btn.window.map { $0.convertToScreen(btn.convert(btn.bounds, to: nil)) }
                    } ?? .zero

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
                guard let self = self, let panel = self.transientPanel, !panel.isPinned else { return }
                self.close()
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let panel = self.transientPanel, !panel.isPinned else { return }
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
        for (_, obs) in pinnedMoveObservers {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
