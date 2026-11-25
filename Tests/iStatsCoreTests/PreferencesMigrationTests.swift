import XCTest
@testable import iStatsCore

final class PreferencesMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "iStats.test.migration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// A realistic v1 profile: every pre-v2 key, legacy popover styles, custom alert thresholds.
    private func seedV1Profile() {
        let K = PreferencesStore.Keys.self
        let L = PreferencesMigration.LegacyAlertKeys.self
        defaults.set(5.0, forKey: K.refreshInterval)
        defaults.set(["cpu", "network"], forKey: K.enabledCategories)
        defaults.set("fahrenheit", forKey: K.temperatureUnit)
        defaults.set("cpu", forKey: "iStats.menuBarDisplayMode")
        defaults.set(["cpu": "history"], forKey: K.categoryLastTabs)
        defaults.set(["cpu": [100.0, 200.0]], forKey: K.pinnedPanelOrigins)
        defaults.set(true, forKey: K.notificationsEnabled)
        defaults.set(true, forKey: L.cpuEnabled)
        defaults.set(75.0, forKey: L.cpuThreshold)
        defaults.set(false, forKey: K.memoryAlertCriticalPressureOnly)
        defaults.set(true, forKey: L.diskEnabled)
        defaults.set(95.0, forKey: L.diskThreshold)
        defaults.set(10, forKey: L.batteryLowThreshold)
        defaults.set(900.0, forKey: L.cooldown)

        let items = #"""
        [
          {"category":"cpu","style":"bar","popoverStyle":"cpuCluster","unknownFutureField":42},
          {"category":"memory","style":"gauge"},
          {"category":"network","style":"throughput","popover":{"openingTab":"history","rememberLastTab":false}}
        ]
        """#
        defaults.set(Data(items.utf8), forKey: K.menuBarItems)
        // memory.gauge has no inline style; its override lives in the legacy dictionary.
        defaults.set(Data(#"{"memory.gauge":"memoryPressure"}"#.utf8), forKey: "iStats.widgetPopoverStyles")
        defaults.set(true, forKey: "iStats.someFutureKey")
    }

    func testV1ProfileMigratesWithoutDataLoss() {
        seedV1Profile()
        let result = PreferencesMigration.migrate(defaults: defaults)
        XCTAssertEqual(result.fromVersion, 1)
        XCTAssertEqual(result.toVersion, PreferencesMigration.currentVersion)
        XCTAssertTrue(result.didMigrate)
        XCTAssertTrue(result.isExistingUser)
        XCTAssertEqual(defaults.integer(forKey: PreferencesStore.Keys.schemaVersion), 2)
        XCTAssertTrue(defaults.bool(forKey: PreferencesStore.Keys.hasCompletedOnboarding))

        // Dead keys removed, unknown keys and untouched settings preserved.
        XCTAssertNil(defaults.object(forKey: "iStats.menuBarDisplayMode"))
        XCTAssertNil(defaults.object(forKey: "iStats.widgetPopoverStyles"))
        XCTAssertEqual(defaults.bool(forKey: "iStats.someFutureKey"), true)
        XCTAssertEqual(defaults.double(forKey: PreferencesStore.Keys.refreshInterval), 5.0)
        XCTAssertEqual(defaults.dictionary(forKey: PreferencesStore.Keys.categoryLastTabs) as? [String: String], ["cpu": "history"])

        // Alert rules built from legacy keys; legacy keys remain readable.
        let rules = try! JSONDecoder().decode([AlertRule].self, from: defaults.data(forKey: PreferencesStore.Keys.alertRules)!)
        let byKind = Dictionary(uniqueKeysWithValues: rules.map { ($0.kind, $0) })
        XCTAssertEqual(byKind[.cpu]?.enabled, true)
        XCTAssertEqual(byKind[.cpu]?.threshold, 75)
        XCTAssertEqual(byKind[.disk]?.threshold, 95)
        XCTAssertEqual(byKind[.batteryLow]?.threshold, 10)
        XCTAssertEqual(byKind[.memory]?.threshold, 85)
        XCTAssertTrue(rules.allSatisfy { $0.cooldownSeconds == 900 })
        XCTAssertEqual(defaults.double(forKey: PreferencesMigration.LegacyAlertKeys.cpuThreshold), 75)

        // Widget layout preserved; legacy popover styles folded into `popover`.
        let json = try! JSONSerialization.jsonObject(with: defaults.data(forKey: PreferencesStore.Keys.menuBarItems)!) as! [[String: Any]]
        XCTAssertEqual(json.count, 3)
        XCTAssertNil(json[0]["popoverStyle"])
        XCTAssertEqual(json[0]["unknownFutureField"] as? Int, 42)
        XCTAssertEqual((json[0]["popover"] as? [String: Any])?["openingTab"] as? String, "detail") // cpuCluster
        XCTAssertEqual((json[1]["popover"] as? [String: Any])?["openingTab"] as? String, "detail") // memoryPressure
        XCTAssertEqual((json[2]["popover"] as? [String: Any])?["openingTab"] as? String, "history")
    }

    func testMigrationIsIdempotent() {
        seedV1Profile()
        PreferencesMigration.migrate(defaults: defaults)
        let snapshot = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("iStats.") }.mapValues { "\($0)" }

        let second = PreferencesMigration.migrate(defaults: defaults)
        XCTAssertFalse(second.didMigrate)
        let after = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("iStats.") }.mapValues { "\($0)" }
        XCTAssertEqual(snapshot, after)
    }

    func testFreshInstallIsNotMarkedOnboarded() {
        let result = PreferencesMigration.migrate(defaults: defaults)
        XCTAssertFalse(result.isExistingUser)
        XCTAssertEqual(defaults.integer(forKey: PreferencesStore.Keys.schemaVersion), 2)
        XCTAssertFalse(defaults.bool(forKey: PreferencesStore.Keys.hasCompletedOnboarding))
        XCTAssertFalse(PreferencesStore(userDefaults: defaults).hasCompletedOnboarding)
    }

    func testExistingUserFlaggedByAnyLegacyKey() {
        defaults.set(true, forKey: PreferencesStore.Keys.showDockIcon)
        PreferencesMigration.migrate(defaults: defaults)
        XCTAssertTrue(PreferencesStore(userDefaults: defaults).hasCompletedOnboarding)
    }

    func testExistingOnboardingValueIsNotOverwritten() {
        defaults.set(false, forKey: PreferencesStore.Keys.hasCompletedOnboarding)
        defaults.set(true, forKey: PreferencesStore.Keys.showDockIcon)
        PreferencesMigration.migrate(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: PreferencesStore.Keys.hasCompletedOnboarding))
    }

    func testFutureSchemaVersionIsLeftAlone() {
        defaults.set(99, forKey: PreferencesStore.Keys.schemaVersion)
        defaults.set(true, forKey: "iStats.menuBarDisplayMode")
        let result = PreferencesMigration.migrate(defaults: defaults)
        XCTAssertFalse(result.didMigrate)
        XCTAssertEqual(defaults.integer(forKey: PreferencesStore.Keys.schemaVersion), 99)
        XCTAssertNotNil(defaults.object(forKey: "iStats.menuBarDisplayMode"))
    }

    func testStoreLoadsMigratedV1ProfileEndToEnd() {
        seedV1Profile()
        let store = PreferencesStore(userDefaults: defaults)

        XCTAssertEqual(store.refreshInterval, 5.0)
        XCTAssertEqual(store.enabledCategories, [.cpu, .network])
        XCTAssertEqual(store.temperatureUnit, .fahrenheit)
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertTrue(store.notificationsEnabled)
        XCTAssertFalse(store.memoryAlertCriticalPressureOnly)
        XCTAssertTrue(store.alertRule(for: .cpu).enabled)
        XCTAssertEqual(store.alertRule(for: .cpu).threshold, 75)
        XCTAssertEqual(store.alertRule(for: .disk).threshold, 95)
        XCTAssertEqual(store.alertRule(for: .batteryLow).threshold, 10)
        XCTAssertEqual(store.alertRule(for: .cpu).cooldownSeconds, 900)
        XCTAssertEqual(store.pinnedOrigin(for: MetricCategory.cpu), CGPoint(x: 100, y: 200))
        XCTAssertEqual(store.lastSelectedTab(for: .cpu), .history)

        XCTAssertEqual(store.menuBarItems.map(\.id), ["cpu.bar", "memory.gauge", "network.throughput"])
        XCTAssertEqual(store.menuBarItems[0].popover?.openingTab, .detail)
        XCTAssertEqual(store.menuBarItems[2].popover?.openingTab, .history)

        // A second launch re-reads the same state.
        let again = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(again.menuBarItems, store.menuBarItems)
        XCTAssertEqual(again.alertRules, store.alertRules)
    }
}
