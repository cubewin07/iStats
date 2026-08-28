import XCTest
import Foundation
@testable import iStatsCore
@testable import iStats

@MainActor
final class PerformancePassTests: XCTestCase {
    // MARK: - Thread-Safe Test Helpers (Swift 6 Concurrency)

    private final class ThreadSafeCounter: @unchecked Sendable {
        private var value: Int = 0
        private let lock = NSLock()

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private final class ThreadSafeMap<K: Hashable, V>: @unchecked Sendable {
        private var map: [K: V] = [:]
        private let lock = NSLock()

        func set(_ key: K, value: V) {
            lock.lock()
            map[key] = value
            lock.unlock()
        }

        func get(_ key: K) -> V? {
            lock.lock()
            defer { lock.unlock() }
            return map[key]
        }

        func contains(_ key: K) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return map[key] != nil
        }
    }

    private final class ThreadSafeSet<T: Hashable>: @unchecked Sendable {
        private var set: Set<T> = []
        private let lock = NSLock()

        func insert(_ item: T) {
            lock.lock()
            set.insert(item)
            lock.unlock()
        }

        func contains(_ item: T) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return set.contains(item)
        }
    }

    // MARK: - Off-Main-Thread Sampling Verification (Requirement 12.1, ADR 0002)

    func testAllSamplersExecuteOffMainThread() async {
        let scheduler = SampleScheduler(defaultInterval: 1.0)

        // Register all concrete samplers
        await scheduler.register(CPUSampler())
        await scheduler.register(MemorySampler())
        await scheduler.register(NetworkSampler())
        await scheduler.register(DiskSampler())
        await scheduler.register(PowerSampler())
        await scheduler.register(ThermalSampler())
        await scheduler.register(FanSampler())
        await scheduler.register(GPUSampler())

        let expectation = expectation(description: "All categories sampled off main thread")
        expectation.expectedFulfillmentCount = 8

        let threadExecutionMap = ThreadSafeMap<MetricCategory, Bool>()

        await scheduler.setOnSample { reading in
            let isBackground = !Thread.isMainThread
            if !threadExecutionMap.contains(reading.category) {
                threadExecutionMap.set(reading.category, value: isBackground)
                expectation.fulfill()
            }
        }

        await scheduler.start()

        await fulfillment(of: [expectation], timeout: 5.0)
        await scheduler.stop()

        for category in MetricCategory.allCases {
            let executedOnBackground = threadExecutionMap.get(category) ?? false
            XCTAssertTrue(
                executedOnBackground,
                "Sampler for category \(category.displayName) failed Requirement 12.1: must execute off the main thread."
            )
        }
    }

    // MARK: - Latency & Footprint Benchmark (Requirement 12.2)

    func testFullSamplingPassLatencyBenchmark() async {
        let samplers: [any Sampler] = [
            CPUSampler(),
            MemorySampler(),
            NetworkSampler(),
            DiskSampler(),
            PowerSampler(),
            ThermalSampler(),
            FanSampler(),
            GPUSampler()
        ]

        let iterations = 10
        var totalDuration: TimeInterval = 0.0
        var samplerDurations: [String: TimeInterval] = [:]

        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            for sampler in samplers {
                let sStart = CFAbsoluteTimeGetCurrent()
                _ = try? sampler.sample()
                let sElapsed = CFAbsoluteTimeGetCurrent() - sStart
                samplerDurations[String(describing: type(of: sampler)), default: 0.0] += sElapsed
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            totalDuration += elapsed
        }

        let averagePassDurationMs = (totalDuration / Double(iterations)) * 1000.0
        print("Performance Benchmark: Average pass duration across all 8 samplers = \(String(format: "%.2f", averagePassDurationMs)) ms")
        for (name, dur) in samplerDurations {
            let avgMs = (dur / Double(iterations)) * 1000.0
            print("  - \(name): \(String(format: "%.2f", avgMs)) ms")
        }

        // In macOS on modern hardware, all 8 samplers execute within single-digit to low double-digit ms.
        // At a 2.0s refresh interval, an execution of 10ms accounts for ~0.5% duty cycle.
        XCTAssertLessThan(
            averagePassDurationMs,
            100.0,
            "Sampling pass exceeded 100ms budget, which could introduce noticeable background CPU footprint."
        )
    }

    // MARK: - Interval Scaling Reduces Frequency (Requirement 12.4)

    func testIntervalScalingReducesSamplingFrequency() async {
        let scheduler = SampleScheduler(defaultInterval: 0.2)
        await scheduler.register(CPUSampler())

        let fastCounter = ThreadSafeCounter()

        await scheduler.setOnSample { _ in
            fastCounter.increment()
        }

        await scheduler.start()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        await scheduler.stop()

        let initialCount = fastCounter.count
        XCTAssertGreaterThanOrEqual(initialCount, 2, "Expected at least 2 samples at 0.2s interval")

        // Now scale interval up to 2.0s
        await scheduler.setDefaultInterval(2.0)
        let slowCounter = ThreadSafeCounter()

        await scheduler.setOnSample { _ in
            slowCounter.increment()
        }

        await scheduler.start()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        await scheduler.stop()

        XCTAssertLessThanOrEqual(
            slowCounter.count,
            1,
            "Increasing refresh interval to 2.0s must reduce sample frequency within 0.5s window."
        )
    }

    // MARK: - Disabled Categories Incur Zero Sampling Overhead (Requirement 12.2)

    func testDisabledCategoriesIncurZeroSamplingOverhead() async {
        let scheduler = SampleScheduler(defaultInterval: 0.1)
        await scheduler.register(CPUSampler())
        await scheduler.register(MemorySampler())
        await scheduler.register(NetworkSampler())
        await scheduler.register(DiskSampler())

        // Disable all except CPU
        await scheduler.setEnabled(category: .memory, isEnabled: false)
        await scheduler.setEnabled(category: .network, isEnabled: false)
        await scheduler.setEnabled(category: .disk, isEnabled: false)

        let sampledCategories = ThreadSafeSet<MetricCategory>()

        await scheduler.setOnSample { reading in
            sampledCategories.insert(reading.category)
        }

        await scheduler.start()
        try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s
        await scheduler.stop()

        XCTAssertTrue(sampledCategories.contains(.cpu))
        XCTAssertFalse(sampledCategories.contains(.memory))
        XCTAssertFalse(sampledCategories.contains(.network))
        XCTAssertFalse(sampledCategories.contains(.disk))
    }
}
