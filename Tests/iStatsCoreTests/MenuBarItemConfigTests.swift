import XCTest
@testable import iStatsCore

final class MenuBarItemConfigTests: XCTestCase {
    func testInitializationAndDeterministicIDs() {
        let config = MenuBarItemConfig(category: .cpu, style: .gauge)

        XCTAssertEqual(config.id, "cpu.gauge")
        XCTAssertEqual(config.category, .cpu)
        XCTAssertEqual(config.style, .gauge)
    }

    func testCodableRoundTrip() throws {
        let original = MenuBarItemConfig(category: .memory, style: .sparkline)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarItemConfig.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.id, "memory.sparkline")
        XCTAssertEqual(decoded.category, .memory)
        XCTAssertEqual(decoded.style, .sparkline)
    }

    func testDefaultConfigs() {
        let defaults = MenuBarItemConfig.defaultConfigs()
        XCTAssertFalse(defaults.isEmpty)
        XCTAssertTrue(defaults.contains(where: { $0.category == .cpu && $0.style == .gauge }))
        XCTAssertTrue(defaults.contains(where: { $0.category == .memory && $0.style == .gauge }))
        XCTAssertTrue(defaults.contains(where: { $0.category == .network && $0.style == .throughput }))
    }

    func testAllAvailableItemsAndStyles() {
        let allItems = MenuBarItemConfig.allAvailableItems
        XCTAssertFalse(allItems.isEmpty)

        let cpuStyles = MenuBarItemConfig.allStyles(for: .cpu)
        XCTAssertTrue(cpuStyles.contains(where: { $0.style == .gauge }))
        XCTAssertTrue(cpuStyles.contains(where: { $0.style == .sparkline }))
        XCTAssertTrue(cpuStyles.contains(where: { $0.style == .bar }))

        let netStyles = MenuBarItemConfig.allStyles(for: .network)
        XCTAssertTrue(netStyles.contains(where: { $0.style == .throughput }))
    }

    func testSupportedStylesForCategories() {
        let cpuStyles = MetricDisplayStyle.supportedStyles(for: .cpu)
        XCTAssertTrue(cpuStyles.contains(.gauge))
        XCTAssertTrue(cpuStyles.contains(.sparkline))
        XCTAssertTrue(cpuStyles.contains(.bar))

        let netStyles = MetricDisplayStyle.supportedStyles(for: .network)
        XCTAssertTrue(netStyles.contains(.throughput))
    }

    func testPreferencesStoreMenuBarItemOperations() {
        let suiteName = "test.istats.menubaritems.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PreferencesStore(userDefaults: defaults)

        // Initial default items
        XCTAssertFalse(store.menuBarItems.isEmpty)
        XCTAssertTrue(store.isItemEnabled(category: .cpu, style: .gauge))

        // Set item enabled / disabled
        store.setItemEnabled(category: .gpu, style: .bar, isEnabled: true)
        XCTAssertTrue(store.isItemEnabled(category: .gpu, style: .bar))
        XCTAssertTrue(store.items(for: .gpu).contains(where: { $0.style == .bar }))

        // Toggle item
        store.toggleItem(category: .gpu, style: .bar)
        XCTAssertFalse(store.isItemEnabled(category: .gpu, style: .bar))

        // Active items filter (category enabled + item enabled)
        store.setItemEnabled(category: .gpu, style: .bar, isEnabled: true)
        XCTAssertTrue(store.activeMenuBarItems.contains(where: { $0.category == .gpu && $0.style == .bar }))

        // Disable parent category -> item excluded from activeMenuBarItems
        store.setCategory(.gpu, isEnabled: false)
        XCTAssertFalse(store.activeMenuBarItems.contains(where: { $0.category == .gpu && $0.style == .bar }))

        // Remove item by setting isEnabled = false
        store.setItemEnabled(category: .gpu, style: .bar, isEnabled: false)
        XCTAssertFalse(store.isItemEnabled(category: .gpu, style: .bar))

        // Reset to defaults
        store.resetToDefaults()
        XCTAssertEqual(store.menuBarItems, MenuBarItemConfig.defaultConfigs())

        defaults.removePersistentDomain(forName: suiteName)
    }
}
