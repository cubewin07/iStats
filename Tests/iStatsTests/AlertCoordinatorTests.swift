import XCTest
import Combine
@testable import iStatsCore
@testable import iStats

@MainActor
final class AlertCoordinatorTests: XCTestCase {
    // MARK: - CPU Evaluator Tests

    func testCPUEvaluator() {
        let lowCPU = CPUSample(totalUsage: 35.0, perCore: [30.0, 40.0], user: 20.0, system: 15.0, idle: 65.0)
        XCTAssertNil(AlertEvaluator.evaluateCPU(sample: lowCPU, threshold: 90.0))

        let highCPU = CPUSample(totalUsage: 94.2, perCore: [95.0, 93.4], user: 80.0, system: 14.2, idle: 5.8)
        let alert = AlertEvaluator.evaluateCPU(sample: highCPU, threshold: 90.0)
        XCTAssertNotNil(alert)
        XCTAssertTrue(alert!.triggered)
        XCTAssertTrue(alert!.body.contains("94.2%"))
    }

    // MARK: - Memory Evaluator Tests

    func testMemoryEvaluator() {
        let normalMem = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 12 * 1024 * 1024 * 1024, // 75%
            free: 4 * 1024 * 1024 * 1024,
            wired: 4 * 1024 * 1024 * 1024,
            compressed: 2 * 1024 * 1024 * 1024,
            cached: 2 * 1024 * 1024 * 1024,
            swapUsed: 0,
            pressure: .normal
        )

        // Below threshold & normal pressure
        XCTAssertNil(AlertEvaluator.evaluateMemory(sample: normalMem, threshold: 85.0, criticalPressureOnly: true))
        XCTAssertNil(AlertEvaluator.evaluateMemory(sample: normalMem, threshold: 85.0, criticalPressureOnly: false))

