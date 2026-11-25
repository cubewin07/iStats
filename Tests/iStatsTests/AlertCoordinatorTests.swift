import XCTest
import Combine
@testable import iStatsCore
@testable import iStats

@MainActor
final class AlertCoordinatorTests: XCTestCase {
    // MARK: - CPU Evaluator Tests

    func testCPUEvaluator() {
        let lowCPU = CPUSample(totalUsage: 35.0, perCore: [30.0, 40.0], user: 20.0, system: 15.0, idle: 65.0)
        XCTAssertNil(AlertMessageBuilder.evaluateCPU(sample: lowCPU, threshold: 90.0))

        let highCPU = CPUSample(totalUsage: 94.2, perCore: [95.0, 93.4], user: 80.0, system: 14.2, idle: 5.8)
        let alert = AlertMessageBuilder.evaluateCPU(sample: highCPU, threshold: 90.0)
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
        XCTAssertNil(AlertMessageBuilder.evaluateMemory(sample: normalMem, threshold: 85.0, criticalPressureOnly: true))
        XCTAssertNil(AlertMessageBuilder.evaluateMemory(sample: normalMem, threshold: 85.0, criticalPressureOnly: false))

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

        let criticalAlert = AlertMessageBuilder.evaluateMemory(sample: criticalMem, threshold: 85.0, criticalPressureOnly: true)
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

        XCTAssertNil(AlertMessageBuilder.evaluateMemory(sample: highUsageNormalPressure, threshold: 85.0, criticalPressureOnly: true))
        let customAlert = AlertMessageBuilder.evaluateMemory(sample: highUsageNormalPressure, threshold: 85.0, criticalPressureOnly: false)
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
        XCTAssertNil(AlertMessageBuilder.evaluateBattery(sample: normalBattery, lowThreshold: 20, lowAlertEnabled: true, fullAlertEnabled: true))

        let lowBattery = PowerSample(
            hasBattery: true,
            charge: 15.0,
            state: .discharging,
            timeRemaining: 3600,
            powerDrawWatts: 14.0
        )
        let lowAlert = AlertMessageBuilder.evaluateBattery(sample: lowBattery, lowThreshold: 20, lowAlertEnabled: true, fullAlertEnabled: false)
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
        let fullAlert = AlertMessageBuilder.evaluateBattery(sample: fullBattery, lowThreshold: 20, lowAlertEnabled: true, fullAlertEnabled: true)
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
        XCTAssertNil(AlertMessageBuilder.evaluateThermal(sample: normalThermal, thresholdCelsius: 90.0, unit: .celsius))

        let hotThermal = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 94.5),
                SensorReading(name: "GPU Die", celsius: 82.0)
            ],
            pressure: .nominal
        )
        let thermalAlert = AlertMessageBuilder.evaluateThermal(sample: hotThermal, thresholdCelsius: 90.0, unit: .celsius)
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
        XCTAssertNil(AlertMessageBuilder.evaluateDisk(sample: normalDisk, threshold: 90.0))

        let fullDisk = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500 * 1024 * 1024 * 1024, used: 475 * 1024 * 1024 * 1024, free: 25 * 1024 * 1024 * 1024) // 95%
            ]
        )
        let diskAlert = AlertMessageBuilder.evaluateDisk(sample: fullDisk, threshold: 90.0)
        XCTAssertNotNil(diskAlert)
        XCTAssertTrue(diskAlert!.body.contains("95.0%"))
    }

    // MARK: - Anti-Spam Cooldown Tests

    func testAntiSpamCooldown() {
        let defaults = UserDefaults(suiteName: "test.istats.alerts.\(UUID().uuidString)")!
        let store = PreferencesStore(userDefaults: defaults)
        store.defaultAlertCooldownSeconds = 300.0 // 5 minutes

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

    // MARK: - Core AlertEvaluator Delegation & Migration Behavior

    func testDisabledRuleDoesNotSendNotification() {
        let suite = "test.istats.alerts.disabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(userDefaults: defaults)
        store.notificationsEnabled = true
        store.setAlertRule(AlertRule(kind: .cpu, enabled: false, threshold: 50, sustainSeconds: 0))

        var dispatched: [(AlertCoordinator.AlertType, String, String)] = []
        let coordinator = AlertCoordinator(preferencesStore: store) { type, title, body in
            dispatched.append((type, title, body))
        }

        let hotCPU = CPUSample(totalUsage: 95.0, perCore: [95.0], user: 80.0, system: 15.0, idle: 5.0)
        coordinator.handleCPUSample(hotCPU, now: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(dispatched.isEmpty)
    }

    func testSustainedRuleRequiresContinuousDuration() {
        let suite = "test.istats.alerts.sustain.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(userDefaults: defaults)
        store.notificationsEnabled = true
        store.setAlertRule(AlertRule(kind: .cpu, enabled: true, threshold: 85, sustainSeconds: 15, cooldownSeconds: 60))

        var dispatched: [(AlertCoordinator.AlertType, String, String)] = []
        let coordinator = AlertCoordinator(preferencesStore: store) { type, title, body in
            dispatched.append((type, title, body))
        }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let highCPU = CPUSample(totalUsage: 92.0, perCore: [92.0], user: 75.0, system: 17.0, idle: 8.0)

        // Single spike does not fire.
        coordinator.handleCPUSample(highCPU, now: t0)
        coordinator.handleCPUSample(highCPU, now: t0.addingTimeInterval(10))
        XCTAssertTrue(dispatched.isEmpty)

        // Sustained past 15s fires once.
        coordinator.handleCPUSample(highCPU, now: t0.addingTimeInterval(15))
        XCTAssertEqual(dispatched.count, 1)
        XCTAssertEqual(dispatched.first?.0, .cpuHigh)
        XCTAssertEqual(dispatched.first?.1, "High CPU Usage")

        // Next sample remains suppressed.
        coordinator.handleCPUSample(highCPU, now: t0.addingTimeInterval(20))
        XCTAssertEqual(dispatched.count, 1)
    }

    func testMigratedV1RulesBehaveLikeOldDefaults() {
        let suite = "test.istats.alerts.v1.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "iStats.notificationsEnabled")
        defaults.set(true, forKey: "iStats.cpuAlertEnabled")
        defaults.set(80.0, forKey: "iStats.cpuAlertThreshold")
        defaults.set(true, forKey: "iStats.diskAlertEnabled")
        defaults.set(88.0, forKey: "iStats.diskAlertThreshold")
        defaults.set(120.0, forKey: "iStats.alertCooldownInterval")

        let store = PreferencesStore(userDefaults: defaults)
        var dispatched: [AlertCoordinator.AlertType] = []
        let coordinator = AlertCoordinator(preferencesStore: store) { type, _, _ in
            dispatched.append(type)
        }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        coordinator.handleCPUSample(
            CPUSample(totalUsage: 82.0, perCore: [82.0], user: 60.0, system: 22.0, idle: 18.0),
            now: t0
        )
        XCTAssertEqual(dispatched, [.cpuHigh])

        // Cooldown of 120s blocks refire even after recovery.
        coordinator.handleCPUSample(
            CPUSample(totalUsage: 40.0, perCore: [40.0], user: 30.0, system: 10.0, idle: 60.0),
            now: t0.addingTimeInterval(30)
        )
        coordinator.handleCPUSample(
            CPUSample(totalUsage: 85.0, perCore: [85.0], user: 60.0, system: 25.0, idle: 15.0),
            now: t0.addingTimeInterval(60)
        )
        XCTAssertEqual(dispatched, [.cpuHigh])

        // Disk rule migrated to 88%
        coordinator.handleDiskSample(
            DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 100, used: 90, free: 10)]),
            now: t0.addingTimeInterval(10)
        )
        XCTAssertEqual(dispatched, [.cpuHigh, .diskLow])
    }

    func testTargetedDiskVolumeAndThermalSourceRules() {
        let suite = "test.istats.alerts.targets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(userDefaults: defaults)
        store.notificationsEnabled = true
        store.setAlertRule(AlertRule(kind: .disk, enabled: true, threshold: 80, target: "/Volumes/Media"))
        store.setAlertRule(AlertRule(kind: .temperature, enabled: true, threshold: 75, target: MetricSource.gpu.rawValue))

        var dispatched: [(AlertCoordinator.AlertType, String)] = []
        let coordinator = AlertCoordinator(preferencesStore: store) { type, _, body in
            dispatched.append((type, body))
        }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // Root volume is 50%, /Volumes/Media is 90% -> triggers for /Volumes/Media.
        let disk = DiskSample(volumes: [
            VolumeCapacity(name: "HD", mountPoint: "/", total: 100, used: 50, free: 50),
            VolumeCapacity(name: "Media", mountPoint: "/Volumes/Media", total: 100, used: 90, free: 10)
        ])
        coordinator.handleDiskSample(disk, now: t0)
        XCTAssertEqual(dispatched.count, 1)
        XCTAssertEqual(dispatched.last?.0, .diskLow)
        XCTAssertTrue(dispatched.last?.1.contains("/Volumes/Media") ?? false)

        // CPU is hot (85), GPU is cool (60) -> GPU-targeted rule must NOT trigger.
        let gpuCool = ThermalSample(sensors: [
            SensorReading(name: "CPU Package", celsius: 85),
            SensorReading(name: "GPU Cluster", celsius: 60)
        ])
        coordinator.handleThermalSample(gpuCool, now: t0)
        XCTAssertEqual(dispatched.count, 1)

        // GPU crosses 78 -> triggers.
        let gpuHot = ThermalSample(sensors: [
            SensorReading(name: "CPU Package", celsius: 85),
            SensorReading(name: "GPU Cluster", celsius: 78)
        ])
        coordinator.handleThermalSample(gpuHot, now: t0.addingTimeInterval(5))
        XCTAssertEqual(dispatched.count, 2)
        XCTAssertEqual(dispatched.last?.0, .thermalHigh)
        XCTAssertTrue(dispatched.last?.1.contains("GPU") ?? false)
    }

    // MARK: - Test Notification Dispatch

    func testSendTestNotification() async {
        let coordinator = AlertCoordinator()
        // Ensure test notification runs cleanly without throwing
        await coordinator.sendTestNotification()
    }
}
