import XCTest
@testable import iStatsCore

final class PowerStateVariantTests: XCTestCase {

    func testPowerStateVariantResolution() {
        // 1. Desktop Mac / No Battery
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: nil, state: nil, hasBattery: false),
            .acDesktop
        )
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 100.0, state: .acConnected, hasBattery: false),
            .acDesktop
        )

        // 2. Unavailable telemetry
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: nil, state: .discharging, hasBattery: true),
            .unavailable
        )

        // 3. Charging on AC
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 45.0, state: .charging, hasBattery: true, drawWatts: 15.0, adapterWatts: 67.0),
            .charging
        )

        // 4. Fully Charged on AC (explicit state or >= 99%)
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 100.0, state: .charged, hasBattery: true, adapterWatts: 67.0),
            .charged
        )
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 99.5, state: .acConnected, hasBattery: true, adapterWatts: 67.0),
            .charged
        )

        // 5. On Hold (AC connected, but not charging and < 99% - e.g. 80% optimized limit)
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 80.0, state: .acConnected, hasBattery: true, drawWatts: 12.0, adapterWatts: 68.0),
            .onHold
        )

        // 6. Power Deficit (AC connected, but draw exceeds adapter capacity)
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 60.0, state: .charging, hasBattery: true, drawWatts: 85.0, adapterWatts: 30.0),
            .powerDeficit
        )
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 60.0, state: .acConnected, hasBattery: true, drawWatts: 70.0, adapterWatts: 45.0),
            .powerDeficit
        )
        // Deficit via negative amperage while on AC
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 75.0, state: .acConnected, hasBattery: true, drawWatts: 25.0, adapterWatts: 30.0, amperageMilliAmps: -800.0),
            .powerDeficit
        )

        // 7. Low Battery (discharging on battery at or below 20%)
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 20.0, state: .discharging, hasBattery: true),
            .lowBattery
        )
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 5.0, state: .discharging, hasBattery: true),
            .lowBattery
        )

        // 8. Normal discharging on battery (> 20%)
        XCTAssertEqual(
            PowerStateVariant.resolve(charge: 75.0, state: .discharging, hasBattery: true),
            .discharging
        )
    }

    func testPowerSampleVariantProperty() {
        // Test sample wrapping
        let holdSample = PowerSample(
            hasBattery: true,
            charge: 80.0,
            state: .acConnected,
            powerDrawWatts: 10.5,
            adapterWatts: 68.0
        )
        XCTAssertEqual(holdSample.variant, .onHold)
        XCTAssertTrue(holdSample.isOnHold)
        XCTAssertFalse(holdSample.isPowerDeficit)
        XCTAssertFalse(holdSample.isLowBattery)
        XCTAssertFalse(holdSample.isUsingBatteryPower)

        let deficitSample = PowerSample(
            hasBattery: true,
            charge: 50.0,
            state: .charging,
            powerDrawWatts: 90.0,
            adapterWatts: 30.0
        )
        XCTAssertEqual(deficitSample.variant, .powerDeficit)
        XCTAssertTrue(deficitSample.isPowerDeficit)

        let lowSample = PowerSample(
            hasBattery: true,
            charge: 14.0,
            state: .discharging
        )
        XCTAssertEqual(lowSample.variant, .lowBattery)
        XCTAssertTrue(lowSample.isLowBattery)
        XCTAssertTrue(lowSample.isUsingBatteryPower)

        let normalBatterySample = PowerSample(
            hasBattery: true,
            charge: 72.0,
            state: .discharging
        )
        XCTAssertEqual(normalBatterySample.variant, .discharging)
        XCTAssertTrue(normalBatterySample.isUsingBatteryPower)
        XCTAssertFalse(normalBatterySample.isLowBattery)

        let desktopSample = PowerSample(
            hasBattery: false,
            powerDrawWatts: 42.0
        )
        XCTAssertEqual(desktopSample.variant, .acDesktop)
    }

    func testPowerStateVariantMetadata() {
        for variant in PowerStateVariant.allCases {
            XCTAssertFalse(variant.displayName.isEmpty)
            XCTAssertFalse(variant.shortBadge.isEmpty)
            XCTAssertFalse(variant.systemImageName.isEmpty)
        }
    }
}
