import XCTest
import iStatsCore
@testable import iStats

/// Mock network info provider for deterministic testing.
private final class MockNetworkInfoProvider: NetworkInfoProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [[RawInterfaceCounters]] = []
    private var shouldThrow: Error?

    init(responses: [[RawInterfaceCounters]] = [], shouldThrow: Error? = nil) {
        self.responses = responses
        self.shouldThrow = shouldThrow
    }

    func setResponses(_ responses: [[RawInterfaceCounters]]) {
        lock.lock()
        self.responses = responses
        self.shouldThrow = nil
        lock.unlock()
    }

    func setShouldThrow(_ error: Error) {
        lock.lock()
        self.shouldThrow = error
        lock.unlock()
    }

    func interfaceCounters() throws -> [RawInterfaceCounters] {
        lock.lock()
        defer { lock.unlock() }

        if let error = shouldThrow {
            throw error
        }

        if !responses.isEmpty {
            return responses.removeFirst()
        }

        return []
    }
}

final class NetworkSamplerTests: XCTestCase {

    // MARK: - Category & Cold Start

    func testNetworkSamplerCategory() {
        let sampler = NetworkSampler(provider: MockNetworkInfoProvider())
        XCTAssertEqual(sampler.category, .network)
    }

    func testFirstSampleReturnsZeroThroughputAndInitialTotals() throws {
        let initialCounters = [
            RawInterfaceCounters(name: "en0", bytesIn: 10_000, bytesOut: 20_000),
            RawInterfaceCounters(name: "en1", bytesIn: 5_000, bytesOut: 15_000)
        ]
        let provider = MockNetworkInfoProvider(responses: [initialCounters])
        let sampler = NetworkSampler(provider: provider)

        let sample = try sampler.sample()

        XCTAssertEqual(sample.interfaces.count, 2)
        XCTAssertEqual(sample.totalBytesInPerSec, 0.0)
        XCTAssertEqual(sample.totalBytesOutPerSec, 0.0)
        XCTAssertEqual(sample.totalBytesIn, 0)
        XCTAssertEqual(sample.totalBytesOut, 0)

        for iface in sample.interfaces {
            XCTAssertEqual(iface.bytesInPerSec, 0.0)
            XCTAssertEqual(iface.bytesOutPerSec, 0.0)
            XCTAssertEqual(iface.totalBytesIn, 0)
            XCTAssertEqual(iface.totalBytesOut, 0)
        }
    }

    // MARK: - Multi-Interface Throughput & Session Totals

    func testSecondSampleCalculatesRatesAndSessionTotals() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let t1 = Date(timeIntervalSince1970: 1002.0) // 2.0 seconds later

        let sample0Counters = [
            RawInterfaceCounters(name: "en0", bytesIn: 10_000, bytesOut: 20_000),
            RawInterfaceCounters(name: "en1", bytesIn: 5_000, bytesOut: 15_000)
        ]

        let (firstSample, prevStates, sessionTotals) = NetworkSampler.calculateSample(
            previous: nil,
            current: sample0Counters,
            currentTimestamp: t0,
            sessionTotals: nil
        )

        XCTAssertEqual(firstSample.totalBytesInPerSec, 0.0)
        XCTAssertEqual(firstSample.totalBytesOutPerSec, 0.0)

        // Sample 1: en0 received 2,000 bytes (1,000 B/s), sent 4,000 bytes (2,000 B/s)
        //           en1 received 1,000 bytes (500 B/s), sent 3,000 bytes (1,500 B/s)
        let sample1Counters = [
            RawInterfaceCounters(name: "en0", bytesIn: 12_000, bytesOut: 24_000),
            RawInterfaceCounters(name: "en1", bytesIn: 6_000, bytesOut: 18_000)
        ]

        let (secondSample, newPrevStates, newSessionTotals) = NetworkSampler.calculateSample(
            previous: prevStates,
            current: sample1Counters,
            currentTimestamp: t1,
            sessionTotals: sessionTotals
        )

        XCTAssertEqual(secondSample.interfaces.count, 2)

        let en0 = secondSample.interfaces.first(where: { $0.interfaceName == "en0" })
        XCTAssertNotNil(en0)
        XCTAssertEqual(en0?.bytesInPerSec ?? 0, 1000.0, accuracy: 0.001)
        XCTAssertEqual(en0?.bytesOutPerSec ?? 0, 2000.0, accuracy: 0.001)
        XCTAssertEqual(en0?.totalBytesIn, 2000)
        XCTAssertEqual(en0?.totalBytesOut, 4000)

