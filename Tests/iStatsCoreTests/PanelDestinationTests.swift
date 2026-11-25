import XCTest
@testable import iStatsCore

final class PanelDestinationTests: XCTestCase {
    func testStorageKeys() {
        XCTAssertEqual(PanelDestination.overview.storageKey, "overview")
        for category in MetricCategory.allCases {
            XCTAssertEqual(PanelDestination.category(category).storageKey, category.rawValue)
        }
    }

    func testStorageKeyRoundTrip() {
        let all: [PanelDestination] = [.overview] + MetricCategory.allCases.map { .category($0) }
        for destination in all {
            XCTAssertEqual(PanelDestination(storageKey: destination.storageKey), destination)
        }
        XCTAssertNil(PanelDestination(storageKey: "nonsense"))
        XCTAssertNil(PanelDestination(storageKey: ""))
    }

    func testCodableRoundTripUsesStorageKeyString() throws {
        let wrapper = [PanelDestination.overview, .category(.fan)]
        let data = try JSONEncoder().encode(wrapper)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["overview","fan"]"#)
        XCTAssertEqual(try JSONDecoder().decode([PanelDestination].self, from: data), wrapper)
    }

    func testDecodingUnknownDestinationFails() {
        XCTAssertThrowsError(try JSONDecoder().decode([PanelDestination].self, from: Data(#"["bogus"]"#.utf8)))
    }

    func testCategoryAccessor() {
        XCTAssertNil(PanelDestination.overview.category)
        XCTAssertEqual(PanelDestination.category(.gpu).category, .gpu)
    }

    func testMenuBarAppearanceRawValues() {
        XCTAssertEqual(MenuBarAppearance.allCases.map(\.rawValue), ["monochrome", "statusTint", "categoryColor"])
    }
}
