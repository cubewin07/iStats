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
        // Property: result is always within 0...100 for arbitrary inputs including negatives, zeros, and large values.
        let values: [Double] = [-1000.0, -1.0, 0.0, 0.5, 1.0, 10.0, 50.0, 99.9, 100.0, 100.1, 500.0, 1_000_000.0]
        for busy in values {
            for total in values {
                let pct = RateMath.cpuUsagePercent(busyDelta: busy, totalDelta: total)
                XCTAssertGreaterThanOrEqual(pct, 0.0, "CPU percent must be >= 0 for busy=\(busy), total=\(total)")
                XCTAssertLessThanOrEqual(pct, 100.0, "CPU percent must be <= 100 for busy=\(busy), total=\(total)")
            }
        }
    }

    func testCPUUsageMonotonicityProperty() {
        // Property: for any fixed total > 0, increasing busy delta produces non-decreasing percentage.
        let total = 1000.0
        var previousPct = 0.0
        for busy in stride(from: 0.0, through: total, by: 12.5) {
            let pct = RateMath.cpuUsagePercent(busyDelta: busy, totalDelta: total)
            XCTAssertGreaterThanOrEqual(pct, previousPct, "CPU percentage must be monotonic non-decreasing")
            previousPct = pct
        }
    }

    func testCPUUsageAdditivityProperty() {
        // Property: cpuUsagePercent(a + b, total) == cpuUsagePercent(a, total) + cpuUsagePercent(b, total)
        // when a + b <= total and total > 0.
        let total = 2500.0
        for a in stride(from: 0.0, through: 1000.0, by: 125.0) {
            for b in stride(from: 0.0, through: 1000.0, by: 125.0) {
                let combinedPct = RateMath.cpuUsagePercent(busyDelta: a + b, totalDelta: total)
                let sumOfPcts = RateMath.cpuUsagePercent(busyDelta: a, totalDelta: total)
                    + RateMath.cpuUsagePercent(busyDelta: b, totalDelta: total)
                XCTAssertEqual(combinedPct, sumOfPcts, accuracy: 1e-9, "Additivity violated for a=\(a), b=\(b)")
            }
        }
    }

    func testCPUUsagePartitionOfUnityProperty() {
        // Property: for any busy + idle == total (total > 0), busy% + idle% == 100%
        let total = 800.0
        for busy in stride(from: 0.0, through: total, by: 37.0) {
            let idle = total - busy
            let busyPct = RateMath.cpuUsagePercent(busyDelta: busy, totalDelta: total)
            let idlePct = RateMath.cpuUsagePercent(busyDelta: idle, totalDelta: total)
            XCTAssertEqual(busyPct + idlePct, 100.0, accuracy: 1e-9, "Partition of unity violated for busy=\(busy)")
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

    // MARK: Counter Delta

    func testCounterDeltaNormal() {
        XCTAssertEqual(RateMath.counterDelta(previous: 100, current: 250), 150)
    }

    func testCounterDeltaResetOrWrapReturnsZero() {
        // Counter wrapped or restarted (current < previous)
        XCTAssertEqual(RateMath.counterDelta(previous: 500, current: 200), 0)
    }

    func testCounterDeltaEqualReturnsZero() {
        XCTAssertEqual(RateMath.counterDelta(previous: 500, current: 500), 0)
    }

    func testCounterDeltaMonotonicityProperty() {
        // Property: when current >= previous, delta == current - previous >= 0.
        // When current < previous, delta == 0.
        let values: [UInt64] = [0, 1, 100, 500, 10_000, 1_000_000, UInt64.max - 100, UInt64.max]
        for prev in values {
            for curr in values {
                let delta = RateMath.counterDelta(previous: prev, current: curr)
                if curr >= prev {
                    XCTAssertEqual(delta, curr - prev)
                } else {
                    XCTAssertEqual(delta, 0)
                }
            }
        }
    }

    func testCounterDeltaExtremeValuesNearUInt64Max() {
        let maxVal = UInt64.max
        XCTAssertEqual(RateMath.counterDelta(previous: maxVal - 100, current: maxVal), 100)
        XCTAssertEqual(RateMath.counterDelta(previous: maxVal, current: maxVal), 0)
        XCTAssertEqual(RateMath.counterDelta(previous: maxVal, current: 0), 0) // Wrapped
        XCTAssertEqual(RateMath.counterDelta(previous: maxVal, current: maxVal - 1), 0) // Decreased
    }
}
