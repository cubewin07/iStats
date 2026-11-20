import XCTest
import Combine
@testable import iStatsCore
@testable import iStats

private struct MockTestSampler: Sampler, @unchecked Sendable {
    let category: MetricCategory
    let output: CPUSample

    func sample() throws -> CPUSample {
        output
    }
}

private final class LockIsolatedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}

@MainActor
final class CoordinatorBatchingTests: XCTestCase {

    // MARK: - 1. Scheduler Batch Stream Tests

    func testSchedulerYieldsBatchedReadings() async {
        let scheduler = SampleScheduler(defaultInterval: 0.05)
        let s1 = MockTestSampler(category: .cpu, output: CPUSample(totalUsage: 10, perCore: [], user: 5, system: 5, idle: 90))
        let s2 = MockTestSampler(category: .memory, output: CPUSample(totalUsage: 20, perCore: [], user: 10, system: 10, idle: 80))

        await scheduler.register(s1)
        await scheduler.register(s2)

        let expBatch = expectation(description: "Batch received from scheduler")
        let receivedBatch = LockIsolatedBox<[MetricReading]?>(nil)

        let streamTask = Task {
            for await batch in scheduler.batchStream {
                receivedBatch.set(batch)
                expBatch.fulfill()
                break
            }
        }

        await scheduler.start()
        await fulfillment(of: [expBatch], timeout: 2.0)
        await scheduler.stop()
        streamTask.cancel()

        let batch = receivedBatch.value
        XCTAssertNotNil(batch)
        XCTAssertEqual(batch?.count, 2, "Batch should contain readings from all active categories in that tick")
        let categories = Set(batch?.map(\.category) ?? [])
        XCTAssertTrue(categories.contains(.cpu))
        XCTAssertTrue(categories.contains(.memory))
    }

