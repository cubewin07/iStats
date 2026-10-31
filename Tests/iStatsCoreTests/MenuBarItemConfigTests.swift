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
        // Test "tachometer" migration to .glyph
        let jsonTachometer = """
        {"category":"fan","style":"tachometer"}
        """.data(using: .utf8)!
        let decodedTacho = try JSONDecoder().decode(MenuBarItemConfig.self, from: jsonTachometer)
        XCTAssertEqual(decodedTacho.style, .glyph)
        XCTAssertEqual(decodedTacho.id, "fan.glyph")

        // Test "blades" migration to .glyph
        let jsonBlades = """
        {"category":"fan","style":"blades"}
        """.data(using: .utf8)!
        let decodedBlades = try JSONDecoder().decode(MenuBarItemConfig.self, from: jsonBlades)
        XCTAssertEqual(decodedBlades.style, .glyph)
        XCTAssertEqual(decodedBlades.id, "fan.glyph")
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

        // Memory: [.text, .gauge, .bar, .sparkline]
        let memStyles = MetricDisplayStyle.supportedStyles(for: .memory)
        XCTAssertEqual(memStyles, [.text, .gauge, .bar, .sparkline])

        // GPU: [.text, .gauge, .bar, .sparkline]
        let gpuStyles = MetricDisplayStyle.supportedStyles(for: .gpu)
        XCTAssertEqual(gpuStyles, [.text, .gauge, .bar, .sparkline])

        // Thermal: [.text, .glyph, .sparkline]
        let thermalStyles = MetricDisplayStyle.supportedStyles(for: .thermal, hasBattery: true)
        XCTAssertEqual(thermalStyles, [.text, .glyph, .sparkline])

        let thermalDesktopStyles = MetricDisplayStyle.supportedStyles(for: .thermal, hasBattery: false)
        XCTAssertEqual(thermalDesktopStyles, [.text, .glyph, .sparkline])

        // Fans: [.text, .throughput, .glyph, .bar, .sparkline]
        let fanStyles = MetricDisplayStyle.supportedStyles(for: .fan)
        XCTAssertEqual(fanStyles, [.text, .throughput, .glyph, .bar, .sparkline])

        // Network: [.throughput, .sparkline, .symbol]
        let netStyles = MetricDisplayStyle.supportedStyles(for: .network)
        XCTAssertEqual(netStyles, [.throughput, .sparkline, .symbol])

        // Disk: [.throughput, .sparkline, .symbol, .gauge, .text]
        let diskStyles = MetricDisplayStyle.supportedStyles(for: .disk)
        XCTAssertEqual(diskStyles, [.throughput, .sparkline, .symbol, .gauge, .text])

        // Power: with battery vs desktop without battery
        let pwrBatteryStyles = MetricDisplayStyle.supportedStyles(for: .power, hasBattery: true)
        XCTAssertEqual(pwrBatteryStyles, [.symbol, .text, .throughput, .sparkline])

        let pwrDesktopStyles = MetricDisplayStyle.supportedStyles(for: .power, hasBattery: false)
        XCTAssertEqual(pwrDesktopStyles, [.throughput, .sparkline])
    }

    func testMenuBarItemConfigMigrationTable() throws {
        let decoder = JSONDecoder()

        // memory.symbol -> memory.gauge
        let memData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"memory","style":"symbol"}
        """.data(using: .utf8)!)
        XCTAssertEqual(memData.style, .gauge)
        XCTAssertEqual(memData.id, "memory.gauge")

        // gpu.symbol -> gpu.gauge
        let gpuData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"gpu","style":"symbol"}
        """.data(using: .utf8)!)
        XCTAssertEqual(gpuData.style, .gauge)
        XCTAssertEqual(gpuData.id, "gpu.gauge")

        // thermal legacy styles -> text with source
        let cpuTempData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"thermal","style":"cpuTemp"}
        """.data(using: .utf8)!)
        XCTAssertEqual(cpuTempData.style, .text)
        XCTAssertEqual(cpuTempData.source, .cpu)
        XCTAssertEqual(cpuTempData.id, "thermal.text.cpu")

        let gpuTempData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"thermal","style":"gpuTemp"}
        """.data(using: .utf8)!)
        XCTAssertEqual(gpuTempData.style, .text)
        XCTAssertEqual(gpuTempData.source, .gpu)
        XCTAssertEqual(gpuTempData.id, "thermal.text.gpu")

        let memTempData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"thermal","style":"memoryTemp"}
        """.data(using: .utf8)!)
        XCTAssertEqual(memTempData.style, .text)
        XCTAssertEqual(memTempData.source, .memory)
        XCTAssertEqual(memTempData.id, "thermal.text.memory")

        let ssdTempData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"thermal","style":"storageTemp"}
        """.data(using: .utf8)!)
        XCTAssertEqual(ssdTempData.style, .text)
        XCTAssertEqual(ssdTempData.source, .ssd)
        XCTAssertEqual(ssdTempData.id, "thermal.text.ssd")

        let batTempData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"thermal","style":"batteryTemp"}
        """.data(using: .utf8)!)
        XCTAssertEqual(batTempData.style, .text)
        XCTAssertEqual(batTempData.source, .battery)
        XCTAssertEqual(batTempData.id, "thermal.text.battery")

        // thermal.gauge -> glyph.peak
        let thmGaugeData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"thermal","style":"gauge"}
        """.data(using: .utf8)!)
        XCTAssertEqual(thmGaugeData.style, .glyph)
        XCTAssertEqual(thmGaugeData.source, .peak)
        XCTAssertEqual(thmGaugeData.id, "thermal.glyph.peak")

        // fan.gauge / fan.symbol -> fan.glyph
        let fanGaugeData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"fan","style":"gauge"}
        """.data(using: .utf8)!)
        XCTAssertEqual(fanGaugeData.style, .glyph)
        XCTAssertEqual(fanGaugeData.id, "fan.glyph")

        let fanSymData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"fan","style":"symbol"}
        """.data(using: .utf8)!)
        XCTAssertEqual(fanSymData.style, .glyph)
        XCTAssertEqual(fanSymData.id, "fan.glyph")

        // network.bar -> network.symbol
        let netBarData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"network","style":"bar"}
        """.data(using: .utf8)!)
        XCTAssertEqual(netBarData.style, .symbol)
        XCTAssertEqual(netBarData.id, "network.symbol")

        // disk.bar -> disk.text
        let diskBarData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"disk","style":"bar"}
        """.data(using: .utf8)!)
        XCTAssertEqual(diskBarData.style, .text)
        XCTAssertEqual(diskBarData.id, "disk.text")

        // power.gauge / power.bar -> power.symbol
        let pwrGaugeData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"power","style":"gauge"}
        """.data(using: .utf8)!)
        XCTAssertEqual(pwrGaugeData.style, .symbol)
        XCTAssertEqual(pwrGaugeData.id, "power.symbol")

        let pwrBarData = try decoder.decode(MenuBarItemConfig.self, from: """
        {"category":"power","style":"bar"}
        """.data(using: .utf8)!)
        XCTAssertEqual(pwrBarData.style, .symbol)
        XCTAssertEqual(pwrBarData.id, "power.symbol")
    }

    func testDeduplicationPreservesOrder() {
        let item1 = MenuBarItemConfig(category: .cpu, style: .bar)
        let item2 = MenuBarItemConfig(category: .memory, style: .gauge)
        let item3 = MenuBarItemConfig(category: .network, style: .throughput)
        let duplicateItem1 = MenuBarItemConfig(category: .cpu, style: .bar)

        let items = [item1, item2, duplicateItem1, item3]
        let deduped = MenuBarItemConfig.deduplicated(items)

        XCTAssertEqual(deduped.count, 3)
        XCTAssertEqual(deduped[0].id, item1.id)
        XCTAssertEqual(deduped[1].id, item2.id)
        XCTAssertEqual(deduped[2].id, item3.id)
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
        XCTAssertEqual(MetricDisplayStyle.gauge.displayName(for: .cpu), "Load Ring")
        XCTAssertEqual(MetricDisplayStyle.gauge.displayName(for: .memory), "Pressure Ring")
        XCTAssertEqual(MetricDisplayStyle.bar.displayName(for: .memory), "Allocation")
        XCTAssertEqual(MetricDisplayStyle.gauge.displayName(for: .gpu), "Load Ring")
        XCTAssertEqual(MetricDisplayStyle.text.displayName(for: .thermal), "Temperature")
        XCTAssertEqual(MetricDisplayStyle.glyph.displayName(for: .thermal), "Thermometer")
        XCTAssertEqual(MetricDisplayStyle.sparkline.displayName(for: .thermal), "Peak History")
        XCTAssertEqual(MetricDisplayStyle.text.displayName(for: .fan), "Fan RPM")
        XCTAssertEqual(MetricDisplayStyle.glyph.displayName(for: .fan), "Fan Glyph")
        XCTAssertEqual(MetricDisplayStyle.throughput.displayName(for: .network), "Up / Down")
        XCTAssertEqual(MetricDisplayStyle.text.displayName(for: .disk), "Free Space")
        XCTAssertEqual(MetricDisplayStyle.gauge.displayName(for: .disk), "Storage Ring")
        XCTAssertEqual(MetricDisplayStyle.symbol.displayName(for: .power), "Battery")
        XCTAssertEqual(MetricDisplayStyle.throughput.displayName(for: .power), "Draw / Adapter W")
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

        // fan.tachometer, fan.gauge, and fan.blades all migrate to fan.glyph and deduplicate to exactly 1
        let fanGlyphs = store.menuBarItems.filter { $0.category == .fan && $0.style == .glyph }
        XCTAssertEqual(fanGlyphs.count, 1)
        XCTAssertTrue(store.isItemEnabled(category: .fan, style: .glyph))

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

