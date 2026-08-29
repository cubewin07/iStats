import XCTest
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class PopoverVerdictTests: XCTestCase {
    // MARK: - Verdict Evaluator Tests

    func testCPUEvaluation() {
        let idleCPU = CPUSample(totalUsage: 4.2, perCore: [4.0, 4.4], user: 2.0, system: 2.2, idle: 95.8)
        let idleVerdict = VerdictEvaluator.evaluateCPU(idleCPU)
        XCTAssertEqual(idleVerdict.level, .fine)
        XCTAssertEqual(idleVerdict.badgeText, "Fine")
        XCTAssertEqual(idleVerdict.dadSentence, "Mostly idle")

        let busyCPU = CPUSample(totalUsage: 45.0, perCore: [40.0, 50.0], user: 35.0, system: 10.0, idle: 55.0)
        let busyVerdict = VerdictEvaluator.evaluateCPU(busyCPU)
        XCTAssertEqual(busyVerdict.level, .elevated)
        XCTAssertEqual(busyVerdict.badgeText, "Busy")

        let maxedCPU = CPUSample(totalUsage: 96.0, perCore: [96.0, 96.0], user: 90.0, system: 6.0, idle: 4.0)
        let maxedVerdict = VerdictEvaluator.evaluateCPU(maxedCPU)
        XCTAssertEqual(maxedVerdict.level, .critical)
        XCTAssertEqual(maxedVerdict.badgeText, "Maxed")
    }

    func testMemoryEvaluationNormalPressureRegardlessOfCache() {
        // 14.2 GB of 16 GB (88% full) but Normal pressure should be Fine (Green)
        let sample = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 14 * 1024 * 1024 * 1024,
            free: 2 * 1024 * 1024 * 1024,
            wired: 3 * 1024 * 1024 * 1024,
            compressed: 1 * 1024 * 1024 * 1024,
            cached: 6 * 1024 * 1024 * 1024,
            swapUsed: 0,
            pressure: .normal
        )
        let verdict = VerdictEvaluator.evaluateMemory(sample)
        XCTAssertEqual(verdict.level, .fine)
        XCTAssertEqual(verdict.badgeText, "Fine")
        XCTAssertTrue(verdict.dadSentence.contains("Plenty of memory"))

        // Warning pressure
        let warnSample = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 15 * 1024 * 1024 * 1024,
            free: 1 * 1024 * 1024 * 1024,
            wired: 4 * 1024 * 1024 * 1024,
            compressed: 4 * 1024 * 1024 * 1024,
            cached: 1 * 1024 * 1024 * 1024,
            swapUsed: 1024 * 1024 * 1024,
            pressure: .warning
        )
        let warnVerdict = VerdictEvaluator.evaluateMemory(warnSample)
        XCTAssertEqual(warnVerdict.level, .warning)
        XCTAssertEqual(warnVerdict.badgeText, "Warning")
        XCTAssertTrue(warnVerdict.dadSentence.contains("reclaiming"))
    }

    func testFanEvaluationQuietVsMax() {
        // 2,300 RPM on a 7,800 RPM max fan is Quiet (Green)
        let fanSample = FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 2331, minRPM: 2317, maxRPM: 7826),
            FanReading(name: "Right Fan", rpm: 2506, minRPM: 2317, maxRPM: 7826)
        ])
        let verdict = VerdictEvaluator.evaluateFan(fanSample)
        XCTAssertEqual(verdict.level, .fine)
        XCTAssertEqual(verdict.badgeText, "Quiet")

        // Fanless
        let fanlessSample = FanSample(fans: [])
        let fanlessVerdict = VerdictEvaluator.evaluateFan(fanlessSample)
        XCTAssertEqual(fanlessVerdict.level, .fine)
        XCTAssertEqual(fanlessVerdict.badgeText, "Fanless")
    }

    func testDiskEvaluationCapacityThresholds() {
        // <85% used -> Plenty of space
        let disk80 = DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1000, used: 700, free: 300)
        ])
        let verdict80 = VerdictEvaluator.evaluateDisk(disk80)
        XCTAssertEqual(verdict80.level, .fine)
        XCTAssertEqual(verdict80.badgeText, "Plenty of space")

        // 90% used -> Getting full
        let disk90 = DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1000, used: 900, free: 100)
        ])
        let verdict90 = VerdictEvaluator.evaluateDisk(disk90)
        XCTAssertEqual(verdict90.level, .elevated)
        XCTAssertEqual(verdict90.badgeText, "Getting full")

        // >=95% used -> Almost full
        let disk97 = DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1000, used: 970, free: 30)
        ])
        let verdict97 = VerdictEvaluator.evaluateDisk(disk97)
        XCTAssertEqual(verdict97.level, .critical)
        XCTAssertEqual(verdict97.badgeText, "Almost full")
    }

    func testPowerEvaluationTimeRemainingVsDesktop() {
        // Battery discharging with 4h 12m left
        let powerSample = PowerSample(
            hasBattery: true,
            charge: 80.0,
            state: .discharging,
            timeRemaining: 4 * 3600 + 12 * 60,
            powerDrawWatts: 14.5,
            adapterWatts: nil
        )
        let verdict = VerdictEvaluator.evaluatePower(powerSample)
        XCTAssertEqual(verdict.level, .fine)
        XCTAssertEqual(verdict.badgeText, "4h 12m left")

        // Desktop Mac (No battery)
        let desktopPower = PowerSample(
            hasBattery: false,
            powerDrawWatts: 48.0
        )
        let desktopVerdict = VerdictEvaluator.evaluatePower(desktopPower)
        XCTAssertEqual(desktopVerdict.level, .fine)
        XCTAssertEqual(desktopVerdict.badgeText, "On AC Power")
        XCTAssertTrue(desktopVerdict.dadSentence.contains("Drawing 48 W"))
    }

    // MARK: - Live Illustration Views Rendering Tests

    func testIllustrationViewsRenderCleanly() {
        // CPU Die
        let cpuSample = CPUSample(
            totalUsage: 25.0,
            perCore: [20.0, 25.0, 30.0, 15.0, 40.0, 35.0],
            user: 15.0,
            system: 10.0,
            idle: 75.0,
            efficiencyCoreCount: 2,
            performanceCoreCount: 4
        )
        let cpuView = CPUDieIllustrationView(sample: cpuSample, size: 72)
        XCTAssertNotNil(NSHostingView(rootView: cpuView))

        // Memory Stick
        let memSample = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 12 * 1024 * 1024 * 1024,
            free: 4 * 1024 * 1024 * 1024,
            wired: 3 * 1024 * 1024 * 1024,
            compressed: 2 * 1024 * 1024 * 1024,
            cached: 4 * 1024 * 1024 * 1024,
            swapUsed: 0,
            pressure: .normal
        )
        let memView = MemoryStickIllustrationView(sample: memSample, height: 72, width: 34)
        XCTAssertNotNil(NSHostingView(rootView: memView))

        // Thermal Heat Map
        let thermalSample = ThermalSample(sensors: [
            SensorReading(name: "CPU Package", celsius: 55.0),
            SensorReading(name: "GPU Cluster 1", celsius: 58.0),
            SensorReading(name: "Memory Module A", celsius: 82.0),
            SensorReading(name: "Storage Flash (NAND)", celsius: 44.0)
        ], pressure: .nominal)
        let thermalView = ThermalHeatMapIllustrationView(sample: thermalSample)
        XCTAssertNotNil(NSHostingView(rootView: thermalView))

        // Fan Blades
        let fanSample = FanSample(fans: [FanReading(name: "Left Fan", rpm: 2400, minRPM: 2000, maxRPM: 6000)])
        let fanView = FanBladesIllustrationView(sample: fanSample, size: 68)
        XCTAssertNotNil(NSHostingView(rootView: fanView))

        // GPU Die
        let gpuSample = GPUSample(utilization: 35.0, memoryUsed: 2 * 1024 * 1024 * 1024, tempCelsius: 60.0, powerWatts: 15.0)
        let gpuView = GPUDieIllustrationView(sample: gpuSample, size: 68)
        XCTAssertNotNil(NSHostingView(rootView: gpuView))

        // Network Pipes
        let netSample = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1024 * 1024 * 5, bytesOutPerSec: 1024 * 500, totalBytesIn: 1024 * 1024 * 100, totalBytesOut: 1024 * 1024 * 20)
        ])
        let netView = NetworkPipesIllustrationView(sample: netSample)
        XCTAssertNotNil(NSHostingView(rootView: netView))

        // Disk Storage Tank
        let diskSample = DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000_000_000, used: 400_000_000_000, free: 600_000_000_000)
        ])
        let diskView = DiskStorageTankIllustrationView(sample: diskSample)
        XCTAssertNotNil(NSHostingView(rootView: diskView))

        // Power Budget
        let powerSample = PowerSample(hasBattery: true, charge: 75.0, state: .discharging, timeRemaining: 18000, powerDrawWatts: 18.0, adapterWatts: 67.0)
        let powerView = PowerBudgetIllustrationView(sample: powerSample)
        XCTAssertNotNil(NSHostingView(rootView: powerView))
    }

    func testCategoryDetailPopoverViewWithAllCategories() {
        let defaults = UserDefaults(suiteName: "iStats.test.categorypopover.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )

        for cat in MetricCategory.allCases {
            let popover = CategoryDetailPopoverView(category: cat, coordinator: coordinator, preferences: prefs)
            let hosting = NSHostingView(rootView: popover)
            hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 260)
            XCTAssertNotNil(hosting)
        }
    }
}
