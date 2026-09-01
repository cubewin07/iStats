import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class MenuBarControllerInteractionTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, MenuBarController, String) {
        let suiteName = "test.istats.controller.interaction.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        let controller = MenuBarController(preferences: prefs, coordinator: coord)
        return (defaults, prefs, coord, controller, suiteName)
    }

    private func cleanup(defaults: UserDefaults, controller: MenuBarController, suiteName: String) {
        for (_, item) in controller.statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        controller.hidePopover()
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 1. Multi-Item Dynamic Lifecycle & Synchronization

    func testDynamicAddRemoveReorderStatusItems() {
        let (defaults, prefs, _, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        // Start with 2 items: CPU gauge and RAM bar
        let cpuItem = MenuBarItemConfig(category: .cpu, style: .gauge)
        let ramItem = MenuBarItemConfig(category: .memory, style: .bar)
        prefs.menuBarItems = [cpuItem, ramItem]
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 2)
        XCTAssertNotNil(controller.statusItems[cpuItem.id])
        XCTAssertNotNil(controller.statusItems[ramItem.id])

        // Add 2 more items: Net throughput and GPU text
        let netItem = MenuBarItemConfig(category: .network, style: .throughput)
        let gpuItem = MenuBarItemConfig(category: .gpu, style: .text)
        prefs.menuBarItems = [cpuItem, ramItem, netItem, gpuItem]
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 4)
        XCTAssertNotNil(controller.statusItems[netItem.id])
        XCTAssertNotNil(controller.statusItems[gpuItem.id])

        // Remove RAM item
        prefs.menuBarItems = [cpuItem, netItem, gpuItem]
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 3)
        XCTAssertNil(controller.statusItems[ramItem.id])
        XCTAssertNotNil(controller.statusItems[cpuItem.id])
        XCTAssertNotNil(controller.statusItems[netItem.id])
        XCTAssertNotNil(controller.statusItems[gpuItem.id])
    }

    func testCategoryEnablementToggleRemovesAndRestoresItems() {
        let (defaults, prefs, _, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let cpuGauge = MenuBarItemConfig(category: .cpu, style: .gauge)
        let cpuText = MenuBarItemConfig(category: .cpu, style: .text)
        let ramBar = MenuBarItemConfig(category: .memory, style: .bar)
        prefs.menuBarItems = [cpuGauge, cpuText, ramBar]
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 3)

        // Disable CPU category -> both cpuGauge and cpuText must be removed
        prefs.setCategory(.cpu, isEnabled: false)
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 1)
        XCTAssertNil(controller.statusItems[cpuGauge.id])
        XCTAssertNil(controller.statusItems[cpuText.id])
        XCTAssertNotNil(controller.statusItems[ramBar.id])

        // Re-enable CPU category -> both cpuGauge and cpuText must be restored
        prefs.setCategory(.cpu, isEnabled: true)
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 3)
        XCTAssertNotNil(controller.statusItems[cpuGauge.id])
        XCTAssertNotNil(controller.statusItems[cpuText.id])
        XCTAssertNotNil(controller.statusItems[ramBar.id])
    }

    func testFallbackStatusItemLifecycle() {
        let (defaults, prefs, _, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        // Clear all active items
        prefs.menuBarItems = []
        controller.syncStatusItems()

        // Fallback status item must be installed so user is never orphaned
        XCTAssertEqual(controller.statusItems.count, 1)
        XCTAssertNotNil(controller.statusItems[MenuBarController.fallbackStatusItemId])

        let fallbackItem = controller.statusItems[MenuBarController.fallbackStatusItemId]
        XCTAssertEqual(fallbackItem?.button?.identifier?.rawValue, MenuBarController.fallbackStatusItemId)
        XCTAssertEqual(fallbackItem?.button?.toolTip, "iStats (All menu items disabled - Click for settings)")
        XCTAssertNotNil(fallbackItem?.button?.image)

        // Re-enable a category item
        let netItem = MenuBarItemConfig(category: .network, style: .throughput)
        prefs.menuBarItems = [netItem]
        controller.syncStatusItems()

        // Fallback must be removed and net item installed
        XCTAssertEqual(controller.statusItems.count, 1)
        XCTAssertNil(controller.statusItems[MenuBarController.fallbackStatusItemId])
        XCTAssertNotNil(controller.statusItems[netItem.id])
    }

    // MARK: - 2. Metric Subscriptions & Re-rendering

    func testTelemetryStreamUpdatesMatchingStatusItems() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let cpuItem = MenuBarItemConfig(category: .cpu, style: .text)
        let memItem = MenuBarItemConfig(category: .memory, style: .text)
        prefs.menuBarItems = [cpuItem, memItem]
        controller.syncStatusItems()

        // 1. Emit CPU reading
        let cpuSample = CPUSample(totalUsage: 77.0, perCore: [77.0], user: 50.0, system: 27.0, idle: 23.0)
        coord.handleReading(.cpu(Sample(value: cpuSample)))

        controller.updateItems(for: .cpu)
        let cpuButton = controller.statusItems[cpuItem.id]?.button
        XCTAssertNotNil(cpuButton?.image)
        XCTAssertEqual(cpuButton?.toolTip, "CPU: 77.0% (User: 50.0%, Sys: 27.0%)")

        // 2. Emit Memory reading
        let memSample = MemorySample(total: 1000, used: 800, free: 200, wired: 100, compressed: 100, cached: 100, swapUsed: 0, pressure: .warning)
        coord.handleReading(.memory(Sample(value: memSample)))

        controller.updateItems(for: .memory)
        let memButton = controller.statusItems[memItem.id]?.button
        XCTAssertNotNil(memButton?.image)
        XCTAssertEqual(memButton?.toolTip, "MEM: 800 B / 1000 B (80.0%) - Pressure: Warning")
    }

    func testPreferenceChangesTriggerItemUpdates() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let thermalItem = MenuBarItemConfig(category: .thermal, style: .text)
        prefs.menuBarItems = [thermalItem]
        controller.syncStatusItems()

        let thermalSample = ThermalSample(sensors: [SensorReading(name: "CPU Package", celsius: 50.0)], pressure: .nominal)
        coord.handleReading(.thermal(Sample(value: thermalSample)))

        // Celsius check
        prefs.temperatureUnit = .celsius
        controller.updateAllStatusItems()
        let buttonC = controller.statusItems[thermalItem.id]?.button
        XCTAssertEqual(buttonC?.toolTip, "Peak Thermal: 50.0 °C (CPU Package)")

        // Fahrenheit check
        prefs.temperatureUnit = .fahrenheit
        controller.updateAllStatusItems()
        let buttonF = controller.statusItems[thermalItem.id]?.button
        XCTAssertEqual(buttonF?.toolTip, "Peak Thermal: 122.0 °F (CPU Package)")
    }

    // MARK: - 3. User Interactions & Action Routing

    func testStatusItemActionRoutingAndCategorySwitching() {
        let (defaults, prefs, _, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let cpuItem = MenuBarItemConfig(category: .cpu, style: .gauge)
        let memItem = MenuBarItemConfig(category: .memory, style: .bar)
        prefs.menuBarItems = [cpuItem, memItem]
        controller.syncStatusItems()

        guard let cpuButton = controller.statusItems[cpuItem.id]?.button,
              let memButton = controller.statusItems[memItem.id]?.button else {
            XCTFail("Status item buttons must exist")
            return
        }

        // 1. Click CPU button via statusItemClicked action selector
        controller.statusItemClicked(cpuButton)
        XCTAssertTrue(controller.currentlyShownButton === cpuButton)
        XCTAssertTrue(controller.popover.contentViewController is NSHostingController<CategoryDetailPopoverView>)

        // 2. Click Memory button -> switches popover to Memory
        controller.statusItemClicked(memButton)
        XCTAssertTrue(controller.currentlyShownButton === memButton)
        XCTAssertTrue(controller.popover.contentViewController is NSHostingController<CategoryDetailPopoverView>)

        // 3. Dismiss popover
        controller.hidePopover()
        XCTAssertNil(controller.currentlyShownButton)
    }

    func testFallbackStatusItemActionRouting() {
        let (defaults, prefs, _, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        prefs.menuBarItems = []
        controller.syncStatusItems()

        guard let fallbackButton = controller.statusItems[MenuBarController.fallbackStatusItemId]?.button else {
            XCTFail("Fallback button must exist")
            return
        }

        // Click fallback button -> opens Universal Popover
        controller.statusItemClicked(fallbackButton)
        XCTAssertTrue(controller.currentlyShownButton === fallbackButton)
        XCTAssertTrue(controller.popover.contentViewController is NSHostingController<DetailPopoverView>)

        controller.hidePopover()
        XCTAssertNil(controller.currentlyShownButton)
    }

    func testButtonPropertiesImagePositioning() {
        let (defaults, prefs, _, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let configWithImage = MenuBarItemConfig(category: .cpu, style: .gauge)
        prefs.menuBarItems = [configWithImage]
        controller.syncStatusItems()

        let button = controller.statusItems[configWithImage.id]?.button
        XCTAssertNotNil(button?.image)
        XCTAssertEqual(button?.imagePosition, .imageOnly)
        XCTAssertEqual(button?.identifier?.rawValue, configWithImage.id)
    }
}
