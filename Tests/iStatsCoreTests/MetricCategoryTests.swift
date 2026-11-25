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
        XCTAssertEqual(MetricCategory.power.displayName, "Battery")
    }

    func testCategoryIdentifiable() {
        for category in MetricCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    func testCategorySymbolNames() {
        XCTAssertEqual(MetricCategory.cpu.symbolName, "cpu")
        XCTAssertEqual(MetricCategory.memory.symbolName, "memorychip")
        XCTAssertEqual(MetricCategory.thermal.symbolName, "thermometer.medium")
        XCTAssertEqual(MetricCategory.fan.symbolName, "fan")
        XCTAssertEqual(MetricCategory.gpu.symbolName, "cube.transparent")
        XCTAssertEqual(MetricCategory.network.symbolName, "network")
        XCTAssertEqual(MetricCategory.disk.symbolName, "internaldrive")
        XCTAssertEqual(MetricCategory.power.symbolName(hasBattery: true), "battery.100percent")
        XCTAssertEqual(MetricCategory.power.symbolName(hasBattery: false), "powerplug")
    }

    func testCategoryShortLabels() {
        XCTAssertEqual(MetricCategory.cpu.shortLabel, "CPU")
        XCTAssertEqual(MetricCategory.memory.shortLabel, "MEM")
        XCTAssertEqual(MetricCategory.thermal.shortLabel, "TMP")
        XCTAssertEqual(MetricCategory.fan.shortLabel, "FAN")
        XCTAssertEqual(MetricCategory.gpu.shortLabel, "GPU")
        XCTAssertEqual(MetricCategory.network.shortLabel, "NET")
        XCTAssertEqual(MetricCategory.disk.shortLabel, "SSD")
        XCTAssertEqual(MetricCategory.power.shortLabel(hasBattery: true), "BAT")
        XCTAssertEqual(MetricCategory.power.shortLabel(hasBattery: false), "PWR")
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