    func testSchedulerMaintainsSingleStreamCompatibility() async {
        let scheduler = SampleScheduler(defaultInterval: 0.05)
        let s1 = MockTestSampler(category: .cpu, output: CPUSample(totalUsage: 15, perCore: [], user: 5, system: 10, idle: 85))

        await scheduler.register(s1)

        let expSingle = expectation(description: "Single reading received from legacy stream")
        let receivedReading = LockIsolatedBox<MetricReading?>(nil)

        let streamTask = Task {
            for await reading in scheduler.stream {
                receivedReading.set(reading)
                expSingle.fulfill()
                break
            }
        }

        await scheduler.start()
        await fulfillment(of: [expSingle], timeout: 2.0)
        await scheduler.stop()
        streamTask.cancel()

        let reading = receivedReading.value
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading?.category, .cpu)
    }

    // MARK: - 2. Coordinator Batch Ingestion Tests

    func testCoordinatorProcessesBatchInSinglePass() {
        let suiteName = "test.istats.coordinator.batch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        coord.resetPerformanceCounters()

        let cpu = CPUSample(totalUsage: 33, perCore: [], user: 15, system: 18, idle: 67)
        let mem = MemorySample(total: 1000, used: 400, free: 600, wired: 100, compressed: 50, cached: 100, swapUsed: 0, pressure: .normal)
        let net = NetworkSample(interfaces: [])

        let r1 = MetricReading.wrap(category: .cpu, value: cpu)
        let r2 = MetricReading.wrap(category: .memory, value: mem)
        let r3 = MetricReading.wrap(category: .network, value: net)

        coord.handleReadings([r1, r2, r3])

        XCTAssertEqual(coord.batchIngestionCount, 1, "Batch of readings must increment batchIngestionCount by exactly 1")
        XCTAssertEqual(coord.singleIngestionCount, 0, "No single-reading ingestion should occur for batch call")
        XCTAssertEqual(coord.latestCPU?.value.totalUsage, 33)
        XCTAssertEqual(coord.latestMemory?.value.used, 400)
        XCTAssertNotNil(coord.latestNetwork)
    }

    func testCoordinatorSingleReadingIngestion() {
        let suiteName = "test.istats.coordinator.single.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        coord.resetPerformanceCounters()

        let cpu = CPUSample(totalUsage: 45, perCore: [], user: 20, system: 25, idle: 55)
        let reading = MetricReading.wrap(category: .cpu, value: cpu)

        coord.handleReading(reading)

        XCTAssertEqual(coord.singleIngestionCount, 1)
        XCTAssertEqual(coord.batchIngestionCount, 0)
        XCTAssertEqual(coord.latestCPU?.value.totalUsage, 45)
    }

    // MARK: - 3. MenuBarIconRenderer Lazy History Tests

    func testMenuBarRendererSkipsHistoryMappingForNonSparklineStyles() {
        let suiteName = "test.istats.renderer.lazyhist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cpu = CPUSample(totalUsage: 50, perCore: [], user: 25, system: 25, idle: 50)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: cpu))

        // Text style does not need history
        let textConfig = MenuBarItemConfig(category: .cpu, style: .text)
        let textResult = MenuBarIconRenderer.render(config: textConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(textResult.image)

        // Gauge style does not need history
        let gaugeConfig = MenuBarItemConfig(category: .cpu, style: .gauge)
        let gaugeResult = MenuBarIconRenderer.render(config: gaugeConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(gaugeResult.image)
    }

    func testCoordinatorHistoryQueriesDirectlyFromStoreOnDemand() {
        let suiteName = "test.istats.coordinator.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(coord.cpuHistory.isEmpty)

        let cpu = CPUSample(totalUsage: 35, perCore: [], user: 20, system: 15, idle: 65)
        let r1 = MetricReading.wrap(category: .cpu, value: cpu)
        coord.handleReadings([r1])

        XCTAssertEqual(coord.cpuHistory.count, 1)
        XCTAssertEqual(coord.cpuHistory.first?.value.totalUsage, 35)
    }

    func testCategoryAvailabilitySkipsRedundantPublishedMutations() {
        let suiteName = "test.istats.coordinator.avail.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var availabilityEmissions = 0
        let cancellable = coord.$categoryAvailability
            .dropFirst()
            .sink { _ in availabilityEmissions += 1 }
        defer { cancellable.cancel() }

        let cpu1 = CPUSample(totalUsage: 20, perCore: [], user: 10, system: 10, idle: 80)
        let mem1 = MemorySample(total: 1000, used: 500, free: 500, wired: 100, compressed: 50, cached: 100, swapUsed: 0, pressure: .normal)

        // First batch changes availability from nil -> .available (1 combined emission)
        coord.handleReadings([
            MetricReading.wrap(category: .cpu, value: cpu1),
            MetricReading.wrap(category: .memory, value: mem1)
        ])
        XCTAssertEqual(availabilityEmissions, 1, "Initial batch should emit exactly 1 availability dictionary change")

        // Second batch has identical .available status -> 0 new emissions
        let cpu2 = CPUSample(totalUsage: 40, perCore: [], user: 20, system: 20, idle: 60)
        coord.handleReadings([
            MetricReading.wrap(category: .cpu, value: cpu2),
            MetricReading.wrap(category: .memory, value: mem1)
        ])
        XCTAssertEqual(availabilityEmissions, 1, "Unchanged availability must not trigger redundant @Published emissions")
    }

    func testCoreHistoryAndProcessHistoryEmitOncePerSample() {
        let suiteName = "test.istats.coordinator.historyemit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var coreEmissions = 0
        let coreCanc = coord.$coreHistory.dropFirst().sink { _ in coreEmissions += 1 }
        defer { coreCanc.cancel() }

        let cpu = CPUSample(
            totalUsage: 40,
            perCore: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
            user: 20,
            system: 20,
            idle: 60
        )
        coord.handleReading(MetricReading.wrap(category: .cpu, value: cpu))
        XCTAssertEqual(coreEmissions, 1, "10-core CPU update must emit coreHistory once, not per core")
        XCTAssertEqual(coord.coreHistory.count, 10)

        var processEmissions = 0
        let procCanc = coord.$processCPUHistory.dropFirst().sink { _ in processEmissions += 1 }
        defer { procCanc.cancel() }

        let procs = (1...5).map { idx in
            ProcessInfoItem(pid: Int32(idx), name: "Proc\(idx)", cpuPercent: Double(idx * 10), memoryBytes: 1024)
        }
        coord.applyProcessSample(ProcessSample(topCPU: procs, topMemory: procs))
        XCTAssertEqual(processEmissions, 1, "5-process update must emit processCPUHistory once, not per process")
        XCTAssertEqual(coord.processCPUHistory.count, 5)
    }

    func testProcessSamplingRunsInLowPowerModeWhenAutoPauseDisabled() async {
        let suiteName = "test.istats.coordinator.lpmproc.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        prefs.autoPauseOnLowPowerMode = false
        let coord = MetricsCoordinator(
            preferencesStore: prefs,
            lowPowerModeProvider: { true }
        )
        defer {
            coord.stopProcessDemand()
            coord.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }

        coord.evaluateLowPowerModeState()
        coord.startProcessDemand()
        // Allow process sampling loop to run its initial pass while Low Power Mode is active
        let deadline = Date().addingTimeInterval(2.5)
        while coord.latestProcesses == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(coord.isLowPowerModeActive)
        XCTAssertFalse(coord.isSamplingPaused)
        XCTAssertNotNil(coord.latestProcesses, "Top Processes must still sample in Low Power Mode when not paused")
    }
}