        let en1 = secondSample.interfaces.first(where: { $0.interfaceName == "en1" })
        XCTAssertNotNil(en1)
        XCTAssertEqual(en1?.bytesInPerSec ?? 0, 500.0, accuracy: 0.001)
        XCTAssertEqual(en1?.bytesOutPerSec ?? 0, 1500.0, accuracy: 0.001)
        XCTAssertEqual(en1?.totalBytesIn, 1000)
        XCTAssertEqual(en1?.totalBytesOut, 3000)

        // Aggregates across interfaces
        XCTAssertEqual(secondSample.totalBytesInPerSec, 1500.0, accuracy: 0.001)
        XCTAssertEqual(secondSample.totalBytesOutPerSec, 3500.0, accuracy: 0.001)
        XCTAssertEqual(secondSample.totalBytesIn, 3000)
        XCTAssertEqual(secondSample.totalBytesOut, 7000)

        // Sample 2: another second later
        let t2 = Date(timeIntervalSince1970: 1003.0)
        let sample2Counters = [
            RawInterfaceCounters(name: "en0", bytesIn: 13_000, bytesOut: 25_000),
            RawInterfaceCounters(name: "en1", bytesIn: 6_500, bytesOut: 19_000)
        ]

        let (thirdSample, _, finalTotals) = NetworkSampler.calculateSample(
            previous: newPrevStates,
            current: sample2Counters,
            currentTimestamp: t2,
            sessionTotals: newSessionTotals
        )

