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

    func testStripOrderIsOverviewThenEnabledCategoriesInAllCasesOrder() {
        let enabled: Set<MetricCategory> = [.power, .cpu, .network]
        XCTAssertEqual(PanelDestination.orderedCategories(enabled: enabled), [.cpu, .network, .power])
        XCTAssertEqual(
            PanelDestination.strip(enabled: enabled),
            [.overview, .category(.cpu), .category(.network), .category(.power)]
        )
        XCTAssertEqual(PanelDestination.strip(enabled: []), [.overview])
        XCTAssertEqual(PanelDestination.strip(enabled: Set(MetricCategory.allCases)).count, 9)
    }

    func testNeighborCyclesFromOverviewThroughCategoriesAndWraps() {
        let order: [MetricCategory] = [.cpu, .memory, .gpu]
        XCTAssertEqual(PanelDestination.overview.neighbor(offset: 1, in: order), .category(.cpu))
        XCTAssertEqual(PanelDestination.category(.cpu).neighbor(offset: 1, in: order), .category(.memory))
        XCTAssertEqual(PanelDestination.category(.gpu).neighbor(offset: 1, in: order), .overview)
        XCTAssertEqual(PanelDestination.overview.neighbor(offset: -1, in: order), .category(.gpu))
        XCTAssertEqual(PanelDestination.category(.memory).neighbor(offset: -1, in: order), .category(.cpu))
        XCTAssertEqual(PanelDestination.category(.cpu).neighbor(offset: -1, in: order), .overview)
    }

    func testNeighborFullCycleReturnsToStartAndLargeOffsetsWrap() {
        let order = MetricCategory.allCases
        var current = PanelDestination.overview
        var visited: [PanelDestination] = []
        for _ in 0..<(order.count + 1) {
            current = current.neighbor(offset: 1, in: order)
            visited.append(current)
        }
        XCTAssertEqual(visited.last, .overview)
        XCTAssertEqual(Set(visited).count, 9)
        XCTAssertEqual(PanelDestination.overview.neighbor(offset: 9, in: order), .overview)
        XCTAssertEqual(PanelDestination.overview.neighbor(offset: -10, in: order), .category(order[order.count - 1]))
    }

    func testNeighborWithNoCategoriesStaysOnOverview() {
        XCTAssertEqual(PanelDestination.overview.neighbor(offset: 1, in: []), .overview)
        XCTAssertEqual(PanelDestination.overview.neighbor(offset: -1, in: []), .overview)
    }

    func testNeighborFromDisabledCategoryBehavesLikeOverview() {
        let order: [MetricCategory] = [.cpu, .memory]
        XCTAssertEqual(PanelDestination.category(.fan).neighbor(offset: 1, in: order), .category(.cpu))
        XCTAssertEqual(PanelDestination.category(.fan).neighbor(offset: -1, in: order), .category(.memory))
    }

    func testMenuBarAppearanceRawValues() {
        XCTAssertEqual(MenuBarAppearance.allCases.map(\.rawValue), ["monochrome", "statusTint", "categoryColor"])
    }
}
