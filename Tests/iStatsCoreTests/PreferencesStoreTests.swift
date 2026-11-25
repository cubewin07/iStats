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

        store.setCategory(.cpu, isEnabled: true)
        XCTAssertTrue(store.isCategoryEnabled(.cpu))
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

    func testSchemaV2DefaultsAndPersistence() {
        let store = PreferencesStore(userDefaults: testDefaults)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertEqual(store.lastPanelDestination, .overview)
        XCTAssertNil(store.lastSettingsSection)
        XCTAssertEqual(store.menuBarAppearance, .statusTint)
        XCTAssertNil(store.networkInterfaceSelection)
        XCTAssertEqual(store.alertRules, AlertRule.defaults)

        store.hasCompletedOnboarding = true
        store.lastPanelDestination = .category(.network)
        store.lastSettingsSection = "alerts"
        store.menuBarAppearance = .categoryColor
        store.networkInterfaceSelection = "en0"

        let reloaded = PreferencesStore(userDefaults: testDefaults)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
        XCTAssertEqual(reloaded.lastPanelDestination, .category(.network))
        XCTAssertEqual(reloaded.lastSettingsSection, "alerts")
        XCTAssertEqual(reloaded.menuBarAppearance, .categoryColor)
        XCTAssertEqual(reloaded.networkInterfaceSelection, "en0")

        reloaded.lastSettingsSection = nil
        reloaded.networkInterfaceSelection = nil
        let cleared = PreferencesStore(userDefaults: testDefaults)
        XCTAssertNil(cleared.lastSettingsSection)
        XCTAssertNil(cleared.networkInterfaceSelection)

        // Reset restores the defaults but keeps the onboarding flag.
        cleared.resetToDefaults()
        XCTAssertEqual(cleared.lastPanelDestination, .overview)
        XCTAssertEqual(cleared.menuBarAppearance, .statusTint)
        XCTAssertTrue(cleared.hasCompletedOnboarding)
    }

    func testInvalidV2ValuesFallBackToDefaults() {
        testDefaults.set("bogus", forKey: PreferencesStore.Keys.lastPanelDestination)
        testDefaults.set("bogus", forKey: PreferencesStore.Keys.menuBarAppearance)
        let store = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(store.lastPanelDestination, .overview)
        XCTAssertEqual(store.menuBarAppearance, .statusTint)
    }

    func testAlertRulesHelpersClampAndPersist() {
        let store = PreferencesStore(userDefaults: testDefaults)
        store.updateAlertRule(.cpu) {
            $0.enabled = true
            $0.threshold = 75
            $0.sustainSeconds = 15
        }
        store.updateAlertRule(.batteryLow) { $0.threshold = 3 } // clamps to 5
        store.updateAlertRule(.temperature) { $0.threshold = 200 } // clamps to 105
        store.defaultAlertCooldownSeconds = 10 // clamps to 30

        XCTAssertEqual(store.alertRule(for: .cpu).threshold, 75)
        XCTAssertEqual(store.alertRule(for: .cpu).sustainSeconds, 15)
        XCTAssertEqual(store.alertRule(for: .batteryLow).threshold, 5)
        XCTAssertEqual(store.alertRule(for: .temperature).threshold, 105)
        XCTAssertEqual(store.defaultAlertCooldownSeconds, 30)
        XCTAssertTrue(store.alertRules.allSatisfy { $0.cooldownSeconds == 30 })

        let reloaded = PreferencesStore(userDefaults: testDefaults)
        XCTAssertTrue(reloaded.alertRule(for: .cpu).enabled)
        XCTAssertEqual(reloaded.alertRule(for: .cpu).threshold, 75)
        XCTAssertEqual(reloaded.alertRule(for: .cpu).sustainSeconds, 15)
        XCTAssertEqual(reloaded.alertRules.map(\.kind), AlertKind.allCases)

        reloaded.resetToDefaults()
        XCTAssertEqual(reloaded.alertRules, AlertRule.defaults)
    }

    func testPinnedOriginsKeyedByDestination() {
        let store = PreferencesStore(userDefaults: testDefaults)
        XCTAssertNil(store.pinnedOrigin(for: .overview))

        store.setPinnedOrigin(CGPoint(x: 10, y: 20), for: .overview)
        store.setPinnedOrigin(CGPoint(x: 30, y: 40), for: MetricCategory.cpu)
        XCTAssertEqual(store.pinnedOrigin(forDestinationKey: "overview"), CGPoint(x: 10, y: 20))
        XCTAssertEqual(store.pinnedOrigin(forDestinationKey: "cpu"), CGPoint(x: 30, y: 40))
        XCTAssertEqual(store.pinnedOrigin(for: PanelDestination.category(.cpu)), CGPoint(x: 30, y: 40))

        let reloaded = PreferencesStore(userDefaults: testDefaults)
        XCTAssertEqual(reloaded.pinnedOrigin(for: .overview), CGPoint(x: 10, y: 20))
        XCTAssertEqual(reloaded.pinnedOrigin(for: MetricCategory.cpu), CGPoint(x: 30, y: 40))

        reloaded.setPinnedOrigin(nil, for: .overview)
        XCTAssertNil(reloaded.pinnedOrigin(forDestinationKey: "overview"))
        XCTAssertNotNil(reloaded.pinnedOrigin(forDestinationKey: "cpu"))
    }

    func testCategoryLastTabIsPerCategory() {
        let store = PreferencesStore(userDefaults: testDefaults)
        store.setLastSelectedTab(.history, for: .cpu)
        store.setLastSelectedTab(.detail, for: .memory)
        XCTAssertEqual(store.lastSelectedTab(for: .cpu), .history)
        XCTAssertEqual(store.lastSelectedTab(for: .memory), .detail)
        XCTAssertNil(store.lastSelectedTab(for: .gpu))
        XCTAssertEqual(PreferencesStore(userDefaults: testDefaults).lastSelectedTab(for: .cpu), .history)
    }

    func testSamplingPausedPersistenceActiveMenuBarItemsAndReset() {
        let store1 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertFalse(store1.isSamplingPaused)
        XCTAssertFalse(store1.activeMenuBarItems.isEmpty)
        let savedItems = store1.menuBarItems

        // Pause sampling -> activeMenuBarItems collapses to empty while preserving menuBarItems
        store1.isSamplingPaused = true
        XCTAssertTrue(store1.isSamplingPaused)
        XCTAssertTrue(store1.activeMenuBarItems.isEmpty)
        XCTAssertEqual(store1.menuBarItems, savedItems)

        // Persistence across instances
        let store2 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertTrue(store2.isSamplingPaused)
        XCTAssertTrue(store2.activeMenuBarItems.isEmpty)

        // Toggle back to active
        store2.isSamplingPaused.toggle()
        XCTAssertFalse(store2.isSamplingPaused)
        XCTAssertEqual(store2.activeMenuBarItems, savedItems)

        // Reset to defaults clears pause state and restores autoPauseOnLowPowerMode
        store2.isSamplingPaused = true
        store2.isAutoPausedByLowPowerMode = true
        store2.autoPauseOnLowPowerMode = false
        let store3 = PreferencesStore(userDefaults: testDefaults)
        XCTAssertTrue(store3.isSamplingPaused)
        XCTAssertTrue(store3.isAutoPausedByLowPowerMode)
        XCTAssertFalse(store3.autoPauseOnLowPowerMode)

        // Resuming automatically clears isAutoPausedByLowPowerMode
        store3.isSamplingPaused = false
        XCTAssertFalse(store3.isAutoPausedByLowPowerMode)

        store3.isSamplingPaused = true
        store3.isAutoPausedByLowPowerMode = true
        store3.resetToDefaults()
        XCTAssertFalse(store3.isSamplingPaused)
        XCTAssertFalse(store3.isAutoPausedByLowPowerMode)
        XCTAssertTrue(store3.autoPauseOnLowPowerMode)
    }

    func testSetActiveMenuBarOrderKeepsDisabledItemsAndRejectsMismatchedSets() {
        let store = PreferencesStore(userDefaults: testDefaults)
        let cpu = MenuBarItemConfig(category: .cpu, style: .gauge)
        let mem = MenuBarItemConfig(category: .memory, style: .bar)
        let net = MenuBarItemConfig(category: .network, style: .throughput)
        store.menuBarItems = [cpu, net, mem]
        store.setCategory(.network, isEnabled: false)

        store.setActiveMenuBarOrder([mem.id, cpu.id])
        XCTAssertEqual(store.menuBarItems.map(\.id), [mem.id, cpu.id, net.id])

        store.setActiveMenuBarOrder([cpu.id])
        store.setActiveMenuBarOrder([cpu.id, net.id])
        XCTAssertEqual(store.menuBarItems.map(\.id), [mem.id, cpu.id, net.id])
    }
}
