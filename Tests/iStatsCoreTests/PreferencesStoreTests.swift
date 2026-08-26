import XCTest
@testable import iStatsCore

final class PreferencesStoreTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "iStats.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        super.tearDown()
    }

    func testDefaultValues() {
        let store = PreferencesStore(userDefaults: testDefaults)

        XCTAssertEqual(store.refreshInterval, 2.0)
        XCTAssertEqual(PreferencesStore.minRefreshInterval, 0.5)
        XCTAssertEqual(PreferencesStore.maxRefreshInterval, 60.0)
        XCTAssertEqual(PreferencesStore.defaultRefreshInterval, 2.0)

        XCTAssertEqual(store.enabledCategories, Set(MetricCategory.allCases))
        XCTAssertEqual(store.temperatureUnit, .celsius)
        XCTAssertEqual(store.networkUnit, .bytesPerSecond)
        XCTAssertEqual(store.byteUnitStandard, .iec)
        XCTAssertFalse(store.showDockIcon)
        XCTAssertFalse(store.launchAtLogin)
    }

    func testRefreshIntervalClampingLowerBound() {
        let store = PreferencesStore(userDefaults: testDefaults)

        store.refreshInterval = 0.1
        XCTAssertEqual(store.refreshInterval, PreferencesStore.minRefreshInterval)

        store.refreshInterval = -10.0
        XCTAssertEqual(store.refreshInterval, PreferencesStore.minRefreshInterval)

        store.refreshInterval = 0.0
        XCTAssertEqual(store.refreshInterval, PreferencesStore.minRefreshInterval)

        store.refreshInterval = 0.5
        XCTAssertEqual(store.refreshInterval, 0.5)
    }

    func testRefreshIntervalClampingUpperBound() {
        let store = PreferencesStore(userDefaults: testDefaults)

        store.refreshInterval = 65.0
        XCTAssertEqual(store.refreshInterval, PreferencesStore.maxRefreshInterval)

        store.refreshInterval = 1000.0
        XCTAssertEqual(store.refreshInterval, PreferencesStore.maxRefreshInterval)

        store.refreshInterval = 60.0
        XCTAssertEqual(store.refreshInterval, 60.0)
    }

    func testRefreshIntervalValidValues() {
        let store = PreferencesStore(userDefaults: testDefaults)

        store.refreshInterval = 1.0
        XCTAssertEqual(store.refreshInterval, 1.0)

        store.refreshInterval = 5.5
        XCTAssertEqual(store.refreshInterval, 5.5)

        store.refreshInterval = 30.0
        XCTAssertEqual(store.refreshInterval, 30.0)
    }

    func testPersistenceAcrossInstances() {
        let store1 = PreferencesStore(userDefaults: testDefaults)
        store1.refreshInterval = 4.5
        store1.temperatureUnit = .fahrenheit
        store1.networkUnit = .bitsPerSecond
        store1.byteUnitStandard = .si
        store1.showDockIcon = true
        store1.launchAtLogin = true
        store1.setCategory(.gpu, isEnabled: false)
        store1.setCategory(.thermal, isEnabled: false)

        // Create a new instance backed by the same UserDefaults suite
        let store2 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store2.refreshInterval, 4.5)
        XCTAssertEqual(store2.temperatureUnit, .fahrenheit)
        XCTAssertEqual(store2.networkUnit, .bitsPerSecond)
        XCTAssertEqual(store2.byteUnitStandard, .si)
        XCTAssertTrue(store2.showDockIcon)
        XCTAssertTrue(store2.launchAtLogin)
        XCTAssertFalse(store2.isCategoryEnabled(.gpu))
        XCTAssertFalse(store2.isCategoryEnabled(.thermal))
        XCTAssertTrue(store2.isCategoryEnabled(.cpu))
        XCTAssertTrue(store2.isCategoryEnabled(.memory))
    }

    func testCategoryEnablementToggling() {
        let store = PreferencesStore(userDefaults: testDefaults)

        XCTAssertTrue(store.isCategoryEnabled(.cpu))
        store.setCategory(.cpu, isEnabled: false)
        XCTAssertFalse(store.isCategoryEnabled(.cpu))

        store.toggleCategory(.cpu)
        XCTAssertTrue(store.isCategoryEnabled(.cpu))

        store.toggleCategory(.cpu)
        XCTAssertFalse(store.isCategoryEnabled(.cpu))
    }

    func testUnitsDisplayNamesAndSymbols() {
        XCTAssertEqual(Units.TemperatureUnit.celsius.symbol, "°C")
        XCTAssertEqual(Units.TemperatureUnit.fahrenheit.symbol, "°F")
        XCTAssertEqual(Units.TemperatureUnit.celsius.displayName, "Celsius (°C)")
        XCTAssertEqual(Units.TemperatureUnit.fahrenheit.displayName, "Fahrenheit (°F)")

        XCTAssertTrue(Units.NetworkUnit.bytesPerSecond.displayName.contains("Bytes/sec"))
        XCTAssertTrue(Units.NetworkUnit.bitsPerSecond.displayName.contains("Bits/sec"))

        XCTAssertTrue(Units.ByteUnitStandard.si.displayName.contains("1000"))
        XCTAssertTrue(Units.ByteUnitStandard.iec.displayName.contains("1024"))
    }

    func testResetToDefaults() {
        let store = PreferencesStore(userDefaults: testDefaults)
        store.refreshInterval = 15.0
        store.temperatureUnit = .fahrenheit
        store.networkUnit = .bitsPerSecond
        store.byteUnitStandard = .si
        store.showDockIcon = true
        store.launchAtLogin = true
        store.setCategory(.cpu, isEnabled: false)

        store.resetToDefaults()

        XCTAssertEqual(store.refreshInterval, PreferencesStore.defaultRefreshInterval)
        XCTAssertEqual(store.enabledCategories, Set(MetricCategory.allCases))
        XCTAssertEqual(store.temperatureUnit, .celsius)
        XCTAssertEqual(store.networkUnit, .bytesPerSecond)
        XCTAssertEqual(store.byteUnitStandard, .iec)
        XCTAssertFalse(store.showDockIcon)
        XCTAssertFalse(store.launchAtLogin)
    }
}
