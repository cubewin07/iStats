import XCTest
@testable import iStatsCore

final class PreferencesPersistenceTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "iStats.test.persistence.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Full Round-Trip Persistence (Requirement 11.4)

    func testFullRoundTripPersistenceAcrossLaunches() {
        // 1. First Launch: User configures preferences
        let firstLaunchStore = PreferencesStore(userDefaults: testDefaults)
        firstLaunchStore.refreshInterval = 5.0
        firstLaunchStore.enabledCategories = [.cpu, .network, .thermal, .gpu]
        firstLaunchStore.temperatureUnit = .fahrenheit
        firstLaunchStore.networkUnit = .bitsPerSecond
        firstLaunchStore.byteUnitStandard = .si
        firstLaunchStore.showDockIcon = true
        firstLaunchStore.launchAtLogin = true
        firstLaunchStore.menuBarDisplayMode = .network

        // 2. Simulate App Termination & Subsequent Launch
        let secondLaunchStore = PreferencesStore(userDefaults: testDefaults)

        XCTAssertEqual(secondLaunchStore.refreshInterval, 5.0)
        XCTAssertEqual(secondLaunchStore.enabledCategories, [.cpu, .network, .thermal, .gpu])
        XCTAssertEqual(secondLaunchStore.temperatureUnit, .fahrenheit)
        XCTAssertEqual(secondLaunchStore.networkUnit, .bitsPerSecond)
        XCTAssertEqual(secondLaunchStore.byteUnitStandard, .si)
        XCTAssertTrue(secondLaunchStore.showDockIcon)
        XCTAssertTrue(secondLaunchStore.launchAtLogin)
        XCTAssertEqual(secondLaunchStore.menuBarDisplayMode, .network)
    }

    // MARK: - Clamping & Boundary Handling

    func testClampingOnDeserialization() {
        // Manually write out-of-bounds value to UserDefaults
        testDefaults.set(-50.0, forKey: PreferencesStore.Keys.refreshInterval)
        let lowerClampedStore = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(lowerClampedStore.refreshInterval, PreferencesStore.minRefreshInterval)

        testDefaults.set(120.0, forKey: PreferencesStore.Keys.refreshInterval)
        let upperClampedStore = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(upperClampedStore.refreshInterval, PreferencesStore.maxRefreshInterval)
    }

    // MARK: - Corrupted Data Graceful Fallbacks

    func testCorruptedDataGracefulFallback() {
        testDefaults.set("invalid_temperature_unit", forKey: PreferencesStore.Keys.temperatureUnit)
        testDefaults.set("invalid_network_unit", forKey: PreferencesStore.Keys.networkUnit)
        testDefaults.set("invalid_byte_standard", forKey: PreferencesStore.Keys.byteUnitStandard)
        testDefaults.set("invalid_mode", forKey: PreferencesStore.Keys.menuBarDisplayMode)
        testDefaults.set(["nonexistent_category", "invalid_enum"], forKey: PreferencesStore.Keys.enabledCategories)

        let store = PreferencesStore(userDefaults: testDefaults)

        XCTAssertEqual(store.temperatureUnit, .celsius)
        XCTAssertEqual(store.networkUnit, .bytesPerSecond)
        XCTAssertEqual(store.byteUnitStandard, .iec)
        XCTAssertEqual(store.menuBarDisplayMode, .cpu)
        XCTAssertTrue(store.enabledCategories.isEmpty)
    }

    // MARK: - ADR 0006 Privacy & Zero-Telemetry Persistence Assertion

    func testADR0006ZeroTelemetryPersisted() {
        let store = PreferencesStore(userDefaults: testDefaults)
        store.refreshInterval = 3.0
        store.temperatureUnit = .celsius
        store.menuBarDisplayMode = .both

        let persistentDict = testDefaults.dictionaryRepresentation()
        let allowedKeys: Set<String> = [
            PreferencesStore.Keys.refreshInterval,
            PreferencesStore.Keys.enabledCategories,
            PreferencesStore.Keys.temperatureUnit,
            PreferencesStore.Keys.networkUnit,
            PreferencesStore.Keys.byteUnitStandard,
            PreferencesStore.Keys.showDockIcon,
            PreferencesStore.Keys.launchAtLogin,
            PreferencesStore.Keys.menuBarDisplayMode
        ]

        for (key, _) in persistentDict where key.hasPrefix("iStats.") {
            XCTAssertTrue(
                allowedKeys.contains(key),
                "ADR 0006 Violation: Found unexpected persisted key '\(key)' in UserDefaults! Only preferences are permitted."
            )
        }
    }

    // MARK: - Reset To Defaults Persistence

    func testResetToDefaultsPersists() {
        let store1 = PreferencesStore(userDefaults: testDefaults)
        store1.refreshInterval = 10.0
        store1.temperatureUnit = .fahrenheit
        store1.menuBarDisplayMode = .battery
        store1.resetToDefaults()

        let store2 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store2.refreshInterval, PreferencesStore.defaultRefreshInterval)
        XCTAssertEqual(store2.temperatureUnit, .celsius)
        XCTAssertEqual(store2.networkUnit, .bytesPerSecond)
        XCTAssertEqual(store2.byteUnitStandard, .iec)
        XCTAssertEqual(store2.menuBarDisplayMode, .cpu)
        XCTAssertFalse(store2.showDockIcon)
        XCTAssertFalse(store2.launchAtLogin)
        XCTAssertEqual(store2.enabledCategories, Set(MetricCategory.allCases))
    }
}
