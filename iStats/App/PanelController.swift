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
    /// Hit-test closure injected by `MenuBarController` so dismissal monitors ignore clicks on any status item button.
    public var statusItemHitTest: ((NSPoint) -> Bool)?

    public var activePanel: MetricPanel? {
        transientPanel ?? (currentCategory.flatMap { pinnedPanels[$0] })
    }

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var spaceChangeObserver: Any?
    private var resignActiveObserver: Any?
    private var pinnedMoveObservers: [MetricCategory: Any] = [:]

    private var preferencesStore: PreferencesStore?
    private var transitionGeneration: UInt64 = 0
    internal var animateInTests: Bool = false

    private var shouldAnimateTransitions: Bool {
        (NSClassFromString("XCTestCase") == nil) || animateInTests
    }

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
        // B6: Never create a transient panel for a category that already has a visible pinned HUD.
        if let pinned = pinnedPanels[category], pinned.isVisible {
            close()
            pinned.makeKeyAndOrderFront(nil)
            return
        }

        transitionGeneration &+= 1
        let wasVisible = transientPanel?.isVisible ?? false
        let isSwitching = wasVisible && (currentCategory != category)

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
            panel.onContentHeightChanged = { [weak self, weak panel] height in
                guard let self, let panel, let cat = panel.category else { return }
                self.setContentHeight(height, forPanel: panel, category: cat, animated: panel.isVisible)
            }
            transientPanel = panel
        }

        currentCategory = category
        currentItemID = itemID
        currentButton = button

        panel.category = category
        panel.isPinned = false

        // Build content once and measure synchronously before ordering front (B5)
        let builtView = content()
        let measuredHeight = measureHeight(of: builtView)

        // Compute layout and placement before showing
        reposition(panel: panel, relativeTo: button, targetHeight: measuredHeight, animated: isSwitching)

        // Inject content into persistent host (A11)
        panel.setSwiftUIContent(builtView)

        if !wasVisible {
            panel.alphaValue = 0.0
            panel.makeKeyAndOrderFront(nil)
            if !shouldAnimateTransitions || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || NSAnimationContext.current.duration == 0 {
                panel.alphaValue = 1.0
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1.0
                }
                panel.animateOpenTransform()
            }
        } else {
            // B1: If show() interrupted an in-flight fade-out, restore alpha back to 1.0 and front the panel
            panel.makeKeyAndOrderFront(nil)
            if !shouldAnimateTransitions || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || NSAnimationContext.current.duration == 0 {
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

        transitionGeneration &+= 1
        let closeGen = transitionGeneration

        removeDismissalMonitors()
        currentCategory = nil
        currentItemID = nil
        currentButton = nil
        isTransientVisible = false

        let teardown: @Sendable () -> Void = { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self = self,
                      self.transitionGeneration == closeGen,
                      self.currentCategory == nil else {
                    return
                }
                panel?.orderOut(nil)
                panel?.clearContent()
                self.transientPanel = nil
                self.onTransientPanelClosed?()
            }
        }

        if immediately || !shouldAnimateTransitions || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || NSAnimationContext.current.duration == 0 {
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

        // B6: Hovering onto a category with an already-visible pinned HUD closes transient and fronts pinned.
        if let pinned = pinnedPanels[category], pinned.isVisible {
            close()
            pinned.makeKeyAndOrderFront(nil)
            return
        }

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

        transitionGeneration &+= 1

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
            if shouldAnimateTransitions && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && NSAnimationContext.current.duration > 0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.28
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true, animate: false)
            }
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

    public func unpin(category: MetricCategory, immediately: Bool = false) {
        guard let panel = pinnedPanels[category] else { return }

        if let obs = pinnedMoveObservers[category] {
            NotificationCenter.default.removeObserver(obs)
            pinnedMoveObservers.removeValue(forKey: category)
        }
        pinnedPanels.removeValue(forKey: category)
        pinnedCategories.remove(category)

        let finishUnpin: @Sendable () -> Void = { [weak panel] in
            MainActor.assumeIsolated {
                panel?.orderOut(nil)
                panel?.clearContent()
            }
        }

        if immediately || !shouldAnimateTransitions || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || NSAnimationContext.current.duration == 0 {
            panel.alphaValue = 0.0
            finishUnpin()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: finishUnpin)
    }

    public func unpinAll(immediately: Bool = false) {
        for category in Array(pinnedPanels.keys) {
            unpin(category: category, immediately: immediately)
        }
    }

    // MARK: - Placement & Dynamic Morphing

    /// Resizes the panel for `category` (or `activePanel`) keeping its top edge anchored and clamping to the screen's visible bottom margin.
    public func setContentHeight(_ height: CGFloat, for category: MetricCategory? = nil, animated: Bool = true) {
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

        guard let panel = targetPanel else { return }
        setContentHeight(height, forPanel: panel, category: category, animated: animated)
    }

    private func setContentHeight(_ height: CGFloat, forPanel panel: MetricPanel, category: MetricCategory?, animated: Bool) {
        guard panel.isVisible else { return }

        let clampedHeight = min(max(height, 160.0), Instrument.Size.maxHeight)
        var targetFrame = panel.frame
        let referenceHeight = panel.targetHeight ?? targetFrame.height
        if abs(referenceHeight - clampedHeight) < 1.0 && abs(targetFrame.height - clampedHeight) < 1.0 {
            return
        }

        // Top-anchored: keep targetFrame.maxY stationary
        let topY = targetFrame.maxY
        targetFrame.size.height = clampedHeight
        targetFrame.origin.y = topY - clampedHeight

        if let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first {
            let minY = screen.visibleFrame.minY + 8.0
            if targetFrame.minY < minY {
                targetFrame.origin.y = minY
                let available = topY - minY
                if available >= 160.0 {
                    targetFrame.size.height = available
                } else {
                    targetFrame.size.height = min(clampedHeight, max(160.0, screen.visibleFrame.height - 16.0))
                }
            }
        }

        panel.targetHeight = targetFrame.height

        let shouldAnimate = animated && shouldAnimateTransitions && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && NSAnimationContext.current.duration > 0
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func measureHeight<V: View>(of view: V) -> CGFloat {
        let measurer = NSHostingController(rootView: AnyView(view))
        let measured = measurer.sizeThatFits(in: CGSize(width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight))
        return min(max(measured.height, 160.0), Instrument.Size.maxHeight)
    }

    private func reposition(panel: MetricPanel, relativeTo button: NSStatusBarButton, targetHeight: CGFloat, animated: Bool) {
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)

        let targetSize = CGSize(
            width: Instrument.Size.panelWidth,
            height: min(max(targetHeight, 160.0), Instrument.Size.maxHeight)
        )

        let targetFrame = PanelPlacement.frame(
            for: buttonRectOnScreen,
            panelSize: targetSize,
            visibleFrame: screen.visibleFrame,
            gap: 6.0,
            margin: 8.0
        )
        panel.targetHeight = targetFrame.height

        let shouldAnimate = animated && shouldAnimateTransitions && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && NSAnimationContext.current.duration > 0
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.30
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
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

    private func isClickOnStatusItem(_ screenPoint: NSPoint) -> Bool {
        if let hitTest = statusItemHitTest, hitTest(screenPoint) {
            return true
        }
        if let btn = currentButton,
           let window = btn.window,
           window.convertToScreen(btn.convert(btn.bounds, to: nil)).contains(screenPoint) {
            return true
        }
        return false
    }

    private func installDismissalMonitorsIfNeeded() {
        guard globalMouseMonitor == nil, let panel = transientPanel, !panel.isPinned else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let activePanel = self.transientPanel, !activePanel.isPinned else { return }

                let clickLocation = NSEvent.mouseLocation
                if !activePanel.frame.contains(clickLocation) && !self.isClickOnStatusItem(clickLocation) {
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
                    let clickLocation = eventWindow.convertPoint(toScreen: event.locationInWindow)
                    if !activePanel.frame.contains(clickLocation) && !self.isClickOnStatusItem(clickLocation) {
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
