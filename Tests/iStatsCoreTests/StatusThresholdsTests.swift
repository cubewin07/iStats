import XCTest
@testable import iStatsCore

final class StatusThresholdsTests: XCTestCase {

    func testStatusLevelComparable() {
        XCTAssertTrue(StatusLevel.fine < StatusLevel.elevated)
        XCTAssertTrue(StatusLevel.elevated < StatusLevel.warning)
        XCTAssertTrue(StatusLevel.warning < StatusLevel.critical)
        XCTAssertEqual(max(StatusLevel.fine, StatusLevel.warning), StatusLevel.warning)
    }

    func testCPUThresholds() {
        XCTAssertEqual(StatusThresholds.cpu(usagePercent: 0.0), .fine)
        XCTAssertEqual(StatusThresholds.cpu(usagePercent: 24.9), .fine)
        XCTAssertEqual(StatusThresholds.cpu(usagePercent: 25.0), .elevated)
        XCTAssertEqual(StatusThresholds.cpu(usagePercent: 64.9), .elevated)
        XCTAssertEqual(StatusThresholds.cpu(usagePercent: 65.0), .warning)
        XCTAssertEqual(StatusThresholds.cpu(usagePercent: 89.9), .warning)
        XCTAssertEqual(StatusThresholds.cpu(usagePercent: 90.0), .critical)
        XCTAssertEqual(StatusThresholds.cpu(usagePercent: 100.0), .critical)
    }

    func testMemoryThresholds() {
        XCTAssertEqual(StatusThresholds.memory(pressure: .normal, swapUsedBytes: 0), .fine)
        XCTAssertEqual(StatusThresholds.memory(pressure: .normal, swapUsedBytes: 500_000_000), .fine)
        XCTAssertEqual(StatusThresholds.memory(pressure: .normal, swapUsedBytes: 1_000_000_000), .elevated)
        XCTAssertEqual(StatusThresholds.memory(pressure: .warning, swapUsedBytes: 0), .warning)
        XCTAssertEqual(StatusThresholds.memory(pressure: .critical, swapUsedBytes: 0), .critical)
    }

    func testGPUThresholds() {
        XCTAssertEqual(StatusThresholds.gpu(utilizationPercent: 0.0), .fine)
        XCTAssertEqual(StatusThresholds.gpu(utilizationPercent: 49.9), .fine)
        XCTAssertEqual(StatusThresholds.gpu(utilizationPercent: 50.0), .elevated)
        XCTAssertEqual(StatusThresholds.gpu(utilizationPercent: 74.9), .elevated)
        XCTAssertEqual(StatusThresholds.gpu(utilizationPercent: 75.0), .warning)
        XCTAssertEqual(StatusThresholds.gpu(utilizationPercent: 91.9), .warning)
        XCTAssertEqual(StatusThresholds.gpu(utilizationPercent: 92.0), .critical)
    }

    func testTemperatureThresholdsBySource() {
        // CPU / GPU / Peak
        XCTAssertEqual(StatusThresholds.temperature(celsius: 55.0, source: .cpu), .fine)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 60.0, source: .cpu), .elevated)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 75.0, source: .gpu), .warning)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 90.0, source: .peak), .critical)

        // Memory
        XCTAssertEqual(StatusThresholds.temperature(celsius: 48.0, source: .memory), .fine)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 50.0, source: .memory), .elevated)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 60.0, source: .memory), .warning)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 75.0, source: .memory), .critical)

        // SSD
        XCTAssertEqual(StatusThresholds.temperature(celsius: 40.0, source: .ssd), .fine)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 45.0, source: .ssd), .elevated)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 55.0, source: .ssd), .warning)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 70.0, source: .ssd), .critical)

        // Battery
        XCTAssertEqual(StatusThresholds.temperature(celsius: 30.0, source: .battery), .fine)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 32.0, source: .battery), .elevated)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 38.0, source: .battery), .warning)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 45.0, source: .battery), .critical)

        // System thermal pressure override
        XCTAssertEqual(StatusThresholds.temperature(celsius: 40.0, source: .cpu, pressure: .fair), .elevated)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 40.0, source: .cpu, pressure: .serious), .warning)
        XCTAssertEqual(StatusThresholds.temperature(celsius: 40.0, source: .cpu, pressure: .critical), .critical)
    }

    func testFanThresholds() {
        let minR = 1200.0
        let maxR = 6000.0
        // Bad bounds guard
        XCTAssertEqual(StatusThresholds.fan(rpm: 2000, minRPM: 3000, maxRPM: 2000), .fine)

        // 0% -> fine
        XCTAssertEqual(StatusThresholds.fan(rpm: 1200, minRPM: minR, maxRPM: maxR), .fine)
        // 50% = 1200 + 0.5 * 4800 = 3600
        XCTAssertEqual(StatusThresholds.fan(rpm: 3600, minRPM: minR, maxRPM: maxR), .elevated)
        // 80% = 1200 + 0.8 * 4800 = 5040
        XCTAssertEqual(StatusThresholds.fan(rpm: 5040, minRPM: minR, maxRPM: maxR), .warning)
        // 95% = 1200 + 0.95 * 4800 = 5760
        XCTAssertEqual(StatusThresholds.fan(rpm: 5760, minRPM: minR, maxRPM: maxR), .critical)
    }

    func testDiskThresholds() {
        XCTAssertEqual(StatusThresholds.disk(usedPercent: 70.0), .fine)
        XCTAssertEqual(StatusThresholds.disk(usedPercent: 80.0), .elevated)
        XCTAssertEqual(StatusThresholds.disk(usedPercent: 90.0), .warning)
        XCTAssertEqual(StatusThresholds.disk(usedPercent: 95.0), .critical)
    }

    func testBatteryThresholds() {
        // Charging
        XCTAssertEqual(StatusThresholds.battery(chargePercent: 5.0, isCharging: true), .fine)
        // Discharging
        XCTAssertEqual(StatusThresholds.battery(chargePercent: 80.0, isCharging: false), .fine)
        XCTAssertEqual(StatusThresholds.battery(chargePercent: 30.0, isCharging: false), .elevated)
        XCTAssertEqual(StatusThresholds.battery(chargePercent: 20.0, isCharging: false), .warning)
        XCTAssertEqual(StatusThresholds.battery(chargePercent: 10.0, isCharging: false), .critical)
        // Power deficit
        XCTAssertEqual(StatusThresholds.battery(chargePercent: 80.0, isCharging: true, powerDeficitWatts: 15.0), .warning)
    }
}
