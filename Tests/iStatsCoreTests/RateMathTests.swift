import XCTest
@testable import iStatsCore

final class RateMathTests: XCTestCase {

    // MARK: CPU usage

    func testCPUUsageHalfBusy() {
        XCTAssertEqual(RateMath.cpuUsagePercent(busyDelta: 50, totalDelta: 100), 50, accuracy: 0.0001)
    }

    func testCPUUsageZeroTotalReturnsZero() {
        // First sample / no elapsed ticks must not divide by zero.
        XCTAssertEqual(RateMath.cpuUsagePercent(busyDelta: 0, totalDelta: 0), 0)
        XCTAssertEqual(RateMath.cpuUsagePercent(busyDelta: 10, totalDelta: 0), 0)
    }

    func testCPUUsageClampedToHundred() {
        // Defensive: busy should never exceed total, but clamp if counters glitch.
        XCTAssertEqual(RateMath.cpuUsagePercent(busyDelta: 150, totalDelta: 100), 100)
    }

    func testCPUUsageNeverNegative() {
        XCTAssertEqual(RateMath.cpuUsagePercent(busyDelta: -10, totalDelta: 100), 0)
    }

    func testCPUUsageBoundsProperty() {
        // Property: result is always within 0...100 for arbitrary non-negative inputs.
        for busy in stride(from: 0.0, through: 300.0, by: 17.0) {
            for total in stride(from: 0.0, through: 300.0, by: 13.0) {
                let pct = RateMath.cpuUsagePercent(busyDelta: busy, totalDelta: total)
                XCTAssertGreaterThanOrEqual(pct, 0)
                XCTAssertLessThanOrEqual(pct, 100)
            }
        }
    }

    // MARK: Network rate

    func testBytesPerSecondNormal() {
        // 1000 bytes over 2 seconds = 500 B/s
        XCTAssertEqual(RateMath.bytesPerSecond(previous: 1000, current: 2000, elapsedSeconds: 2), 500, accuracy: 0.0001)
    }

    func testBytesPerSecondCounterResetClampsToZero() {
        // current < previous (interface restarted) -> 0, never negative (Req 6.4)
        XCTAssertEqual(RateMath.bytesPerSecond(previous: 5000, current: 100, elapsedSeconds: 1), 0)
    }

    func testBytesPerSecondZeroElapsedReturnsZero() {
        XCTAssertEqual(RateMath.bytesPerSecond(previous: 0, current: 1000, elapsedSeconds: 0), 0)
    }

    func testBytesPerSecondNeverNegativeProperty() {
        let samples: [UInt64] = [0, 100, 50, 1_000_000, 999_999, 0, UInt64.max, 10]
        for p in samples {
            for c in samples {
                let rate = RateMath.bytesPerSecond(previous: p, current: c, elapsedSeconds: 1)
                XCTAssertGreaterThanOrEqual(rate, 0)
            }
        }
    }
}
