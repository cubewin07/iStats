import XCTest
@testable import iStatsCore

final class InstrumentGeometryTests: XCTestCase {

    // MARK: - SegmentLayout Tests

    func testSegmentLayoutEmptyAndZeroTotal() {
        XCTAssertEqual(SegmentLayout.widths(values: [], totalWidth: 100), [])
        XCTAssertEqual(SegmentLayout.widths(values: [10, 20], totalWidth: 0), [])
        XCTAssertEqual(SegmentLayout.widths(values: [0, 0, 0], totalWidth: 100), [0.0, 0.0, 0.0])
    }

    func testSegmentLayoutTotalWidthPreservedWithGaps() {
        let values = [40.0, 30.0, 30.0]
        let totalWidth = 200.0
        let gap = 2.0
        let widths = SegmentLayout.widths(values: values, totalWidth: totalWidth, minVisible: 4.0, gap: gap)

        XCTAssertEqual(widths.count, 3)
        let totalGaps = Double(values.count - 1) * gap
        let sumWidths = widths.reduce(0.0, +)
        XCTAssertEqual(sumWidths + totalGaps, totalWidth, accuracy: 1e-4)
    }

    func testSegmentLayoutMinVisibleGuaranteeForTinySegments() {
        let values = [99.9, 0.1]
        let totalWidth = 100.0
        let minVisible = 6.0
        let widths = SegmentLayout.widths(values: values, totalWidth: totalWidth, minVisible: minVisible, gap: 1.0)

        XCTAssertEqual(widths.count, 2)
        XCTAssertGreaterThanOrEqual(widths[1], minVisible - 1e-4, "Tiny segment must receive minimum visible width")
        let totalGaps = 1.0
        XCTAssertEqual(widths.reduce(0.0, +) + totalGaps, totalWidth, accuracy: 1e-4)
    }

    func testSegmentLayoutZeroValuesDoNotReceiveMinVisible() {
        let values = [50.0, 0.0, 50.0]
        let widths = SegmentLayout.widths(values: values, totalWidth: 100.0, minVisible: 5.0, gap: 2.0)
        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(widths[1], 0.0, "Zero value segment should remain 0")
        XCTAssertGreaterThan(widths[0], 0)
        XCTAssertGreaterThan(widths[2], 0)
    }

    // MARK: - GaugeMath Tests

    func testGaugeMathAngleClampingAndFraction() {
        let range = 0.0...100.0
        let sweep = 200.0
        let start = -100.0

        // Minimum boundary
        XCTAssertEqual(GaugeMath.angle(value: 0.0, range: range, sweep: sweep, startAngle: start), -100.0)
        // Midpoint
        XCTAssertEqual(GaugeMath.angle(value: 50.0, range: range, sweep: sweep, startAngle: start), 0.0)
        // Maximum boundary
        XCTAssertEqual(GaugeMath.angle(value: 100.0, range: range, sweep: sweep, startAngle: start), 100.0)

        // Below minimum clamps to start
        XCTAssertEqual(GaugeMath.angle(value: -20.0, range: range, sweep: sweep, startAngle: start), -100.0)
        // Above maximum clamps to start + sweep
        XCTAssertEqual(GaugeMath.angle(value: 150.0, range: range, sweep: sweep, startAngle: start), 100.0)
    }

    func testGaugeMathDegenerateRange() {
        let degenerate = 50.0...50.0
        XCTAssertEqual(GaugeMath.angle(value: 50.0, range: degenerate, sweep: 180.0, startAngle: 0.0), 0.0)
    }
}

