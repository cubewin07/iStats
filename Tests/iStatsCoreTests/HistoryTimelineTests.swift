import XCTest
@testable import iStatsCore

final class HistoryTimelineTests: XCTestCase {
    func testChronologicalBoundedHistoryAndTimeRange() {
        let base = Date(timeIntervalSince1970: 1000)
        let points = [4, 1, 3, 2].map { HistoryPoint(timestamp: base.addingTimeInterval(Double($0)), value: Double($0)) }
        let timeline = HistoryTimeline(points: points, capacity: 3, expectedInterval: 1)
        XCTAssertEqual(timeline.points.compactMap(\.value), [2, 3, 4])
        XCTAssertEqual(timeline.timeRange?.lowerBound, base.addingTimeInterval(2))
        XCTAssertEqual(timeline.timeRange?.upperBound, base.addingTimeInterval(4))
    }

    func testGapsAndUnavailableValuesSplitSegmentsWithoutZeroes() {
        let base = Date(timeIntervalSince1970: 0)
        let points = [
            HistoryPoint(timestamp: base, value: 0),
            HistoryPoint(timestamp: base.addingTimeInterval(1), value: nil),
            HistoryPoint(timestamp: base.addingTimeInterval(2), value: 42),
            HistoryPoint(timestamp: base.addingTimeInterval(10), value: 60),
            HistoryPoint(timestamp: base.addingTimeInterval(11), value: .nan)
        ]
        let timeline = HistoryTimeline(points: points, expectedInterval: 1)
        XCTAssertEqual(timeline.segments.map(\.count), [1, 1, 1])
        XCTAssertEqual(timeline.segments.flatMap { $0 }.compactMap(\.value), [0, 42, 60])
    }

    func testEmptyAndSingleSample() {
        XCTAssertNil(HistoryTimeline(points: [], expectedInterval: 1).timeRange)
        let date = Date(timeIntervalSince1970: 123)
        let timeline = HistoryTimeline(points: [HistoryPoint(timestamp: date, value: 4)], expectedInterval: 1)
        XCTAssertEqual(timeline.timeRange, date...date)
        XCTAssertEqual(timeline.segments.count, 1)
    }
}
