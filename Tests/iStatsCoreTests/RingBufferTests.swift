import XCTest
@testable import iStatsCore

final class RingBufferTests: XCTestCase {

    func testAppendUnderCapacityKeepsOrder() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertFalse(buffer.isFull)
        XCTAssertEqual(buffer.elements, [1, 2, 3])
        XCTAssertEqual(buffer.latest, 3)
    }

    func testAppendAtCapacityEvictsOldest() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        XCTAssertTrue(buffer.isFull)
        buffer.append(4) // evicts 1
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.elements, [2, 3, 4])
        XCTAssertEqual(buffer.latest, 4)
    }

    func testWrapAroundMultipleTimesKeepsChronologicalOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for n in 1...10 { buffer.append(n) }
        // Last three appended: 8, 9, 10
        XCTAssertEqual(buffer.elements, [8, 9, 10])
        XCTAssertEqual(buffer.latest, 10)
        XCTAssertEqual(buffer.count, 3)
    }

    func testEmptyBuffer() {
        let buffer = RingBuffer<Int>(capacity: 4)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertNil(buffer.latest)
        XCTAssertEqual(buffer.elements, [])
    }

    func testCapacityOfOne() {
        var buffer = RingBuffer<String>(capacity: 1)
        buffer.append("a")
        buffer.append("b")
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.elements, ["b"])
        XCTAssertEqual(buffer.latest, "b")
    }
}
