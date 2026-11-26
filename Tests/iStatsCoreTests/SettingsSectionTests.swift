import XCTest
@testable import iStatsCore

final class SettingsSectionTests: XCTestCase {

    func testStorageKeyRoundTripForEverySection() {
        for section in SettingsSection.allSections() {
            XCTAssertEqual(SettingsSection(storageKey: section.storageKey), section, section.storageKey)
        }
    }

    func testStorageKeysAreUnique() {
        let keys = SettingsSection.allSections().map(\.storageKey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testCategoryKeysAreMetricCategoryRawValues() {
        for category in MetricCategory.allCases {
            XCTAssertEqual(SettingsSection.category(category).storageKey, category.rawValue)
            XCTAssertEqual(SettingsSection(storageKey: category.rawValue), .category(category))
        }
    }

    func testAlertsIsAliasForNotifications() {
        XCTAssertEqual(SettingsSection(storageKey: "alerts"), .notifications)
        XCTAssertEqual(SettingsSection.resolved(storageKey: "alerts"), .notifications)
        XCTAssertEqual(SettingsSection.notifications.storageKey, "notifications")
    }

    func testUnknownAndStaleKeysFallBackToGeneral() {
        XCTAssertNil(SettingsSection(storageKey: "banana"))
        XCTAssertNil(SettingsSection(storageKey: ""))
        XCTAssertEqual(SettingsSection.resolved(storageKey: "banana"), .general)
        XCTAssertEqual(SettingsSection.resolved(storageKey: nil), .general)
        XCTAssertEqual(SettingsSection.resolved(storageKey: ""), .general)
    }

    func testGroupOrderingMatchesSidebar() {
        let groups = SettingsSection.groups()
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0], [.general, .appearance, .menuBar])
        XCTAssertEqual(groups[1], MetricCategory.allCases.map { SettingsSection.category($0) })
        XCTAssertEqual(groups[1].count, 8)
        XCTAssertEqual(groups[2], [.notifications, .about])
        XCTAssertEqual(SettingsSection.allSections(), groups.flatMap { $0 })
    }

    func testActiveCategoriesFilterTheCategoryGroupOnly() {
        let groups = SettingsSection.groups(activeCategories: [.cpu, .network])
        XCTAssertEqual(groups[1], [.category(.cpu), .category(.network)])
        XCTAssertEqual(groups[0].count, 3)
        XCTAssertEqual(groups[2].count, 2)
    }

    func testPowerPageIsAlwaysPresentAndLabelledByBattery() {
        let withBattery = SettingsSection.allSections(hasBattery: true)
        let without = SettingsSection.allSections(hasBattery: false)
        XCTAssertTrue(withBattery.contains(.category(.power)))
        XCTAssertTrue(without.contains(.category(.power)))
        XCTAssertEqual(SettingsSection.category(.power).title(hasBattery: true), "Battery")
        XCTAssertEqual(SettingsSection.category(.power).title(hasBattery: false), "Power")
    }

    func testTitlesAndSymbolsAreNonEmpty() {
        for section in SettingsSection.allSections() {
            XCTAssertFalse(section.title().isEmpty)
            XCTAssertFalse(section.symbolName().isEmpty)
        }
    }

    func testIdentifiableIDMatchesStorageKey() {
        XCTAssertEqual(SettingsSection.menuBar.id, "menuBar")
        XCTAssertEqual(SettingsSection.category(.gpu).id, "gpu")
    }

    func testPersistsThroughPreferencesStore() {
        let suite = "test.istats.settingssection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(SettingsSection.resolved(storageKey: store.lastSettingsSection), .general)
        store.lastSettingsSection = SettingsSection.category(.disk).storageKey
        let reloaded = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(SettingsSection.resolved(storageKey: reloaded.lastSettingsSection), .category(.disk))
    }

    func testDeepLinkNotificationConstants() {
        XCTAssertEqual(SettingsSection.openNotificationName.rawValue, "iStats.openSettingsSection")
        XCTAssertEqual(SettingsSection.deepLinkUserInfoKey, "section")
    }
}

final class TemperatureThresholdScaleTests: XCTestCase {

    func testCelsiusIsIdentityOnValidValues() {
        for value in stride(from: 60.0, through: 105.0, by: 5.0) {
            XCTAssertEqual(TemperatureThresholdScale.displayValue(celsius: value, unit: .celsius), value)
            XCTAssertEqual(TemperatureThresholdScale.celsius(fromDisplay: value, unit: .celsius), value, accuracy: 1e-9)
        }
    }

    func testFahrenheitStepsAreRoundDisplayValuesThatConvertBack() {
        let unit = Units.TemperatureUnit.fahrenheit
        let range = TemperatureThresholdScale.range(unit: unit)
        let step = TemperatureThresholdScale.step(unit: unit)
        var display = range.lowerBound
        while display <= range.upperBound {
            let celsius = TemperatureThresholdScale.celsius(fromDisplay: display, unit: unit)
            XCTAssertTrue(AlertKind.temperature.thresholdRange.contains(celsius), "\(display)F -> \(celsius)C")
            XCTAssertEqual(TemperatureThresholdScale.displayValue(celsius: celsius, unit: unit), display, accuracy: 1e-9)
            display += step
        }
    }

    func testFahrenheitEndpointsMatchCelsiusEndpoints() {
        XCTAssertEqual(TemperatureThresholdScale.celsius(fromDisplay: 140, unit: .fahrenheit), 60.0, accuracy: 1e-9)
        XCTAssertEqual(TemperatureThresholdScale.celsius(fromDisplay: 220, unit: .fahrenheit), 104.444, accuracy: 0.001)
        XCTAssertEqual(TemperatureThresholdScale.displayValue(celsius: 85, unit: .fahrenheit), 185, accuracy: 1e-9)
    }

    func testOutOfRangeInputIsClamped() {
        XCTAssertEqual(TemperatureThresholdScale.celsius(fromDisplay: 0, unit: .fahrenheit), 60.0, accuracy: 1e-9)
        XCTAssertEqual(TemperatureThresholdScale.celsius(fromDisplay: 500, unit: .celsius), 105.0, accuracy: 1e-9)
    }
}

final class DiagnosticsReportTests: XCTestCase {

    private func report(_ availability: [MetricCategory: Availability]) -> DiagnosticsReport {
        DiagnosticsReport(
            appVersion: "1.2.3", build: "45", hardwareModel: "Mac14,2",
            architecture: "arm64", osVersion: "Version 14.5 (Build 23F79)",
            availability: availability
        )
    }

    func testRenderListsModelOSAndEverySampler() {
        let text = report([.cpu: .available, .fan: .unavailable(reason: "no fans")]).render()
        XCTAssertTrue(text.contains("App: 1.2.3 (45)"))
        XCTAssertTrue(text.contains("Mac: Mac14,2 (arm64)"))
        XCTAssertTrue(text.contains("macOS: Version 14.5 (Build 23F79)"))
        XCTAssertTrue(text.contains("cpu: available"))
        XCTAssertTrue(text.contains("fan: unavailable (no fans)"))
        XCTAssertTrue(text.contains("gpu: no reading yet"))
        for category in MetricCategory.allCases {
            XCTAssertTrue(text.contains("  \(category.rawValue):"), category.rawValue)
        }
    }

    func testCurrentReportReadsHardwareModelWithoutCrashing() {
        let current = DiagnosticsReport.current(availability: [:])
        XCTAssertFalse(current.hardwareModel.isEmpty)
        XCTAssertFalse(current.render().isEmpty)
    }
}
