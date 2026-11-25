import AppKit
import SwiftUI
import iStatsCore

/// Coordinates presentation, placement, dismissal, tracking, and pinning of the Glass Panel (ADR 0009 / Task 8.3).
@MainActor
public final class PanelController: NSObject, ObservableObject {
    public static let shared = PanelController()

    public private(set) var transientPanel: MetricPanel?
    public private(set) var pinnedPanels: [PanelDestination: MetricPanel] = [:]
    @Published public private(set) var pinnedDestinations: Set<PanelDestination> = []
    @Published public private(set) var isTransientVisible: Bool = false
    public private(set) var currentDestination: PanelDestination?
    public private(set) var currentItemID: String?
    public private(set) var currentButton: NSStatusBarButton?

    public var onTransientPanelClosed: (() -> Void)?
    /// Hit-test closure injected by `MenuBarController` so dismissal monitors ignore clicks on any status item button.
    public var statusItemHitTest: ((NSPoint) -> Bool)?
    /// Resolves an active status bar button and config ID for a category (used when swapping panels).
    public var statusButtonProvider: ((MetricCategory) -> (button: NSStatusBarButton, itemID: String?)?)?
    /// Notifies `MenuBarController` when `swap(to:)` anchors the transient panel to another category's status item.
    public var onTransientCategorySwapped: ((MetricCategory, NSStatusBarButton) -> Void)?
    /// Optional view builder injected by `MenuBarController` so destination swaps use its coordinator and preferences.
    public var destinationViewProvider: ((PanelDestination) -> AnyView)?

    public var currentCategory: MetricCategory? { currentDestination?.category }

    public var pinnedCategories: Set<MetricCategory> {
        Set(pinnedDestinations.compactMap(\.category))
    }