        let criticalMem = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 15 * 1024 * 1024 * 1024,
            free: 1 * 1024 * 1024 * 1024,
            wired: 8 * 1024 * 1024 * 1024,
            compressed: 6 * 1024 * 1024 * 1024,
            cached: 0,
            swapUsed: 4 * 1024 * 1024 * 1024,
            pressure: .critical
        )

        let criticalAlert = AlertEvaluator.evaluateMemory(sample: criticalMem, threshold: 85.0, criticalPressureOnly: true)
        XCTAssertNotNil(criticalAlert)
        XCTAssertTrue(criticalAlert!.body.contains("Critical"))

        // High usage with criticalPressureOnly = false
        let highUsageNormalPressure = MemorySample(
            total: 10 * 1024 * 1024 * 1024,
            used: 9 * 1024 * 1024 * 1024, // 90%
            free: 1 * 1024 * 1024 * 1024,
            wired: 4 * 1024 * 1024 * 1024,
            compressed: 1 * 1024 * 1024 * 1024,
            cached: 1 * 1024 * 1024 * 1024,
            swapUsed: 0,
            pressure: .normal
        )

        XCTAssertNil(AlertEvaluator.evaluateMemory(sample: highUsageNormalPressure, threshold: 85.0, criticalPressureOnly: true))
        let customAlert = AlertEvaluator.evaluateMemory(sample: highUsageNormalPressure, threshold: 85.0, criticalPressureOnly: false)
        XCTAssertNotNil(customAlert)
        XCTAssertTrue(customAlert!.body.contains("90.0%"))
    }

    // MARK: - Battery Evaluator Tests

    func testBatteryEvaluator() {
        let normalBattery = PowerSample(
            hasBattery: true,
            charge: 55.0,
            state: .discharging,
            timeRemaining: 12000,
            powerDrawWatts: 12.5
        )
        XCTAssertNil(AlertEvaluator.evaluateBattery(sample: normalBattery, lowThreshold: 20, lowAlertEnabled: true, fullAlertEnabled: true))

        let lowBattery = PowerSample(
            hasBattery: true,
            charge: 15.0,
            state: .discharging,
            timeRemaining: 3600,
            powerDrawWatts: 14.0
        )
        let lowAlert = AlertEvaluator.evaluateBattery(sample: lowBattery, lowThreshold: 20, lowAlertEnabled: true, fullAlertEnabled: false)
        XCTAssertNotNil(lowAlert)
        XCTAssertEqual(lowAlert?.type, .batteryLow)
        XCTAssertTrue(lowAlert!.body.contains("15%"))

        let fullBattery = PowerSample(
            hasBattery: true,
            charge: 100.0,
            state: .charging,
            timeRemaining: 0,
            powerDrawWatts: 0.0
        )
        let fullAlert = AlertEvaluator.evaluateBattery(sample: fullBattery, lowThreshold: 20, lowAlertEnabled: true, fullAlertEnabled: true)
        XCTAssertNotNil(fullAlert)
        XCTAssertEqual(fullAlert?.type, .batteryFull)
        XCTAssertTrue(fullAlert!.title.contains("Fully Charged"))
    }

    // MARK: - Thermal Evaluator Tests

    func testThermalEvaluator() {
        let normalThermal = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 55.0),
                SensorReading(name: "GPU Die", celsius: 48.0)
            ],
            pressure: .nominal
        )
        XCTAssertNil(AlertEvaluator.evaluateThermal(sample: normalThermal, thresholdCelsius: 90.0, unit: .celsius))

        let hotThermal = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 94.5),
                SensorReading(name: "GPU Die", celsius: 82.0)
            ],
            pressure: .nominal
        )
        let thermalAlert = AlertEvaluator.evaluateThermal(sample: hotThermal, thresholdCelsius: 90.0, unit: .celsius)
        XCTAssertNotNil(thermalAlert)
        XCTAssertTrue(thermalAlert!.body.contains("94.5°C") || thermalAlert!.body.contains("94.5 °C"))
    }

    // MARK: - Disk Evaluator Tests

    func testDiskEvaluator() {
        let normalDisk = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500 * 1024 * 1024 * 1024, used: 250 * 1024 * 1024 * 1024, free: 250 * 1024 * 1024 * 1024) // 50%
            ]
        )
        XCTAssertNil(AlertEvaluator.evaluateDisk(sample: normalDisk, threshold: 90.0))

        let fullDisk = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500 * 1024 * 1024 * 1024, used: 475 * 1024 * 1024 * 1024, free: 25 * 1024 * 1024 * 1024) // 95%
            ]
        )
        let diskAlert = AlertEvaluator.evaluateDisk(sample: fullDisk, threshold: 90.0)
        XCTAssertNotNil(diskAlert)
        XCTAssertTrue(diskAlert!.body.contains("95.0%"))
    }

    // MARK: - Anti-Spam Cooldown Tests

    func testAntiSpamCooldown() {
        let defaults = UserDefaults(suiteName: "test.istats.alerts.\(UUID().uuidString)")!
        let store = PreferencesStore(userDefaults: defaults)
        store.alertCooldownInterval = 300.0 // 5 minutes

        let coordinator = AlertCoordinator(preferencesStore: store)
        
        let t0 = Date()
        XCTAssertTrue(coordinator.canTrigger(type: .cpuHigh, now: t0))

        coordinator.recordAlertTrigger(type: .cpuHigh, now: t0)

        // 10 seconds later: blocked by cooldown
        let t1 = t0.addingTimeInterval(10)
        XCTAssertFalse(coordinator.canTrigger(type: .cpuHigh, now: t1))

        // Different alert type (e.g. thermal): allowed
        XCTAssertTrue(coordinator.canTrigger(type: .thermalHigh, now: t1))

        // 301 seconds later: allowed again
        let t2 = t0.addingTimeInterval(301)
        XCTAssertTrue(coordinator.canTrigger(type: .cpuHigh, now: t2))

        // Reset cooldowns allows immediately
        coordinator.recordAlertTrigger(type: .cpuHigh, now: t2)
        XCTAssertFalse(coordinator.canTrigger(type: .cpuHigh, now: t2.addingTimeInterval(5)))
        coordinator.resetCooldowns()
        XCTAssertTrue(coordinator.canTrigger(type: .cpuHigh, now: t2.addingTimeInterval(5)))
    }

    // MARK: - Test Notification Dispatch

    func testSendTestNotification() async {
        let coordinator = AlertCoordinator()
        // Ensure test notification runs cleanly without throwing
        await coordinator.sendTestNotification()
    }
}
