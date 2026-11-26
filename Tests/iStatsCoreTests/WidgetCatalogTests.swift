import XCTest
@testable import iStatsCore

final class WidgetCatalogTests: XCTestCase {
    func testEveryCategoryHasAtLeastOneEntryAndMatchesSupportedStyles() {
        for hasBattery in [true, false] {
            for category in MetricCategory.allCases {
                let entries = WidgetCatalog.entries(for: category, hasBattery: hasBattery)
                let supported = MetricDisplayStyle.supportedStyles(for: category, hasBattery: hasBattery)

                XCTAssertFalse(entries.isEmpty, "\(category) must have at least one catalog entry")
                XCTAssertEqual(
                    entries.map(\.style),
                    supported,
                    "Catalog entries for \(category) (hasBattery=\(hasBattery)) must exactly match supportedStyles"
                )

                // Unique IDs, non-empty metadata, and non-empty sample values
                let ids = entries.map(\.id)
                XCTAssertEqual(Set(ids).count, ids.count, "Catalog entry IDs for \(category) must be unique")
                for entry in entries {
                    XCTAssertEqual(entry.category, category)
                    XCTAssertFalse(entry.title.isEmpty, "Title must not be empty for \(entry.id)")
                    XCTAssertFalse(entry.summary.isEmpty, "Summary must not be empty for \(entry.id)")
                    XCTAssertFalse(entry.sampleValues.isEmpty, "Sample values must not be empty for \(entry.id)")
                }
            }
        }
    }

    func testBatteryOnlyEntriesAreHiddenWithoutBattery() {
        let laptopPower = WidgetCatalog.entries(for: .power, hasBattery: true)
        let desktopPower = WidgetCatalog.entries(for: .power, hasBattery: false)

        XCTAssertTrue(laptopPower.contains(where: { $0.requiresBattery && $0.style == .glyph }))
        XCTAssertFalse(desktopPower.contains(where: { $0.requiresBattery }))
        XCTAssertFalse(desktopPower.contains(where: { $0.style == .glyph }))
        XCTAssertEqual(desktopPower.map(\.style), [.text, .sparkline])
        XCTAssertEqual(desktopPower.first?.title, "Power Draw")
    }

    func testDefaultEntryIsAlwaysSupportedAndPresent() {
        for hasBattery in [true, false] {
            for category in MetricCategory.allCases {
                let def = WidgetCatalog.defaultEntry(for: category, hasBattery: hasBattery)
                let entries = WidgetCatalog.entries(for: category, hasBattery: hasBattery)
                XCTAssertTrue(entries.contains(def), "Default entry for \(category) (hasBattery=\(hasBattery)) must be in entries")
            }
        }
        XCTAssertEqual(WidgetCatalog.defaultEntry(for: .power, hasBattery: true).style, .glyph)
        XCTAssertEqual(WidgetCatalog.defaultEntry(for: .power, hasBattery: false).style, .text)
    }

    func testCatalogEntriesBuildValidWidgetModels() {
        for hasBattery in [true, false] {
            for entry in WidgetCatalog.allEntries(hasBattery: hasBattery) {
                for appearance in MenuBarAppearance.allCases {
                    let config = entry.makeConfig()
                    let snapshot = entry.sampleSnapshot(hasBattery: hasBattery)
                    let model = WidgetModel.make(
                        config: config,
                        snapshot: snapshot,
                        options: WidgetOptions(appearance: appearance)
                    )
                    XCTAssertFalse(model.visualKey.isEmpty, "Visual key must be non-empty for \(entry.id)")
                }
            }
        }
    }
}
