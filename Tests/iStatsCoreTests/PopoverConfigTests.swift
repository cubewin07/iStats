import XCTest
@testable import iStatsCore

final class PopoverConfigTests: XCTestCase {

    // MARK: - 1. Exhaustive 33 Legacy PopoverStyle Migration Tests

    func testAll33LegacyPopoverStyleValuesMigration() {
        let all33LegacyCases = PopoverStyle.allCases
        XCTAssertEqual(all33LegacyCases.count, 29, "Expected 29 total legacy PopoverStyle cases")

        for legacy in all33LegacyCases {
            let migrated = PopoverConfig.migrated(fromLegacyRawValue: legacy.rawValue, category: .cpu)
            switch legacy {
            case .categoryDefault, .cpuUserSystem, .memoryComposition, .memoryAllocation,
                 .gpuLoadRing, .thermalRing, .fanDualRPM, .fanTachometer, .fanBlades, .fanBars,
                 .networkBars, .diskStorageRing, .diskActivityLEDs, .powerBudget, .powerWattage,
                 .powerChargeRing, .powerBar:
                XCTAssertEqual(migrated.openingTab, .overview, "\(legacy.rawValue) must migrate to .overview")
                if legacy.rawValue.starts(with: "thermal") && legacy != .thermalRing {
                    // component focus
                } else {
                    XCTAssertNil(migrated.focusSource)
                }

            case .thermalCPU:
                XCTAssertEqual(migrated.openingTab, .overview)
                XCTAssertEqual(migrated.focusSource, .cpu)

            case .thermalGPU:
                XCTAssertEqual(migrated.openingTab, .overview)
                XCTAssertEqual(migrated.focusSource, .gpu)

            case .thermalMemory:
                XCTAssertEqual(migrated.openingTab, .overview)
                XCTAssertEqual(migrated.focusSource, .memory)

            case .thermalStorage:
                XCTAssertEqual(migrated.openingTab, .overview)
                XCTAssertEqual(migrated.focusSource, .ssd)

            case .thermalBattery:
                XCTAssertEqual(migrated.openingTab, .overview)
                XCTAssertEqual(migrated.focusSource, .battery)

            case .cpuCluster, .memoryPressure, .gpuEngine, .gpuDie, .networkDiagnostics, .diskStorageTanks:
                XCTAssertEqual(migrated.openingTab, .detail, "\(legacy.rawValue) must migrate to .detail")

            case .history:
                XCTAssertEqual(migrated.openingTab, .history, "history must migrate to .history")
            }
        }
    }

    func testUnknownLegacyRawStringFallsBackToOverview() {
        let unknown = PopoverConfig.migrated(fromLegacyRawValue: "futurePopoverStyleXYZ", category: .memory)
        XCTAssertEqual(unknown.openingTab, .overview)
        XCTAssertTrue(unknown.rememberLastTab)
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
        XCTAssertEqual(PopoverTab.detail.title(for: .network), "Connection")
        XCTAssertEqual(PopoverTab.detail.title(for: .disk), "Volumes")
        XCTAssertEqual(PopoverTab.detail.title(for: .power), "Health")
    }

    // MARK: - 3. Supported Tabs per Category

    func testSupportedTabs() {
        // Fans only has 2 tabs: Overview · History
        XCTAssertEqual(PopoverTab.supportedTabs(for: .fan), [.overview, .history])

        // Power has 3 tabs on laptop (with battery), 2 tabs on desktop (no battery)
        XCTAssertEqual(PopoverTab.supportedTabs(for: .power, hasBattery: true), [.overview, .detail, .history])
        XCTAssertEqual(PopoverTab.supportedTabs(for: .power, hasBattery: false), [.overview, .history])

        // Other categories have 3 tabs
        for cat in [MetricCategory.cpu, .memory, .gpu, .thermal, .network, .disk] {
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
        XCTAssertEqual(item.popover?.rememberLastTab, false)
        XCTAssertEqual(item.popover?.focusSource, .gpu)
    }
}
