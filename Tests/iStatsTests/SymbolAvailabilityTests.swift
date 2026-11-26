import XCTest
import AppKit
@testable import iStatsCore
@testable import iStats

/// Every symbol the identity table can emit must resolve on the test host (macOS 13 floor in the deployment target).
final class SymbolAvailabilityTests: XCTestCase {
    func testEveryIdentityAndLiveSymbolResolves() {
        var missing: [String] = []
        for category in MetricCategory.allCases {
            var names = Set(category.identity.allSymbols)
            names.insert(category.identity.symbol(hasBattery: true))
            names.insert(category.identity.symbol(hasBattery: false))
            for name in names where NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
                missing.append("\(category.rawValue): \(name)")
            }
        }
        XCTAssertTrue(missing.isEmpty, "Unresolvable SF Symbols: \(missing)")
    }

    func testStatusSymbolsResolve() {
        for level in StatusLevel.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: level.symbolName, accessibilityDescription: nil), level.symbolName)
            XCTAssertNotNil(NSImage(systemSymbolName: level.symbolNameFilled, accessibilityDescription: nil), level.symbolNameFilled)
        }
    }
}
