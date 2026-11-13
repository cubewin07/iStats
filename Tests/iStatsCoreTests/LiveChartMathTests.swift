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

    // MARK: - ChartTimeline (Task 8.5.1 / A1, A5, A7, B7)

    func testChartTimelineTargetEdge() {
        let timeline = ChartTimeline(sampleInterval: 1.0)
        XCTAssertEqual(timeline.targetEdge(now: 100.5, latestTimestamp: 100.0), 99.5, accuracy: 1e-9)
        XCTAssertEqual(timeline.targetEdge(now: 102.0, latestTimestamp: 100.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(timeline.targetEdge(now: 100.0, latestTimestamp: 100.0), 99.0, accuracy: 1e-9)
    }

    func testChartTimelineLateSampleArrivalNeverMovesBackward() {
        var timeline = ChartTimeline(edge: 99.0, sampleInterval: 1.0)
        var latestTimestamp = 100.0
        var previousEdge = timeline.edge

        // Advance at 60 fps up to 101.050 (sample #2 arrives 50 ms late)
        var now = 100.0
        let dt = 1.0 / 60.0
        for _ in 0..<63 {
            now += dt
            let newEdge = timeline.step(now: now, latestTimestamp: latestTimestamp, dt: dt, isScrubbing: false)
            XCTAssertGreaterThanOrEqual(newEdge, previousEdge - 1e-12, "Edge must never move backward on late sample")
            previousEdge = newEdge
        }
        // Edge paused smoothly at latestTimestamp (100.0) while waiting for late sample
        XCTAssertEqual(timeline.edge, 100.0, accuracy: 1e-6)

        // Late sample arrives at now = 101.050 + dt
        now += dt
        latestTimestamp = now
        let afterLate = timeline.step(now: now, latestTimestamp: latestTimestamp, dt: dt, isScrubbing: false)
        XCTAssertGreaterThanOrEqual(afterLate, previousEdge - 1e-12)
        XCTAssertLessThanOrEqual(afterLate - previousEdge, dt + 1e-9)
    }

    func testChartTimelineFlatSeriesAdvancesByTimestamp() {
        // B7: flat values (e.g., 0.0) still advance smoothly via wall-clock timestamps
        var timeline = ChartTimeline(edge: 99.0, sampleInterval: 1.0)
        let points = [
            ChartPoint(timestamp: 98.0, value: 0.0),
            ChartPoint(timestamp: 99.0, value: 0.0),
            ChartPoint(timestamp: 100.0, value: 0.0)
        ]

        let edgeMid = timeline.step(now: 100.5, latestTimestamp: points.last!.timestamp, dt: 0.5, isScrubbing: false)
        XCTAssertEqual(edgeMid, 99.5, accuracy: 1e-6)

        let edgeEnd = timeline.step(now: 101.0, latestTimestamp: points.last!.timestamp, dt: 0.5, isScrubbing: false)
        XCTAssertEqual(edgeEnd, 100.0, accuracy: 1e-6)
        XCTAssertEqual(timeline.valueAtEdge(points: points), 0.0)
    }

    func testChartTimelineWakeFromSleepSnapsCleanly() {
        var timeline = ChartTimeline(edge: 100.0, sampleInterval: 1.0)
        // Wake from sleep 120 seconds later (> 3 * sampleInterval)
        let snapped = timeline.step(now: 221.0, latestTimestamp: 221.0, dt: 0.016, isScrubbing: false)
        XCTAssertEqual(snapped, 220.0, accuracy: 1e-9)
    }

    func testChartTimelinePartialBufferXPositionNoStretch() {
        // 15 samples at 1 Hz (t = 1...15) in a 60 s window; edge at 15.0
        let timeline = ChartTimeline(edge: 15.0, sampleInterval: 1.0)
        let width = 300.0
        let window = 60.0

        let firstX = timeline.xPosition(for: 0.0, width: width, window: window)
        let lastX = timeline.xPosition(for: 15.0, width: width, window: window)

        XCTAssertEqual(firstX, 225.0, accuracy: 1e-6)
        XCTAssertEqual(lastX, 300.0, accuracy: 1e-6)
        XCTAssertEqual((lastX - firstX) / width, 0.25, accuracy: 1e-6)
    }

    func testChartTimelineHoverFreezeAndEaseOutCatchUp() {
        var timeline = ChartTimeline(edge: 99.0, sampleInterval: 1.0)

        // Start scrubbing: edge freezes at 99.0 across 1.5 s of new samples
        let frozen1 = timeline.step(now: 100.5, latestTimestamp: 100.5, dt: 0.5, isScrubbing: true)
        let frozen2 = timeline.step(now: 101.5, latestTimestamp: 101.5, dt: 1.0, isScrubbing: true)
        XCTAssertEqual(frozen1, 99.0, accuracy: 1e-9)
        XCTAssertEqual(frozen2, 99.0, accuracy: 1e-9)
        XCTAssertEqual(timeline.frozenEdge, 99.0)

        // Release scrub (gap is 1.5 s <= 3.0 s): eases out over 250 ms
        let releaseMid = timeline.step(now: 101.625, latestTimestamp: 101.625, dt: 0.125, isScrubbing: false)
        XCTAssertNil(timeline.frozenEdge)
        XCTAssertGreaterThan(releaseMid, 99.0)
        XCTAssertLessThan(releaseMid, 100.625)

        let releaseDone = timeline.step(now: 101.75, latestTimestamp: 101.75, dt: 0.125, isScrubbing: false)
        XCTAssertEqual(releaseDone, 100.75, accuracy: 1e-6)
    }

    func testChartTimelineHoverReleaseSnapsAfterLongScrub() {
        var timeline = ChartTimeline(edge: 99.0, sampleInterval: 1.0)
        _ = timeline.step(now: 100.0, latestTimestamp: 100.0, dt: 0.016, isScrubbing: true)
        // Long scrub > 3 * sampleInterval
        let snapped = timeline.step(now: 106.0, latestTimestamp: 106.0, dt: 0.016, isScrubbing: false)
        XCTAssertNil(timeline.frozenEdge)
        XCTAssertEqual(snapped, 105.0, accuracy: 1e-9)
    }

    func testChartTimelineValueAtEdgeFollowsMonotoneSpline() {
        let points = [
            ChartPoint(timestamp: 10.0, value: 0.0),
            ChartPoint(timestamp: 11.0, value: 20.0),
            ChartPoint(timestamp: 12.0, value: 80.0),
            ChartPoint(timestamp: 13.0, value: 80.0),
            ChartPoint(timestamp: 14.0, value: 40.0)
        ]

        // At exact sample timestamp
        let tlExact = ChartTimeline(edge: 12.0, sampleInterval: 1.0)
        XCTAssertEqual(tlExact.valueAtEdge(points: points) ?? -1, 80.0, accuracy: 1e-6)

        // Mid-segment between 11.0 (20.0) and 12.0 (80.0)
        let tlMid = ChartTimeline(edge: 11.5, sampleInterval: 1.0)
        let midVal = tlMid.valueAtEdge(points: points)
        XCTAssertNotNil(midVal)
        XCTAssertGreaterThan(midVal ?? 0.0, 20.0)
        XCTAssertLessThan(midVal ?? 100.0, 80.0)

        // Verify exact match against smoothSegments evaluation at midpoint u = 0.5
        let pts2D = points.map { LiveChartMath.Point2D(x: $0.timestamp, y: $0.value) }
        let seg = LiveChartMath.smoothSegments(points: pts2D)[1] // [11.0, 12.0]
        let expected = 0.125 * seg.start.y + 0.375 * seg.control1.y + 0.375 * seg.control2.y + 0.125 * seg.end.y
        XCTAssertEqual(midVal ?? -1, expected, accuracy: 1e-9)

        // Degenerate / boundary counts
        XCTAssertNil(tlExact.valueAtEdge(points: []))
        XCTAssertEqual(tlExact.valueAtEdge(points: [ChartPoint(timestamp: 5.0, value: 42.0)]), 42.0)
        let tlBefore = ChartTimeline(edge: 5.0, sampleInterval: 1.0)
        XCTAssertEqual(tlBefore.valueAtEdge(points: points), 0.0)
        let tlAfter = ChartTimeline(edge: 20.0, sampleInterval: 1.0)
        XCTAssertEqual(tlAfter.valueAtEdge(points: points), 40.0)
    }

    // MARK: - ChartScale & ChartScaleState (Task 8.5.1 / A4, A9)

    func testChartScaleNiceCeilingLadder() {
        // maxVal = 25 -> rawSpan = 27.5 -> roughStep = 9.167 -> step = 10 -> ceiling = 30
        let scale30 = ChartScale.niceCeiling(for: 25.0)
        XCTAssertEqual(scale30.floor, 0.0)
        XCTAssertEqual(scale30.ceiling, 30.0, accuracy: 1e-9)
        XCTAssertEqual(scale30.ticks, [0.0, 10.0, 20.0, 30.0])

        // Verify 2.5 step on ladder: maxVal = 6 -> rawSpan = 6.6 -> roughStep = 2.2 -> step = 2.5 -> ceiling = 7.5
        let scale75 = ChartScale.niceCeiling(for: 6.0)
        XCTAssertEqual(scale75.ceiling, 7.5, accuracy: 1e-9)
        XCTAssertEqual(scale75.ticks, [0.0, 2.5, 5.0, 7.5])

        // Non-zero floor (e.g., Thermal 40...65 -> rawSpan = 27.5 -> step = 10 -> ceiling = 70)
        let thermalScale = ChartScale.niceCeiling(for: 65.0, floorVal: 40.0)
        XCTAssertEqual(thermalScale.floor, 40.0)
        XCTAssertEqual(thermalScale.ceiling, 70.0, accuracy: 1e-9)
        XCTAssertEqual(thermalScale.ticks, [40.0, 50.0, 60.0, 70.0])

        // minSpan guard when maxVal == 0
        let zeroScale = ChartScale.niceCeiling(for: 0.0, floorVal: 0.0, minSpan: 3.0)
        XCTAssertEqual(zeroScale.ceiling, 3.0, accuracy: 1e-9)
        XCTAssertEqual(zeroScale.ticks, [0.0, 1.0, 2.0, 3.0])
    }

    func testChartScaleDomainFloors() {
        XCTAssertEqual(ChartScale.domainFloor(for: .thermal, visibleMin: 48.0, fixedFloor: nil), 40.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .thermal, visibleMin: 45.0, fixedFloor: nil), 40.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .thermal, visibleMin: 44.0, fixedFloor: nil), 30.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .thermal, visibleMin: 22.0, fixedFloor: nil), 20.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .thermal, visibleMin: 10.0, fixedFloor: nil), 20.0)

        XCTAssertEqual(ChartScale.domainFloor(for: .fan, visibleMin: 1800.0, fixedFloor: 1200.0), 1200.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .fan, visibleMin: 1800.0, fixedFloor: nil), 0.0)

        XCTAssertEqual(ChartScale.domainFloor(for: .cpu, visibleMin: 35.0, fixedFloor: nil), 0.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .memory, visibleMin: 55.0, fixedFloor: nil), 0.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .gpu, visibleMin: 10.0, fixedFloor: nil), 0.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .network, visibleMin: 500.0, fixedFloor: nil), 0.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .disk, visibleMin: 500.0, fixedFloor: nil), 0.0)
        XCTAssertEqual(ChartScale.domainFloor(for: .power, visibleMin: 12.0, fixedFloor: nil), 0.0)
    }

    func testChartScaleStateUpwardSpringAndDownwardHysteresis() {
        var scale = ChartScaleState(initialFloor: 0.0, initialCeiling: 10.0)

        // 1. Immediate upward expansion (10 -> 100) with 0.35 s critically damped spring
        scale.step(targetCeiling: 100.0, dt: 0.175)
        XCTAssertGreaterThan(scale.displayedCeiling, 50.0)
        XCTAssertLessThan(scale.displayedCeiling, 100.0)

        scale.step(targetCeiling: 100.0, dt: 0.175) // total 0.35 s
        XCTAssertGreaterThan(scale.displayedCeiling, 98.0)
        XCTAssertLessThanOrEqual(scale.displayedCeiling, 100.0)

        // Finish settling
        scale.step(targetCeiling: 100.0, dt: 1.0)
        XCTAssertEqual(scale.displayedCeiling, 100.0, accuracy: 1e-6)

        // 2. Mild drop to 75 (>= 70% of 100): must NOT contract even after 5 s
        for _ in 0..<50 {
            scale.step(targetCeiling: 75.0, dt: 0.1)
        }
        XCTAssertEqual(scale.displayedCeiling, 100.0, accuracy: 1e-6)
        XCTAssertEqual(scale.belowThresholdDuration, 0.0, accuracy: 1e-9)

        // 3. Drop to 40 (< 70%) for 2.0 s, then recover to 80: hold timer resets, ceiling stays 100
        scale.step(targetCeiling: 40.0, dt: 2.0)
        XCTAssertEqual(scale.displayedCeiling, 100.0, accuracy: 1e-6)
        XCTAssertEqual(scale.belowThresholdDuration, 2.0, accuracy: 1e-9)

        scale.step(targetCeiling: 80.0, dt: 0.1)
        XCTAssertEqual(scale.belowThresholdDuration, 0.0, accuracy: 1e-9)
        XCTAssertEqual(scale.displayedCeiling, 100.0, accuracy: 1e-6)

        // 4. Sustained drop to 40 for 3.0 s hold, then 0.60 s ease-out contraction
        for _ in 0..<29 {
            scale.step(targetCeiling: 40.0, dt: 0.1) // 2.9 s
            XCTAssertEqual(scale.displayedCeiling, 100.0, accuracy: 1e-6)
        }
        scale.step(targetCeiling: 40.0, dt: 0.1) // crosses 3.0 s
        XCTAssertTrue(scale.isContracting)

        scale.step(targetCeiling: 40.0, dt: 0.30)
        XCTAssertLessThan(scale.displayedCeiling, 100.0)
        XCTAssertGreaterThan(scale.displayedCeiling, 40.0)

        scale.step(targetCeiling: 40.0, dt: 0.30) // finishes 0.60 s contraction
        XCTAssertEqual(scale.displayedCeiling, 40.0, accuracy: 1e-6)
        XCTAssertFalse(scale.isContracting)
    }

    func testChartScaleStateUpdateByCategory() {
        var cpuScale = ChartScaleState()
        let cpuBounds = cpuScale.update(visibleMax: 23.0, visibleMin: 5.0, category: .cpu, dt: 0.016)
        XCTAssertEqual(cpuBounds.floor, 0.0)
        XCTAssertEqual(cpuBounds.ceiling, 100.0)

        var thermalScale = ChartScaleState()
        let thermalBounds = thermalScale.update(visibleMax: 65.0, visibleMin: 48.0, category: .thermal, dt: 0.016)
        XCTAssertEqual(thermalBounds.floor, 40.0)
        XCTAssertEqual(thermalBounds.ceiling, 70.0)
    }
}

