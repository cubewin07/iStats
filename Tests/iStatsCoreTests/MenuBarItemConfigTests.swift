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

    func testSharedVocabularyAlignment() {
        XCTAssertEqual(MetricDisplayStyle.allCases.count, 6)
        XCTAssertEqual(MetricDisplayStyle.text.vocabularyName, "Value")
        XCTAssertEqual(MetricDisplayStyle.throughput.vocabularyName, "Dual")
        XCTAssertEqual(MetricDisplayStyle.bar.vocabularyName, "Bar")
        XCTAssertEqual(MetricDisplayStyle.gauge.vocabularyName, "Ring")
        XCTAssertEqual(MetricDisplayStyle.sparkline.vocabularyName, "Graph")
        XCTAssertEqual(MetricDisplayStyle.glyph.vocabularyName, "Glyph")

        XCTAssertEqual(MetricDisplayStyle.value, .text)
        XCTAssertEqual(MetricDisplayStyle.dual, .throughput)
        XCTAssertEqual(MetricDisplayStyle.ring, .gauge)
        XCTAssertEqual(MetricDisplayStyle.graph, .sparkline)
        XCTAssertEqual(MetricDisplayStyle.symbol, .glyph)
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

    func testEveryLegacyRawValueMigratesToSupportedStyleWithoutDropping() throws {
        let decoder = JSONDecoder()
        for category in MetricCategory.allCases {
            let supported = MetricDisplayStyle.supportedStyles(for: category, hasBattery: true)
            for rawStyle in MenuBarItemConfig.allLegacyStyleRawValues {
                let json = #"{"category":"\#(category.rawValue)","style":"\#(rawStyle)"}"#.data(using: .utf8)!
                let decoded = try decoder.decode(MenuBarItemConfig.self, from: json)
                XCTAssertEqual(decoded.category, category)
                XCTAssertTrue(
                    supported.contains(decoded.style),
                    "Legacy (\(category.rawValue), \(rawStyle)) migrated to unsupported style \(decoded.style)"
                )
            }
        }
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
        XCTAssertFalse(cpuStyles.contains(where: { $0.style == .glyph }))

        let netStyles = MenuBarItemConfig.allStyles(for: .network)
        XCTAssertTrue(netStyles.contains(where: { $0.style == .throughput }))
        XCTAssertFalse(netStyles.contains(where: { $0.style == .gauge }))
    }

    func testSupportedStylesForCategories() {
        // CPU: [.text, .gauge, .bar, .sparkline]
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .cpu), [.text, .gauge, .bar, .sparkline])

        // Memory: [.text, .gauge, .bar, .sparkline]
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .memory), [.text, .gauge, .bar, .sparkline])

        // GPU: [.text, .gauge, .bar, .sparkline]
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .gpu), [.text, .gauge, .bar, .sparkline])

        // Thermal: [.text, .glyph, .sparkline]
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .thermal, hasBattery: true), [.text, .glyph, .sparkline])
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .thermal, hasBattery: false), [.text, .glyph, .sparkline])

        // Fans: overloaded .throughput removed -> [.text, .glyph, .bar, .sparkline]
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .fan), [.text, .glyph, .bar, .sparkline])
        XCTAssertFalse(MetricDisplayStyle.supportedStyles(for: .fan).contains(.throughput))

        // Network: [.throughput, .sparkline, .glyph]
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .network), [.throughput, .sparkline, .glyph])

        // Disk: [.throughput, .sparkline, .glyph, .gauge, .text]
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .disk), [.throughput, .sparkline, .glyph, .gauge, .text])

        // Power: overloaded .throughput removed; battery-only .glyph hidden on desktop
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .power, hasBattery: true), [.glyph, .text, .sparkline])
        XCTAssertEqual(MetricDisplayStyle.supportedStyles(for: .power, hasBattery: false), [.text, .sparkline])
        XCTAssertFalse(MetricDisplayStyle.supportedStyles(for: .power, hasBattery: true).contains(.throughput))
        XCTAssertFalse(MetricDisplayStyle.supportedStyles(for: .power, hasBattery: false).contains(.throughput))
    }

    func testMenuBarItemConfigMigrationTable() throws {
        let decoder = JSONDecoder()

        // memory.symbol -> memory.gauge
        let memData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"memory","style":"symbol"}"#.data(using: .utf8)!)
        XCTAssertEqual(memData.style, .gauge)
        XCTAssertEqual(memData.id, "memory.gauge")

        // gpu.symbol -> gpu.gauge
        let gpuData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"gpu","style":"symbol"}"#.data(using: .utf8)!)
        XCTAssertEqual(gpuData.style, .gauge)
        XCTAssertEqual(gpuData.id, "gpu.gauge")

        // thermal legacy per-sensor styles -> text with source
        let thermalCases: [(String, MetricSource)] = [
            ("cpuTemp", .cpu),
            ("gpuTemp", .gpu),
            ("memoryTemp", .memory),
            ("storageTemp", .ssd),
            ("batteryTemp", .battery)
        ]
        for (raw, expectedSource) in thermalCases {
            let decoded = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"thermal","style":"\#(raw)"}"#.data(using: .utf8)!)
            XCTAssertEqual(decoded.style, .text)
            XCTAssertEqual(decoded.source, expectedSource)
            XCTAssertEqual(decoded.id, "thermal.text.\(expectedSource.rawValue)")
        }

        // thermal.gauge -> glyph.peak
        let thmGaugeData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"thermal","style":"gauge"}"#.data(using: .utf8)!)
        XCTAssertEqual(thmGaugeData.style, .glyph)
        XCTAssertEqual(thmGaugeData.source, .peak)
        XCTAssertEqual(thmGaugeData.id, "thermal.glyph.peak")

        // fan.throughput -> fan.text; fan.gauge / fan.symbol -> fan.glyph
        let fanTpData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"fan","style":"throughput"}"#.data(using: .utf8)!)
        XCTAssertEqual(fanTpData.style, .text)
        XCTAssertEqual(fanTpData.id, "fan.text")

        let fanGaugeData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"fan","style":"gauge"}"#.data(using: .utf8)!)
        XCTAssertEqual(fanGaugeData.style, .glyph)
        XCTAssertEqual(fanGaugeData.id, "fan.glyph")

        let fanSymData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"fan","style":"symbol"}"#.data(using: .utf8)!)
        XCTAssertEqual(fanSymData.style, .glyph)
        XCTAssertEqual(fanSymData.id, "fan.glyph")

        // network.symbol / network.bar -> network.glyph
        let netSymData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"network","style":"symbol"}"#.data(using: .utf8)!)
        XCTAssertEqual(netSymData.style, .glyph)
        XCTAssertEqual(netSymData.id, "network.glyph")

        let netBarData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"network","style":"bar"}"#.data(using: .utf8)!)
        XCTAssertEqual(netBarData.style, .glyph)
        XCTAssertEqual(netBarData.id, "network.glyph")

        // disk.symbol -> disk.glyph; disk.bar -> disk.text
        let diskSymData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"disk","style":"symbol"}"#.data(using: .utf8)!)
        XCTAssertEqual(diskSymData.style, .glyph)
        XCTAssertEqual(diskSymData.id, "disk.glyph")

        let diskBarData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"disk","style":"bar"}"#.data(using: .utf8)!)
        XCTAssertEqual(diskBarData.style, .text)
        XCTAssertEqual(diskBarData.id, "disk.text")

        // power.symbol / power.gauge / power.bar -> power.glyph; power.throughput -> power.text
        for raw in ["symbol", "gauge", "bar"] {
            let pwrData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"power","style":"\#(raw)"}"#.data(using: .utf8)!)
            XCTAssertEqual(pwrData.style, .glyph)
            XCTAssertEqual(pwrData.id, "power.glyph")
        }

        let pwrTpData = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"power","style":"throughput"}"#.data(using: .utf8)!)
        XCTAssertEqual(pwrTpData.style, .text)
        XCTAssertEqual(pwrTpData.id, "power.text")

        // Vocabulary aliases decode cleanly too
        let valueAlias = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"cpu","style":"value"}"#.data(using: .utf8)!)
        XCTAssertEqual(valueAlias.style, .text)
        let ringAlias = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"cpu","style":"ring"}"#.data(using: .utf8)!)
        XCTAssertEqual(ringAlias.style, .gauge)
        let graphAlias = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"cpu","style":"graph"}"#.data(using: .utf8)!)
        XCTAssertEqual(graphAlias.style, .sparkline)
        let dualAlias = try decoder.decode(MenuBarItemConfig.self, from: #"{"category":"network","style":"dual"}"#.data(using: .utf8)!)
        XCTAssertEqual(dualAlias.style, .throughput)
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

    func testCategorySpecificDisplayNames() {
        XCTAssertEqual(MetricDisplayStyle.bar.displayName(for: .cpu), "Cluster Bars")
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
        XCTAssertEqual(MetricDisplayStyle.glyph.displayName(for: .power), "Battery")
        XCTAssertEqual(MetricDisplayStyle.text.displayName(for: .power, hasBattery: true), "Charge + Time")
        XCTAssertEqual(MetricDisplayStyle.text.displayName(for: .power, hasBattery: false), "Power Draw")
        XCTAssertEqual(MetricDisplayStyle.sparkline.displayName(for: .power), "Wattage History")
    }

    func testPreferencesStoreMenuBarItemOperations() {
        let suiteName = "test.istats.menubaritems.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PreferencesStore(userDefaults: defaults)

        // Initial default items
        XCTAssertFalse(store.menuBarItems.isEmpty)
        XCTAssertTrue(store.isExactItemEnabled(category: .cpu, style: .bar))

        // Set item enabled / disabled
        store.setItemEnabled(category: .gpu, style: .bar, isEnabled: true)
        XCTAssertTrue(store.isExactItemEnabled(category: .gpu, style: .bar))
        XCTAssertTrue(store.items(for: .gpu).contains(where: { $0.style == .bar }))

        // Disable item
        store.setItemEnabled(category: .gpu, style: .bar, isEnabled: false)
        XCTAssertFalse(store.isExactItemEnabled(category: .gpu, style: .bar))

        // Active items filter (category enabled + item enabled)
        store.setItemEnabled(category: .gpu, style: .bar, isEnabled: true)
        XCTAssertTrue(store.activeMenuBarItems.contains(where: { $0.category == .gpu && $0.style == .bar }))

        // Disable parent category -> item excluded from activeMenuBarItems
        store.setCategory(.gpu, isEnabled: false)
        XCTAssertFalse(store.activeMenuBarItems.contains(where: { $0.category == .gpu && $0.style == .bar }))

        // Remove item by setting isEnabled = false
        store.setItemEnabled(category: .gpu, style: .bar, isEnabled: false)
        XCTAssertFalse(store.isExactItemEnabled(category: .gpu, style: .bar))

        // Reset to defaults
        store.resetToDefaults()
        XCTAssertEqual(store.menuBarItems, MenuBarItemConfig.defaultConfigs())

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPreferencesStoreMigrationAndDeduplicationOnLoad() throws {
        let suiteName = "test.istats.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate legacy persisted data with duplicate migrated items (fan.tachometer, fan.gauge, fan.blades)
        // plus legacy fan.throughput, power.throughput, and cpu.symbol.
        let legacyJSON = """
        [
            {"category":"cpu","style":"bar"},
            {"category":"fan","style":"tachometer"},
            {"category":"fan","style":"gauge"},
            {"category":"fan","style":"blades"},
            {"category":"fan","style":"throughput"},
            {"category":"power","style":"throughput"},
            {"category":"cpu","style":"symbol"}
        ]
        """.data(using: .utf8)!

        defaults.set(legacyJSON, forKey: PreferencesStore.Keys.menuBarItems)

        let store = PreferencesStore(userDefaults: defaults)

        // cpu.bar should be present
        XCTAssertTrue(store.isExactItemEnabled(category: .cpu, style: .bar))

        // fan.tachometer, fan.gauge, and fan.blades all migrate to fan.glyph and deduplicate to exactly 1
        let fanGlyphs = store.menuBarItems.filter { $0.category == .fan && $0.style == .glyph }
        XCTAssertEqual(fanGlyphs.count, 1)
        XCTAssertTrue(store.isExactItemEnabled(category: .fan, style: .glyph))

        // Legacy fan.throughput and power.throughput migrate cleanly to .text instead of being dropped
        XCTAssertTrue(store.isExactItemEnabled(category: .fan, style: .text))
        XCTAssertTrue(store.isExactItemEnabled(category: .power, style: .text))

        // Legacy cpu.symbol migrates cleanly to cpu.gauge instead of being dropped
        XCTAssertFalse(store.isExactItemEnabled(category: .cpu, style: .glyph))
        XCTAssertTrue(store.isExactItemEnabled(category: .cpu, style: .gauge))

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLegacyPopoverStyleKeyDecodesIntoPopoverAndIsNotReEncoded() throws {
        let legacy = #"{"category":"cpu","style":"bar","popoverStyle":"history"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MenuBarItemConfig.self, from: legacy)
        XCTAssertEqual(decoded.popover?.openingTab, .history)

        let reencoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(reencoded.contains("popoverStyle"))

        // Unset popoverStyle leaves popover nil and resolves to the style default.
        let plain = try JSONDecoder().decode(MenuBarItemConfig.self, from: #"{"category":"cpu","style":"bar"}"#.data(using: .utf8)!)
        XCTAssertNil(plain.popover)
        XCTAssertEqual(plain.resolvedPopoverConfig.openingTab, .overview)
    }
}
