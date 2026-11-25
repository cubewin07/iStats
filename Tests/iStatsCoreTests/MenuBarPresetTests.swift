import XCTest
@testable import iStatsCore

final class MenuBarPresetTests: XCTestCase {
    func testBalancedMatchesDefaultConfigs() {
        for hasBattery in [true, false] {
            for hasFans in [true, false] {
                XCTAssertEqual(
                    MenuBarPreset.balanced.configs(hasBattery: hasBattery, hasFans: hasFans),
                    MenuBarItemConfig.defaultConfigs(),
                    "Balanced preset must stay consistent with MenuBarItemConfig.defaultConfigs()"
                )
            }
        }
    }

    func testMinimalIsSingleCPUValue() {
        let configs = MenuBarPreset.minimal.configs(hasBattery: true, hasFans: true)
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs.first?.category, .cpu)
        XCTAssertEqual(configs.first?.style, .text)
    }

    func testEverythingIsHardwareAware() {
        let fullLaptop = MenuBarPreset.everything.configs(hasBattery: true, hasFans: true)
        XCTAssertTrue(fullLaptop.contains(where: { $0.category == .power }))
        XCTAssertTrue(fullLaptop.contains(where: { $0.category == .fan }))
        XCTAssertEqual(fullLaptop.count, MetricCategory.allCases.count)

        let fanlessLaptop = MenuBarPreset.everything.configs(hasBattery: true, hasFans: false)
        XCTAssertTrue(fanlessLaptop.contains(where: { $0.category == .power }))
        XCTAssertFalse(fanlessLaptop.contains(where: { $0.category == .fan }))

        let desktopWithFans = MenuBarPreset.everything.configs(hasBattery: false, hasFans: true)
        XCTAssertFalse(desktopWithFans.contains(where: { $0.category == .power }))
        XCTAssertTrue(desktopWithFans.contains(where: { $0.category == .fan }))

        let fanlessDesktop = MenuBarPreset.everything.configs(hasBattery: false, hasFans: false)
        XCTAssertFalse(fanlessDesktop.contains(where: { $0.category == .power }))
        XCTAssertFalse(fanlessDesktop.contains(where: { $0.category == .fan }))
    }

    func testEveryPresetProducesUniqueSupportedConfigs() {
        for preset in MenuBarPreset.allCases {
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertFalse(preset.summary.isEmpty)

            for hasBattery in [true, false] {
                for hasFans in [true, false] {
                    let configs = preset.configs(hasBattery: hasBattery, hasFans: hasFans)
                    XCTAssertFalse(configs.isEmpty, "\(preset) must produce at least one config")
                    XCTAssertEqual(configs, MenuBarPreset.items(for: preset, hasBattery: hasBattery, hasFans: hasFans))

                    let ids = configs.map(\.id)
                    XCTAssertEqual(Set(ids).count, ids.count, "\(preset) must produce unique widget IDs")

                    for config in configs {
                        let supported = MetricDisplayStyle.supportedStyles(for: config.category, hasBattery: hasBattery)
                        XCTAssertTrue(
                            supported.contains(config.style),
                            "\(preset) emitted unsupported style \(config.style) for \(config.category) (hasBattery=\(hasBattery))"
                        )
                        if !hasBattery {
                            XCTAssertNotEqual(config.category, .power, "\(preset) must omit battery widgets when !hasBattery")
                        }
                        if !hasFans {
                            XCTAssertNotEqual(config.category, .fan, "\(preset) must omit fan widgets when !hasFans")
                        }
                    }
                }
            }
        }
    }
}
