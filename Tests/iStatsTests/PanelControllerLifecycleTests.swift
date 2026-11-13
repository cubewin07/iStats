import XCTest
import SwiftUI
import AppKit
@testable import iStatsCore
@testable import iStats

@MainActor
final class PanelControllerLifecycleTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.panel.lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        return (defaults, prefs, coord, suiteName)
    }

    private func cleanup(defaults: UserDefaults, suiteName: String) {
        PanelController.shared.animateInTests = false
        PanelController.shared.unpinAll(immediately: true)
        PanelController.shared.close(immediately: true)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPersistentHostReusesBackgroundAndHostingViewAcrossCategorySwitches() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        PanelController.shared.configure(preferences: prefs)
        let item1 = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let item2 = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(item1)
            NSStatusBar.system.removeStatusItem(item2)
        }
        guard let btn1 = item1.button, let btn2 = item2.button else {
            XCTFail("Expected status bar buttons")
            return
        }

        PanelController.shared.show(category: .cpu, relativeTo: btn1) {
            Text("CPU")
        }
        guard let panel = PanelController.shared.transientPanel else {
            XCTFail("Expected transient panel")
            return
        }
        let bgID = ObjectIdentifier(panel.backgroundContainer)
        let hostID = ObjectIdentifier(panel.hostingView)
        XCTAssertTrue(panel.hostingView.sizingOptions.isEmpty, "sizingOptions must be [] so Auto Layout does not fight animated frames")

        PanelController.shared.show(category: .memory, relativeTo: btn2) {
            Text("Memory")
        }
        guard let switchedPanel = PanelController.shared.transientPanel else {
            XCTFail("Expected transient panel after switch")
            return
        }
        XCTAssertTrue(switchedPanel === panel)
        XCTAssertEqual(ObjectIdentifier(switchedPanel.backgroundContainer), bgID)
        XCTAssertEqual(ObjectIdentifier(switchedPanel.hostingView), hostID)
    }

    func testCloseClearsHostedRootAndFiresOnDisappear() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        PanelController.shared.configure(preferences: prefs)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        guard let button = statusItem.button else {
            XCTFail("Expected status bar button")
            return
        }

        var appearCount = 0
        var disappearCount = 0

        struct ProbeView: View {
            let onAppearAction: () -> Void
            let onDisappearAction: () -> Void
            var body: some View {
                Text("Probe")
                    .frame(width: Instrument.Size.panelWidth, height: 200)
                    .onAppear(perform: onAppearAction)
                    .onDisappear(perform: onDisappearAction)
            }
        }

        PanelController.shared.show(category: .cpu, relativeTo: button) {
            ProbeView(
                onAppearAction: { appearCount += 1 },
                onDisappearAction: { disappearCount += 1 }
            )
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(appearCount, 1)
        XCTAssertEqual(disappearCount, 0)

        PanelController.shared.close(immediately: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(disappearCount, 1, "Closing panel must swap rootView to EmptyView so onDisappear fires")
    }

    func testShowDuringFadeOutKeepsPanelVisibleAndCancelsStaleCloseTeardown() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        PanelController.shared.configure(preferences: prefs)
        PanelController.shared.animateInTests = true

        let item1 = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let item2 = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(item1)
            NSStatusBar.system.removeStatusItem(item2)
        }
        guard let btn1 = item1.button, let btn2 = item2.button else {
            XCTFail("Expected status bar buttons")
            return
        }

        PanelController.shared.show(category: .cpu, relativeTo: btn1) {
            Text("CPU")
        }
        guard let originalPanel = PanelController.shared.transientPanel else {
            XCTFail("Expected transient panel")
            return
        }
        XCTAssertTrue(originalPanel.isVisible)

        // Start async 0.12s fade-out close
        PanelController.shared.close()
        XCTAssertTrue(originalPanel.isVisible, "Panel stays visible during async fade-out")

        // Immediately show another category mid-fade-out (B1 race)
        PanelController.shared.show(category: .memory, relativeTo: btn2) {
            Text("Memory")
        }

        // Wait past the 0.12s fade-out duration so the stale close completion handler has fired
        let exp = expectation(description: "Wait past stale fade-out completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(originalPanel.isVisible, "Stale close teardown must not orderOut panel after show()")
        XCTAssertEqual(originalPanel.alphaValue, 1.0, accuracy: 0.02, "show() during fade-out must restore alpha to 1.0")
        XCTAssertTrue(PanelController.shared.isTransientPanelOpen(for: .memory))
        XCTAssertTrue(PanelController.shared.transientPanel === originalPanel)
    }

    func testHoverOntoPinnedCategoryClosesTransientAndCreatesNoSecondTransient() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        PanelController.shared.configure(preferences: prefs)
        let cpuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let memItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(cpuItem)
            NSStatusBar.system.removeStatusItem(memItem)
        }
        guard let cpuButton = cpuItem.button, let memButton = memItem.button else {
            XCTFail("Expected status bar buttons")
            return
        }

        // 1. Open and pin CPU
        PanelController.shared.show(category: .cpu, relativeTo: cpuButton) {
            Text("CPU")
        }
        PanelController.shared.togglePin(for: .cpu)
        XCTAssertTrue(PanelController.shared.isPinned(for: .cpu))

        // 2. Open transient Memory panel
        PanelController.shared.show(category: .memory, relativeTo: memButton) {
            Text("Memory")
        }
        XCTAssertTrue(PanelController.shared.isTransientPanelOpen(for: .memory))

        // 3. Hover onto CPU (already pinned): must close transient Memory and create NO CPU transient (B6)
        PanelController.shared.handleStatusItemHover(category: .cpu, button: cpuButton) {
            Text("CPU Transient")
        }

        XCTAssertFalse(PanelController.shared.isTransientPanelOpen(for: .cpu))
        XCTAssertFalse(PanelController.shared.isTransientPanelOpen())
        XCTAssertNil(PanelController.shared.transientPanel)
        XCTAssertTrue(PanelController.shared.isPinned(for: .cpu))
    }

    func testShowOnPinnedCategoryClosesTransientAndFrontsPinned() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        PanelController.shared.configure(preferences: prefs)
        let cpuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let memItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(cpuItem)
            NSStatusBar.system.removeStatusItem(memItem)
        }
        guard let cpuButton = cpuItem.button, let memButton = memItem.button else {
            XCTFail("Expected status bar buttons")
            return
        }

        PanelController.shared.show(category: .cpu, relativeTo: cpuButton) { Text("CPU") }
        PanelController.shared.togglePin(for: .cpu)

        PanelController.shared.show(category: .memory, relativeTo: memButton) { Text("Memory") }
        XCTAssertTrue(PanelController.shared.isTransientPanelOpen(for: .memory))

        PanelController.shared.show(category: .cpu, relativeTo: cpuButton) { Text("CPU Transient") }
        XCTAssertNil(PanelController.shared.transientPanel)
        XCTAssertTrue(PanelController.shared.isPinned(for: .cpu))
    }

    func testHeightPreferenceResizesTopAnchoredAndClampsToScreen() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        PanelController.shared.configure(preferences: prefs)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        guard let button = statusItem.button else {
            XCTFail("Expected status bar button")
            return
        }

        PanelController.shared.show(category: .cpu, relativeTo: button) {
            Color.clear.frame(width: Instrument.Size.panelWidth, height: 220)
        }

        guard let panel = PanelController.shared.transientPanel else {
            XCTFail("Expected transient panel")
            return
        }
        // In headless SwiftPM test runs, status bar buttons can sit at y=0, leaving < 360 pt above minY.
        // Position the panel near the top of visibleFrame so both an unclamped resize and screen-bottom clamp are exercised.
        if let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first {
            let topFrame = NSRect(
                x: panel.frame.origin.x,
                y: screen.visibleFrame.maxY - 226.0,
                width: panel.frame.width,
                height: 220.0
            )
            panel.setFrame(topFrame, display: false)
        }
        let initialMaxY = panel.frame.maxY
        XCTAssertEqual(panel.frame.height, 220.0, accuracy: 2.0)

        // Resize taller (360 pt): top edge maxY must remain stationary
        PanelController.shared.setContentHeight(360.0, for: .cpu, animated: false)
        XCTAssertEqual(panel.frame.maxY, initialMaxY, accuracy: 0.5, "Top edge must stay anchored during height resize")
        XCTAssertEqual(panel.frame.height, 360.0, accuracy: 2.0)

        // Resize past maxHeight (2000 pt): clamped to Instrument.Size.maxHeight and visible bottom margin
        PanelController.shared.setContentHeight(2000.0, for: .cpu, animated: false)
        XCTAssertEqual(panel.frame.maxY, initialMaxY, accuracy: 0.5, "Top edge must stay anchored when clamped")
        XCTAssertLessThanOrEqual(panel.frame.height, Instrument.Size.maxHeight + 0.5)
        if let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first {
            XCTAssertGreaterThanOrEqual(panel.frame.minY, screen.visibleFrame.minY + 8.0 - 0.5)
        }
    }

    func testMenuBarControllerInjectsStatusItemHitTestClosure() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let cpuItem = MenuBarItemConfig(category: .cpu, style: .gauge)
        let memItem = MenuBarItemConfig(category: .memory, style: .bar)
        prefs.menuBarItems = [cpuItem, memItem]

        let menuController = MenuBarController(preferences: prefs, coordinator: coord)
        menuController.syncStatusItems()

        guard let memButton = menuController.statusItems[memItem.id]?.button,
              let memWindow = memButton.window else {
            XCTFail("Expected Memory status item button with window")
            return
        }

        let memRect = memWindow.convertToScreen(memButton.convert(memButton.bounds, to: nil))
        let memCenter = NSPoint(x: memRect.midX, y: memRect.midY)

        XCTAssertTrue(menuController.containsStatusItem(at: memCenter))
        XCTAssertEqual(PanelController.shared.statusItemHitTest?(memCenter), true)
        XCTAssertEqual(PanelController.shared.statusItemHitTest?(NSPoint(x: -5000, y: -5000)), false)
    }

    func testPinRestoresSavedOriginAndUnpinClearsPanel() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let saved = CGPoint(x: 220, y: 340)
        prefs.setPinnedOrigin(saved, for: .cpu)
        PanelController.shared.configure(preferences: prefs)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        guard let button = statusItem.button else {
            XCTFail("Expected status bar button")
            return
        }

        PanelController.shared.show(category: .cpu, relativeTo: button) {
            Text("CPU")
        }
        PanelController.shared.togglePin(for: .cpu)

        guard let pinned = PanelController.shared.pinnedPanels[.cpu] else {
            XCTFail("Expected pinned CPU panel")
            return
        }
        if let main = NSScreen.main, main.visibleFrame.intersects(CGRect(origin: saved, size: pinned.frame.size)) {
            XCTAssertEqual(pinned.frame.origin.x, saved.x, accuracy: 1.0)
            XCTAssertEqual(pinned.frame.origin.y, saved.y, accuracy: 1.0)
        }

        PanelController.shared.unpin(category: .cpu)
        XCTAssertFalse(PanelController.shared.isPinned(for: .cpu))
        XCTAssertFalse(pinned.isVisible)
    }
}
