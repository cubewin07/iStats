import XCTest
@testable import iStatsCore

final class MetricCategoryTests: XCTestCase {

    func testAllCategoriesPresent() {
        let all = MetricCategory.allCases
        XCTAssertEqual(all.count, 8)
        XCTAssertTrue(all.contains(.cpu))
        XCTAssertTrue(all.contains(.memory))
        XCTAssertTrue(all.contains(.thermal))
        XCTAssertTrue(all.contains(.fan))
        XCTAssertTrue(all.contains(.gpu))
        XCTAssertTrue(all.contains(.network))
        XCTAssertTrue(all.contains(.disk))
        XCTAssertTrue(all.contains(.power))
    }

    func testCategoryDisplayNames() {
        XCTAssertEqual(MetricCategory.cpu.displayName, "CPU")
        XCTAssertEqual(MetricCategory.memory.displayName, "Memory")
        XCTAssertEqual(MetricCategory.thermal.displayName, "Temperature")
        XCTAssertEqual(MetricCategory.fan.displayName, "Fans")
        XCTAssertEqual(MetricCategory.gpu.displayName, "GPU")
        XCTAssertEqual(MetricCategory.network.displayName, "Network")
        XCTAssertEqual(MetricCategory.disk.displayName, "Disk")
        XCTAssertEqual(MetricCategory.power.displayName, "Battery & Power")
    }

    func testCategoryIdentifiable() {
        for category in MetricCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    func testCategoryCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for category in MetricCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(MetricCategory.self, from: data)
            XCTAssertEqual(category, decoded)
        }
    }
}
