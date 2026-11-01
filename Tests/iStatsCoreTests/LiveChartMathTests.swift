import XCTest
@testable import iStatsCore

final class LiveChartMathTests: XCTestCase {

    // MARK: - Monotone Cubic Spline (Fritsch–Carlson)

    func testSmoothSegmentsMonotonicityNoOvershoot() {
        // Monotonically non-decreasing points
        let points = [
            LiveChartMath.Point2D(x: 0, y: 0),
            LiveChartMath.Point2D(x: 10, y: 0),
            LiveChartMath.Point2D(x: 20, y: 50),
            LiveChartMath.Point2D(x: 30, y: 100),
            LiveChartMath.Point2D(x: 40, y: 100),
            LiveChartMath.Point2D(x: 50, y: 70),
            LiveChartMath.Point2D(x: 60, y: 10)
        ]

        let segments = LiveChartMath.smoothSegments(points: points, tension: 1.0)
        XCTAssertEqual(segments.count, points.count - 1)

        for segment in segments {
            let minY = min(segment.start.y, segment.end.y)
            let maxY = max(segment.start.y, segment.end.y)

            // Test that control points never overshoot outside [minY, maxY]
            XCTAssertGreaterThanOrEqual(segment.control1.y, minY - 1e-6, "Control1 y cannot drop below minY")
            XCTAssertLessThanOrEqual(segment.control1.y, maxY + 1e-6, "Control1 y cannot exceed maxY")

            XCTAssertGreaterThanOrEqual(segment.control2.y, minY - 1e-6, "Control2 y cannot drop below minY")
            XCTAssertLessThanOrEqual(segment.control2.y, maxY + 1e-6, "Control2 y cannot exceed maxY")
        }
    }

    func testSmoothSegmentsFlatLine() {
        let points = [
            LiveChartMath.Point2D(x: 0, y: 42),
            LiveChartMath.Point2D(x: 10, y: 42),
            LiveChartMath.Point2D(x: 20, y: 42)
        ]

        let segments = LiveChartMath.smoothSegments(points: points)
        XCTAssertEqual(segments.count, 2)
        for seg in segments {
            XCTAssertEqual(seg.control1.y, 42.0, accuracy: 1e-6)
            XCTAssertEqual(seg.control2.y, 42.0, accuracy: 1e-6)
        }
    }

    func testSmoothSegmentsDegenerateCounts() {
        XCTAssertEqual(LiveChartMath.smoothSegments(points: []).count, 0)
        XCTAssertEqual(LiveChartMath.smoothSegments(points: [LiveChartMath.Point2D(x: 0, y: 10)]).count, 0)
        let twoPoints = [LiveChartMath.Point2D(x: 0, y: 0), LiveChartMath.Point2D(x: 10, y: 10)]
        XCTAssertEqual(LiveChartMath.smoothSegments(points: twoPoints).count, 1)
    }

    // MARK: - Glide Offset

    func testGlideOffsetClamping() {
        XCTAssertEqual(LiveChartMath.glideOffset(elapsed: 0.0, interval: 1.0), 0.0)
        XCTAssertEqual(LiveChartMath.glideOffset(elapsed: 0.5, interval: 1.0), 0.5)
        XCTAssertEqual(LiveChartMath.glideOffset(elapsed: 1.0, interval: 1.0), 1.0)
        XCTAssertEqual(LiveChartMath.glideOffset(elapsed: 1.5, interval: 1.0), 1.0)
        XCTAssertEqual(LiveChartMath.glideOffset(elapsed: -0.2, interval: 1.0), 0.0)
        XCTAssertEqual(LiveChartMath.glideOffset(elapsed: 0.5, interval: 0.0), 0.0)
    }

    // MARK: - Nice Axis Ticks

    func testNiceTicks125Steps() {
        let ticks100 = LiveChartMath.niceTicks(max: 100, count: 4)
        XCTAssertFalse(ticks100.isEmpty)
        XCTAssertEqual(ticks100.first, 0.0)
        // Step should be 20 or 25
        let step = ticks100[1] - ticks100[0]
        XCTAssertTrue([10.0, 20.0, 25.0, 50.0].contains(step))

        let ticks10 = LiveChartMath.niceTicks(max: 10, count: 5)
        XCTAssertEqual(ticks10.first, 0.0)
        let step10 = ticks10[1] - ticks10[0]
        XCTAssertTrue([1.0, 2.0, 2.5, 5.0].contains(step10))

        XCTAssertEqual(LiveChartMath.niceTicks(max: 0, count: 4), [0.0])
    }

    // MARK: - Peak Index & Stats

    func testPeakIndex() {
        XCTAssertNil(LiveChartMath.peakIndex(values: []))
        XCTAssertEqual(LiveChartMath.peakIndex(values: [10.0]), 0)
        XCTAssertEqual(LiveChartMath.peakIndex(values: [10.0, 45.0, 32.0, 12.0]), 1)
        XCTAssertEqual(LiveChartMath.peakIndex(values: [10.0, 20.0, 50.0, 50.0]), 2) // first occurrence
    }

    func testComputeStatsAndHoverIndex() {
        let values = [10.0, 20.0, 30.0, 40.0]
        let stats = LiveChartMath.computeStats(for: values)
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.min, 10.0)
        XCTAssertEqual(stats?.avg, 25.0)
        XCTAssertEqual(stats?.max, 40.0)
        XCTAssertEqual(stats?.now, 40.0)

        XCTAssertEqual(LiveChartMath.hoverIndex(for: 0, totalWidth: 100, count: 4), 0)
        XCTAssertEqual(LiveChartMath.hoverIndex(for: 50, totalWidth: 100, count: 4), 2)
        XCTAssertEqual(LiveChartMath.hoverIndex(for: 100, totalWidth: 100, count: 4), 3)
    }
}
