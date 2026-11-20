import XCTest
@testable import iStatsCore

final class DownsamplerTests: XCTestCase {

    func testAlignedBucketsEpochGroupingAndStats() {
        // bucketWidth = 2.5 s -> [1000.0, 1002.5) = bucket 400, [1002.5, 1005.0) = bucket 401
        let points = [
            ScalarPoint(timestamp: Date(timeIntervalSince1970: 1000.2), value: 10.0),
            ScalarPoint(timestamp: Date(timeIntervalSince1970: 1001.2), value: 30.0),
            ScalarPoint(timestamp: Date(timeIntervalSince1970: 1002.2), value: 20.0),
            ScalarPoint(timestamp: Date(timeIntervalSince1970: 1003.2), value: 50.0)
        ]

        let buckets = Downsampler.alignedBuckets(points, bucketWidth: 2.5, windowDuration: 300.0)
        XCTAssertEqual(buckets.count, 2)

        XCTAssertEqual(buckets[0].timestamp, 400.5 * 2.5, accuracy: 1e-6)
        XCTAssertEqual(buckets[0].min, 10.0, accuracy: 1e-9)
        XCTAssertEqual(buckets[0].max, 30.0, accuracy: 1e-9)
        XCTAssertEqual(buckets[0].mean, 20.0, accuracy: 1e-9)

        XCTAssertEqual(buckets[1].timestamp, 401.5 * 2.5, accuracy: 1e-6)
        XCTAssertEqual(buckets[1].min, 50.0, accuracy: 1e-9)
        XCTAssertEqual(buckets[1].max, 50.0, accuracy: 1e-9)
        XCTAssertEqual(buckets[1].mean, 50.0, accuracy: 1e-9)
    }

    func testAlignedBucketsPreservesClosedHistoricalBucketsOnAppend() {
        // Simulate 1 Hz sampling across a 5m (2.5 s buckets) and 15m (7.5 s buckets) window.
        for (bucketWidth, window) in [(2.5, 300.0), (7.5, 900.0)] {
            var points: [ScalarPoint] = []
            for i in 0..<240 {
                let t = 1_700_000_000.0 + Double(i)
                let val = Double((i * 17) % 100)
                points.append(ScalarPoint(timestamp: Date(timeIntervalSince1970: t), value: val))
            }

            var previousBuckets = Downsampler.alignedBuckets(points, bucketWidth: bucketWidth, windowDuration: window)

            // Append 20 additional 1 Hz samples one by one; every bucket prior to the active
            // epoch bucket must stay identical (zero bucket-boundary boiling, A6).
            for offset in 240..<260 {
                let t = 1_700_000_000.0 + Double(offset)
                let val = Double((offset * 29) % 100)
                points.append(ScalarPoint(timestamp: Date(timeIntervalSince1970: t), value: val))

                let currentBuckets = Downsampler.alignedBuckets(points, bucketWidth: bucketWidth, windowDuration: window)
                let activeBucketCenter = (floor(t / bucketWidth) + 0.5) * bucketWidth

                // Check every closed bucket that existed in previousBuckets and is strictly before activeBucketCenter
                let closedPrevious = previousBuckets.filter { $0.timestamp < activeBucketCenter - 1e-6 }
                for prev in closedPrevious {
                    let matching = currentBuckets.first(where: { abs($0.timestamp - prev.timestamp) < 1e-6 })
                    XCTAssertEqual(matching, prev, "Closed historical bucket at \(prev.timestamp) mutated on append")
                }

                previousBuckets = currentBuckets
            }
        }
    }

    func testAlignedBucketsWindowCutoffDropsWholeBucketsWithoutMutation() {
        // Window = 10 s, bucketWidth = 2.5 s -> buckets are [0, 2.5), [2.5, 5), [5, 7.5), [7.5, 10), [10, 12.5)
        var points = (0...10).map { i in
            ScalarPoint(timestamp: Date(timeIntervalSince1970: Double(i)), value: Double(i * 10))
        }

        let initial = Downsampler.alignedBuckets(points, bucketWidth: 2.5, windowDuration: 10.0)
        XCTAssertEqual(initial.count, 5) // bucketEnd 2.5 > 0.0

        // Append t = 11 -> cutoff = 1.0 -> bucket 0 (bucketEnd = 2.5 > 1.0) stays intact!
        points.append(ScalarPoint(timestamp: Date(timeIntervalSince1970: 11.0), value: 110.0))
        let at11 = Downsampler.alignedBuckets(points, bucketWidth: 2.5, windowDuration: 10.0)
        XCTAssertEqual(at11[0], initial[0])
        XCTAssertEqual(at11[1], initial[1])

        // Append t = 13 -> cutoff = 3.0 -> bucket 0 (bucketEnd = 2.5 <= 3.0) drops cleanly; bucket 1 intact!
        points.append(ScalarPoint(timestamp: Date(timeIntervalSince1970: 13.0), value: 130.0))
        let at13 = Downsampler.alignedBuckets(points, bucketWidth: 2.5, windowDuration: 10.0)
        XCTAssertEqual(at13.first, initial[1])
        XCTAssertEqual(at13[1], initial[2])
    }

    func testAlignedBucketsEdgeCases() {
        XCTAssertEqual(Downsampler.alignedBuckets([], bucketWidth: 2.5, windowDuration: 300.0), [])

        let sample = [ScalarPoint(timestamp: Date(timeIntervalSince1970: 100.0), value: 42.0)]
        XCTAssertEqual(Downsampler.alignedBuckets(sample, bucketWidth: 0.0, windowDuration: 300.0), [])
        XCTAssertEqual(Downsampler.alignedBuckets(sample, bucketWidth: 2.5, windowDuration: -1.0), [])

        // Unsorted + non-finite points
        let messy = [
            ScalarPoint(timestamp: Date(timeIntervalSince1970: 104.0), value: 20.0),
            ScalarPoint(timestamp: Date(timeIntervalSince1970: 101.0), value: .nan),
            ScalarPoint(timestamp: Date(timeIntervalSince1970: 101.0), value: 10.0)
        ]
        let buckets = Downsampler.alignedBuckets(messy, bucketWidth: 2.5, windowDuration: 300.0)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertLessThan(buckets[0].timestamp, buckets[1].timestamp)
        XCTAssertEqual(buckets[0].mean, 10.0)
        XCTAssertEqual(buckets[1].mean, 20.0)
    }
}
