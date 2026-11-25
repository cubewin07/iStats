import XCTest
@testable import iStatsCore

final class PopoverConfigTests: XCTestCase {

    // MARK: - 1. Exhaustive Legacy PopoverStyle Raw Value Migration Tests

    /// The removed `PopoverStyle` enum's raw values: still decoded from pre-v2 data.
    private static let legacyOverview = [
        "categoryDefault", "cpuUserSystem", "memoryComposition", "memoryAllocation",
        "gpuLoadRing", "thermalRing", "fanDualRPM", "fanTachometer", "fanBlades", "fanBars",
        "networkBars", "diskStorageRing", "diskActivityLEDs", "powerBudget", "powerWattage",
        "powerChargeRing", "powerBar"
    ]
    private static let legacyDetail = [
        "cpuCluster", "memoryPressure", "gpuEngine", "gpuDie", "networkDiagnostics", "diskStorageTanks"
    ]
    private static let legacyThermalFocus: [String: MetricSource] = [
        "thermalCPU": .cpu, "thermalGPU": .gpu, "thermalMemory": .memory,
        "thermalStorage": .ssd, "thermalBattery": .battery
    ]

    func testAllLegacyPopoverStyleValuesMigration() {
        let total = Self.legacyOverview.count + Self.legacyDetail.count + Self.legacyThermalFocus.count + 1
        XCTAssertEqual(total, 29, "Expected 29 total legacy PopoverStyle raw values")

        for raw in Self.legacyOverview {
            let migrated = PopoverConfig.migrated(fromLegacyRawValue: raw, category: .cpu)
            XCTAssertEqual(migrated.openingTab, .overview, "\(raw) must migrate to .overview")
            XCTAssertNil(migrated.focusSource)
        }
        for raw in Self.legacyDetail {
            XCTAssertEqual(PopoverConfig.migrated(fromLegacyRawValue: raw, category: .cpu).openingTab, .detail, "\(raw) must migrate to .detail")
        }
        for (raw, source) in Self.legacyThermalFocus {
            let migrated = PopoverConfig.migrated(fromLegacyRawValue: raw, category: .thermal)
            XCTAssertEqual(migrated.openingTab, .overview)
            XCTAssertEqual(migrated.focusSource, source)
        }
        XCTAssertEqual(PopoverConfig.migrated(fromLegacyRawValue: "history", category: .cpu).openingTab, .history)
    }

    func testUnknownLegacyRawStringFallsBackToOverview() {
        let unknown = PopoverConfig.migrated(fromLegacyRawValue: "futurePopoverStyleXYZ", category: .memory)
        XCTAssertEqual(unknown.openingTab, .overview)
    }

    // MARK: - 2. PopoverTab Titles

    func testPopoverTabTitlesAcrossCategories() {
        // Overview & History are uniform
        for cat in MetricCategory.allCases {
            XCTAssertEqual(PopoverTab.overview.title(for: cat), "Overview")
            XCTAssertEqual(PopoverTab.history.title(for: cat), "History")
        }

        // Detail tab is category-specific
        XCTAssertEqual(PopoverTab.detail.title(for: .cpu), "Cores")
        XCTAssertEqual(PopoverTab.detail.title(for: .memory), "Pressure")
        XCTAssertEqual(PopoverTab.detail.title(for: .gpu, hasDetailedGPUEngines: true), "Engines")
        XCTAssertEqual(PopoverTab.detail.title(for: .gpu, hasDetailedGPUEngines: false), "Device")
        XCTAssertEqual(PopoverTab.detail.title(for: .thermal), "Sensors")
        XCTAssertEqual(PopoverTab.detail.title(for: .fan), "Fans")
        XCTAssertEqual(PopoverTab.detail.title(for: .network), "Connection")
        XCTAssertEqual(PopoverTab.detail.title(for: .disk), "Volumes")
        XCTAssertEqual(PopoverTab.detail.title(for: .power), "Health")
    }

    // MARK: - 3. Supported Tabs per Category

    func testSupportedTabs() {
        // Power has 3 tabs on laptop (with battery), 2 tabs on desktop (no battery)
        XCTAssertEqual(PopoverTab.supportedTabs(for: .power, hasBattery: true), [.overview, .detail, .history])
        XCTAssertEqual(PopoverTab.supportedTabs(for: .power, hasBattery: false), [.overview, .history])

        // All other categories (including Fan with its hardware Details table) have 3 tabs
        for cat in [MetricCategory.cpu, .memory, .gpu, .thermal, .fan, .network, .disk] {
            XCTAssertEqual(PopoverTab.supportedTabs(for: cat), [.overview, .detail, .history])
        }
    }

    // MARK: - 4. Decode JSON with Legacy popoverStyle Key

    func testDecodeJSONWithLegacyPopoverStyleKey() throws {
        let json = """
        {
            "category": "cpu",
            "style": "gauge",
            "popoverStyle": "cpuCluster"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(MenuBarItemConfig.self, from: json)
        XCTAssertEqual(item.category, .cpu)
        XCTAssertEqual(item.style, .gauge)
        XCTAssertNotNil(item.popover)
        XCTAssertEqual(item.popover?.openingTab, .detail)
    }

    func testDecodeJSONWithDirectPopoverConfig() throws {
        let json = """
        {
            "category": "thermal",
            "style": "text",
            "source": "gpu",
            "popover": {
                "openingTab": "overview",
                "rememberLastTab": false,
                "focusSource": "gpu"
            }
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(MenuBarItemConfig.self, from: json)
        XCTAssertEqual(item.category, .thermal)
        XCTAssertEqual(item.style, .text)
        XCTAssertEqual(item.source, .gpu)
        XCTAssertEqual(item.popover?.openingTab, .overview)

        // `rememberLastTab` is decoded-and-ignored; it is never written back.
        let encoded = try JSONEncoder().encode(item.popover)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("rememberLastTab"))
        XCTAssertEqual(item.popover?.focusSource, .gpu)
    }
}
