import XCTest
import SwiftUI
import AppKit
@testable import iStatsCore
@testable import iStats

@MainActor
final class PanelPlacementTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, String) {
        let suiteName = "test.istats.panel.placement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        return (defaults, prefs, suiteName)
    }

    private func cleanup(defaults: UserDefaults, suiteName: String) {
        PanelController.shared.unpinAll(immediately: true)
        PanelController.shared.close(immediately: true)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testBottomMarginClampingWhenPanelHeightExceedsAvailableSpace() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 800)
        // Button near the top, but panel is taller than available room below and cannot flip above
        let buttonRect = CGRect(x: 700, y: 500, width: 40, height: 24)
        let panelSize = CGSize(width: 352, height: 560)

        let result = PanelPlacement.frame(
            for: buttonRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            gap: 6.0,
            margin: 8.0
        )

        XCTAssertGreaterThanOrEqual(result.minY, visibleFrame.minY + 8.0)
        XCTAssertEqual(result.size.width, 352.0)
        XCTAssertEqual(result.size.height, 560.0)
    }

    func testNarrowScreenClampsOriginToLeadingMargin() {
        let visibleFrame = CGRect(x: 100, y: 0, width: 320, height: 800)
        let buttonRect = CGRect(x: 240, y: 776, width: 30, height: 24)
        let panelSize = CGSize(width: 352, height: 300)

        let result = PanelPlacement.frame(
            for: buttonRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            gap: 6.0,
            margin: 8.0
        )

        XCTAssertEqual(result.origin.x, visibleFrame.minX + 8.0)
    }

    func testFirstOpenMeasuresContentHeightBeforeOrderingFront() {
        let (defaults, prefs, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        PanelController.shared.configure(preferences: prefs)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        guard let button = statusItem.button else {
            XCTFail("Expected status bar button")
            return
        }

        // Fixed 284 pt tall SwiftUI view should open directly at 284 pt without an async jump (B5)
        PanelController.shared.show(category: .cpu, relativeTo: button) {
            Color.clear.frame(width: Instrument.Size.panelWidth, height: 284)
        }

        guard let panel = PanelController.shared.transientPanel else {
            XCTFail("Expected transient panel")
            return
        }
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame.height, 284.0, accuracy: 2.0)
    }

    func testFirstOpenClampsTallSwiftUIContentToMaxHeight() {
        let (defaults, prefs, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        PanelController.shared.configure(preferences: prefs)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        guard let button = statusItem.button else {
            XCTFail("Expected status bar button")
            return
        }

        PanelController.shared.show(category: .thermal, relativeTo: button) {
            Color.clear.frame(width: Instrument.Size.panelWidth, height: 900)
        }

        guard let panel = PanelController.shared.transientPanel else {
            XCTFail("Expected transient panel")
            return
        }
        XCTAssertEqual(panel.frame.height, Instrument.Size.maxHeight, accuracy: 2.0)
    }
}