        let en0_s2 = thirdSample.interfaces.first(where: { $0.interfaceName == "en0" })
        XCTAssertEqual(en0_s2?.totalBytesIn, 3000)
        XCTAssertEqual(en0_s2?.totalBytesOut, 5000)
        XCTAssertEqual(thirdSample.totalBytesIn, 4500)
        XCTAssertEqual(thirdSample.totalBytesOut, 9000)
    }

    // MARK: - Counter Reset & Interface Restart Handling

    func testCounterResetClampsDeltaToZeroAndPreservesSessionTotals() {
        let t0 = Date(timeIntervalSince1970: 100.0)
        let t1 = Date(timeIntervalSince1970: 101.0)
        let t2 = Date(timeIntervalSince1970: 102.0)

        // Initial sample
        let initial = [RawInterfaceCounters(name: "en0", bytesIn: 50_000, bytesOut: 50_000)]
        let (_, prev0, totals0) = NetworkSampler.calculateSample(
            previous: nil,
            current: initial,
            currentTimestamp: t0,
            sessionTotals: nil
        )

        // Normal second sample (+10,000 bytes)
        let normal = [RawInterfaceCounters(name: "en0", bytesIn: 60_000, bytesOut: 60_000)]
        let (sample1, prev1, totals1) = NetworkSampler.calculateSample(
            previous: prev0,
            current: normal,
            currentTimestamp: t1,
            sessionTotals: totals0
        )

        XCTAssertEqual(sample1.interfaces.first?.bytesInPerSec ?? 0, 10_000.0, accuracy: 0.001)
        XCTAssertEqual(sample1.interfaces.first?.totalBytesIn, 10_000)

        // Interface resets/restarts: counter drops to 1,000
        let reset = [RawInterfaceCounters(name: "en0", bytesIn: 1_000, bytesOut: 500)]
        let (sample2, prev2, totals2) = NetworkSampler.calculateSample(
            previous: prev1,
            current: reset,
            currentTimestamp: t2,
            sessionTotals: totals1
        )

        let ifaceReset = sample2.interfaces.first
        XCTAssertEqual(ifaceReset?.bytesInPerSec, 0.0, "Rate must clamp to 0 on reset without negative spike")
        XCTAssertEqual(ifaceReset?.bytesOutPerSec, 0.0, "Rate must clamp to 0 on reset without negative spike")
        XCTAssertEqual(ifaceReset?.totalBytesIn, 10_000, "Session totals must not drop on counter reset")
        XCTAssertEqual(ifaceReset?.totalBytesOut, 10_000, "Session totals must not drop on counter reset")

        // Subsequent sample after reset: +500 bytes
        let t3 = Date(timeIntervalSince1970: 103.0)
        let nextSample = [RawInterfaceCounters(name: "en0", bytesIn: 1_500, bytesOut: 800)]
        let (sample3, _, _) = NetworkSampler.calculateSample(
            previous: prev2,
            current: nextSample,
            currentTimestamp: t3,
            sessionTotals: totals2
        )

        let ifaceNext = sample3.interfaces.first
        XCTAssertEqual(ifaceNext?.bytesInPerSec ?? 0, 500.0, accuracy: 0.001)
        XCTAssertEqual(ifaceNext?.bytesOutPerSec ?? 0, 300.0, accuracy: 0.001)
        XCTAssertEqual(ifaceNext?.totalBytesIn, 10_500, "Session totals must continue accumulating smoothly")
        XCTAssertEqual(ifaceNext?.totalBytesOut, 10_300, "Session totals must continue accumulating smoothly")
    }

    // MARK: - Interface Churn & Dynamic Discovery

    func testDynamicInterfaceAdditionAndDisappearance() {
        let t0 = Date(timeIntervalSince1970: 500.0)
        let t1 = Date(timeIntervalSince1970: 501.0)

        // Sample 0: only en0
        let c0 = [RawInterfaceCounters(name: "en0", bytesIn: 1000, bytesOut: 1000)]
        let (_, prev0, totals0) = NetworkSampler.calculateSample(
            previous: nil,
            current: c0,
            currentTimestamp: t0,
            sessionTotals: nil
        )

        // Sample 1: en0 updated, and new interface utun0 appears
        let c1 = [
            RawInterfaceCounters(name: "en0", bytesIn: 1500, bytesOut: 1200),
            RawInterfaceCounters(name: "utun0", bytesIn: 8000, bytesOut: 4000)
        ]
        let (sample1, prev1, totals1) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c1,
            currentTimestamp: t1,
            sessionTotals: totals0
        )

        XCTAssertEqual(sample1.interfaces.count, 2)
        let en0 = sample1.interfaces.first(where: { $0.interfaceName == "en0" })
        XCTAssertEqual(en0?.bytesInPerSec ?? 0, 500.0, accuracy: 0.001)
        XCTAssertEqual(en0?.totalBytesIn, 500)

        let utun0 = sample1.interfaces.first(where: { $0.interfaceName == "utun0" })
        XCTAssertEqual(utun0?.bytesInPerSec, 0.0, "Newly appeared interface starts at 0 B/s")
        XCTAssertEqual(utun0?.totalBytesIn, 0, "Newly appeared interface starts at 0 session total")

        // Sample 2: en0 disappears (e.g. WiFi turned off), utun0 remains
        let t2 = Date(timeIntervalSince1970: 502.0)
        let c2 = [RawInterfaceCounters(name: "utun0", bytesIn: 9000, bytesOut: 4500)]
        let (sample2, _, _) = NetworkSampler.calculateSample(
            previous: prev1,
            current: c2,
            currentTimestamp: t2,
            sessionTotals: totals1
        )

        XCTAssertEqual(sample2.interfaces.count, 1)
        let utun0_s2 = sample2.interfaces.first(where: { $0.interfaceName == "utun0" })
        XCTAssertEqual(utun0_s2?.bytesInPerSec ?? 0, 1000.0, accuracy: 0.001)
        XCTAssertEqual(utun0_s2?.totalBytesIn, 1000)
    }

    // MARK: - Loopback Filtering

    func testLoopbackFiltering() {
        let counters = [
            RawInterfaceCounters(name: "en0", bytesIn: 1000, bytesOut: 1000, isLoopback: false),
            RawInterfaceCounters(name: "lo0", bytesIn: 50_000, bytesOut: 50_000, isLoopback: true)
        ]

        let (filteredSample, _, _) = NetworkSampler.calculateSample(
            previous: nil,
            current: counters,
            currentTimestamp: Date(),
            sessionTotals: nil,
            includeLoopback: false
        )
        XCTAssertEqual(filteredSample.interfaces.count, 1)
        XCTAssertEqual(filteredSample.interfaces.first?.interfaceName, "en0")

        let (unfilteredSample, _, _) = NetworkSampler.calculateSample(
            previous: nil,
            current: counters,
            currentTimestamp: Date(),
            sessionTotals: nil,
            includeLoopback: true
        )
        XCTAssertEqual(unfilteredSample.interfaces.count, 2)
        XCTAssertTrue(unfilteredSample.interfaces.contains(where: { $0.interfaceName == "lo0" }))
    }

    // MARK: - Error Handling

    func testSamplerThrowsWhenProviderFails() {
        let provider = MockNetworkInfoProvider(shouldThrow: SamplerError.systemCallFailed("sysctl error"))
        let sampler = NetworkSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample()) { error in
            guard case SamplerError.systemCallFailed(let msg) = error else {
                XCTFail("Expected SamplerError.systemCallFailed but got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("sysctl error"))
        }
    }

    // MARK: - Live Host Provider

    func testLiveHostNetworkInfoProviderAndSampler() throws {
        let provider = HostNetworkInfoProvider()
        let counters = try provider.interfaceCounters()
        XCTAssertFalse(counters.isEmpty, "Host should have at least one network interface")

        let sampler = NetworkSampler(provider: provider)
        let sample1 = try sampler.sample()
        XCTAssertEqual(sampler.category, .network)

        // Wait a tiny interval and sample again
        Thread.sleep(forTimeInterval: 0.05)

        let sample2 = try sampler.sample()
        XCTAssertGreaterThanOrEqual(sample2.totalBytesInPerSec, 0.0)
        XCTAssertGreaterThanOrEqual(sample2.totalBytesOutPerSec, 0.0)
        XCTAssertGreaterThanOrEqual(sample2.totalBytesIn, 0)
        XCTAssertGreaterThanOrEqual(sample2.totalBytesOut, 0)
    }

    // MARK: - Property & Invariant Tests (Task 3.2)

    func testSessionTotalsMonotonicityUnderRandomCounterResets() {
        var prevStates: [String: InterfaceState]? = nil
        var sessionTotals: [String: InterfaceSessionTotal]? = nil

        var currentIn: [String: UInt64] = ["en0": 1000, "en1": 2000, "utun0": 500]
        var currentOut: [String: UInt64] = ["en0": 2000, "en1": 4000, "utun0": 1000]

        var previousTotalSessionIn: UInt64 = 0
        var previousTotalSessionOut: UInt64 = 0
        var prevIfaceSessionIn: [String: UInt64] = ["en0": 0, "en1": 0, "utun0": 0]
        var prevIfaceSessionOut: [String: UInt64] = ["en0": 0, "en1": 0, "utun0": 0]

        var seed: UInt64 = 0x123456789ABCDEF
        func nextRandom() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed
        }

        var currentTime = Date(timeIntervalSince1970: 10_000.0)

        for step in 0..<100 {
            let elapsed = Double(nextRandom() % 10 + 1) * 0.5 // 0.5 to 5.0 seconds
            currentTime = currentTime.addingTimeInterval(elapsed)

            var resetOccurred: [String: Bool] = [:]

            for name in ["en0", "en1", "utun0"] {
                let shouldReset = (nextRandom() % 10 == 0) && (currentIn[name] ?? 0) > 100
                resetOccurred[name] = shouldReset

                if shouldReset {
                    // True counter reset / restart: counter drops to a fraction of previous
                    currentIn[name] = (currentIn[name] ?? 0) / 4
                    currentOut[name] = (currentOut[name] ?? 0) / 4
                } else {
                    // Normal delta
                    let deltaIn = nextRandom() % 50_000
                    let deltaOut = nextRandom() % 50_000
                    currentIn[name] = (currentIn[name] ?? 0) &+ deltaIn
                    currentOut[name] = (currentOut[name] ?? 0) &+ deltaOut
                }
            }

            let counters = ["en0", "en1", "utun0"].map {
                RawInterfaceCounters(name: $0, bytesIn: currentIn[$0]!, bytesOut: currentOut[$0]!)
            }

            let (sample, newPrev, newTotals) = NetworkSampler.calculateSample(
                previous: prevStates,
                current: counters,
                currentTimestamp: currentTime,
                sessionTotals: sessionTotals
            )

            prevStates = newPrev
            sessionTotals = newTotals

            // Invariant 1: Aggregate session totals are monotonic non-decreasing
            XCTAssertGreaterThanOrEqual(
                sample.totalBytesIn,
                previousTotalSessionIn,
                "Step \(step): Total session bytes in must never decrease"
            )
            XCTAssertGreaterThanOrEqual(
                sample.totalBytesOut,
                previousTotalSessionOut,
                "Step \(step): Total session bytes out must never decrease"
            )
            previousTotalSessionIn = sample.totalBytesIn
            previousTotalSessionOut = sample.totalBytesOut

            // Invariant 2: Per-interface session totals are monotonic non-decreasing
            for iface in sample.interfaces {
                let name = iface.interfaceName
                XCTAssertGreaterThanOrEqual(
                    iface.totalBytesIn,
                    prevIfaceSessionIn[name] ?? 0,
                    "Step \(step): Interface \(name) session in must never decrease"
                )
                XCTAssertGreaterThanOrEqual(
                    iface.totalBytesOut,
                    prevIfaceSessionOut[name] ?? 0,
                    "Step \(step): Interface \(name) session out must never decrease"
                )
                prevIfaceSessionIn[name] = iface.totalBytesIn
                prevIfaceSessionOut[name] = iface.totalBytesOut

                // Invariant 3: Rate is never negative
                XCTAssertGreaterThanOrEqual(iface.bytesInPerSec, 0.0)
                XCTAssertGreaterThanOrEqual(iface.bytesOutPerSec, 0.0)

                // Invariant 4: Reset step yields 0 rate
                if step > 0 && resetOccurred[name] == true {
                    XCTAssertEqual(iface.bytesInPerSec, 0.0, "Step \(step): Rate must be 0 on reset for \(name)")
                    XCTAssertEqual(iface.bytesOutPerSec, 0.0, "Step \(step): Rate must be 0 on reset for \(name)")
                }
            }
        }
    }

    func testZeroOrNegativeTimeStepYieldsZeroRate() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let tSame = Date(timeIntervalSince1970: 1000.0) // 0 elapsed
        let tBackward = Date(timeIntervalSince1970: 999.0) // -1.0 elapsed

        let c0 = [RawInterfaceCounters(name: "en0", bytesIn: 1000, bytesOut: 1000)]
        let (_, prev0, totals0) = NetworkSampler.calculateSample(
            previous: nil,
            current: c0,
            currentTimestamp: t0,
            sessionTotals: nil
        )

        let c1 = [RawInterfaceCounters(name: "en0", bytesIn: 5000, bytesOut: 5000)]
        let (sampleZero, _, _) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c1,
            currentTimestamp: tSame,
            sessionTotals: totals0
        )
        XCTAssertEqual(sampleZero.interfaces.first?.bytesInPerSec, 0.0)
        XCTAssertEqual(sampleZero.interfaces.first?.bytesOutPerSec, 0.0)

        let (sampleBackward, _, _) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c1,
            currentTimestamp: tBackward,
            sessionTotals: totals0
        )
        XCTAssertEqual(sampleBackward.interfaces.first?.bytesInPerSec, 0.0)
        XCTAssertEqual(sampleBackward.interfaces.first?.bytesOutPerSec, 0.0)
    }

    func testExtremeCountersNearUInt64Max() {
        let t0 = Date(timeIntervalSince1970: 100.0)
        let t1 = Date(timeIntervalSince1970: 101.0)
        let maxVal = UInt64.max

        let c0 = [RawInterfaceCounters(name: "en0", bytesIn: maxVal - 5000, bytesOut: maxVal - 10000)]
        let (_, prev0, totals0) = NetworkSampler.calculateSample(
            previous: nil,
            current: c0,
            currentTimestamp: t0,
            sessionTotals: nil
        )

        let c1 = [RawInterfaceCounters(name: "en0", bytesIn: maxVal, bytesOut: maxVal)]
        let (sample1, _, totals1) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c1,
            currentTimestamp: t1,
            sessionTotals: totals0
        )

        let en0 = sample1.interfaces.first
        XCTAssertEqual(en0?.bytesInPerSec ?? 0, 5000.0, accuracy: 0.001)
        XCTAssertEqual(en0?.bytesOutPerSec ?? 0, 10000.0, accuracy: 0.001)
        XCTAssertEqual(en0?.totalBytesIn, 5000)
        XCTAssertEqual(en0?.totalBytesOut, 10000)

        // Now wrap around to 100
        let t2 = Date(timeIntervalSince1970: 102.0)
        let c2 = [RawInterfaceCounters(name: "en0", bytesIn: 100, bytesOut: 100)]
        let (sample2, _, totals2) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c2,
            currentTimestamp: t2,
            sessionTotals: totals1
        )

        let en0_wrap = sample2.interfaces.first
        XCTAssertEqual(en0_wrap?.bytesInPerSec, 0.0, "Wrap around clamps delta to 0")
        XCTAssertEqual(en0_wrap?.bytesOutPerSec, 0.0, "Wrap around clamps delta to 0")
        XCTAssertEqual(totals2["en0"]?.bytesIn, 5000)
        XCTAssertEqual(totals2["en0"]?.bytesOut, 10000)
    }
}
