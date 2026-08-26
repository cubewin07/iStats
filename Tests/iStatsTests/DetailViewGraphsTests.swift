import XCTest
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class DetailViewGraphsTests: XCTestCase {
    // MARK: - MetricsCoordinator Tests

    func testMetricsCoordinatorInitialization() {
        let scheduler = SampleScheduler()
        let store = MetricsStore()
        let defaults = UserDefaults(suiteName: "iStats.test.coordinator.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)

        let coordinator = MetricsCoordinator(scheduler: scheduler, store: store, preferencesStore: prefs)

        XCTAssertNil(coordinator.latestCPU)
        XCTAssertNil(coordinator.latestMemory)
        XCTAssertTrue(coordinator.cpuHistory.isEmpty)
        XCTAssertTrue(coordinator.memoryHistory.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testMetricsCoordinatorHandlesReadings() {
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: PreferencesStore(userDefaults: UserDefaults(suiteName: "iStats.test.\(UUID().uuidString)")!)
        )

        let cpuSample = CPUSample(
            totalUsage: 25.5,
            perCore: [20.0, 31.0],
            user: 15.0,
            system: 10.5,
            idle: 74.5,
            loadAverage: LoadAverage(oneMinute: 1.5, fiveMinute: 1.2, fifteenMinute: 0.9),
            frequencyHz: 3_200_000_000
        )
        let cpuReading = MetricReading.cpu(Sample(value: cpuSample, timestamp: Date(), availability: .available))
        coordinator.handleReading(cpuReading)

        XCTAssertNotNil(coordinator.latestCPU)
        XCTAssertEqual(coordinator.latestCPU?.value.totalUsage, 25.5)
        XCTAssertEqual(coordinator.cpuHistory.count, 1)

        let memSample = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 10 * 1024 * 1024 * 1024,
            free: 6 * 1024 * 1024 * 1024,
            wired: 3 * 1024 * 1024 * 1024,
            compressed: 2 * 1024 * 1024 * 1024,
            cached: 4 * 1024 * 1024 * 1024,
            swapUsed: 512 * 1024 * 1024,
            pressure: .normal
        )
        let memReading = MetricReading.memory(Sample(value: memSample, timestamp: Date(), availability: .available))
        coordinator.handleReading(memReading)

        XCTAssertNotNil(coordinator.latestMemory)
        XCTAssertEqual(coordinator.latestMemory?.value.total, 16 * 1024 * 1024 * 1024)
        XCTAssertEqual(coordinator.memoryHistory.count, 1)
    }

    // MARK: - RollingGraphView Tests

    func testRollingGraphPointCalculation() {
        let graph = RollingGraphView(
            values: [0.0, 50.0, 100.0],
            minValue: 0.0,
            maxValue: 100.0,
            tintColor: .blue,
            capacity: 3,
            height: 100,
            showGrid: true
        )

        let points = graph.calculatePoints(width: 200, height: 100)
        XCTAssertEqual(points.count, 3)

        // First point (0%) should be near the bottom (height - 2)
        XCTAssertEqual(points[0].x, 0.0, accuracy: 0.1)
        XCTAssertEqual(points[0].y, 98.0, accuracy: 0.1)

        // Middle point (50%) should be in the vertical center
        XCTAssertEqual(points[1].x, 100.0, accuracy: 0.1)
        XCTAssertEqual(points[1].y, 50.0, accuracy: 0.1)

        // Last point (100%) should be near the top (2.0)
        XCTAssertEqual(points[2].x, 200.0, accuracy: 0.1)
        XCTAssertEqual(points[2].y, 2.0, accuracy: 0.1)
    }

    func testRollingGraphEmptyValues() {
        let graph = RollingGraphView(values: [], minValue: 0, maxValue: 100)
        let points = graph.calculatePoints(width: 100, height: 50)
        XCTAssertTrue(points.isEmpty)
    }

    // MARK: - MenuBarController Title & Tooltip Formatting

    func testMenuBarFormatting() {
        let cpu = CPUSample(
            totalUsage: 14.2,
            perCore: [10, 18],
            user: 8,
            system: 6,
            idle: 86
        )
        let mem = MemorySample(
            total: 1000,
            used: 650,
            free: 350,
            wired: 200,
            compressed: 100,
            cached: 150,
            swapUsed: 0,
            pressure: .normal
        )

        // Icon mode
        XCTAssertEqual(MenuBarController.formatTitle(mode: .icon, cpu: cpu, memory: mem), "")

        // CPU mode
        XCTAssertEqual(MenuBarController.formatTitle(mode: .cpu, cpu: cpu, memory: mem), "CPU 14%")
        XCTAssertEqual(MenuBarController.formatTitle(mode: .cpu, cpu: nil, memory: mem), "CPU --%")

        // Memory mode
        XCTAssertEqual(MenuBarController.formatTitle(mode: .memory, cpu: cpu, memory: mem), "RAM 65%")
        XCTAssertEqual(MenuBarController.formatTitle(mode: .memory, cpu: cpu, memory: nil), "RAM --%")

        // Both mode
        XCTAssertEqual(MenuBarController.formatTitle(mode: .both, cpu: cpu, memory: mem), "CPU 14%  RAM 65%")
        XCTAssertEqual(MenuBarController.formatTitle(mode: .both, cpu: nil, memory: mem), "CPU --%  RAM 65%")

        // Tooltip
        let tooltip = MenuBarController.formatToolTip(cpu: cpu, memory: mem)
        XCTAssertTrue(tooltip.contains("CPU: 14.2%"))
        XCTAssertTrue(tooltip.contains("RAM: 65.0% (Normal)"))
    }

    // MARK: - SwiftUI View Instantiation & Hierarchy Tests

    func testCPUSummaryViewRendering() {
        let sample = CPUSample(
            totalUsage: 45.0,
            perCore: [30.0, 40.0, 50.0, 60.0, 20.0, 35.0, 70.0, 55.0],
            user: 30.0,
            system: 15.0,
            idle: 55.0,
            loadAverage: LoadAverage(oneMinute: 2.1, fiveMinute: 1.8, fifteenMinute: 1.5),
            frequencyHz: 3_500_000_000
        )
        let history = [Sample(value: sample, timestamp: Date(), availability: .available)]

        let view = CPUSummaryView(sample: sample, history: history)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        XCTAssertNotNil(hosting)
    }

    func testDetailPopoverViewRendering() {
        let defaults = UserDefaults(suiteName: "iStats.test.popover.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )

        let cpu = CPUSample(totalUsage: 12.0, perCore: [12.0], user: 8.0, system: 4.0, idle: 88.0)
        let mem = MemorySample(total: 8000, used: 4000, free: 4000, wired: 1000, compressed: 500, cached: 1000, swapUsed: 0, pressure: .normal)

        let popover = DetailPopoverView(
            coordinator: coordinator,
            preferences: prefs,
            cpuSample: cpu,
            memorySample: mem,
            cpuHistory: [Sample(value: cpu)],
            memoryHistory: [Sample(value: mem)]
        )

        let hosting = NSHostingView(rootView: popover)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
        XCTAssertNotNil(hosting)
    }
}
