import XCTest
@testable import iStatsCore

final class MetricsStoreTests: XCTestCase {

    func testDefaultInitialization() {
        let store = MetricsStore()

        XCTAssertEqual(store.defaultBufferCapacity, 60)
        XCTAssertEqual(store.totalCount, 0)
        XCTAssertTrue(store.activeCategories.isEmpty)

        for category in MetricCategory.allCases {
            XCTAssertEqual(store.capacity(for: category), 60)
            XCTAssertEqual(store.count(for: category), 0)
            XCTAssertTrue(store.isEmpty(for: category))
            XCTAssertFalse(store.isFull(for: category))
            XCTAssertNil(store.latest(for: category))
            XCTAssertEqual(store.readings(for: category), [])
            XCTAssertEqual(store[category], [])
        }
    }

    func testCustomAndCategoryCapacities() {
        let store = MetricsStore(
            defaultCapacity: 10,
            categoryCapacities: [.cpu: 5, .memory: 20]
        )

        XCTAssertEqual(store.defaultBufferCapacity, 10)
        XCTAssertEqual(store.capacity(for: .cpu), 5)
        XCTAssertEqual(store.capacity(for: .memory), 20)
        XCTAssertEqual(store.capacity(for: .network), 10)
    }

    func testAppendAndChronologicalOrder() {
        var store = MetricsStore(defaultCapacity: 5)
        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = Date(timeIntervalSince1970: 101)
        let t2 = Date(timeIntervalSince1970: 102)

        let cpu1 = MetricReading.cpu(Sample(value: CPUSample(totalUsage: 10.0, perCore: [10.0], user: 5.0, system: 5.0, idle: 90.0), timestamp: t0))
        let cpu2 = MetricReading.cpu(Sample(value: CPUSample(totalUsage: 20.0, perCore: [20.0], user: 10.0, system: 10.0, idle: 80.0), timestamp: t1))
        let cpu3 = MetricReading.cpu(Sample(value: CPUSample(totalUsage: 30.0, perCore: [30.0], user: 15.0, system: 15.0, idle: 70.0), timestamp: t2))

        store.append(cpu1)
        store.append(cpu2)
        store.append(cpu3)

        XCTAssertEqual(store.count(for: .cpu), 3)
        XCTAssertFalse(store.isFull(for: .cpu))
        XCTAssertFalse(store.isEmpty(for: .cpu))
        XCTAssertEqual(store.readings(for: .cpu), [cpu1, cpu2, cpu3])
        XCTAssertEqual(store[.cpu], [cpu1, cpu2, cpu3])
        XCTAssertEqual(store.latest(for: .cpu), cpu3)
        XCTAssertEqual(store.totalCount, 3)
        XCTAssertEqual(store.activeCategories, [.cpu])
    }

    func testEvictionAtCapacity() {
        var store = MetricsStore(defaultCapacity: 3)
        let t = Date()

        let cpuSample = { (usage: Double) -> MetricReading in
            .cpu(Sample(value: CPUSample(totalUsage: usage, perCore: [usage], user: usage, system: 0, idle: 100 - usage), timestamp: t))
        }

        let s1 = cpuSample(10)
        let s2 = cpuSample(20)
        let s3 = cpuSample(30)
        let s4 = cpuSample(40)
        let s5 = cpuSample(50)

        store.append(s1)
        store.append(s2)
        store.append(s3)

        XCTAssertEqual(store.count(for: .cpu), 3)
        XCTAssertTrue(store.isFull(for: .cpu))
        XCTAssertEqual(store.readings(for: .cpu), [s1, s2, s3])

        // Appending s4 should evict s1 (FIFO)
        store.append(s4)
        XCTAssertEqual(store.count(for: .cpu), 3)
        XCTAssertEqual(store.readings(for: .cpu), [s2, s3, s4])
        XCTAssertEqual(store.latest(for: .cpu), s4)

        // Appending s5 should evict s2
        store.append(s5)
        XCTAssertEqual(store.count(for: .cpu), 3)
        XCTAssertEqual(store.readings(for: .cpu), [s3, s4, s5])
        XCTAssertEqual(store.latest(for: .cpu), s5)
    }

