import XCTest
@testable import iStatsCore

final class CategoryIdentityTests: XCTestCase {
    func testEveryCategoryHasNameLabelSymbol() {
        for c in MetricCategory.allCases {
            for hasBattery in [true, false] {
                XCTAssertFalse(c.identity.displayName(hasBattery: hasBattery).isEmpty)
                XCTAssertFalse(c.identity.shortLabel(hasBattery: hasBattery).isEmpty)
                XCTAssertFalse(c.identity.symbol(hasBattery: hasBattery).isEmpty)
            }
        }
    }

    func testPowerFollowsBattery() {
        let p = CategoryIdentity(.power)
        XCTAssertEqual(p.displayName(hasBattery: true), "Battery")
        XCTAssertEqual(p.displayName(hasBattery: false), "Power")
        XCTAssertEqual(p.symbol(hasBattery: true), "battery.100percent")
        XCTAssertEqual(p.symbol(hasBattery: false), "powerplug")
        XCTAssertEqual(p.shortLabel(hasBattery: false), "PWR")
    }

    func testIdentitySymbols() {
        XCTAssertEqual(CategoryIdentity(.gpu).symbol(), "cube.transparent")
        XCTAssertEqual(CategoryIdentity(.network).symbol(), "network")
        XCTAssertEqual(CategoryIdentity(.fan).symbol(), "fan")
        XCTAssertEqual(CategoryIdentity(.thermal).symbol(), "thermometer.medium")
    }

    func testBatteryLiveSymbol() {
        let p = CategoryIdentity(.power)
        func sym(_ pct: Double, _ charging: Bool = false) -> String {
            p.liveSymbol(LiveSymbolState(batteryChargePercent: pct, isCharging: charging))
        }
        XCTAssertEqual(sym(0), "battery.0percent")
        XCTAssertEqual(sym(25), "battery.25percent")
        XCTAssertEqual(sym(50), "battery.50percent")
        XCTAssertEqual(sym(75), "battery.75percent")
        XCTAssertEqual(sym(100), "battery.100percent")
        XCTAssertEqual(sym(40, true), "battery.100percent.bolt")
        XCTAssertEqual(p.liveSymbol(LiveSymbolState(), hasBattery: true), "battery.100percent")
        XCTAssertEqual(p.liveSymbol(LiveSymbolState(batteryChargePercent: 50), hasBattery: false), "powerplug")
    }

    func testNetworkLiveSymbol() {
        let n = CategoryIdentity(.network)
        XCTAssertEqual(n.liveSymbol(LiveSymbolState(connectionType: .wifi)), "wifi")
        XCTAssertEqual(n.liveSymbol(LiveSymbolState(connectionType: .ethernet)), "cable.connector")
        XCTAssertEqual(n.liveSymbol(LiveSymbolState()), "network")
    }

    func testFanThermalDiskLiveSymbol() {
        XCTAssertEqual(CategoryIdentity(.fan).liveSymbol(LiveSymbolState(isFanless: true)), "fan.slash")
        XCTAssertEqual(CategoryIdentity(.fan).liveSymbol(LiveSymbolState(isFanless: false)), "fan")
        let t = CategoryIdentity(.thermal)
        XCTAssertEqual(t.liveSymbol(LiveSymbolState(thermalPeakCelsius: 40)), "thermometer.low")
        XCTAssertEqual(t.liveSymbol(LiveSymbolState(thermalPeakCelsius: 65)), "thermometer.medium")
        XCTAssertEqual(t.liveSymbol(LiveSymbolState(thermalPeakCelsius: 85)), "thermometer.high")
        let d = CategoryIdentity(.disk)
        XCTAssertEqual(d.liveSymbol(LiveSymbolState(isExternalVolume: false)), "internaldrive.fill")
        XCTAssertEqual(d.liveSymbol(LiveSymbolState(isExternalVolume: true)), "externaldrive.fill")
    }

    func testStatusLevelSymbols() {
        for level in StatusLevel.allCases {
            XCTAssertEqual(level.symbolNameFilled, level.symbolName + ".fill")
        }
        XCTAssertEqual(Set(StatusLevel.allCases.map(\.symbolName)).count, 4)
    }

    func testAllSymbolsIncludeIdentityAndLive() {
        for c in MetricCategory.allCases {
            XCTAssertTrue(c.identity.allSymbols.contains(c.identity.symbol()))
        }
    }
}
