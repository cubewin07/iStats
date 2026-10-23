import XCTest
@testable import iStatsCore

final class SampleSchedulerCoalescingTests: XCTestCase {

    // MARK: - 1. Quality of Service (QoS) Tests

    func testSamplingTasksExecuteWithUtilityPriority() async {
        let exp = expectation(description: "Sampling executed with utility priority")
        let observedPriority = LockIsolated<TaskPriority?>(nil)

        let sampler = ConfigurableSampler(
            category: .cpu,
            output: CPUSample(totalUsage: 10, perCore: [10], user: 5, system: 5, idle: 90),
            onSampleCalled: {
                let priority = Task.currentPriority
                observedPriority.withValue { $0 = priority }
                exp.fulfill()
            }
        )

        let scheduler = SampleScheduler(defaultInterval: 0.05)
        await scheduler.register(sampler)

        // Start scheduler explicitly from a high-priority / MainActor context to test priority clamping
        await Task(priority: .high) {
            await scheduler.start()
        }.value

        await fulfillment(of: [exp], timeout: 2.0)
        await scheduler.stop()

        let priority = observedPriority.withValue { $0 }
        XCTAssertNotNil(priority)
        // Background telemetry must run at .utility or lower (never .high / .userInitiated)
        XCTAssertTrue(
            priority == .utility || priority == .background || priority == .low,
            "Expected background sampling to execute at .utility or lower, but ran at: \(String(describing: priority))"
        )
    }

    // MARK: - 2. Batched Synchronization Tests

    func testBatchedSamplingTickExecutesConcurrentlyWithinSmallDelta() async {
        let expTick = expectation(description: "All categories executed within the same batched tick")
        expTick.expectedFulfillmentCount = 4

        let timestamps = LockIsolated<[MetricCategory: Date]>([:])

        func makeSampler(for cat: MetricCategory) -> ConfigurableSampler<CPUSample> {
            ConfigurableSampler(
                category: cat,
                output: CPUSample(totalUsage: 0, perCore: [], user: 0, system: 0, idle: 100),
                onSampleCalled: {
                    timestamps.withValue { dict in
                        if dict[cat] == nil {
                            dict[cat] = Date()
                        }
                    }
                    expTick.fulfill()
                }
            )
        }

        let scheduler = SampleScheduler(defaultInterval: 0.1)
        await scheduler.register(makeSampler(for: .cpu))
        await scheduler.register(makeSampler(for: .memory))
        await scheduler.register(makeSampler(for: .disk))
        await scheduler.register(makeSampler(for: .network))

        await scheduler.start()
        await fulfillment(of: [expTick], timeout: 2.0)
        await scheduler.stop()

        let recorded = timestamps.withValue { $0 }
        XCTAssertEqual(recorded.count, 4)

        let times = Array(recorded.values)
        if let minTime = times.min(), let maxTime = times.max() {
            let spread = maxTime.timeIntervalSince(minTime)
            // In a batched tick, all categories sharing an interval should fire within 50ms of each other
            XCTAssertLessThanOrEqual(
                spread,
                0.08,
                "Batched tick categories drifted too far apart: spread was \(spread)s (expected <= 0.08s)"
            )
        }
    }

    func testBatchedSamplingTickPreventsDriftAcrossSubsequentTicks() async {
        let tickCounts = LockIsolated<[MetricCategory: Int]>([:])
        let secondTickTimes = LockIsolated<[MetricCategory: Date]>([:])
        let expSecondTick = expectation(description: "Second tick captured for all categories")
        expSecondTick.expectedFulfillmentCount = 3

        func makeSampler(for cat: MetricCategory, sleepMs: UInt32) -> ConfigurableSampler<CPUSample> {
            ConfigurableSampler(
                category: cat,
                output: CPUSample(totalUsage: 0, perCore: [], user: 0, system: 0, idle: 100),
                onSampleCalled: {
                    let count = tickCounts.withValue { dict -> Int in
                        let c = (dict[cat] ?? 0) + 1
                        dict[cat] = c
                        return c
                    }
                    if count == 2 {
                        secondTickTimes.withValue { dict in
                            dict[cat] = Date()
                        }
                        expSecondTick.fulfill()
                    }
                    if sleepMs > 0 {
                        usleep(sleepMs * 1000)
                    }
                }
            )
        }

        let scheduler = SampleScheduler(defaultInterval: 0.1)
        // Three samplers with different run durations: 0ms, 30ms, 60ms
        await scheduler.register(makeSampler(for: .cpu, sleepMs: 0))
        await scheduler.register(makeSampler(for: .memory, sleepMs: 30))
        await scheduler.register(makeSampler(for: .disk, sleepMs: 60))

        await scheduler.start()
        await fulfillment(of: [expSecondTick], timeout: 3.0)
        await scheduler.stop()

        let times = secondTickTimes.withValue { Array($0.values) }
        XCTAssertEqual(times.count, 3)
        if let minTime = times.min(), let maxTime = times.max() {
            let spread = maxTime.timeIntervalSince(minTime)
            // On unaligned independent loops, tick 2 start times drift by 60ms+
            // In a batched cadence, all categories for tick 2 are dispatched together (<= 50ms spread)
            XCTAssertLessThanOrEqual(
                spread,
                0.05,
                "Subsequent tick categories drifted out of phase: spread was \(spread)s (expected <= 0.05s in batched mode)"
            )
        }
    }

    // MARK: - 3. Timeout Isolation in Batched Mode