    func testMultiCategoryIsolation() {
        var store = MetricsStore(defaultCapacity: 5)
        let t = Date()

        let cpu = MetricReading.cpu(Sample(value: CPUSample(totalUsage: 25.0, perCore: [25.0], user: 20.0, system: 5.0, idle: 75.0), timestamp: t))
        let mem = MetricReading.memory(Sample(value: MemorySample(total: 16000, used: 8000, free: 8000, wired: 2000, compressed: 1000, cached: 3000, swapUsed: 0, pressure: .normal), timestamp: t))

        store.append(cpu)
        store.append(mem)

        XCTAssertEqual(store.count(for: .cpu), 1)
        XCTAssertEqual(store.count(for: .memory), 1)
        XCTAssertEqual(store.count(for: .thermal), 0)
        XCTAssertEqual(store.totalCount, 2)
        XCTAssertEqual(Set(store.activeCategories), Set([.cpu, .memory]))

        XCTAssertEqual(store.latest(for: .cpu), cpu)
        XCTAssertEqual(store.latest(for: .memory), mem)
        XCTAssertNil(store.latest(for: .disk))
    }

    func testBatchAppend() {
        var store = MetricsStore(defaultCapacity: 5)
        let t = Date()

        let readings: [MetricReading] = [
            .cpu(Sample(value: CPUSample(totalUsage: 10, perCore: [10], user: 5, system: 5, idle: 90), timestamp: t)),
            .gpu(Sample(value: GPUSample(utilization: 40.0), timestamp: t)),
            .network(Sample(value: NetworkSample(interfaces: []), timestamp: t))
        ]

        store.append(readings)

        XCTAssertEqual(store.totalCount, 3)
        XCTAssertEqual(store.count(for: .cpu), 1)
        XCTAssertEqual(store.count(for: .gpu), 1)
        XCTAssertEqual(store.count(for: .network), 1)
        XCTAssertEqual(Set(store.activeCategories), Set([.cpu, .gpu, .network]))
    }

    func testRecordConvenienceAndUnavailable() {
        var store = MetricsStore(defaultCapacity: 5)
        let t = Date()

        let cpu = CPUSample(totalUsage: 50.0, perCore: [50.0], user: 40.0, system: 10.0, idle: 50.0)
        store.record(category: .cpu, value: cpu, timestamp: t)

        XCTAssertEqual(store.count(for: .cpu), 1)
        XCTAssertEqual(store.latestCPU()?.value, cpu)

        store.recordUnavailable(category: .gpu, reason: "GPU unsupported on this test host", timestamp: t)
        XCTAssertEqual(store.count(for: .gpu), 1)

        guard let latestGPU = store.latest(for: .gpu) else {
            return XCTFail("Expected latest GPU reading")
        }
        XCTAssertEqual(latestGPU.category, .gpu)
        XCTAssertEqual(latestGPU.availability, .unavailable(reason: "GPU unsupported on this test host"))
        XCTAssertEqual(latestGPU.timestamp, t)
        XCTAssertNil(store.latestGPU()) // Typed accessor returns nil for .unavailable
    }

    func testTypedExtractorsAndHistory() {
        var store = MetricsStore(defaultCapacity: 5)
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)

