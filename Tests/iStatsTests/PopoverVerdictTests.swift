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
        XCTAssertTrue(verdictWarning.secondaryValue?.contains("Swap active") ?? false)

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

        // Nominal & Optimal temperatures (<75°C)
        let nominalSample = ThermalSample(sensors: [
            SensorReading(name: "CPU Package", celsius: 52.0),
            SensorReading(name: "GPU Cluster 1", celsius: 48.0)
        ], pressure: .nominal)
        let nominalVerdict = VerdictEvaluator.evaluateThermal(nominalSample)
        XCTAssertEqual(nominalVerdict.level, .fine)
        XCTAssertEqual(nominalVerdict.badgeText, "Cool")
        XCTAssertEqual(nominalVerdict.dadSentence, "Temperatures are optimal")

        // Nominal but primary sensor >= 75°C
        let warmSample = ThermalSample(sensors: [
            SensorReading(name: "CPU Package", celsius: 78.0)
        ], pressure: .nominal)
        let warmVerdict = VerdictEvaluator.evaluateThermal(warmSample)
        XCTAssertEqual(warmVerdict.level, .elevated)
        XCTAssertEqual(warmVerdict.badgeText, "Warm")
        XCTAssertEqual(warmVerdict.dadSentence, "macOS has not throttled")

        // Nominal but hotspot sensor >= 95°C
        let hotspotSample = ThermalSample(sensors: [
            SensorReading(name: "CPU Package", celsius: 65.0),
            SensorReading(name: "Memory Module B", celsius: 96.0)
        ], pressure: .nominal)
        let hotspotVerdict = VerdictEvaluator.evaluateThermal(hotspotSample)
        XCTAssertEqual(hotspotVerdict.level, .warning)
        XCTAssertEqual(hotspotVerdict.badgeText, "Hot")
        XCTAssertEqual(hotspotVerdict.dadSentence, "Hottest sensor elevated; not throttling")

        // Elevated pressure states: .fair -> Warm, .serious -> Hot, .critical -> Too hot
        let fairSample = ThermalSample(sensors: [SensorReading(name: "CPU Package", celsius: 80.0)], pressure: .fair)
        let fairVerdict = VerdictEvaluator.evaluateThermal(fairSample)
        XCTAssertEqual(fairVerdict.level, .elevated)
        XCTAssertEqual(fairVerdict.badgeText, "Warm")

        let seriousSample = ThermalSample(sensors: [SensorReading(name: "CPU Package", celsius: 92.0)], pressure: .serious)
        let seriousVerdict = VerdictEvaluator.evaluateThermal(seriousSample)
        XCTAssertEqual(seriousVerdict.level, .warning)
        XCTAssertEqual(seriousVerdict.badgeText, "Hot")

        let criticalSample = ThermalSample(sensors: [SensorReading(name: "CPU Package", celsius: 104.0)], pressure: .critical)
        let criticalVerdict = VerdictEvaluator.evaluateThermal(criticalSample)
        XCTAssertEqual(criticalVerdict.level, .critical)
        XCTAssertEqual(criticalVerdict.badgeText, "Too hot")
        XCTAssertEqual(criticalVerdict.dadSentence, "macOS is throttling CPU to cool down")
    }

    // MARK: - 4. Fan Verdict Evaluation

    func testFanEvaluationQuietSpinningLoudMaxAndFanless() {
        // Cold start / nil
        let nilVerdict = VerdictEvaluator.evaluateFan(nil)
        XCTAssertEqual(nilVerdict.level, .fine)
        XCTAssertEqual(nilVerdict.badgeText, "Ready")

        // Fanless system
        let fanlessSample = FanSample(fans: [])
        let fanlessVerdict = VerdictEvaluator.evaluateFan(fanlessSample)
        XCTAssertEqual(fanlessVerdict.level, .fine)
        XCTAssertEqual(fanlessVerdict.badgeText, "Fanless")
        XCTAssertEqual(fanlessVerdict.dadSentence, "This Mac has no fans (passive cooling)")

        // Quiet (<15% ratio): 2400 RPM on 2000-6000 bounds -> 10% ratio
        let quietFan = FanSample(fans: [FanReading(name: "Left Fan", rpm: 2400, minRPM: 2000, maxRPM: 6000)])
        let quietVerdict = VerdictEvaluator.evaluateFan(quietFan)
        XCTAssertEqual(quietVerdict.level, .fine)
        XCTAssertEqual(quietVerdict.badgeText, "Quiet")
        XCTAssertEqual(quietVerdict.dadSentence, "Whisper quiet / idle cooling")

        // Spinning up (15% ..< 45% ratio): 3200 RPM -> 30% ratio
        let spinFan = FanSample(fans: [FanReading(name: "Left Fan", rpm: 3200, minRPM: 2000, maxRPM: 6000)])
        let spinVerdict = VerdictEvaluator.evaluateFan(spinFan)
        XCTAssertEqual(spinVerdict.level, .elevated)
        XCTAssertEqual(spinVerdict.badgeText, "Spinning up")
        XCTAssertEqual(spinVerdict.dadSentence, "Fans actively dissipating heat")

        // Loud (45% ..< 80% ratio): 4500 RPM -> 62% ratio
        let loudFan = FanSample(fans: [FanReading(name: "Left Fan", rpm: 4500, minRPM: 2000, maxRPM: 6000)])
        let loudVerdict = VerdictEvaluator.evaluateFan(loudFan)
        XCTAssertEqual(loudVerdict.level, .warning)
        XCTAssertEqual(loudVerdict.badgeText, "Loud")
        XCTAssertEqual(loudVerdict.dadSentence, "Cooling under sustained heat")

        // Max (>= 80% ratio): 5800 RPM -> 95% ratio
        let maxFan = FanSample(fans: [FanReading(name: "Left Fan", rpm: 5800, minRPM: 2000, maxRPM: 6000)])
        let maxVerdict = VerdictEvaluator.evaluateFan(maxFan)
        XCTAssertEqual(maxVerdict.level, .critical)
        XCTAssertEqual(maxVerdict.badgeText, "Max")
        XCTAssertEqual(maxVerdict.dadSentence, "Fans running at maximum cooling power")
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
        XCTAssertEqual(unmeteredVerdict.badgeText, "Active")
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

    func testPowerEvaluationAllBatteryAndACStates() {
        // Cold start / nil
        let nilVerdict = VerdictEvaluator.evaluatePower(nil)
        XCTAssertEqual(nilVerdict.level, .fine)
        XCTAssertEqual(nilVerdict.badgeText, "Ready")

        // Desktop Mac (No battery)
        let desktopPower = PowerSample(hasBattery: false, powerDrawWatts: 48.0)
        let desktopVerdict = VerdictEvaluator.evaluatePower(desktopPower)
        XCTAssertEqual(desktopVerdict.level, .fine)
        XCTAssertEqual(desktopVerdict.badgeText, "On AC Power")
        XCTAssertEqual(desktopVerdict.dadSentence, "This Mac is on power. Drawing 48 W.")

        // Fully charged
        let fullyCharged = PowerSample(hasBattery: true, charge: 100.0, state: .charged, powerDrawWatts: 0.0, adapterWatts: 67.0)
        let fullyChargedVerdict = VerdictEvaluator.evaluatePower(fullyCharged)
        XCTAssertEqual(fullyChargedVerdict.level, .fine)
        XCTAssertEqual(fullyChargedVerdict.badgeText, "Fully Charged")
        XCTAssertEqual(fullyChargedVerdict.dadSentence, "On AC power. Battery full.")

        // AC Connected not charging
        let acConnected = PowerSample(hasBattery: true, charge: 80.0, state: .acConnected, powerDrawWatts: 12.0, adapterWatts: 67.0)
        let acVerdict = VerdictEvaluator.evaluatePower(acConnected)
        XCTAssertEqual(acVerdict.level, .fine)
        XCTAssertEqual(acVerdict.badgeText, "Not Charging")

        // Charging rapidly with estimated time
        let charging = PowerSample(hasBattery: true, charge: 55.0, state: .charging, timeRemaining: 42 * 60, powerDrawWatts: 30.0, adapterWatts: 67.0)
        let chargingVerdict = VerdictEvaluator.evaluatePower(charging)
        XCTAssertEqual(chargingVerdict.level, .fine)
        XCTAssertEqual(chargingVerdict.badgeText, "42 min to full")
        XCTAssertEqual(chargingVerdict.dadSentence, "Battery charging rapidly")

        // Discharging normal (>40%)
        let dischargeNormal = PowerSample(hasBattery: true, charge: 85.0, state: .discharging, timeRemaining: 5 * 3600, powerDrawWatts: 12.0)
        let normalVerdict = VerdictEvaluator.evaluatePower(dischargeNormal)
        XCTAssertEqual(normalVerdict.level, .fine)
        XCTAssertEqual(normalVerdict.badgeText, "5h 0m left")
        XCTAssertEqual(normalVerdict.dadSentence, "Battery discharge is normal")

        // Running down (20% ..< 40%)
        let runningDown = PowerSample(hasBattery: true, charge: 35.0, state: .discharging, timeRemaining: 2 * 3600 + 15 * 60, powerDrawWatts: 15.0)
        let runningDownVerdict = VerdictEvaluator.evaluatePower(runningDown)
        XCTAssertEqual(runningDownVerdict.level, .elevated)
        XCTAssertEqual(runningDownVerdict.badgeText, "Running down")

        // Plug in soon (10% ..< 20%)
        let plugInSoon = PowerSample(hasBattery: true, charge: 18.0, state: .discharging, timeRemaining: 50 * 60, powerDrawWatts: 14.0)
        let plugInSoonVerdict = VerdictEvaluator.evaluatePower(plugInSoon)
        XCTAssertEqual(plugInSoonVerdict.level, .warning)
        XCTAssertEqual(plugInSoonVerdict.badgeText, "Plug in soon")
        XCTAssertEqual(plugInSoonVerdict.dadSentence, "Battery level is low")

        // Plug in now (<= 10%)
        let plugInNow = PowerSample(hasBattery: true, charge: 8.0, state: .discharging, timeRemaining: 20 * 60, powerDrawWatts: 14.0)
        let plugInNowVerdict = VerdictEvaluator.evaluatePower(plugInNow)
        XCTAssertEqual(plugInNowVerdict.level, .critical)
        XCTAssertEqual(plugInNowVerdict.badgeText, "Plug in now")
        XCTAssertEqual(plugInNowVerdict.dadSentence, "Battery is critically low")
    }
}
