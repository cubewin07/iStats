import XCTest
@testable import iStatsCore

final class MenuBarItemConfigTests: XCTestCase {
    func testInitializationAndDefaults() {
        let id = UUID()
        let config = MenuBarItemConfig(id: id, category: .cpu, style: .gauge, isEnabled: true)

        XCTAssertEqual(config.id, id)
        XCTAssertEqual(config.category, .cpu)
        XCTAssertEqual(config.style, .gauge)
        XCTAssertTrue(config.isEnabled)
    }

    func testCodableRoundTrip() throws {
        let original = MenuBarItemConfig(category: .memory, style: .sparkline, isEnabled: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarItemConfig.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.category, .memory)
        XCTAssertEqual(decoded.style, .sparkline)
        XCTAssertFalse(decoded.isEnabled)
    }

    func testDefaultConfigs() {
        let defaults = MenuBarItemConfig.defaultConfigs()
        XCTAssertFalse(defaults.isEmpty)
        XCTAssertTrue(defaults.contains(where: { $0.category == .cpu }))
        XCTAssertTrue(defaults.contains(where: { $0.category == .memory }))
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

        // Add item
        let newItem = MenuBarItemConfig(category: .gpu, style: .bar)
        store.addMenuBarItem(newItem)
        XCTAssertTrue(store.menuBarItems.contains(where: { $0.id == newItem.id }))
        XCTAssertTrue(store.items(for: .gpu).contains(where: { $0.id == newItem.id }))

        // Toggle item
        store.toggleMenuBarItem(id: newItem.id)
        XCTAssertFalse(store.menuBarItems.first(where: { $0.id == newItem.id })!.isEnabled)

        // Active items filter (category enabled + item enabled)
        XCTAssertFalse(store.activeMenuBarItems.contains(where: { $0.id == newItem.id }))

        // Enable item again
        store.toggleMenuBarItem(id: newItem.id)
        XCTAssertTrue(store.activeMenuBarItems.contains(where: { $0.id == newItem.id }))

        // Disable parent category -> item excluded from activeMenuBarItems
        store.setCategory(.gpu, isEnabled: false)
        XCTAssertFalse(store.activeMenuBarItems.contains(where: { $0.id == newItem.id }))

        // Remove item
        store.removeMenuBarItem(id: newItem.id)
        XCTAssertFalse(store.menuBarItems.contains(where: { $0.id == newItem.id }))

        // Remove all items for category
        let cpuItem1 = MenuBarItemConfig(category: .cpu, style: .gauge)
        let cpuItem2 = MenuBarItemConfig(category: .cpu, style: .text)
        store.addMenuBarItem(cpuItem1)
        store.addMenuBarItem(cpuItem2)
        XCTAssertEqual(store.items(for: .cpu).count, 2 + (store.menuBarItems.filter({ $0.category == .cpu }).count - 2))

        store.removeAllItems(for: .cpu)
        XCTAssertTrue(store.items(for: .cpu).isEmpty)

        // Reset to defaults
        store.resetToDefaults()
        XCTAssertEqual(store.menuBarItems, MenuBarItemConfig.defaultConfigs())

        defaults.removePersistentDomain(forName: suiteName)
    }
}