        let cpu1 = CPUSample(totalUsage: 10, perCore: [10], user: 5, system: 5, idle: 90)
        let cpu2 = CPUSample(totalUsage: 20, perCore: [20], user: 10, system: 10, idle: 80)
        let mem = MemorySample(total: 32000, used: 16000, free: 16000, wired: 4000, compressed: 2000, cached: 6000, swapUsed: 0, pressure: .normal)
        let therm = ThermalSample(sensors: [SensorReading(name: "CPU Proximity", celsius: 45.0)])
        let fan = FanSample(fans: [FanReading(name: "Left Fan", rpm: 1800, minRPM: 1200, maxRPM: 5000)])
        let gpu = GPUSample(utilization: 65.0)
        let net = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1000, bytesOutPerSec: 2000, totalBytesIn: 100000, totalBytesOut: 200000)])
        let disk = DiskSample(volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000_000, used: 500_000_000, free: 500_000_000)], io: nil)
        let power = PowerSample(hasBattery: true, charge: 0.85, state: .charging, timeRemaining: 2700, cycleCount: 120, powerDrawWatts: 18.5)

        store.record(category: .cpu, value: cpu1, timestamp: t1)
        store.recordUnavailable(category: .cpu, reason: "Mach timeout", timestamp: t1.addingTimeInterval(1))
        store.record(category: .cpu, value: cpu2, timestamp: t2)

        store.record(category: .memory, value: mem, timestamp: t1)
        store.record(category: .thermal, value: therm, timestamp: t1)
        store.record(category: .fan, value: fan, timestamp: t1)
        store.record(category: .gpu, value: gpu, timestamp: t1)
        store.record(category: .network, value: net, timestamp: t1)
        store.record(category: .disk, value: disk, timestamp: t1)
        store.record(category: .power, value: power, timestamp: t1)

        XCTAssertEqual(store.latestCPU()?.value, cpu2)
        XCTAssertEqual(store.latestMemory()?.value, mem)
        XCTAssertEqual(store.latestThermal()?.value, therm)
        XCTAssertEqual(store.latestFan()?.value, fan)
        XCTAssertEqual(store.latestGPU()?.value, gpu)
        XCTAssertEqual(store.latestNetwork()?.value, net)
        XCTAssertEqual(store.latestDisk()?.value, disk)
        XCTAssertEqual(store.latestPower()?.value, power)

        // cpuHistory should filter out the .unavailable reading
        let cpuHist = store.cpuHistory()
        XCTAssertEqual(cpuHist.count, 2)
        XCTAssertEqual(cpuHist.map(\.value), [cpu1, cpu2])

        XCTAssertEqual(store.memoryHistory().count, 1)
        XCTAssertEqual(store.thermalHistory().count, 1)
        XCTAssertEqual(store.fanHistory().count, 1)
        XCTAssertEqual(store.gpuHistory().count, 1)
        XCTAssertEqual(store.networkHistory().count, 1)
        XCTAssertEqual(store.diskHistory().count, 1)
        XCTAssertEqual(store.powerHistory().count, 1)
    }

    func testClearCategoryAndClearAll() {
        var store = MetricsStore(defaultCapacity: 5)
        let t = Date()

        store.record(category: .cpu, value: CPUSample(totalUsage: 10, perCore: [10], user: 5, system: 5, idle: 90), timestamp: t)
        store.record(category: .memory, value: MemorySample(total: 10, used: 5, free: 5, wired: 2, compressed: 1, cached: 2, swapUsed: 0, pressure: .normal), timestamp: t)

        XCTAssertEqual(store.totalCount, 2)

        // Clear CPU only
        store.clear(category: .cpu)
        XCTAssertEqual(store.count(for: .cpu), 0)
        XCTAssertTrue(store.isEmpty(for: .cpu))
        XCTAssertEqual(store.count(for: .memory), 1)
        XCTAssertEqual(store.totalCount, 1)
        XCTAssertEqual(store.activeCategories, [.memory])

        // Clear all
        store.clearAll()
        XCTAssertEqual(store.totalCount, 0)
        XCTAssertTrue(store.activeCategories.isEmpty)
    }

    func testEquatable() {
        var store1 = MetricsStore(defaultCapacity: 5)
        var store2 = MetricsStore(defaultCapacity: 5)
        let store3 = MetricsStore(defaultCapacity: 10)

        let t = Date(timeIntervalSince1970: 500)
        let cpu = MetricReading.cpu(Sample(value: CPUSample(totalUsage: 10, perCore: [10], user: 5, system: 5, idle: 90), timestamp: t))

        store1.append(cpu)
        store2.append(cpu)

        XCTAssertEqual(store1, store2)
        XCTAssertNotEqual(store1, store3)

        store2.recordUnavailable(category: .memory, reason: "error", timestamp: t)
        XCTAssertNotEqual(store1, store2)
    }

    // MARK: - Extended In-Memory Scalar Trends (Task 7.6)

    func testScalarSeriesRetention900Samples() {
        var store = MetricsStore()
        let baseTime = Date(timeIntervalSince1970: 10_000)

        // Append 1,000 samples
        for i in 0..<1000 {
            let t = baseTime.addingTimeInterval(Double(i))
            let cpu = MetricReading.cpu(Sample(
                value: CPUSample(totalUsage: Double(i % 100), perCore: [Double(i % 100)], user: Double(i % 50), system: Double(i % 50), idle: 0),
                timestamp: t
            ))
            store.append(cpu)
        }

        // Full-struct buffer stays capped at 60 (zero bloat)
        XCTAssertEqual(store.count(for: .cpu), 60)
        XCTAssertEqual(store.cpuHistory().count, 60)

        // Scalar buffer retains 900 samples (15m window)
        XCTAssertEqual(store.scalarCount(for: .cpuUser), 900)
        XCTAssertEqual(store.scalarCount(for: .cpuSystem), 900)

        // Oldest evicted; first stored sample timestamp is baseTime + 100s
        let points = store.scalarPoints(for: .cpuUser)
        XCTAssertEqual(points.count, 900)
        XCTAssertEqual(points.first?.timestamp, baseTime.addingTimeInterval(100))
        XCTAssertEqual(points.last?.timestamp, baseTime.addingTimeInterval(999))
    }

    func testSpikePreservingDownsampler() {
        // Create 900 flat points (5.0) with an isolated acute spike (99.0) at index 450
        var rawValues = [Double](repeating: 5.0, count: 900)
        rawValues[450] = 99.0

        let downsampled = Downsampler.downsampleSpikePreserving(rawValues, targetCount: 120)

        XCTAssertEqual(downsampled.count, 120)
        XCTAssertTrue(downsampled.contains(99.0), "Downsampler must preserve acute spike of 99.0")
        XCTAssertEqual(downsampled.max(), 99.0)
    }

    func testScalarHistoryDurationFilterAndDownsample() {
        var store = MetricsStore()
        let baseTime = Date(timeIntervalSince1970: 20_000)

        // Append 600 seconds of data (10 minutes)
        for i in 0..<600 {
            let t = baseTime.addingTimeInterval(Double(i))
            let mem = MetricReading.memory(Sample(
                value: MemorySample(total: 1000, used: UInt64(i), free: 1000 - UInt64(i), wired: 100, compressed: 50, cached: 50, swapUsed: 0, pressure: .normal),
                timestamp: t
            ))
            store.append(mem)
        }

        // 1m duration -> returns 60 points (no downsampling needed as 60 <= 120)
        let oneMinute = store.scalarHistory(for: .memoryUsedPercent, duration: 60, maxPoints: 120)
        XCTAssertEqual(oneMinute.count, 60)

        // 5m duration (300s) -> downsampled to 120 points
        let fiveMinutes = store.scalarHistory(for: .memoryUsedPercent, duration: 300, maxPoints: 120)
        XCTAssertEqual(fiveMinutes.count, 120)

        // 15m duration (900s) with 600s stored -> downsampled to 120 points
        let fifteenMinutes = store.scalarHistory(for: .memoryUsedPercent, duration: 900, maxPoints: 120)
        XCTAssertEqual(fifteenMinutes.count, 120)
    }

    func testScalarMemoryFootprintWithinBudget() {
        let pointStride = MemoryLayout<ScalarPoint>.stride
        let seriesCount = ScalarSeriesKey.allCases.count
        let totalPoints = 900 * seriesCount
        let rawDataBytes = totalPoints * pointStride

        // 16 bytes per point * 900 * 11 series = 158,400 bytes (~154 KB)
        XCTAssertEqual(pointStride, 16, "ScalarPoint (Date + Double) stride must be exactly 16 bytes")
        XCTAssertLessThanOrEqual(rawDataBytes, 160_000, "11 series of 900 points must fit within 160 KB")
    }
}
