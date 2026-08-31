import XCTest
import Darwin
@testable import iStatsCore
@testable import iStats

final class PowerSamplerTests: XCTestCase {

    // MARK: - Mocks

    final class MockPowerInfoProvider: PowerInfoProvider, @unchecked Sendable {
        var mockSnapshot = RawPowerSourceSnapshot(hasBattery: true)
        var mockSmartBattery: RawSmartBatteryData? = nil
        var shouldThrow: Bool = false

        func powerSourceSnapshot() throws -> RawPowerSourceSnapshot {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock power source error")
            }
            return mockSnapshot
        }

        func smartBatteryData() throws -> RawSmartBatteryData? {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock smart battery error")
            }
            return mockSmartBattery
        }
    }

    // MARK: - Task 4.1 Tests: Charge, State, Time Remaining

    func testPowerSamplerCategory() {
        let sampler = PowerSampler(provider: MockPowerInfoProvider())
        XCTAssertEqual(sampler.category, .power)
    }

    func testPowerSamplerDischargingStateAndTimeRemaining() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "Battery Power",
            currentCapacity: 75,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false,
            timeToEmpty: 180, // 180 minutes
            timeToFullCharge: nil,
            timeRemainingEstimate: 10800.0 // 180 * 60 seconds
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.charge, 75.0)
        XCTAssertEqual(sample.state, .discharging)
        XCTAssertEqual(sample.timeRemaining, 10800.0)
    }

    func testPowerSamplerChargingState() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "AC Power",
            currentCapacity: 45,
            maxCapacity: 100,
            isCharging: true,
            isCharged: false,
            timeToEmpty: 0,
            timeToFullCharge: 50, // 50 minutes to full
            timeRemainingEstimate: -2.0 // AC unlimited
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.charge, 45.0)
        XCTAssertEqual(sample.state, .charging)
        XCTAssertEqual(sample.timeRemaining, 3000.0) // 50 * 60 = 3000s
    }

    func testPowerSamplerChargedState() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "AC Power",
            currentCapacity: 100,
            maxCapacity: 100,
            isCharging: false,
            isCharged: true,
            timeToEmpty: 0,
            timeToFullCharge: 0,
            timeRemainingEstimate: -2.0
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.charge, 100.0)
        XCTAssertEqual(sample.state, .charged)
        XCTAssertNil(sample.timeRemaining)
    }

    func testPowerSamplerACConnectedNotCharging() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "AC Power",
            currentCapacity: 80,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false,
            timeToEmpty: 0,
            timeToFullCharge: 0,
            timeRemainingEstimate: -2.0
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.charge, 80.0)
        XCTAssertEqual(sample.state, .acConnected)
        XCTAssertNil(sample.timeRemaining)
    }

    func testPowerSamplerACConnectedWhenFirmwareReportsChargedUnder100() throws {
        let mock = MockPowerInfoProvider()
        // Firmware sets isCharged: true at 80% (charge limit), but charge is < 99.0%
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "AC Power",
            currentCapacity: 80,
            maxCapacity: 100,
            isCharging: false,
            isCharged: true, // IOKit/firmware flag
            timeToEmpty: 0,
            timeToFullCharge: 0,
            timeRemainingEstimate: -2.0
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.charge, 80.0)
        XCTAssertEqual(sample.state, .acConnected, "When charge is under 99%, state must degrade to .acConnected instead of .charged")
        XCTAssertNil(sample.timeRemaining)
    }

    func testPowerSamplerTimeRemainingCalculatingReturnsNil() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "Battery Power",
            currentCapacity: 80,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false,
            timeToEmpty: -1, // Calculating
            timeToFullCharge: -1,
            timeRemainingEstimate: -1.0 // Calculating
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.charge, 80.0)
        XCTAssertEqual(sample.state, .discharging)
        XCTAssertNil(sample.timeRemaining, "When macOS is calculating time remaining, timeRemaining must be nil (not 0 or -1)")
    }

    func testPowerSamplerThrowsWhenProviderFails() {
        let mock = MockPowerInfoProvider()
        mock.shouldThrow = true

        let sampler = PowerSampler(provider: mock)
        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError but got \(error)")
                return
            }
            if case .systemCallFailed(let reason) = samplerError {
                XCTAssertTrue(reason.contains("Mock power source error"))
            } else {
                XCTFail("Expected systemCallFailed but got \(samplerError)")
            }
        }
    }

    func testPowerSamplerNoBatteryMachine() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: false,
            isPresent: false,
            powerSourceState: "AC Power"
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertFalse(sample.hasBattery)
        XCTAssertNil(sample.charge)
        XCTAssertNil(sample.state)
        XCTAssertNil(sample.timeRemaining)
        XCTAssertNil(sample.cycleCount)
        XCTAssertNil(sample.condition)
        XCTAssertNil(sample.designCapacity)
        XCTAssertNil(sample.currentMaxCapacity)
    }

    // MARK: - Task 4.2 Tests: Battery Health Metrics

    func testPowerSamplerBatteryHealthMetrics() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "Battery Power",
            currentCapacity: 80,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false
        )
        mock.mockSmartBattery = RawSmartBatteryData(
            cycleCount: 79,
            condition: "Normal",
            designCapacity: 6249,
            currentMaxCapacity: 5894
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.cycleCount, 79)
        XCTAssertEqual(sample.condition, "Normal")
        XCTAssertEqual(sample.designCapacity, 6249)
        XCTAssertEqual(sample.currentMaxCapacity, 5894)
    }

    func testPowerSamplerHealthConditionServiceBattery() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "Battery Power",
            currentCapacity: 50,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false
        )
        mock.mockSmartBattery = RawSmartBatteryData(
            cycleCount: 1200,
            condition: "Service Battery",
            designCapacity: 6000,
            currentMaxCapacity: 3500
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.cycleCount, 1200)
        XCTAssertEqual(sample.condition, "Service Battery")
        XCTAssertEqual(sample.designCapacity, 6000)
        XCTAssertEqual(sample.currentMaxCapacity, 3500)
    }

    func testPowerSamplerSmartBatteryUnavailableDegradesToNil() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "Battery Power",
            currentCapacity: 80,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false
        )
        mock.mockSmartBattery = nil // Unavailable smart battery

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.charge, 80.0)
        XCTAssertNil(sample.cycleCount)
        XCTAssertNil(sample.condition)
        XCTAssertNil(sample.designCapacity)
        XCTAssertNil(sample.currentMaxCapacity)
        XCTAssertNil(sample.powerDrawWatts)
        XCTAssertNil(sample.adapterWatts)
    }

    // MARK: - Task 4.3 Tests: Power Draw & Adapter Wattage

    func testPowerSamplerInstantaneousPowerDrawAndAdapterWatts() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "AC Power",
            currentCapacity: 80,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false
        )
        mock.mockSmartBattery = RawSmartBatteryData(
            cycleCount: 79,
            condition: "Normal",
            designCapacity: 6249,
            currentMaxCapacity: 5894,
            adapterWatts: 68.0,
            powerDrawWatts: 15.299
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.adapterWatts, 68.0)
        XCTAssertEqual(sample.powerDrawWatts, 15.299)
    }

    func testPowerSamplerPowerDrawFromAmperageAndVoltage() throws {
        // Amperage = -1500 mA, Voltage = 12000 mV -> 18.0 W
        let watts = abs(-1500.0 * 12000.0) / 1_000_000.0

        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "Battery Power",
            currentCapacity: 50,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false
        )
        mock.mockSmartBattery = RawSmartBatteryData(
            cycleCount: 150,
            condition: "Normal",
            designCapacity: 6000,
            currentMaxCapacity: 5500,
            adapterWatts: nil, // Unplugged
            powerDrawWatts: watts
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertNil(sample.adapterWatts)
        XCTAssertEqual(sample.powerDrawWatts, 18.0)
    }

    func testPowerSamplerUnexposedWattageDegradesToNil() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: true,
            powerSourceState: "Battery Power",
            currentCapacity: 80,
            maxCapacity: 100,
            isCharging: false,
            isCharged: false
        )
        mock.mockSmartBattery = RawSmartBatteryData(
            cycleCount: 79,
            condition: "Normal",
            designCapacity: 6249,
            currentMaxCapacity: 5894,
            adapterWatts: nil,
            powerDrawWatts: nil
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertTrue(sample.hasBattery)
        XCTAssertNil(sample.adapterWatts, "Unexposed adapter watts must be nil (not 0.0)")
        XCTAssertNil(sample.powerDrawWatts, "Unexposed power draw watts must be nil (not 0.0)")
    }

    // MARK: - Task 4.4 Tests: Handle the No-Battery Case (Requirement 8.4)

    func testPowerSamplerBatteryNotPresentGracefulDegradation() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: false, // Battery reported but physically absent/disconnected
            powerSourceState: "AC Power",
            currentCapacity: nil,
            maxCapacity: nil,
            isCharging: false,
            isCharged: false
        )
        mock.mockSmartBattery = nil

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertFalse(sample.hasBattery, "When battery isPresent is false, hasBattery must be false")
        XCTAssertNil(sample.charge, "Battery charge must be nil when battery is not present")
        XCTAssertNil(sample.state, "Battery state must be nil when battery is not present")
        XCTAssertNil(sample.timeRemaining, "Time remaining must be nil when battery is not present")
        XCTAssertNil(sample.cycleCount, "Cycle count must be nil when battery is not present")
        XCTAssertNil(sample.condition, "Condition must be nil when battery is not present")
        XCTAssertNil(sample.designCapacity, "Design capacity must be nil when battery is not present")
        XCTAssertNil(sample.currentMaxCapacity, "Max capacity must be nil when battery is not present")
    }

    func testPowerSamplerDesktopMacWithPowerSupplyWattage() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: false,
            isPresent: false,
            powerSourceState: "AC Power"
        )
        mock.mockSmartBattery = RawSmartBatteryData(
            cycleCount: nil,
            condition: nil,
            designCapacity: nil,
            currentMaxCapacity: nil,
            adapterWatts: 140.0,
            powerDrawWatts: 38.5
        )

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertFalse(sample.hasBattery)
        XCTAssertNil(sample.charge)
        XCTAssertNil(sample.state)
        XCTAssertNil(sample.timeRemaining)
        XCTAssertNil(sample.cycleCount)
        XCTAssertNil(sample.condition)
        XCTAssertNil(sample.designCapacity)
        XCTAssertNil(sample.currentMaxCapacity)
        XCTAssertEqual(sample.adapterWatts, 140.0, "Desktop power supply wattage should be preserved if exposed")
        XCTAssertEqual(sample.powerDrawWatts, 38.5, "Desktop power draw wattage should be preserved if exposed")
    }

    func testPowerSamplerDesktopMacAllMetricsAreStrictlyNil() throws {
        let mock = MockPowerInfoProvider()
        mock.mockSnapshot = RawPowerSourceSnapshot(
            hasBattery: false,
            isPresent: false,
            powerSourceState: "AC Power"
        )
        mock.mockSmartBattery = nil

        let sampler = PowerSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertFalse(sample.hasBattery)
        XCTAssertNil(sample.charge)
        XCTAssertNil(sample.state)
        XCTAssertNil(sample.timeRemaining)
        XCTAssertNil(sample.cycleCount)
        XCTAssertNil(sample.condition)
        XCTAssertNil(sample.designCapacity)
        XCTAssertNil(sample.currentMaxCapacity)
        XCTAssertNil(sample.adapterWatts)
        XCTAssertNil(sample.powerDrawWatts)
    }

    func testLiveHostPowerInfoProviderAndSampler() throws {
        let provider = HostPowerInfoProvider()
        let snapshot = try provider.powerSourceSnapshot()
        let smartData = try? provider.smartBatteryData()

        let sampler = PowerSampler(provider: provider)
        let sample = try sampler.sample()

        if sample.hasBattery {
            if let charge = sample.charge {
                XCTAssertGreaterThanOrEqual(charge, 0.0)
                XCTAssertLessThanOrEqual(charge, 100.0)
            }
            XCTAssertNotNil(sample.state)
            XCTAssertNotEqual(sample.state, .unknown)

            if let cycles = sample.cycleCount {
                XCTAssertGreaterThanOrEqual(cycles, 0)
            }
            if let cond = sample.condition {
                XCTAssertFalse(cond.isEmpty)
            }
            if let design = sample.designCapacity {
                XCTAssertGreaterThan(design, 0)
            }
            if let currentMax = sample.currentMaxCapacity {
                XCTAssertGreaterThan(currentMax, 0)
            }
            if let adapter = sample.adapterWatts {
                XCTAssertGreaterThan(adapter, 0.0)
            }
            if let draw = sample.powerDrawWatts {
                XCTAssertGreaterThanOrEqual(draw, 0.0)
            }
        }
    }
}