    func testTimeoutIsolationInBatchedTick() async {
        let scheduler = SampleScheduler(defaultInterval: 0.5, timeBudget: 0.25)

        let fastSampleReceived = expectation(description: "Fast sample completed quickly")
        let fastBatchReceived = expectation(description: "Fast batch flushed before slow sampler timed out")
        let slowSampleUnavailable = expectation(description: "Slow sample timed out to unavailable")

        let slowSampler = ConfigurableSampler(
            category: .fan,
            output: FanSample(),
            sleepSeconds: 0.45 // Exceeds 0.25s timeBudget
        )
        let fastSampler = ConfigurableSampler(
            category: .cpu,
            output: CPUSample(totalUsage: 15, perCore: [15], user: 5, system: 10, idle: 85)
        )

        await scheduler.register(slowSampler)
        await scheduler.register(fastSampler)

        let startTime = Date()
        let fastArrivalDelay = LockIsolated<TimeInterval?>(nil)
        let fastBatchDelay = LockIsolated<TimeInterval?>(nil)

        let stream = scheduler.stream
        let streamTask = Task {
            var fastFulfilled = false
            var slowFulfilled = false
            for await reading in stream {
                if reading.category == .cpu && reading.availability.isAvailable && !fastFulfilled {
                    fastFulfilled = true
                    fastArrivalDelay.withValue { $0 = Date().timeIntervalSince(startTime) }
                    fastSampleReceived.fulfill()
                }
                if reading.category == .fan && !reading.availability.isAvailable && !slowFulfilled {
                    if reading.availability.unavailableReason?.contains("timed out") == true {
                        slowFulfilled = true
                        slowSampleUnavailable.fulfill()
                    }
                }
            }
        }

        let batchStream = scheduler.batchStream
        let batchTask = Task {
            var batchFulfilled = false
            for await batch in batchStream {
                if batch.contains(where: { $0.category == .cpu && $0.availability.isAvailable }) && !batchFulfilled {
                    batchFulfilled = true
                    fastBatchDelay.withValue { $0 = Date().timeIntervalSince(startTime) }
                    fastBatchReceived.fulfill()
                }
            }
        }

        await scheduler.start()
        await fulfillment(of: [fastSampleReceived, fastBatchReceived, slowSampleUnavailable], timeout: 2.0)
        await scheduler.stop()
        streamTask.cancel()
        batchTask.cancel()

        if let delay = fastArrivalDelay.withValue({ $0 }) {
            XCTAssertLessThan(delay, 0.20, "Fast sampler on stream was blocked by slow sampler (took \(delay)s vs 0.25s timeout)")
        }
        if let bDelay = fastBatchDelay.withValue({ $0 }) {
            XCTAssertLessThan(bDelay, 0.20, "Fast sampler on batchStream was blocked by slow sampler (took \(bDelay)s vs 0.25s timeout)")
        }
    }

    // MARK: - 4. Mixed Interval Cadence Groups

    func testMixedIntervalCadenceGroups() async {
        // Fast category: 0.04s, Slower category: 0.12s (3x ratio)
        let scheduler = SampleScheduler(defaultInterval: 0.12)

        let fastTicks = LockIsolated<Int>(0)
        let slowTicks = LockIsolated<Int>(0)

        let fastSampler = ConfigurableSampler(
            category: .cpu,
            output: CPUSample(totalUsage: 0, perCore: [], user: 0, system: 0, idle: 100),
            onSampleCalled: {
                fastTicks.withValue { $0 += 1 }
            }
        )

        let slowSampler = ConfigurableSampler(
            category: .power,
            output: PowerSample(hasBattery: false),
            onSampleCalled: {
                slowTicks.withValue { $0 += 1 }
            }
        )

        await scheduler.register(fastSampler)
        await scheduler.register(slowSampler)
        await scheduler.setInterval(category: .cpu, interval: 0.04)

        await scheduler.start()
        // Wait 0.25s
        try? await Task.sleep(nanoseconds: 250_000_000)
        await scheduler.stop()

        let fastCount = fastTicks.withValue { $0 }
        let slowCount = slowTicks.withValue { $0 }

        // Fast sampler should have run significantly more times than the slower sampler
        XCTAssertGreaterThan(fastCount, slowCount)
        XCTAssertGreaterThanOrEqual(fastCount, 3)
        XCTAssertGreaterThanOrEqual(slowCount, 1)
    }

    func testEnablingCategoryOnExistingCadenceTriggersImmediateSample() async {
        // Use a long interval (10s) so the cadence loop sleeps after tick 1
        let scheduler = SampleScheduler(defaultInterval: 10.0)
        let cpuObserved = expectation(description: "Initial CPU sample")
        let gpuObservedImmediately = expectation(description: "Newly enabled GPU sampled immediately without waiting 10s")

        await scheduler.register(ConfigurableSampler(
            category: .cpu,
            output: CPUSample(totalUsage: 10, perCore: [10], user: 5, system: 5, idle: 90)
        ))
        await scheduler.register(ConfigurableSampler(
            category: .gpu,
            output: GPUSample(utilization: 42.0)
        ))
        await scheduler.setEnabled(category: .gpu, isEnabled: false)

        let stream = scheduler.stream
        let streamTask = Task {
            var cpuDone = false
            var gpuDone = false
            for await reading in stream {
                if reading.category == .cpu && !cpuDone {
                    cpuDone = true
                    cpuObserved.fulfill()
                } else if reading.category == .gpu && !gpuDone {
                    gpuDone = true
                    gpuObservedImmediately.fulfill()
                }
            }
        }

        await scheduler.start()
        await fulfillment(of: [cpuObserved], timeout: 1.0)

        // Now enable GPU while the 10s cadence loop is already sleeping
        await scheduler.setEnabled(category: .gpu, isEnabled: true)
        await fulfillment(of: [gpuObservedImmediately], timeout: 1.0)

        await scheduler.stop()
        streamTask.cancel()
    }
}

// Thread-safe wrapper for test state assertions
private final class LockIsolated<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    func withValue<R>(_ block: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return block(&_value)
    }
}
