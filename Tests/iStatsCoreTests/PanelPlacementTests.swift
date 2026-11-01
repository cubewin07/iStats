import XCTest
import CoreGraphics
import iStatsCore

final class PanelPlacementTests: XCTestCase {

    func testCenteredBelowStatusItem() {
        // Standard macOS 16-inch display (3456x2234 at 2x scaling: 1728x1117)
        // Menu bar height = 24 pt, visibleFrame height = 1093 pt (y: 0 to 1093)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1093)
        // Status button at x: 800, width: 40, y: 1093 (menu bar height 24, y: 1093 to 1117)
        let buttonRect = CGRect(x: 800, y: 1093, width: 40, height: 24)
        let panelSize = CGSize(width: 352, height: 400)

        let result = PanelPlacement.frame(
            for: buttonRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            gap: 6.0,
            margin: 8.0
        )

        // MidX of button is 820. Panel width is 352 -> x = 820 - 176 = 644
        XCTAssertEqual(result.origin.x, 644.0)
        // Top edge of panel should be buttonRect.minY - gap = 1093 - 6 = 1087
        // So y = 1087 - 400 = 687
        XCTAssertEqual(result.origin.y, 687.0)
        XCTAssertEqual(result.size.width, 352.0)
        XCTAssertEqual(result.size.height, 400.0)
    }

    func testLeftEdgeClamping() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1093)
        // Status button on extreme left edge
        let buttonRect = CGRect(x: 10, y: 1093, width: 30, height: 24)
        let panelSize = CGSize(width: 352, height: 400)

        let result = PanelPlacement.frame(
            for: buttonRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            gap: 6.0,
            margin: 8.0
        )

        // Clamped to visibleFrame.minX + margin = 8.0
        XCTAssertEqual(result.origin.x, 8.0)
        XCTAssertEqual(result.origin.y, 687.0)
    }

    func testRightEdgeClamping() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1093)
        // Status button on extreme right near Control Center
        let buttonRect = CGRect(x: 1700, y: 1093, width: 20, height: 24)
        let panelSize = CGSize(width: 352, height: 400)

        let result = PanelPlacement.frame(
            for: buttonRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            gap: 6.0,
            margin: 8.0
        )

        // Clamped to visibleFrame.maxX - margin - width = 1728 - 8 - 352 = 1368.0
        XCTAssertEqual(result.origin.x, 1368.0)
        XCTAssertEqual(result.origin.y, 687.0)
    }

    func testMultiDisplaySecondaryMonitor() {
        // Secondary display placed to the right: x: 1920, width: 2560, y: 0, height: 1440
        let visibleFrame = CGRect(x: 1920, y: 0, width: 2560, height: 1416)
        let buttonRect = CGRect(x: 2500, y: 1416, width: 30, height: 24)
        let panelSize = CGSize(width: 352, height: 450)

        let result = PanelPlacement.frame(
            for: buttonRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            gap: 6.0,
            margin: 8.0
        )

        // MidX = 2515. x = 2515 - 176 = 2339
        XCTAssertEqual(result.origin.x, 2339.0)
        // y = 1416 - 6 - 450 = 960
        XCTAssertEqual(result.origin.y, 960.0)
    }

    func testFlipsAboveWhenInsufficientSpaceBelow() {
        // Bottom-positioned dock / bar scenario:
        let visibleFrame = CGRect(x: 0, y: 100, width: 1000, height: 800)
        // Button is low down at y: 120 (only 20 pt available below)
        let buttonRect = CGRect(x: 400, y: 120, width: 50, height: 30)
        let panelSize = CGSize(width: 352, height: 300)

        let result = PanelPlacement.frame(
            for: buttonRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            gap: 6.0,
            margin: 8.0
        )

        // Should place above: y = buttonRect.maxY + gap = 150 + 6 = 156
        XCTAssertEqual(result.origin.y, 156.0)
        XCTAssertEqual(result.origin.x, 249.0) // 425 - 176
    }
}
