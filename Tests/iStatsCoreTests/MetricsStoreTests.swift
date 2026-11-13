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

        // 16 bytes per point * 900 * 12 series = 172,800 bytes (~169 KB)
        XCTAssertEqual(seriesCount, 12, "Expected 12 scalar series including powerChargePercent")
        XCTAssertEqual(pointStride, 16, "ScalarPoint (Date + Double) stride must be exactly 16 bytes")
        XCTAssertLessThanOrEqual(rawDataBytes, 175_000, "12 series of 900 points must fit within 175 KB")
    }

    // MARK: - Timestamped & Bucketed Series + B8/B9 Fixes (Task 8.5.2)

    func testTimedScalarHistoryPreservesTimestampsAndRequestedEdgeCutoff() {
        var store = MetricsStore()
        let base = 1_700_000_000.0

        // Append 70 samples at 1 Hz with slight sampling jitter on the newest sample (+0.15 s)
        for i in 0..<70 {
            let jitter = (i == 69) ? 0.15 : 0.0
            let t = Date(timeIntervalSince1970: base + Double(i) + jitter)
            store.record(
                category: .memory,
                value: MemorySample(
                    total: 1000,
                    used: UInt64(100 + i),
                    free: UInt64(900 - i),
                    wired: 100,
                    compressed: 50,
                    cached: 50,
                    swapUsed: 0,
                    pressure: .normal
                ),
                timestamp: t
            )
        }

        // Query at explicit reference edge base + 69.0 (before the 69.15 jittered sample)
        let ref69 = Date(timeIntervalSince1970: base + 69.0)
        let windowAt69 = store.timedScalarHistory(for: .memoryUsedPercent, duration: 60.0, referenceDate: ref69)
        // Window (9.0, 69.0] contains t = 10...68 -> 59 points (69.15 is excluded because > ref69)
        XCTAssertEqual(windowAt69.count, 59)
        XCTAssertEqual(windowAt69.first?.timestamp ?? -1, base + 10.0, accuracy: 1e-9)
        XCTAssertEqual(windowAt69.last?.timestamp ?? -1, base + 68.0, accuracy: 1e-9)
        XCTAssertEqual(windowAt69.first?.value ?? -1, 11.0, accuracy: 1e-9)

        // Query at reference edge base + 69.2 (after the 69.15 jittered sample).
        // Oldest cutoff is 9.2 (> 9.0), so t = 10...68 + 69.15 -> exactly 60 points,
        // and timestamps are preserved verbatim instead of snapping to newest - 60.
        let ref69_2 = Date(timeIntervalSince1970: base + 69.2)
        let windowAt69_2 = store.timedScalarHistory(for: .memoryUsedPercent, duration: 60.0, referenceDate: ref69_2)
        XCTAssertEqual(windowAt69_2.count, 60)
        XCTAssertEqual(windowAt69_2.first?.timestamp ?? -1, base + 10.0, accuracy: 1e-9)
        XCTAssertEqual(windowAt69_2.last?.timestamp ?? -1, base + 69.15, accuracy: 1e-9)

        // Advancing reference edge slightly to 69.8 (before t=70 arrives) keeps 60 points stable (no B8 jitter)
        let ref69_8 = Date(timeIntervalSince1970: base + 69.8)
        let windowAt69_8 = store.timedScalarHistory(for: .memoryUsedPercent, duration: 60.0, referenceDate: ref69_8)
        XCTAssertEqual(windowAt69_8.count, 60)
        XCTAssertEqual(windowAt69_8, windowAt69_2)
    }

    func testBucketedScalarHistoryStabilityAcrossAppends() {
        var store = MetricsStore()
        let base = 1_700_000_000.0

        // Seed 300s (5 minutes) of 1 Hz CPU samples
        for i in 0..<300 {
            let t = Date(timeIntervalSince1970: base + Double(i))
            let cpu = CPUSample(
                totalUsage: Double(i % 100),
                perCore: [Double(i % 100)],
                user: Double((i * 13) % 70),
                system: Double((i * 7) % 30),
                idle: 10.0
            )
            store.record(category: .cpu, value: cpu, timestamp: t)
        }

        // 5m window (300s) with 2.5s buckets
        var previous5m = store.bucketedScalarHistory(
            for: .cpuUser,
            duration: 300.0,
            bucketWidth: 2.5,
            referenceDate: Date(timeIntervalSince1970: base + 299.0)
        )
        XCTAssertFalse(previous5m.isEmpty)

        // Append 15 more 1 Hz samples one by one and verify closed historical buckets never mutate
        for offset in 300..<315 {
            let t = base + Double(offset)
            let cpu = CPUSample(
                totalUsage: 50.0,
                perCore: [50.0],
                user: Double((offset * 19) % 75),
                system: 12.0,
                idle: 13.0
            )
            store.record(category: .cpu, value: cpu, timestamp: Date(timeIntervalSince1970: t))

            let current5m = store.bucketedScalarHistory(
                for: .cpuUser,
                duration: 300.0,
                bucketWidth: 2.5,
                referenceDate: Date(timeIntervalSince1970: t)
            )
            let activeBucketCenter = (floor(t / 2.5) + 0.5) * 2.5
            let cutoff = t - 300.0

            for prev in previous5m {
                let prevBucketEnd = prev.timestamp + 1.25
                guard prev.timestamp < activeBucketCenter - 1e-6, prevBucketEnd > cutoff else { continue }
                let match = current5m.first(where: { abs($0.timestamp - prev.timestamp) < 1e-6 })
                XCTAssertEqual(match, prev, "Closed 5m bucket at \(prev.timestamp) mutated on append")
            }
            previous5m = current5m
        }

        // Also check 15m window (900s, 7.5s buckets) drops whole buckets cleanly when referenceDate advances
        let at314 = store.bucketedScalarHistory(
            for: .cpuUser,
            duration: 900.0,
            bucketWidth: 7.5,
            referenceDate: Date(timeIntervalSince1970: base + 314.0)
        )
        let later = store.bucketedScalarHistory(
            for: .cpuUser,
            duration: 900.0,
            bucketWidth: 7.5,
            referenceDate: Date(timeIntervalSince1970: base + 902.5)
        )
        XCTAssertLessThan(later.count, at314.count)
        for bucket in later {
            let original = at314.first(where: { abs($0.timestamp - bucket.timestamp) < 1e-6 })
            XCTAssertEqual(bucket, original, "Surviving 15m bucket must remain identical when referenceDate advances")
        }
    }

    func testPowerWattsDoesNotStoreChargeWhenWattageNil_B9() {
        var store = MetricsStore()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_001)
        let t2 = Date(timeIntervalSince1970: 1_700_000_002)

        // Battery sample with nil wattage and 85% charge -> must NOT write 85 into powerWatts
        store.record(
            category: .power,
            value: PowerSample(
                hasBattery: true,
                charge: 85.0,
                state: .discharging,
                timeRemaining: 3600,
                cycleCount: 50,
                powerDrawWatts: nil
            ),
            timestamp: t0
        )

        XCTAssertEqual(store.scalarCount(for: .powerWatts), 0)
        XCTAssertEqual(store.scalarCount(for: .powerChargePercent), 1)
        XCTAssertEqual(store.scalarPoints(for: .powerChargePercent).first?.value, 85.0)

        // Sample with both wattage and charge -> each goes to its dedicated series
        store.record(
            category: .power,
            value: PowerSample(
                hasBattery: true,
                charge: 84.5,
                state: .discharging,
                timeRemaining: 3500,
                cycleCount: 50,
                powerDrawWatts: 18.2
            ),
            timestamp: t1
        )

        XCTAssertEqual(store.scalarCount(for: .powerWatts), 1)
        XCTAssertEqual(store.scalarPoints(for: .powerWatts).last?.value, 18.2)
        XCTAssertEqual(store.scalarCount(for: .powerChargePercent), 2)
        XCTAssertEqual(store.scalarPoints(for: .powerChargePercent).last?.value, 84.5)

        // Desktop sample with wattage and nil charge -> writes powerWatts only
        store.record(
            category: .power,
            value: PowerSample(
                hasBattery: false,
                charge: nil,
                state: .acConnected,
                powerDrawWatts: 42.0
            ),
            timestamp: t2
        )

        XCTAssertEqual(store.scalarCount(for: .powerWatts), 2)
        XCTAssertEqual(store.scalarCount(for: .powerChargePercent), 2)

        // Clearing .power clears both scalar buffers
        store.clear(category: .power)
        XCTAssertEqual(store.scalarCount(for: .powerWatts), 0)
        XCTAssertEqual(store.scalarCount(for: .powerChargePercent), 0)
    }

    func testDualChannelTimestampAlignment() {
        var store = MetricsStore()
        let base = 1_700_000_000.0

        for i in 0..<10 {
            let t = Date(timeIntervalSince1970: base + Double(i))
            store.record(
                category: .network,
                value: NetworkSample(interfaces: [
                    InterfaceThroughput(
                        interfaceName: "en0",
                        bytesInPerSec: Double(1000 + i * 100),
                        bytesOutPerSec: Double(500 + i * 50),
                        totalBytesIn: UInt64(i * 1000),
                        totalBytesOut: UInt64(i * 500)
                    )
                ]),
                timestamp: t
            )
            // Record power with wattage only on even seconds to verify mismatched series alignment
            let watts: Double? = (i % 2 == 0) ? Double(10 + i) : nil
            store.record(
                category: .power,
                value: PowerSample(
                    hasBattery: true,
                    charge: Double(90 - i),
                    state: .discharging,
                    powerDrawWatts: watts
                ),
                timestamp: t
            )
        }

        let ref = Date(timeIntervalSince1970: base + 9.0)
        let netDual = store.timedDualScalarHistory(
            primary: .networkInBytesPerSec,
            secondary: .networkOutBytesPerSec,
            duration: 60.0,
            referenceDate: ref
        )
        XCTAssertEqual(netDual.count, 10)
        XCTAssertEqual(netDual.first, DualChartPoint(timestamp: base, primary: 1000.0, secondary: 500.0))
        XCTAssertEqual(netDual.last, DualChartPoint(timestamp: base + 9.0, primary: 1900.0, secondary: 950.0))

        // Inner-join timestamp alignment across sparse powerWatts + dense powerChargePercent
        let sparseDual = store.timedDualScalarHistory(
            primary: .powerWatts,
            secondary: .powerChargePercent,
            duration: 60.0,
            referenceDate: ref
        )
        XCTAssertEqual(sparseDual.count, 5)
        XCTAssertEqual(sparseDual.map(\.timestamp), [0, 2, 4, 6, 8].map { base + Double($0) })
        XCTAssertEqual(sparseDual.map(\.primary), [10, 12, 14, 16, 18])
        XCTAssertEqual(sparseDual.map(\.secondary), [90, 88, 86, 84, 82])

        // Bucketed dual alignment
        let bucketedNet = store.bucketedDualScalarHistory(
            primary: .networkInBytesPerSec,
            secondary: .networkOutBytesPerSec,
            duration: 60.0,
            bucketWidth: 2.5,
            referenceDate: ref
        )
        XCTAssertEqual(bucketedNet.primary.count, bucketedNet.secondary.count)
        XCTAssertFalse(bucketedNet.primary.isEmpty)
        XCTAssertEqual(bucketedNet.primary.map(\.timestamp), bucketedNet.secondary.map(\.timestamp))
    }
}
