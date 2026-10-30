import XCTest
@testable import iStatsCore
@testable import iStats

final class PopoverVerdictTests: XCTestCase {
    // MARK: - 1. CPU Verdict Evaluation

    func testCPUEvaluationAllBranches() {
        // Cold start / nil
        let nilVerdict = VerdictEvaluator.evaluateCPU(nil)
        XCTAssertEqual(nilVerdict.level, .fine)
        XCTAssertEqual(nilVerdict.badgeText, "Ready")
        XCTAssertEqual(nilVerdict.primaryValue, "—%")

        // Idle (<5%)
        let idleCPU = CPUSample(totalUsage: 3.2, perCore: [3.0, 3.4], user: 2.0, system: 1.2, idle: 96.8)
        let idleVerdict = VerdictEvaluator.evaluateCPU(idleCPU)
        XCTAssertEqual(idleVerdict.level, .fine)
        XCTAssertEqual(idleVerdict.badgeText, "Fine")
        XCTAssertEqual(idleVerdict.dadSentence, "Mostly idle")
        XCTAssertEqual(idleVerdict.primaryValue, "3.2%")

        // Normal (5% ..< 25%)
        let normalCPU = CPUSample(totalUsage: 18.0, perCore: [16.0, 20.0], user: 12.0, system: 6.0, idle: 82.0)
        let normalVerdict = VerdictEvaluator.evaluateCPU(normalCPU)
        XCTAssertEqual(normalVerdict.level, .fine)
        XCTAssertEqual(normalVerdict.badgeText, "Fine")
        XCTAssertEqual(normalVerdict.dadSentence, "Working normally")

        // Busy (25% ..< 65%)
        let busyCPU = CPUSample(totalUsage: 45.0, perCore: [40.0, 50.0], user: 35.0, system: 10.0, idle: 55.0)
        let busyVerdict = VerdictEvaluator.evaluateCPU(busyCPU)
        XCTAssertEqual(busyVerdict.level, .elevated)
        XCTAssertEqual(busyVerdict.badgeText, "Busy")
        XCTAssertEqual(busyVerdict.dadSentence, "Apps are using the processor")

        // Very busy (65% ..< 90%)
        let veryBusyCPU = CPUSample(totalUsage: 78.5, perCore: [75.0, 82.0], user: 65.0, system: 13.5, idle: 21.5)
        let veryBusyVerdict = VerdictEvaluator.evaluateCPU(veryBusyCPU)
        XCTAssertEqual(veryBusyVerdict.level, .warning)
        XCTAssertEqual(veryBusyVerdict.badgeText, "Very busy")
        XCTAssertEqual(veryBusyVerdict.dadSentence, "Heavy processing workload active")

        // Maxed (>= 90%)
        let maxedCPU = CPUSample(totalUsage: 96.0, perCore: [96.0, 96.0], user: 90.0, system: 6.0, idle: 4.0)
        let maxedVerdict = VerdictEvaluator.evaluateCPU(maxedCPU)
        XCTAssertEqual(maxedVerdict.level, .critical)
        XCTAssertEqual(maxedVerdict.badgeText, "Maxed")
        XCTAssertEqual(maxedVerdict.dadSentence, "The processor is maxed out")
    }

    // MARK: - 2. Memory Verdict Evaluation

    func testMemoryEvaluationPressureAndSwap() {
        // Cold start / nil
        let nilVerdict = VerdictEvaluator.evaluateMemory(nil)
        XCTAssertEqual(nilVerdict.level, .fine)
        XCTAssertEqual(nilVerdict.badgeText, "Ready")
        XCTAssertEqual(nilVerdict.primaryValue, "—")

        // High allocation (88% filled) but Normal pressure -> Fine
        let sampleNormal = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 14 * 1024 * 1024 * 1024,
            free: 2 * 1024 * 1024 * 1024,
            wired: 3 * 1024 * 1024 * 1024,
            compressed: 1 * 1024 * 1024 * 1024,
            cached: 6 * 1024 * 1024 * 1024,
            swapUsed: 0,
            pressure: .normal
        )
        let verdictNormal = VerdictEvaluator.evaluateMemory(sampleNormal)
        XCTAssertEqual(verdictNormal.level, .fine)
        XCTAssertEqual(verdictNormal.badgeText, "Fine")
        XCTAssertEqual(verdictNormal.dadSentence, "Plenty of memory available")
        XCTAssertEqual(verdictNormal.primaryValue, "Normal")
        XCTAssertFalse(verdictNormal.secondaryValue?.contains("Swap") ?? true)

