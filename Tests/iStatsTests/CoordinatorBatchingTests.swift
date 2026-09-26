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
        var receivedBatch: [MetricReading]?

        let streamTask = Task {
            for await batch in scheduler.batchStream {
                receivedBatch = batch
                expBatch.fulfill()
                break
            }
        }

        await scheduler.start()
        await fulfillment(of: [expBatch], timeout: 2.0)
        await scheduler.stop()
        streamTask.cancel()

        XCTAssertNotNil(receivedBatch)
        XCTAssertEqual(receivedBatch?.count, 2, "Batch should contain readings from all active categories in that tick")
        let categories = Set(receivedBatch?.map(\.category) ?? [])
        XCTAssertTrue(categories.contains(.cpu))
        XCTAssertTrue(categories.contains(.memory))
    }

    func testSchedulerMaintainsSingleStreamCompatibility() async {
        let scheduler = SampleScheduler(defaultInterval: 0.05)
        let s1 = MockTestSampler(category: .cpu, output: CPUSample(totalUsage: 15, perCore: [], user: 5, system: 10, idle: 85))

        await scheduler.register(s1)

        let expSingle = expectation(description: "Single reading received from legacy stream")
        var receivedReading: MetricReading?

        let streamTask = Task {
            for await reading in scheduler.stream {
                receivedReading = reading
                expSingle.fulfill()
                break
            }
        }

        await scheduler.start()
        await fulfillment(of: [expSingle], timeout: 2.0)
        await scheduler.stop()
        streamTask.cancel()

        XCTAssertNotNil(receivedReading)
        XCTAssertEqual(receivedReading?.category, .cpu)
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
}
