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
        XCTAssertEqual(store.menuBarDisplayMode, .cpu)
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
        XCTAssertEqual(store.menuBarDisplayMode, .cpu)
    }

    func testMenuBarDisplayModePersistenceAndReset() {
        let store1 = PreferencesStore(userDefaults: testDefaults)
        store1.menuBarDisplayMode = .both
        XCTAssertEqual(store1.menuBarDisplayMode, .both)

        let store2 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store2.menuBarDisplayMode, .both)

        store2.menuBarDisplayMode = .memory
        let store3 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store3.menuBarDisplayMode, .memory)

        store3.menuBarDisplayMode = .network
        let store4 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store4.menuBarDisplayMode, .network)

        store4.menuBarDisplayMode = .battery
        let store5 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store5.menuBarDisplayMode, .battery)

        store5.menuBarDisplayMode = .thermal
        let store6 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store6.menuBarDisplayMode, .thermal)

        store6.menuBarDisplayMode = .gpu
        let store7 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store7.menuBarDisplayMode, .gpu)

        store7.menuBarDisplayMode = .icon
        let store8 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store8.menuBarDisplayMode, .icon)

        XCTAssertEqual(PreferencesStore.MenuBarDisplayMode.icon.displayName, "Icon Only")
        XCTAssertEqual(PreferencesStore.MenuBarDisplayMode.cpu.displayName, "CPU Usage")
        XCTAssertEqual(PreferencesStore.MenuBarDisplayMode.memory.displayName, "Memory Usage")
        XCTAssertEqual(PreferencesStore.MenuBarDisplayMode.both.displayName, "CPU & Memory")
        XCTAssertEqual(PreferencesStore.MenuBarDisplayMode.network.displayName, "Network Rate")
        XCTAssertEqual(PreferencesStore.MenuBarDisplayMode.battery.displayName, "Battery Level")
        XCTAssertEqual(PreferencesStore.MenuBarDisplayMode.thermal.displayName, "SoC Temperature")
        XCTAssertEqual(PreferencesStore.MenuBarDisplayMode.gpu.displayName, "GPU Usage")
    }

    func testSamplingPausedPersistenceActiveMenuBarItemsAndReset() {
        let store1 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertFalse(store1.isSamplingPaused)
        XCTAssertFalse(store1.activeMenuBarItems.isEmpty)
        let savedItems = store1.menuBarItems

        // Pause sampling -> activeMenuBarItems collapses to empty while preserving menuBarItems
        store1.setSamplingPaused(true)
        XCTAssertTrue(store1.isSamplingPaused)
        XCTAssertTrue(store1.activeMenuBarItems.isEmpty)
        XCTAssertEqual(store1.menuBarItems, savedItems)

        // Persistence across instances
        let store2 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertTrue(store2.isSamplingPaused)
        XCTAssertTrue(store2.activeMenuBarItems.isEmpty)

        // Toggle back to active
        store2.toggleSamplingPaused()
        XCTAssertFalse(store2.isSamplingPaused)
        XCTAssertEqual(store2.activeMenuBarItems, savedItems)

        // Reset to defaults clears pause state and restores autoPauseOnLowPowerMode
        store2.setSamplingPaused(true)
        store2.isAutoPausedByLowPowerMode = true
        store2.autoPauseOnLowPowerMode = false
        let store3 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertTrue(store3.isSamplingPaused)
        XCTAssertTrue(store3.isAutoPausedByLowPowerMode)
        XCTAssertFalse(store3.autoPauseOnLowPowerMode)

        // Resuming automatically clears isAutoPausedByLowPowerMode
        store3.setSamplingPaused(false)
        XCTAssertFalse(store3.isAutoPausedByLowPowerMode)

        store3.setSamplingPaused(true)
        store3.isAutoPausedByLowPowerMode = true
        store3.resetToDefaults()
        XCTAssertFalse(store3.isSamplingPaused)
        XCTAssertFalse(store3.isAutoPausedByLowPowerMode)
        XCTAssertTrue(store3.autoPauseOnLowPowerMode)
    }

    func testMoveActiveMenuBarItemDirection() {
        let store = PreferencesStore(userDefaults: testDefaults)
        let item1 = MenuBarItemConfig(category: .cpu, style: .bar)
        let item2 = MenuBarItemConfig(category: .memory, style: .bar)
        let item3 = MenuBarItemConfig(category: .network, style: .throughput)
        store.menuBarItems = [item1, item2, item3]

        // Move item 1 right (+1)
        store.moveActiveMenuBarItem(id: item1.id, direction: 1)
        XCTAssertEqual(store.activeMenuBarItems.map(\.id), [item2.id, item1.id, item3.id])

        // Move item 1 right again (+1)
        store.moveActiveMenuBarItem(id: item1.id, direction: 1)
        XCTAssertEqual(store.activeMenuBarItems.map(\.id), [item2.id, item3.id, item1.id])

        // Move item 1 left (-1)
        store.moveActiveMenuBarItem(id: item1.id, direction: -1)
        XCTAssertEqual(store.activeMenuBarItems.map(\.id), [item2.id, item1.id, item3.id])

        // Edge case: moving leftmost item further left is a no-op
        store.moveActiveMenuBarItem(id: item2.id, direction: -1)
        XCTAssertEqual(store.activeMenuBarItems.map(\.id), [item2.id, item1.id, item3.id])
    }

    func testMoveActiveMenuBarItemIndexSet() {
        let store = PreferencesStore(userDefaults: testDefaults)
        let item1 = MenuBarItemConfig(category: .cpu, style: .bar)
        let item2 = MenuBarItemConfig(category: .memory, style: .bar)
        let item3 = MenuBarItemConfig(category: .network, style: .throughput)
        store.menuBarItems = [item1, item2, item3]

        // Move index 2 to index 0
        store.moveActiveMenuBarItem(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.activeMenuBarItems.map(\.id), [item3.id, item1.id, item2.id])
    }
}