        // Warning pressure with swap active
        let sampleWarning = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 15 * 1024 * 1024 * 1024,
            free: 1 * 1024 * 1024 * 1024,
            wired: 4 * 1024 * 1024 * 1024,
            compressed: 4 * 1024 * 1024 * 1024,
            cached: 1 * 1024 * 1024 * 1024,
            swapUsed: 1024 * 1024 * 1024,
            pressure: .warning
        )
        let verdictWarning = VerdictEvaluator.evaluateMemory(sampleWarning)
        XCTAssertEqual(verdictWarning.level, .warning)
        XCTAssertEqual(verdictWarning.badgeText, "Warning")
        XCTAssertEqual(verdictWarning.dadSentence, "macOS is reclaiming memory. Apps may feel slower.")
        XCTAssertTrue(verdictWarning.secondaryValue?.contains("Swap used:") ?? false)

        // Critical pressure
        let sampleCritical = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 16 * 1024 * 1024 * 1024,
            free: 0,
            wired: 6 * 1024 * 1024 * 1024,
            compressed: 8 * 1024 * 1024 * 1024,
            cached: 0,
            swapUsed: 4 * 1024 * 1024 * 1024,
            pressure: .critical
        )
        let verdictCritical = VerdictEvaluator.evaluateMemory(sampleCritical)
        XCTAssertEqual(verdictCritical.level, .critical)
        XCTAssertEqual(verdictCritical.badgeText, "Critical")
        XCTAssertEqual(verdictCritical.dadSentence, "The Mac is out of usable memory. Close some apps.")
    }

    // MARK: - 3. Thermal Verdict Evaluation

    func testThermalEvaluationPressureAndSensorHotspots() {
        // Cold start / nil / empty
        let nilVerdict = VerdictEvaluator.evaluateThermal(nil)
        XCTAssertEqual(nilVerdict.level, .fine)
        XCTAssertEqual(nilVerdict.badgeText, "Ready")

        let nominalSample = ThermalSample(sensors: [SensorReading(name: "CPU Package", celsius: 96)], pressure: .nominal)
        let nominal = VerdictEvaluator.evaluateThermal(nominalSample)
        XCTAssertEqual(nominal.level, .fine)
        XCTAssertEqual(nominal.badgeText, "Nominal")
        XCTAssertEqual(nominal.dadSentence, "macOS reports nominal thermal pressure")

        let unknown = VerdictEvaluator.evaluateThermal(ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 50)]))
        XCTAssertEqual(unknown.badgeText, "Unavailable")
        XCTAssertEqual(unknown.dadSentence, "Thermal pressure is not reported")

        let fair = VerdictEvaluator.evaluateThermal(ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 80)], pressure: .fair))
        XCTAssertEqual(fair.level, .elevated)
        XCTAssertEqual(fair.badgeText, "Fair")
        let serious = VerdictEvaluator.evaluateThermal(ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 92)], pressure: .serious))
        XCTAssertEqual(serious.level, .warning)
        XCTAssertEqual(serious.badgeText, "Serious")
        let critical = VerdictEvaluator.evaluateThermal(ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 104)], pressure: .critical))
        XCTAssertEqual(critical.level, .critical)
        XCTAssertEqual(critical.dadSentence, "macOS reports critical thermal pressure")
    }

    // MARK: - 4. Fan Verdict Evaluation

    func testFanVerdictUsesReportedRPMWithoutAssumingBoundsOrNoise() {
        XCTAssertEqual(VerdictEvaluator.evaluateFan(nil).badgeText, "Ready")
        let empty = VerdictEvaluator.evaluateFan(FanSample(fans: []))
        XCTAssertEqual(empty.badgeText, "No fans detected")
        XCTAssertEqual(empty.primaryValue, "—")
        let sample = FanSample(fans: [FanReading(name: "Left", rpm: 2500), FanReading(name: "Right", rpm: 3100)])
        let verdict = VerdictEvaluator.evaluateFan(sample)
        XCTAssertEqual(verdict.primaryValue, Units.formatRPM(3100))
        XCTAssertEqual(verdict.secondaryValue, "2 fans reported")
        XCTAssertEqual(verdict.badgeText, "Monitoring")
    }

    // MARK: - 5. GPU Verdict Evaluation

    func testGPUEvaluationBranches() {
        // Cold start / nil
        let nilVerdict = VerdictEvaluator.evaluateGPU(nil)
        XCTAssertEqual(nilVerdict.level, .fine)
        XCTAssertEqual(nilVerdict.badgeText, "Ready")

        // Missing utilization telemetry
        let unmeteredGPU = GPUSample(utilization: nil, memoryUsed: 512 * 1024 * 1024)
        let unmeteredVerdict = VerdictEvaluator.evaluateGPU(unmeteredGPU)
        XCTAssertEqual(unmeteredVerdict.level, .fine)
        XCTAssertEqual(unmeteredVerdict.badgeText, "Unavailable")
        XCTAssertEqual(unmeteredVerdict.primaryValue, "—")
        XCTAssertEqual(unmeteredVerdict.dadSentence, "GPU load is not reported on this Mac")

        // Idle (<15%)
        let idleGPU = GPUSample(utilization: 6.0)
        let idleVerdict = VerdictEvaluator.evaluateGPU(idleGPU)
        XCTAssertEqual(idleVerdict.level, .fine)
        XCTAssertEqual(idleVerdict.badgeText, "Idle")

        // Working (15% ..< 50%)
        let workingGPU = GPUSample(utilization: 32.0)
        let workingVerdict = VerdictEvaluator.evaluateGPU(workingGPU)
        XCTAssertEqual(workingVerdict.level, .elevated)
        XCTAssertEqual(workingVerdict.badgeText, "Working")

        // Working hard (50% ..< 90%)
        let hardGPU = GPUSample(utilization: 72.0)
        let hardVerdict = VerdictEvaluator.evaluateGPU(hardGPU)
        XCTAssertEqual(hardVerdict.level, .warning)
        XCTAssertEqual(hardVerdict.badgeText, "Working hard")

        // Maxed (>= 90%)
        let maxedGPU = GPUSample(utilization: 94.5)
        let maxedVerdict = VerdictEvaluator.evaluateGPU(maxedGPU)
        XCTAssertEqual(maxedVerdict.level, .critical)
        XCTAssertEqual(maxedVerdict.badgeText, "Maxed")
    }

    // MARK: - 6. Network Verdict Evaluation

    func testNetworkEvaluationTrafficFlows() {
        // Cold start / nil
        let nilVerdict = VerdictEvaluator.evaluateNetwork(nil)
        XCTAssertEqual(nilVerdict.level, .fine)
        XCTAssertEqual(nilVerdict.badgeText, "Ready")

        // Idle (<200 KB/s total)
        let idleNet = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 5000, bytesOutPerSec: 2000, totalBytesIn: 10000, totalBytesOut: 5000)
        ])
        let idleVerdict = VerdictEvaluator.evaluateNetwork(idleNet)
        XCTAssertEqual(idleVerdict.level, .fine)
        XCTAssertEqual(idleVerdict.badgeText, "Idle")
        XCTAssertEqual(idleVerdict.dadSentence, "Network connection is mostly idle")

        // Active download (>200 KB/s, down > up * 2)
        let activeDown = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 600_000, bytesOutPerSec: 50_000, totalBytesIn: 1_000_000, totalBytesOut: 100_000)
        ])
        let downVerdict = VerdictEvaluator.evaluateNetwork(activeDown)
        XCTAssertEqual(downVerdict.level, .fine)
        XCTAssertEqual(downVerdict.badgeText, "Downloading")
        XCTAssertEqual(downVerdict.dadSentence, "Network receiving data")

        // Heavy download (>5 MB/s)
        let heavyDown = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 12_000_000, bytesOutPerSec: 100_000, totalBytesIn: 50_000_000, totalBytesOut: 500_000)
        ])
        let heavyDownVerdict = VerdictEvaluator.evaluateNetwork(heavyDown)
        XCTAssertEqual(heavyDownVerdict.level, .elevated)
        XCTAssertEqual(heavyDownVerdict.badgeText, "Downloading")
        XCTAssertEqual(heavyDownVerdict.dadSentence, "Fast download in progress")

        // Heavy upload (>5 MB/s)
        let heavyUp = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 100_000, bytesOutPerSec: 8_000_000, totalBytesIn: 500_000, totalBytesOut: 30_000_000)
        ])
        let heavyUpVerdict = VerdictEvaluator.evaluateNetwork(heavyUp)
        XCTAssertEqual(heavyUpVerdict.level, .elevated)
        XCTAssertEqual(heavyUpVerdict.badgeText, "Uploading")
        XCTAssertEqual(heavyUpVerdict.dadSentence, "Large upload in progress")
    }

    // MARK: - 7. Disk Capacity Verdict Evaluation

    func testDiskEvaluationCapacityThresholds() {
        // Cold start / nil
        let nilVerdict = VerdictEvaluator.evaluateDisk(nil)
        XCTAssertEqual(nilVerdict.level, .fine)
        XCTAssertEqual(nilVerdict.badgeText, "Ready")

        // <85% used -> Plenty of space
        let disk80 = DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1000, used: 700, free: 300)
        ])
        let verdict80 = VerdictEvaluator.evaluateDisk(disk80)
        XCTAssertEqual(verdict80.level, .fine)
        XCTAssertEqual(verdict80.badgeText, "Plenty of space")
        XCTAssertEqual(verdict80.dadSentence, "Storage capacity is healthy")

        // 85% ..< 95% used -> Getting full
        let disk90 = DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1000, used: 880, free: 120)
        ])
        let verdict90 = VerdictEvaluator.evaluateDisk(disk90)
        XCTAssertEqual(verdict90.level, .elevated)
        XCTAssertEqual(verdict90.badgeText, "Getting full")
        XCTAssertEqual(verdict90.dadSentence, "Storage is over 85% capacity")

        // >=95% used -> Almost full
        let disk97 = DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1000, used: 970, free: 30)
        ])
        let verdict97 = VerdictEvaluator.evaluateDisk(disk97)
        XCTAssertEqual(verdict97.level, .critical)
        XCTAssertEqual(verdict97.badgeText, "Almost full")
        XCTAssertEqual(verdict97.dadSentence, "macOS needs free space. Storage critical.")
    }

    // MARK: - 8. Power Verdict Evaluation

    func testPowerVerdictReportsStateWithoutAssumingChargeOrAdapterDeficit() {
        XCTAssertEqual(VerdictEvaluator.evaluatePower(nil).badgeText, "Ready")
        XCTAssertEqual(VerdictEvaluator.evaluatePower(PowerSample(hasBattery: false)).primaryValue, "—")
        let unknown = VerdictEvaluator.evaluatePower(PowerSample(hasBattery: true, state: .unknown))
        XCTAssertEqual(unknown.primaryValue, "—")
        XCTAssertEqual(unknown.badgeText, "Unavailable")
        let charging = VerdictEvaluator.evaluatePower(PowerSample(hasBattery: true, charge: 55, state: .charging, powerDrawWatts: 80, adapterWatts: 60))
        XCTAssertEqual(charging.badgeText, "Charging")
        XCTAssertEqual(charging.primaryValue, "55%")
        XCTAssertEqual(VerdictEvaluator.evaluatePower(PowerSample(hasBattery: true, charge: 8, state: .discharging)).level, .critical)
        XCTAssertEqual(VerdictEvaluator.evaluatePower(PowerSample(hasBattery: true, charge: 18, state: .discharging)).level, .warning)
    }
}
