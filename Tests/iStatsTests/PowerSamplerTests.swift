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
    }
}