    public var activePanel: MetricPanel? {
        transientPanel ?? (currentDestination.flatMap { pinnedPanels[$0] })
    }

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var spaceChangeObserver: Any?
    private var resignActiveObserver: Any?
    private var pinnedMoveObservers: [PanelDestination: Any] = [:]

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
        toggle(destination: .category(category), itemID: itemID, relativeTo: button, content: content)
    }

    public func toggle<V: View>(
        destination: PanelDestination,
        itemID: String? = nil,
        relativeTo button: NSStatusBarButton,
        content: () -> V
    ) {
        if let pinned = pinnedPanels[destination], pinned.isVisible {
            close()
            pinned.makeKeyAndOrderFront(nil)
            return
        }

        if isTransientPanelOpen(for: destination) && (itemID == nil || currentItemID == itemID) {
            close()
        } else {
            show(destination: destination, itemID: itemID, relativeTo: button, content: content)
        }
    }

    public func show<V: View>(
        category: MetricCategory,
        itemID: String? = nil,
        relativeTo button: NSStatusBarButton,
        content: () -> V
    ) {
        show(destination: .category(category), itemID: itemID, relativeTo: button, content: content)
    }

    public func show<V: View>(
        destination: PanelDestination,
        itemID: String? = nil,
        relativeTo button: NSStatusBarButton,
        content: () -> V
    ) {
        presentTransient(
            destination: destination,
            itemID: itemID,
            relativeTo: button,
            anchorFrame: nil,
            content: content
        )
    }

    private func presentTransient<V: View>(
        destination: PanelDestination,
        itemID: String?,
        relativeTo button: NSStatusBarButton?,
        anchorFrame: NSRect?,
        content: () -> V
    ) {
        // B6: Never create a transient panel for a destination that already has a visible pinned HUD.
        if let pinned = pinnedPanels[destination], pinned.isVisible {
            close()
            pinned.makeKeyAndOrderFront(nil)
            return
        }

        transitionGeneration &+= 1
        let wasVisible = transientPanel?.isVisible ?? false
        let isSwitching = wasVisible && (currentDestination != destination)

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
                guard let self, let panel, let dest = panel.destination else { return }
                self.setContentHeight(height, forPanel: panel, destination: dest, animated: panel.isVisible)
            }
            transientPanel = panel
        }

        currentDestination = destination
        currentItemID = itemID
        currentButton = button
        recordLastDestination(destination)

        panel.destination = destination
        panel.isPinned = false

        // Build content once and measure synchronously before ordering front (B5)
        let builtView = content().environment(\.isManagedByPanelController, true)
        let measuredHeight = measureHeight(of: builtView)

        // Compute layout and placement before showing
        if let button {
            reposition(panel: panel, relativeTo: button, targetHeight: measuredHeight, animated: isSwitching)
        } else if let anchorFrame {
            reposition(panel: panel, anchoredTo: anchorFrame, targetHeight: measuredHeight)
        }

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
        syncNetworkForegroundProbing()

        installDismissalMonitorsIfNeeded()
    }

    public func close(immediately: Bool = false) {
        guard let panel = transientPanel else { return }

        transitionGeneration &+= 1
        let closeGen = transitionGeneration

        removeDismissalMonitors()
        currentDestination = nil
        currentItemID = nil
        currentButton = nil
        isTransientVisible = false
        syncNetworkForegroundProbing()

        let teardown: @Sendable () -> Void = { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self = self,
                      self.transitionGeneration == closeGen,
                      self.currentDestination == nil else {
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
        isTransientPanelOpen(for: category.map { PanelDestination.category($0) })
    }

    public func isTransientPanelOpen(for destination: PanelDestination?) -> Bool {
        guard let panel = transientPanel, panel.isVisible else { return false }
        if let destination {
            return currentDestination == destination
        }
        return true
    }

    public func isPinned(for category: MetricCategory) -> Bool {
        isPinned(for: PanelDestination.category(category))
    }

    public func isPinned(for destination: PanelDestination) -> Bool {
        pinnedDestinations.contains(destination) && (pinnedPanels[destination]?.isVisible == true)
    }

    public func isPanelOpen(for category: MetricCategory) -> Bool {
        isPanelOpen(for: PanelDestination.category(category))
    }

    public func isPanelOpen(for destination: PanelDestination) -> Bool {
        isTransientPanelOpen(for: destination) || isPinned(for: destination)
    }

    private func syncNetworkForegroundProbing() {
        NetworkConnectivityMonitor.shared.setForegroundProbing(isPanelOpen(for: .network))
    }

    private func recordLastDestination(_ destination: PanelDestination) {
        // Assigning an unchanged value would still publish and re-render every observing panel.
        guard let store = preferencesStore, store.lastPanelDestination != destination else { return }
        store.lastPanelDestination = destination
    }

    private func makeView(for destination: PanelDestination) -> AnyView {
        if let provider = destinationViewProvider {
            return provider(destination)
        }
        return AnyView(
            PanelFactory.makePanelView(
                destination: destination,
                coordinator: .shared,
                preferences: preferencesStore ?? .shared
            )
        )
    }

    /// Swaps the active open panel to a different destination (Overview or any category).
    public func swap(to destination: PanelDestination, from sourceDestination: PanelDestination? = nil) {
        if let pinned = pinnedPanels[destination], pinned.isVisible {
            close()
            pinned.makeKeyAndOrderFront(nil)
            recordLastDestination(destination)
            return
        }

        if case .category(let category) = destination, let target = statusButtonProvider?(category) {
            show(destination: destination, itemID: target.itemID, relativeTo: target.button) {
                self.makeView(for: destination)
            }
            if isTransientPanelOpen(for: destination) {
                onTransientCategorySwapped?(category, target.button)
            }
            return
        }

        if let button = currentButton {
            show(destination: destination, itemID: nil, relativeTo: button) {
                self.makeView(for: destination)
            }
            return
        }

        let sourcePinned = sourceDestination.flatMap { pinnedPanels[$0] }
            ?? pinnedPanels[.category(.fan)]
            ?? pinnedPanels.values.first(where: { $0.isVisible })

        if let sourcePinned {
            presentTransient(
                destination: destination,
                itemID: nil,
                relativeTo: nil,
                anchorFrame: sourcePinned.frame
            ) {
                self.makeView(for: destination)
            }
        }
    }

    /// Thin wrapper over `swap(to:)` for existing category-only callers (e.g. Fanless state -> Temperature).
    public func swapToCategory(_ category: MetricCategory) {
        swap(to: .category(category))
    }

    // MARK: - Menu Tracking (F2)

    /// Instantly switches panels when the user hovers over another status item while a panel is open.
    public func handleStatusItemHover<V: View>(
        category: MetricCategory,
        itemID: String? = nil,
        button: NSStatusBarButton,
        content: () -> V
    ) {
        handleStatusItemHover(destination: .category(category), itemID: itemID, button: button, content: content)
    }

    public func handleStatusItemHover<V: View>(
        destination: PanelDestination,
        itemID: String? = nil,
        button: NSStatusBarButton,
        content: () -> V
    ) {
        guard let panel = transientPanel, panel.isVisible, !panel.isPinned else { return }

        // B6: Hovering onto a destination with an already-visible pinned HUD closes transient and fronts pinned.
        if let pinned = pinnedPanels[destination], pinned.isVisible {
            close()
            pinned.makeKeyAndOrderFront(nil)
            recordLastDestination(destination)
            return
        }

        guard currentDestination != destination || (itemID != nil && currentItemID != itemID) else { return }

        // Switch destination with swift crossfade
        show(destination: destination, itemID: itemID, relativeTo: button, content: content)
    }

    // MARK: - Pinning & Detaching (F3)

    public func togglePin() {
        guard let destination = currentDestination else { return }
        togglePin(for: destination)
    }

    public func togglePin(for category: MetricCategory) {
        togglePin(for: PanelDestination.category(category))
    }

    public func togglePin(for destination: PanelDestination) {
        if pinnedPanels[destination] != nil {
            unpin(destination: destination)
            return
        }

        guard let panel = transientPanel, currentDestination == destination else { return }

        transitionGeneration &+= 1

        // Pinning the currently open transient panel into an independent floating HUD
        panel.destination = destination
        panel.isPinned = true
        removeDismissalMonitors()
        onTransientPanelClosed?()

        pinnedPanels[destination] = panel
        pinnedDestinations.insert(destination)
        transientPanel = nil
        currentDestination = nil
        currentItemID = nil
        currentButton = nil
        isTransientVisible = false
        syncNetworkForegroundProbing()

        let storageKey = destination.storageKey
        if let savedOrigin = preferencesStore?.pinnedOrigin(forDestinationKey: storageKey) {
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
            preferencesStore?.setPinnedOrigin(panel.frame.origin, forDestinationKey: storageKey)
        }

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self = self, let panel = panel else { return }
                self.preferencesStore?.setPinnedOrigin(panel.frame.origin, forDestinationKey: storageKey)
            }
        }
        pinnedMoveObservers[destination] = observer

        panel.onUnpinRequested = { [weak self] in
            self?.unpin(destination: destination)
        }
        panel.onCloseRequested = { [weak self] in
            self?.unpin(destination: destination)
        }
    }

    public func unpin(category: MetricCategory, immediately: Bool = false) {
        unpin(destination: .category(category), immediately: immediately)
    }

    public func unpin(destination: PanelDestination, immediately: Bool = false) {
        guard let panel = pinnedPanels[destination] else { return }

        if let obs = pinnedMoveObservers[destination] {
            NotificationCenter.default.removeObserver(obs)
            pinnedMoveObservers.removeValue(forKey: destination)
        }
        pinnedPanels.removeValue(forKey: destination)
        pinnedDestinations.remove(destination)
        syncNetworkForegroundProbing()

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
        for destination in Array(pinnedPanels.keys) {
            unpin(destination: destination, immediately: immediately)
        }
    }

    // MARK: - Placement & Dynamic Morphing

    /// Resizes the panel for `category` (or `activePanel`) keeping its top edge anchored and clamping to the screen's visible bottom margin.
    public func setContentHeight(_ height: CGFloat, for category: MetricCategory? = nil, animated: Bool = true) {
        setContentHeight(height, for: category.map { PanelDestination.category($0) }, animated: animated)
    }

    public func setContentHeight(_ height: CGFloat, for destination: PanelDestination?, animated: Bool = true) {
        let targetPanel: MetricPanel?
        if let destination {
            if currentDestination == destination, let transient = transientPanel, transient.isVisible {
                targetPanel = transient
            } else {
                targetPanel = pinnedPanels[destination]
            }
        } else {
            targetPanel = activePanel
        }

        guard let panel = targetPanel else { return }
        setContentHeight(height, forPanel: panel, destination: destination, animated: animated)
    }

    private func setContentHeight(_ height: CGFloat, forPanel panel: MetricPanel, destination: PanelDestination?, animated: Bool) {
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

    private func reposition(panel: MetricPanel, anchoredTo anchorFrame: NSRect, targetHeight: CGFloat) {
        let clampedHeight = min(max(targetHeight, 160.0), Instrument.Size.maxHeight)
        var targetFrame = NSRect(
            x: anchorFrame.minX,
            y: anchorFrame.maxY - clampedHeight,
            width: Instrument.Size.panelWidth,
            height: clampedHeight
        )

        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchorFrame) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            targetFrame.origin.x = min(max(targetFrame.origin.x, visible.minX + 8.0), visible.maxX - targetFrame.width - 8.0)
            targetFrame.origin.y = min(max(targetFrame.origin.y, visible.minY + 8.0), visible.maxY - targetFrame.height)
        }

        panel.targetHeight = targetFrame.height
        panel.setFrame(targetFrame, display: true)
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
