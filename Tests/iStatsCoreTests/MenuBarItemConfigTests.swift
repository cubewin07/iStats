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

    func testCodableMigrationFromLegacyValues() throws {
        // Test "tachometer" migration to .gauge
        let jsonTachometer = """
        {"category":"fan","style":"tachometer"}
        """.data(using: .utf8)!
        let decodedTacho = try JSONDecoder().decode(MenuBarItemConfig.self, from: jsonTachometer)
        XCTAssertEqual(decodedTacho.style, .gauge)
        XCTAssertEqual(decodedTacho.id, "fan.gauge")

        // Test "blades" migration to .symbol
        let jsonBlades = """
        {"category":"fan","style":"blades"}
        """.data(using: .utf8)!
        let decodedBlades = try JSONDecoder().decode(MenuBarItemConfig.self, from: jsonBlades)
        XCTAssertEqual(decodedBlades.style, .symbol)
        XCTAssertEqual(decodedBlades.id, "fan.symbol")
    }

    func testDefaultConfigs() {
        let defaults = MenuBarItemConfig.defaultConfigs()
        XCTAssertFalse(defaults.isEmpty)
        XCTAssertTrue(defaults.contains(where: { $0.category == .cpu && $0.style == .bar }))
        XCTAssertTrue(defaults.contains(where: { $0.category == .memory && $0.style == .bar }))
        XCTAssertTrue(defaults.contains(where: { $0.category == .network && $0.style == .throughput }))
    }

    func testAllAvailableItemsAndStyles() {
        let allItems = MenuBarItemConfig.allAvailableItems
        XCTAssertFalse(allItems.isEmpty)

        let cpuStyles = MenuBarItemConfig.allStyles(for: .cpu)
        XCTAssertTrue(cpuStyles.contains(where: { $0.style == .gauge }))
        XCTAssertTrue(cpuStyles.contains(where: { $0.style == .sparkline }))
        XCTAssertTrue(cpuStyles.contains(where: { $0.style == .bar }))
        XCTAssertTrue(cpuStyles.contains(where: { $0.style == .text }))
        XCTAssertFalse(cpuStyles.contains(where: { $0.style == .symbol }))

        let netStyles = MenuBarItemConfig.allStyles(for: .network)
        XCTAssertTrue(netStyles.contains(where: { $0.style == .throughput }))
        XCTAssertFalse(netStyles.contains(where: { $0.style == .gauge }))
    }

    func testSupportedStylesForCategories() {
        // CPU: [.text, .gauge, .bar, .sparkline]
        let cpuStyles = MetricDisplayStyle.supportedStyles(for: .cpu)
        XCTAssertEqual(cpuStyles, [.text, .gauge, .bar, .sparkline])

        // Memory: [.text, .gauge, .bar, .sparkline, .symbol]
        let memStyles = MetricDisplayStyle.supportedStyles(for: .memory)
        XCTAssertEqual(memStyles, [.text, .gauge, .bar, .sparkline, .symbol])

        // GPU: [.text, .gauge, .bar, .sparkline, .symbol]
        let gpuStyles = MetricDisplayStyle.supportedStyles(for: .gpu)
        XCTAssertEqual(gpuStyles, [.text, .gauge, .bar, .sparkline, .symbol])

        // Thermal: [.text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .batteryTemp, .gauge, .sparkline]
        let thermalStyles = MetricDisplayStyle.supportedStyles(for: .thermal, hasBattery: true)
        XCTAssertEqual(thermalStyles, [.text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .batteryTemp, .gauge, .sparkline])

        let thermalDesktopStyles = MetricDisplayStyle.supportedStyles(for: .thermal, hasBattery: false)
        XCTAssertEqual(thermalDesktopStyles, [.text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .gauge, .sparkline])
        XCTAssertFalse(thermalStyles.contains(.bar))

        // Fans: [.text, .throughput, .gauge, .bar, .sparkline, .symbol]
        let fanStyles = MetricDisplayStyle.supportedStyles(for: .fan)
        XCTAssertEqual(fanStyles, [.text, .throughput, .gauge, .bar, .sparkline, .symbol])

        // Network: [.throughput, .bar, .sparkline, .symbol]
        let netStyles = MetricDisplayStyle.supportedStyles(for: .network)
        XCTAssertEqual(netStyles, [.throughput, .bar, .sparkline, .symbol])

        // Disk: [.throughput, .gauge, .bar, .sparkline, .symbol]
        let diskStyles = MetricDisplayStyle.supportedStyles(for: .disk)
        XCTAssertEqual(diskStyles, [.throughput, .gauge, .bar, .sparkline, .symbol])

        // Power: with battery vs desktop without battery
        let pwrBatteryStyles = MetricDisplayStyle.supportedStyles(for: .power, hasBattery: true)
        XCTAssertEqual(pwrBatteryStyles, [.text, .throughput, .gauge, .bar, .sparkline, .symbol])

        let pwrDesktopStyles = MetricDisplayStyle.supportedStyles(for: .power, hasBattery: false)
        XCTAssertEqual(pwrDesktopStyles, [.throughput, .sparkline])
    }

    func testRecommendedWidgetsRemainSupportedOnBothHardwareTypes() {
        for category in MetricCategory.allCases {
            for hasBattery in [true, false] {
                let recommended = MetricDisplayStyle.recommendedStyles(for: category, hasBattery: hasBattery)
                let supported = MetricDisplayStyle.supportedStyles(for: category, hasBattery: hasBattery)
                XCTAssertFalse(recommended.isEmpty)
                XCTAssertEqual(Set(recommended).count, recommended.count)
                XCTAssertTrue(recommended.allSatisfy { supported.contains($0) })
            }
        }
        XCTAssertEqual(MetricDisplayStyle.text.displayName(for: .fan), "Fan RPM")
    }

    func testExhaustivePopoverStyleSupportAndDefaultResolution() {
        for category in MetricCategory.allCases {
            for hasBattery in [true, false] {
                let supportedWidgets = MetricDisplayStyle.supportedStyles(for: category, hasBattery: hasBattery)
                let supportedPopovers = PopoverStyle.supportedPopovers(for: category, hasBattery: hasBattery)

                XCTAssertFalse(supportedPopovers.isEmpty, "Category \(category) hasBattery=\(hasBattery) must have supported popovers")
                XCTAssertTrue(supportedPopovers.contains(.categoryDefault), "Category \(category) must always include .categoryDefault")

                for widget in supportedWidgets {
                    let defaultPop = PopoverStyle.defaultStyle(for: category, widgetStyle: widget, hasBattery: hasBattery)
                    XCTAssertTrue(
                        supportedPopovers.contains(defaultPop),
                        "Category \(category) widget \(widget) hasBattery=\(hasBattery) resolved to \(defaultPop) which is NOT in supportedPopovers: \(supportedPopovers)"
                    )
                }
            }
        }
    }

    func testCategorySpecificDisplayNames() {
        XCTAssertEqual(MetricDisplayStyle.bar.displayName(for: .cpu), "Core Cluster")
        XCTAssertEqual(MetricDisplayStyle.gauge.displayName(for: .cpu), "User/System")
        XCTAssertEqual(MetricDisplayStyle.symbol.displayName(for: .memory), "Pressure")
        XCTAssertEqual(MetricDisplayStyle.bar.displayName(for: .memory), "Allocation")
        XCTAssertEqual(MetricDisplayStyle.symbol.displayName(for: .gpu), "GPU Die")
        XCTAssertEqual(MetricDisplayStyle.text.displayName(for: .thermal), "Peak °C")
        XCTAssertEqual(MetricDisplayStyle.cpuTemp.displayName(for: .thermal), "CPU °C")
        XCTAssertEqual(MetricDisplayStyle.gpuTemp.displayName(for: .thermal), "GPU °C")
        XCTAssertEqual(MetricDisplayStyle.memoryTemp.displayName(for: .thermal), "Memory °C")
        XCTAssertEqual(MetricDisplayStyle.storageTemp.displayName(for: .thermal), "SSD °C")
        XCTAssertEqual(MetricDisplayStyle.batteryTemp.displayName(for: .thermal), "Battery °C")
        XCTAssertEqual(MetricDisplayStyle.gauge.displayName(for: .thermal), "Temp Ring")
        XCTAssertEqual(MetricDisplayStyle.sparkline.displayName(for: .thermal), "Peak History")
        XCTAssertEqual(MetricDisplayStyle.gauge.displayName(for: .fan), "Tachometer")
        XCTAssertEqual(MetricDisplayStyle.symbol.displayName(for: .fan), "Blades")
        XCTAssertEqual(MetricDisplayStyle.throughput.displayName(for: .network), "Up / Down")
        XCTAssertEqual(MetricDisplayStyle.bar.displayName(for: .disk), "Storage Bar")
        XCTAssertEqual(MetricDisplayStyle.gauge.displayName(for: .disk), "Storage Ring")
        XCTAssertEqual(MetricDisplayStyle.throughput.displayName(for: .power), "Power / Adapter Rating")
        XCTAssertEqual(MetricDisplayStyle.sparkline.displayName(for: .power), "Wattage History")
    }

    func testPreferencesStoreMenuBarItemOperations() {
        let suiteName = "test.istats.menubaritems.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PreferencesStore(userDefaults: defaults)

        // Initial default items
        XCTAssertFalse(store.menuBarItems.isEmpty)
        XCTAssertTrue(store.isItemEnabled(category: .cpu, style: .bar))

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

    func testPreferencesStoreMigrationAndDeduplicationOnLoad() throws {
        let suiteName = "test.istats.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate legacy persisted data with duplicate migrated items (fans.tachometer and fans.gauge)
        // and an unsupported item (cpu.symbol)
        let legacyJSON = """
        [
            {"category":"cpu","style":"bar"},
            {"category":"fan","style":"tachometer"},
            {"category":"fan","style":"gauge"},
            {"category":"fan","style":"blades"},
            {"category":"cpu","style":"symbol"}
        ]
        """.data(using: .utf8)!

        defaults.set(legacyJSON, forKey: PreferencesStore.Keys.menuBarItems)

        let store = PreferencesStore(userDefaults: defaults)

        // cpu.bar should be present
        XCTAssertTrue(store.isItemEnabled(category: .cpu, style: .bar))

        // fan.gauge should be present only ONCE (deduplicated)
        let fanGauges = store.menuBarItems.filter { $0.category == .fan && $0.style == .gauge }
        XCTAssertEqual(fanGauges.count, 1)

        // fan.blades migrated to fan.symbol
        XCTAssertTrue(store.isItemEnabled(category: .fan, style: .symbol))

        // cpu.symbol is unsupported on CPU and should be pruned
        XCTAssertFalse(store.isItemEnabled(category: .cpu, style: .symbol))

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPopoverStyleSupportedAndDefaultStyles() {
        // Supported popovers per category
        let cpuPopovers = PopoverStyle.supportedPopovers(for: .cpu)
        XCTAssertTrue(cpuPopovers.contains(.categoryDefault))
        XCTAssertTrue(cpuPopovers.contains(.cpuUserSystem))
        XCTAssertTrue(cpuPopovers.contains(.cpuCluster))
        XCTAssertTrue(cpuPopovers.contains(.history))

        let thermalPopovers = PopoverStyle.supportedPopovers(for: .thermal, hasBattery: true)
        XCTAssertTrue(thermalPopovers.contains(.thermalCPU))
        XCTAssertTrue(thermalPopovers.contains(.thermalGPU))
        XCTAssertTrue(thermalPopovers.contains(.thermalBattery))

        // Default style resolution
        XCTAssertEqual(PopoverStyle.defaultStyle(for: .cpu, widgetStyle: .bar), .cpuCluster)
        XCTAssertEqual(PopoverStyle.defaultStyle(for: .cpu, widgetStyle: .gauge), .cpuUserSystem)
        XCTAssertEqual(PopoverStyle.defaultStyle(for: .cpu, widgetStyle: .text), .categoryDefault)
        XCTAssertEqual(PopoverStyle.defaultStyle(for: .thermal, widgetStyle: .cpuTemp), .thermalCPU)
        XCTAssertEqual(PopoverStyle.defaultStyle(for: .thermal, widgetStyle: .gpuTemp), .thermalGPU)
        XCTAssertEqual(PopoverStyle.defaultStyle(for: .power, widgetStyle: .throughput), .powerWattage)
    }

    func testPurposefulPopoverDestinationsCoverEveryLegacySelection() {
        for category in MetricCategory.allCases {
            for hasBattery in [true, false] {
                let choices = PopoverStyle.purposefulPopovers(for: category, hasBattery: hasBattery)
                XCTAssertEqual(Set(choices).count, choices.count)
                for legacy in PopoverStyle.supportedPopovers(for: category, hasBattery: hasBattery) {
                    XCTAssertTrue(choices.contains(legacy.purposefulStyle(for: category)),
                                  "Missing destination for \(category) / \(legacy)")
                }
            }
        }
    }

    func testLegacyPopoverPresentationDoesNotChangeEncodedValue() throws {
        let original = MenuBarItemConfig(category: .fan, style: .symbol, popoverStyle: .fanBlades)
        let decoded = try JSONDecoder().decode(MenuBarItemConfig.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.popoverStyle, .fanBlades)
        XCTAssertEqual(decoded.resolvedPopoverStyle.purposefulStyle(for: .fan), .categoryDefault)
        XCTAssertEqual(PopoverStyle.memoryAllocation.purposefulStyle(for: .memory), .memoryComposition)
        XCTAssertEqual(PopoverStyle.thermalCPU.purposefulStyle(for: .thermal), .thermalCPU)
    }

    func testMenuBarItemConfigPopoverStyleResolutionAndCodable() throws {
        // Default (unset popoverStyle) resolves to defaultStyle
        let config1 = MenuBarItemConfig(category: .cpu, style: .bar)
        XCTAssertNil(config1.popoverStyle)
        XCTAssertEqual(config1.resolvedPopoverStyle, .cpuCluster)

        // Explicit popoverStyle overrides defaultStyle
        let config2 = MenuBarItemConfig(category: .cpu, style: .bar, popoverStyle: .categoryDefault)
        XCTAssertEqual(config2.popoverStyle, .categoryDefault)
        XCTAssertEqual(config2.resolvedPopoverStyle, .categoryDefault)

        // Codable roundtrip with popoverStyle
        let data = try JSONEncoder().encode(config2)
        let decoded = try JSONDecoder().decode(MenuBarItemConfig.self, from: data)
        XCTAssertEqual(decoded.popoverStyle, .categoryDefault)
        XCTAssertEqual(decoded.resolvedPopoverStyle, .categoryDefault)

        // Decoding legacy JSON without popoverStyle sets it to nil
        let legacyJSON = """
        {"category":"cpu","style":"bar"}
        """.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(MenuBarItemConfig.self, from: legacyJSON)
        XCTAssertNil(decodedLegacy.popoverStyle)
        XCTAssertEqual(decodedLegacy.resolvedPopoverStyle, .cpuCluster)
    }

    func testLegacyPopoverOverrideSurvivesReloadAndRoutesToReplacement() {
        let suiteName = "test.istats.legacy-popover.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferencesStore(userDefaults: defaults)
        store.setItemEnabled(category: .fan, style: .text, isEnabled: true)
        store.setPopoverStyle(.fanBlades, for: .fan, widgetStyle: .text)
        let reloaded = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.popoverStyle(for: .fan, widgetStyle: .text), .fanBlades)
        XCTAssertEqual(reloaded.resolvedPopoverStyle(for: .fan, widgetStyle: .text).purposefulStyle(for: .fan), .categoryDefault)
        XCTAssertTrue(reloaded.isItemEnabled(category: .fan, style: .text))
    }

    func testPreferencesStorePopoverStyleCustomizationPersistence() {
        let suiteName = "test.istats.popovers.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PreferencesStore(userDefaults: defaults)

        // Default unresolved style is nil / resolves to defaultStyle
        XCTAssertNil(store.popoverStyle(for: .cpu, widgetStyle: .bar))
        XCTAssertEqual(store.resolvedPopoverStyle(for: .cpu, widgetStyle: .bar), .cpuCluster)

        // Customize popover style
        store.setPopoverStyle(.categoryDefault, for: .cpu, widgetStyle: .bar)
        XCTAssertEqual(store.popoverStyle(for: .cpu, widgetStyle: .bar), .categoryDefault)
        XCTAssertEqual(store.resolvedPopoverStyle(for: .cpu, widgetStyle: .bar), .categoryDefault)
        XCTAssertEqual(store.menuBarItems.first(where: { $0.id == "cpu.bar" })?.popoverStyle, .categoryDefault)

        // Toggling item off and on preserves custom popover style
        store.setItemEnabled(category: .cpu, style: .bar, isEnabled: false)
        XCTAssertFalse(store.isItemEnabled(category: .cpu, style: .bar))
        XCTAssertEqual(store.popoverStyle(for: .cpu, widgetStyle: .bar), .categoryDefault)

        store.setItemEnabled(category: .cpu, style: .bar, isEnabled: true)
        XCTAssertTrue(store.isItemEnabled(category: .cpu, style: .bar))
        XCTAssertEqual(store.menuBarItems.first(where: { $0.id == "cpu.bar" })?.popoverStyle, .categoryDefault)

        // Setting default style explicitly normalizes custom override to nil
        store.setPopoverStyle(.categoryDefault, for: .cpu, widgetStyle: .bar)
        XCTAssertEqual(store.popoverStyle(for: .cpu, widgetStyle: .bar), .categoryDefault)
        store.setPopoverStyle(.cpuCluster, for: .cpu, widgetStyle: .bar)
        XCTAssertNil(store.popoverStyle(for: .cpu, widgetStyle: .bar))
        XCTAssertEqual(store.resolvedPopoverStyle(for: .cpu, widgetStyle: .bar), .cpuCluster)

        // Setting an unsupported popover style for a category normalizes to nil
        store.setPopoverStyle(.thermalCPU, for: .cpu, widgetStyle: .bar)
        XCTAssertNil(store.popoverStyle(for: .cpu, widgetStyle: .bar))
        XCTAssertEqual(store.resolvedPopoverStyle(for: .cpu, widgetStyle: .bar), .cpuCluster)

        // Relaunching PreferencesStore restores persisted popover styles
        store.setPopoverStyle(.history, for: .cpu, widgetStyle: .bar)
        let reloadedStore = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.popoverStyle(for: .cpu, widgetStyle: .bar), .history)
        XCTAssertEqual(reloadedStore.resolvedPopoverStyle(for: .cpu, widgetStyle: .bar), .history)
        XCTAssertEqual(reloadedStore.menuBarItems.first(where: { $0.id == "cpu.bar" })?.popoverStyle, .history)

        // Reset to defaults clears customizations
        store.resetToDefaults()
        XCTAssertNil(store.popoverStyle(for: .cpu, widgetStyle: .bar))
        XCTAssertEqual(store.resolvedPopoverStyle(for: .cpu, widgetStyle: .bar), .cpuCluster)

        defaults.removePersistentDomain(forName: suiteName)
    }
}

