import XCTest
import Dispatch
import SwiftUI
import iStatsCore
@testable import iStats

final class MemoryPressureTests: XCTestCase {

    func testMemoryPressurePropertiesAndRanking() {
        XCTAssertEqual(MemoryPressure.normal.displayName, "Normal")
        XCTAssertEqual(MemoryPressure.warning.displayName, "Warning")
        XCTAssertEqual(MemoryPressure.critical.displayName, "Critical")

        XCTAssertFalse(MemoryPressure.normal.isElevated)
        XCTAssertTrue(MemoryPressure.warning.isElevated)
        XCTAssertTrue(MemoryPressure.critical.isElevated)

        XCTAssertEqual(MemoryPressure.normal.severityRank, 0)
        XCTAssertEqual(MemoryPressure.warning.severityRank, 1)
        XCTAssertEqual(MemoryPressure.critical.severityRank, 2)

        XCTAssertTrue(MemoryPressure.normal < MemoryPressure.warning)
        XCTAssertTrue(MemoryPressure.warning < MemoryPressure.critical)
        XCTAssertTrue(MemoryPressure.normal < MemoryPressure.critical)
        XCTAssertFalse(MemoryPressure.critical < MemoryPressure.warning)
    }

    func testDispatchSourceMemoryPressureEventMapping() {
        let normalMapped = MemoryPressureMonitor.mapEvent(.normal)
        XCTAssertEqual(normalMapped, .normal)

        let warningMapped = MemoryPressureMonitor.mapEvent(.warning)
        XCTAssertEqual(warningMapped, .warning)

        let criticalMapped = MemoryPressureMonitor.mapEvent(.critical)
        XCTAssertEqual(criticalMapped, .critical)

        let combined = MemoryPressureMonitor.mapEvent([.warning, .critical])
        XCTAssertEqual(combined, .critical)
    }

    final class ThreadSafeCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [MemoryPressure] = []

        func append(_ item: MemoryPressure) {
            lock.lock()
            defer { lock.unlock() }
            items.append(item)
        }

        var values: [MemoryPressure] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    func testMemoryPressureMonitorUpdatesAndListeners() {
        let monitor = MemoryPressureMonitor(startImmediately: false)
        XCTAssertEqual(monitor.currentPressure, .normal)

        let collector = ThreadSafeCollector()
        let exp = expectation(description: "Listener called on pressure changes")
        exp.expectedFulfillmentCount = 3 // initial + 2 updates

        monitor.addListener { pressure in
            collector.append(pressure)
            exp.fulfill()
        }

        monitor.updatePressure(.warning)
        XCTAssertEqual(monitor.currentPressure, .warning)

        monitor.updatePressure(.critical)
        XCTAssertEqual(monitor.currentPressure, .critical)

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(collector.values, [.normal, .warning, .critical])
    }

    func testMemoryPressureMonitorStartStopIdempotency() {
        let monitor = MemoryPressureMonitor(startImmediately: false)
        monitor.start()
        monitor.start() // idempotent
        XCTAssertEqual(monitor.currentPressure, .normal)
        monitor.stop()
        monitor.stop() // idempotent
    }

    @MainActor
    func testMemoryPressureUIViewsRendering() {
        let normalBadge = MemoryPressureBadgeView(pressure: .normal)
        let warningBadge = MemoryPressureBadgeView(pressure: .warning)
        let criticalBadge = MemoryPressureBadgeView(pressure: .critical)

        XCTAssertNotNil(normalBadge.body)
        XCTAssertNotNil(warningBadge.body)
        XCTAssertNotNil(criticalBadge.body)

        let normalBanner = MemoryPressureAlertBanner(pressure: .normal)
        let warningBanner = MemoryPressureAlertBanner(pressure: .warning)
        let criticalBanner = MemoryPressureAlertBanner(pressure: .critical)

        XCTAssertNotNil(normalBanner.body)
        XCTAssertNotNil(warningBanner.body)
        XCTAssertNotNil(criticalBanner.body)

        let sample = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 12 * 1024 * 1024 * 1024,
            free: 4 * 1024 * 1024 * 1024,
            wired: 3 * 1024 * 1024 * 1024,
            compressed: 1 * 1024 * 1024 * 1024,
            cached: 2 * 1024 * 1024 * 1024,
            swapUsed: 0,
            pressure: .critical
        )

        let memorySummary = MemorySummaryView(sample: sample)
        XCTAssertNotNil(memorySummary.body)

        let detailPopover = DetailPopoverView(memorySample: sample)
        XCTAssertNotNil(detailPopover.body)
    }
}
