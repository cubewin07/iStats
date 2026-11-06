import XCTest
@testable import iStats
@testable import iStatsCore

final class ProcessSamplerTests: XCTestCase {

    func testProcessSamplerLiveSampling() {
        let sampler = ProcessSampler()
        // First sample establishes previous CPU times
        let firstSample = sampler.sample()
        XCTAssertNotNil(firstSample)

        // Small busy loop or sleep to accrue measurable time
        usleep(100_000) // 100 ms

        // Second sample computes delta CPU percentage
        let secondSample = sampler.sample()
        XCTAssertFalse(secondSample.topMemory.isEmpty, "Top memory processes should not be empty")

        for item in secondSample.topCPU {
            XCTAssertGreaterThan(item.pid, 0)
            XCTAssertFalse(item.name.isEmpty)
            XCTAssertGreaterThanOrEqual(item.cpuPercent, 0.0)
        }

        for item in secondSample.topMemory {
            XCTAssertGreaterThan(item.pid, 0)
            XCTAssertFalse(item.name.isEmpty)
            XCTAssertGreaterThan(item.memoryBytes, 0)
        }
    }

    @MainActor
    func testCoordinatorProcessDemandManagement() {
        let coordinator = MetricsCoordinator.shared

        coordinator.startProcessDemand()
        coordinator.startProcessDemand()
        // Active demand is running

        coordinator.stopProcessDemand()
        coordinator.stopProcessDemand()
        // Should be stopped cleanly
    }
}

