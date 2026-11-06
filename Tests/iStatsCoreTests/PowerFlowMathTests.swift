import XCTest
@testable import iStatsCore

final class PowerFlowMathTests: XCTestCase {

    func testParticleSpeedClampingAndLogCurve() {
        XCTAssertEqual(PowerFlowMath.particleSpeed(watts: 0), 0.0)
        XCTAssertEqual(PowerFlowMath.particleSpeed(watts: -10), 0.0)

        let speed1W = PowerFlowMath.particleSpeed(watts: 1.0)
        XCTAssertGreaterThanOrEqual(speed1W, 0.1)
        XCTAssertLessThanOrEqual(speed1W, 1.0)

        let speed50W = PowerFlowMath.particleSpeed(watts: 50.0)
        let speed100W = PowerFlowMath.particleSpeed(watts: 100.0)
        XCTAssertEqual(speed100W, 1.0, accuracy: 0.01)
        XCTAssertGreaterThan(speed50W, speed1W)
        XCTAssertLessThan(speed50W, speed100W)

        let speed200W = PowerFlowMath.particleSpeed(watts: 200.0)
        XCTAssertEqual(speed200W, 1.0)
    }

    func testChargingWithVoltageAndAmperage() {
        let flow = PowerFlowMath.calculateFlow(
            hasBattery: true,
            state: .charging,
            adapterWatts: 67.0,
            powerDrawWatts: 18.5,
            voltageVolts: 12.0,
            amperageMilliAmps: 2500.0 // +30W into battery
        )

        XCTAssertEqual(flow.adapterToMac, 18.5)
        XCTAssertEqual(flow.adapterToBattery, 30.0)
        XCTAssertNil(flow.batteryToMac)
        XCTAssertEqual(flow.batteryNetWatts, 30.0)
        XCTAssertGreaterThan(flow.speedAdapterToMac, 0.1)
        XCTAssertGreaterThan(flow.speedAdapterToBattery, 0.1)
        XCTAssertEqual(flow.speedBatteryToMac, 0.0)
    }

    func testDischargingOnBattery() {
        let flow = PowerFlowMath.calculateFlow(
            hasBattery: true,
            state: .discharging,
            adapterWatts: nil,
            powerDrawWatts: 22.0,
            voltageVolts: 11.5,
            amperageMilliAmps: -1913.0 // -22W out of battery
        )

        XCTAssertNil(flow.adapterToMac)
        XCTAssertNil(flow.adapterToBattery)
        XCTAssertEqual(flow.batteryToMac, 22.0)
        XCTAssertEqual(flow.batteryNetWatts, (11.5 * -1913.0) / 1000.0)
        XCTAssertGreaterThan(flow.speedBatteryToMac, 0.1)
    }

    func testOnHoldState() {
        let flow = PowerFlowMath.calculateFlow(
            hasBattery: true,
            state: .acConnected,
            adapterWatts: 96.0,
            powerDrawWatts: 25.0,
            voltageVolts: 12.6,
            amperageMilliAmps: 0.0 // 0W net
        )

        XCTAssertEqual(flow.adapterToMac, 25.0)
        XCTAssertNil(flow.adapterToBattery)
        XCTAssertNil(flow.batteryToMac)
        XCTAssertEqual(flow.batteryNetWatts, 0.0)
    }

    func testPowerDeficitAssisting() {
        let flow = PowerFlowMath.calculateFlow(
            hasBattery: true,
            state: .acConnected,
            adapterWatts: 30.0,
            powerDrawWatts: 55.0,
            voltageVolts: 11.0,
            amperageMilliAmps: -2272.7 // ~ -25W
        )

        XCTAssertEqual(flow.adapterToMac, 30.0)
        XCTAssertNil(flow.adapterToBattery)
        XCTAssertEqual(try XCTUnwrap(flow.batteryToMac), abs((11.0 * -2272.7) / 1000.0), accuracy: 0.1)
        XCTAssertLessThan(flow.batteryNetWatts ?? 0, 0)
    }

    func testMissingVoltageAndAmperageFallbacks() {
        let flow = PowerFlowMath.calculateFlow(
            hasBattery: true,
            state: .charging,
            adapterWatts: 60.0,
            powerDrawWatts: 20.0,
            voltageVolts: nil,
            amperageMilliAmps: nil
        )

        XCTAssertEqual(flow.adapterToMac, 20.0)
        XCTAssertEqual(flow.adapterToBattery, 40.0)
        XCTAssertNil(flow.batteryToMac)
        XCTAssertNil(flow.batteryNetWatts)
    }

    func testDesktopMacWithoutBattery() {
        let flow = PowerFlowMath.calculateFlow(
            hasBattery: false,
            state: nil,
            adapterWatts: 140.0,
            powerDrawWatts: 42.0,
            voltageVolts: nil,
            amperageMilliAmps: nil
        )

        XCTAssertEqual(flow.adapterToMac, 42.0)
        XCTAssertNil(flow.adapterToBattery)
        XCTAssertNil(flow.batteryToMac)
        XCTAssertNil(flow.batteryNetWatts)
    }
}
