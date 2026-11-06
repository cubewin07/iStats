import XCTest
import CoreGraphics
@testable import iStatsCore

final class MenuBarOrderingTests: XCTestCase {
    private func rect(_ x: CGFloat, width: CGFloat = 50, y: CGFloat = 0) -> CGRect {
        CGRect(x: x, y: y, width: width, height: 24)
    }

    func testObservedOrderSortsLeftToRight() {
        let order = MenuBarOrdering.observedOrder(frames: [("c", rect(200)), ("a", rect(0)), ("b", rect(100))])
        XCTAssertEqual(order, ["a", "b", "c"])
    }

    func testObservedOrderRejectsStackedItems() {
        XCTAssertNil(MenuBarOrdering.observedOrder(frames: [("a", rect(556)), ("b", rect(556))]))
        XCTAssertNil(MenuBarOrdering.observedOrder(frames: [("a", rect(278, width: 64)), ("b", rect(277, width: 65))]))
    }

    func testObservedOrderRejectsUnusableLayouts() {
        XCTAssertNil(MenuBarOrdering.observedOrder(frames: [("a", rect(0))]), "single item")
        XCTAssertNil(MenuBarOrdering.observedOrder(frames: [("a", rect(0, width: 0)), ("b", rect(100))]), "zero width")
        XCTAssertNil(MenuBarOrdering.observedOrder(frames: [("a", rect(0, y: 0)), ("b", rect(100, y: 900))]), "two displays")
    }
}
