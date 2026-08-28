import XCTest
import iStatsCore
@testable import iStats

final class CPUSamplerTests: XCTestCase {

    final class MockCPUInfoProvider: CPUInfoProvider, @unchecked Sendable {
        private var responses: [[ProcessorTicks]]
        private var index = 0
        private let mockLoadAverage: LoadAverage?
        private let mockFrequencyHz: UInt64?
        private let mockTopology: (efficiencyCount: Int, performanceCount: Int)?
        private let lock = NSLock()

        init(
            responses: [[ProcessorTicks]],
            loadAverage: LoadAverage? = nil,
            cpuFrequencyHz: UInt64? = nil,
            topology: (efficiencyCount: Int, performanceCount: Int)? = nil
        ) {
            self.responses = responses
            self.mockLoadAverage = loadAverage
            self.mockFrequencyHz = cpuFrequencyHz
            self.mockTopology = topology
        }

        func processorTicks() throws -> [ProcessorTicks] {
            lock.lock()
            defer { lock.unlock() }
            guard index < responses.count else {
                return responses.last ?? []
            }
            let res = responses[index]
            index += 1
            return res
        }

        func loadAverage() throws -> LoadAverage? {
            mockLoadAverage
        }

        func cpuFrequencyHz() throws -> UInt64? {
            mockFrequencyHz
        }

        func cpuTopology() throws -> (efficiencyCount: Int, performanceCount: Int)? {
            mockTopology
        }
    }

    struct FailingCPUInfoProvider: CPUInfoProvider {
        func processorTicks() throws -> [ProcessorTicks] {
            throw SamplerError.systemCallFailed("Mach host_processor_info kernel error")
        }
    }

    func testFirstSampleReturnsZeroUtilization() throws {
        let core0 = ProcessorTicks(user: 1000, system: 500, idle: 8500, nice: 0)
        let core1 = ProcessorTicks(user: 2000, system: 1000, idle: 7000, nice: 0)

        let mockLoad = LoadAverage(oneMinute: 1.8, fiveMinute: 2.1, fifteenMinute: 2.5)
        let provider = MockCPUInfoProvider(
            responses: [[core0, core1]],
            loadAverage: mockLoad,
            cpuFrequencyHz: 2_600_000_000
        )
        let sampler = CPUSampler(provider: provider)

        let sample = try sampler.sample()

        XCTAssertEqual(sample.totalUsage, 0.0)
        XCTAssertEqual(sample.perCore, [0.0, 0.0])
        XCTAssertEqual(sample.user, 0.0)
        XCTAssertEqual(sample.system, 0.0)
        XCTAssertEqual(sample.idle, 0.0)
        XCTAssertEqual(sample.loadAverage, mockLoad)
        XCTAssertEqual(sample.frequencyHz, 2_600_000_000)
    }

    func testSecondSampleCalculatesCorrectRate() throws {
        let t1Core0 = ProcessorTicks(user: 100, system: 50, idle: 850, nice: 0)
        let t1Core1 = ProcessorTicks(user: 1000, system: 200, idle: 800, nice: 0)

        // Core 0: uDelta=100, sDelta=50, iDelta=850, nDelta=0 -> busy=150, total=1000 (15%)
        // Core 1: uDelta=500, sDelta=100, iDelta=400, nDelta=0 -> busy=600, total=1000 (60%)
        // Total: user=600, sys=150, idle=1250, total=2000 -> totalUsage=37.5%, user=30%, sys=7.5%, idle=62.5%
        let t2Core0 = ProcessorTicks(user: 200, system: 100, idle: 1700, nice: 0)
        let t2Core1 = ProcessorTicks(user: 1500, system: 300, idle: 1200, nice: 0)

        let mockLoad = LoadAverage(oneMinute: 2.4, fiveMinute: 2.0, fifteenMinute: 1.8)
        let provider = MockCPUInfoProvider(
            responses: [[t1Core0, t1Core1], [t2Core0, t2Core1]],
            loadAverage: mockLoad,
            cpuFrequencyHz: nil
        )
        let sampler = CPUSampler(provider: provider)

        _ = try sampler.sample() // sample 1 (baseline)
        let sample2 = try sampler.sample() // sample 2 (rate calculation)

        XCTAssertEqual(sample2.totalUsage, 37.5, accuracy: 0.0001)
        XCTAssertEqual(sample2.perCore.count, 2)
        XCTAssertEqual(sample2.perCore[0], 15.0, accuracy: 0.0001)
        XCTAssertEqual(sample2.perCore[1], 60.0, accuracy: 0.0001)
        XCTAssertEqual(sample2.user, 30.0, accuracy: 0.0001)
        XCTAssertEqual(sample2.system, 7.5, accuracy: 0.0001)
        XCTAssertEqual(sample2.idle, 62.5, accuracy: 0.0001)
        XCTAssertEqual(sample2.loadAverage, mockLoad)
        XCTAssertNil(sample2.frequencyHz)
    }

    func testCounterWrapHandlesCleanlyWithoutNegativeSpikes() throws {
        let t1 = ProcessorTicks(user: 5000, system: 3000, idle: 20000, nice: 0)
        // Counter wraps/resets to smaller values
        let t2 = ProcessorTicks(user: 100, system: 50, idle: 200, nice: 0)

        let provider = MockCPUInfoProvider(responses: [[t1], [t2]])
        let sampler = CPUSampler(provider: provider)

        _ = try sampler.sample()
        let sample2 = try sampler.sample()

        XCTAssertEqual(sample2.totalUsage, 0.0)
        XCTAssertEqual(sample2.perCore, [0.0])
        XCTAssertEqual(sample2.user, 0.0)
        XCTAssertEqual(sample2.system, 0.0)
        XCTAssertEqual(sample2.idle, 0.0)
    }

    func testCoreTopologyChangeResetsGracefully() throws {
        let t1 = [ProcessorTicks(user: 100, system: 50, idle: 850, nice: 0)]
        let t2 = [
            ProcessorTicks(user: 200, system: 100, idle: 1700, nice: 0),
            ProcessorTicks(user: 300, system: 150, idle: 1550, nice: 0)
        ]

        let provider = MockCPUInfoProvider(responses: [t1, t2])
        let sampler = CPUSampler(provider: provider)

        _ = try sampler.sample()
        let sample2 = try sampler.sample()

        // Mismatched core count treated safely as new baseline
        XCTAssertEqual(sample2.totalUsage, 0.0)
        XCTAssertEqual(sample2.perCore, [0.0, 0.0])
    }

    func testSamplerThrowsWhenProviderFails() {
        let sampler = CPUSampler(provider: FailingCPUInfoProvider())
        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError but got \(error)")
                return
            }
            if case .systemCallFailed(let reason) = samplerError {
                XCTAssertTrue(reason.contains("Mach host_processor_info kernel error"))
            } else {
                XCTFail("Expected systemCallFailed but got \(samplerError)")
            }
        }
    }

    func testLiveHostProcessorInfoProvider() throws {
        let provider = HostProcessorInfoProvider()
        let ticks = try provider.processorTicks()

        XCTAssertFalse(ticks.isEmpty, "Host should have at least one CPU core")
        for tick in ticks {
            let total = tick.user + tick.system + tick.idle + tick.nice
            XCTAssertGreaterThan(total, 0, "Core ticks should be greater than 0")
        }

        // Test live load average retrieval
        let load = try provider.loadAverage()
        XCTAssertNotNil(load, "Host load average should be available via sysctl vm.loadavg")
        if let load {
            XCTAssertGreaterThanOrEqual(load.oneMinute, 0.0)
            XCTAssertGreaterThanOrEqual(load.fiveMinute, 0.0)
            XCTAssertGreaterThanOrEqual(load.fifteenMinute, 0.0)
        }

        // Test CPU frequency retrieval (non-negative on Intel, nil on Apple Silicon)
        let frequency = try provider.cpuFrequencyHz()
        if let freq = frequency {
            XCTAssertGreaterThan(freq, 0, "CPU frequency in Hz should be positive")
        }

        let sampler = CPUSampler(provider: provider)
        let sample1 = try sampler.sample()
        XCTAssertEqual(sample1.totalUsage, 0.0)
        XCTAssertEqual(sample1.perCore.count, ticks.count)
        XCTAssertNotNil(sample1.loadAverage)

        Thread.sleep(forTimeInterval: 0.1)

        let sample2 = try sampler.sample()
        XCTAssertGreaterThanOrEqual(sample2.totalUsage, 0.0)
        XCTAssertLessThanOrEqual(sample2.totalUsage, 100.0)
        XCTAssertEqual(sample2.perCore.count, ticks.count)
        for corePct in sample2.perCore {
            XCTAssertGreaterThanOrEqual(corePct, 0.0)
            XCTAssertLessThanOrEqual(corePct, 100.0)
        }

        let sum = sample2.user + sample2.system + sample2.idle
        // If ticks elapsed, user + system + idle reconciles to ~100%
        if sample2.totalUsage > 0 {
            XCTAssertEqual(sum, 100.0, accuracy: 0.5)
        }

        // Test live CPU topology retrieval
        let topology = try provider.cpuTopology()
        if let (eCount, pCount) = topology {
            XCTAssertGreaterThanOrEqual(eCount, 0)
            XCTAssertGreaterThanOrEqual(pCount, 0)
            XCTAssertEqual(eCount + pCount, ticks.count)
            XCTAssertEqual(sample2.efficiencyCoreCount, eCount)
            XCTAssertEqual(sample2.performanceCoreCount, pCount)
            if eCount > 0 {
                XCTAssertNotNil(sample2.efficiencyUsage)
            }
            if pCount > 0 {
                XCTAssertNotNil(sample2.performanceUsage)
            }
        }
    }

    func testCPUSamplerTopologyDetectionAndClusterUsage() throws {
        // 4 cores total: 2 E-cores (C0, C1) + 2 P-cores (C2, C3)
        // t1: all 0
        let t1 = [
            ProcessorTicks(user: 0, system: 0, idle: 0, nice: 0),
            ProcessorTicks(user: 0, system: 0, idle: 0, nice: 0),
            ProcessorTicks(user: 0, system: 0, idle: 0, nice: 0),
            ProcessorTicks(user: 0, system: 0, idle: 0, nice: 0)
        ]
        // t2:
        // C0 (E): user=200, system=0, idle=800 -> 20%
        // C1 (E): user=400, system=0, idle=600 -> 40%
        // E-cores avg = (20 + 40) / 2 = 30%
        // C2 (P): user=600, system=0, idle=400 -> 60%
        // C3 (P): user=800, system=0, idle=200 -> 80%
        // P-cores avg = (60 + 80) / 2 = 70%
        let t2 = [
            ProcessorTicks(user: 200, system: 0, idle: 800, nice: 0),
            ProcessorTicks(user: 400, system: 0, idle: 600, nice: 0),
            ProcessorTicks(user: 600, system: 0, idle: 400, nice: 0),
            ProcessorTicks(user: 800, system: 0, idle: 200, nice: 0)
        ]

        let mockProvider = MockCPUInfoProvider(
            responses: [t1, t2],
            topology: (efficiencyCount: 2, performanceCount: 2)
        )
        let sampler = CPUSampler(provider: mockProvider)

        _ = try sampler.sample()
        let sample = try sampler.sample()

        XCTAssertEqual(sample.efficiencyCoreCount, 2)
        XCTAssertEqual(sample.performanceCoreCount, 2)
        XCTAssertEqual(sample.efficiencyUsage!, 30.0, accuracy: 1e-5)
        XCTAssertEqual(sample.performanceUsage!, 70.0, accuracy: 1e-5)
        XCTAssertEqual(sample.coreType(at: 0), .efficiency)
        XCTAssertEqual(sample.coreType(at: 1), .efficiency)
        XCTAssertEqual(sample.coreType(at: 2), .performance)
        XCTAssertEqual(sample.coreType(at: 3), .performance)
    }

    // MARK: - Property-Based Tests for CPU % Math (Task 2.3)

    func testPropertyBoundsInvariantAcrossSyntheticScenarios() {
        // Property: totalUsage, perCore, user, system, idle are ALWAYS in 0...100
        let coreCounts = [1, 2, 4, 8, 16]
        let deltas: [(u: UInt64, s: UInt64, i: UInt64, n: UInt64)] = [
            (0, 0, 1000, 0),       // 100% idle
            (1000, 0, 0, 0),       // 100% user
            (0, 1000, 0, 0),       // 100% system
            (0, 0, 0, 1000),       // 100% nice
            (250, 250, 250, 250),  // 75% busy (25% u, 25% s, 25% n, 25% i)
            (1, 1, 998, 0),        // 0.2% busy
            (0, 0, 0, 0),          // 0 elapsed ticks
            (10_000, 5_000, 85_000, 0) // 15% busy
        ]

        for cores in coreCounts {
            for delta in deltas {
                let prev = (0..<cores).map { idx in
                    ProcessorTicks(user: 1000 * UInt64(idx + 1), system: 500, idle: 5000, nice: 100)
                }
                let curr = (0..<cores).map { idx in
                    ProcessorTicks(
                        user: prev[idx].user + delta.u,
                        system: prev[idx].system + delta.s,
                        idle: prev[idx].idle + delta.i,
                        nice: prev[idx].nice + delta.n
                    )
                }

                let sample = CPUSampler.calculateSample(previous: prev, current: curr)

                XCTAssertGreaterThanOrEqual(sample.totalUsage, 0.0)
                XCTAssertLessThanOrEqual(sample.totalUsage, 100.0)
                XCTAssertEqual(sample.perCore.count, cores)

                for (cIdx, corePct) in sample.perCore.enumerated() {
                    XCTAssertGreaterThanOrEqual(corePct, 0.0, "Core \(cIdx) percentage < 0")
                    XCTAssertLessThanOrEqual(corePct, 100.0, "Core \(cIdx) percentage > 100")
                }

                XCTAssertGreaterThanOrEqual(sample.user, 0.0)
                XCTAssertLessThanOrEqual(sample.user, 100.0)
                XCTAssertGreaterThanOrEqual(sample.system, 0.0)
                XCTAssertLessThanOrEqual(sample.system, 100.0)
                XCTAssertGreaterThanOrEqual(sample.idle, 0.0)
                XCTAssertLessThanOrEqual(sample.idle, 100.0)
            }
        }
    }

    func testPropertyReconciliationInvariant() {
        // Property: when totalDelta > 0, user% + system% + idle% == 100.0 (within rounding tolerance)
        // and user% + system% == totalUsage (since user includes nice)
        let testCases: [(u: UInt64, s: UInt64, i: UInt64, n: UInt64)] = [
            (100, 50, 850, 0),
            (333, 333, 334, 0),
            (1, 2, 3, 4),
            (9999, 1, 0, 0),
            (0, 0, 10000, 0),
            (5000, 2000, 2000, 1000),
            (12345, 67890, 54321, 11111)
        ]

        for tc in testCases {
            let prev = [
                ProcessorTicks(user: 1000, system: 1000, idle: 1000, nice: 1000),
                ProcessorTicks(user: 2000, system: 2000, idle: 2000, nice: 2000)
            ]
            let curr = [
                ProcessorTicks(user: prev[0].user + tc.u, system: prev[0].system + tc.s, idle: prev[0].idle + tc.i, nice: prev[0].nice + tc.n),
                ProcessorTicks(user: prev[1].user + tc.u * 2, system: prev[1].system + tc.s * 2, idle: prev[1].idle + tc.i * 2, nice: prev[1].nice + tc.n * 2)
            ]

            let sample = CPUSampler.calculateSample(previous: prev, current: curr)
            let sum = sample.user + sample.system + sample.idle

            XCTAssertEqual(sum, 100.0, accuracy: 1e-5, "Partition of unity failed for tc=\(tc)")
            XCTAssertEqual(sample.user + sample.system, sample.totalUsage, accuracy: 1e-5, "user+system did not match totalUsage")
        }
    }

    func testPropertyZeroElapsedTicksProducesZeroUtilization() {
        // Property: when counters do not change, all metrics safely report 0.0%
        let prev = [
            ProcessorTicks(user: 500, system: 200, idle: 10000, nice: 50),
            ProcessorTicks(user: 800, system: 300, idle: 12000, nice: 60)
        ]
        let curr = prev // Identical snapshot

        let sample = CPUSampler.calculateSample(previous: prev, current: curr)

        XCTAssertEqual(sample.totalUsage, 0.0)
        XCTAssertEqual(sample.perCore, [0.0, 0.0])
        XCTAssertEqual(sample.user, 0.0)
        XCTAssertEqual(sample.system, 0.0)
        XCTAssertEqual(sample.idle, 0.0)
    }

    func testPropertyMonotonicity() {
        // Property: increasing busy delta for a constant total delta produces non-decreasing utilization
        let total: UInt64 = 10_000
        var previousUsage = 0.0

        for busy in stride(from: UInt64(0), through: total, by: 500) {
            let idle = total - busy
            let prev = [ProcessorTicks(user: 1000, system: 1000, idle: 1000, nice: 0)]
            let curr = [ProcessorTicks(user: 1000 + busy, system: 1000, idle: 1000 + idle, nice: 0)]

            let sample = CPUSampler.calculateSample(previous: prev, current: curr)

            XCTAssertGreaterThanOrEqual(sample.totalUsage, previousUsage)
            XCTAssertEqual(sample.perCore[0], sample.totalUsage)
            previousUsage = sample.totalUsage
        }
    }

    func testPropertyPerCoreWeightedAverageReconciliation() {
        // Property: when all cores have equal total elapsed ticks, totalUsage == arithmetic mean(perCore)
        let prev = [
            ProcessorTicks(user: 100, system: 100, idle: 100, nice: 0),
            ProcessorTicks(user: 200, system: 200, idle: 200, nice: 0),
            ProcessorTicks(user: 300, system: 300, idle: 300, nice: 0),
            ProcessorTicks(user: 400, system: 400, idle: 400, nice: 0)
        ]
        // Each core has total 1000 ticks elapsed, with different busy fractions:
        // Core 0: busy=100 (10%)
        // Core 1: busy=300 (30%)
        // Core 2: busy=600 (60%)
        // Core 3: busy=800 (80%)
        // Mean = (10 + 30 + 60 + 80) / 4 = 45.0%
        let curr = [
            ProcessorTicks(user: 100 + 100, system: 100, idle: 100 + 900, nice: 0),
            ProcessorTicks(user: 200 + 200, system: 200 + 100, idle: 200 + 700, nice: 0),
            ProcessorTicks(user: 300 + 400, system: 300 + 200, idle: 300 + 400, nice: 0),
            ProcessorTicks(user: 400 + 500, system: 400 + 300, idle: 400 + 200, nice: 0)
        ]

        let sample = CPUSampler.calculateSample(previous: prev, current: curr)

        XCTAssertEqual(sample.perCore[0], 10.0, accuracy: 1e-5)
        XCTAssertEqual(sample.perCore[1], 30.0, accuracy: 1e-5)
        XCTAssertEqual(sample.perCore[2], 60.0, accuracy: 1e-5)
        XCTAssertEqual(sample.perCore[3], 80.0, accuracy: 1e-5)

        let coreMean = sample.perCore.reduce(0.0, +) / Double(sample.perCore.count)
        XCTAssertEqual(sample.totalUsage, coreMean, accuracy: 1e-5)
        XCTAssertEqual(sample.totalUsage, 45.0, accuracy: 1e-5)
    }

    func testPropertyCounterWrapOnCoreSubsets() {
        // Property: counter wrap on one core does not corrupt other cores or total calculation
        let prev = [
            ProcessorTicks(user: 50_000, system: 20_000, idle: 100_000, nice: 0), // Will wrap
            ProcessorTicks(user: 1_000, system: 500, idle: 8_500, nice: 0),       // Normal 50% busy
            ProcessorTicks(user: 5_000, system: 2_000, idle: 30_000, nice: 0)     // Unchanged (0 elapsed)
        ]

        let curr = [
            ProcessorTicks(user: 10, system: 5, idle: 20, nice: 0),              // Wrapped to smaller values
            ProcessorTicks(user: 1_250, system: 750, idle: 9_000, nice: 0),      // uDelta=250, sDelta=250, iDelta=500 -> total=1000, busy=500 (50%)
            ProcessorTicks(user: 5_000, system: 2_000, idle: 30_000, nice: 0)     // Exactly equal
        ]

        let sample = CPUSampler.calculateSample(previous: prev, current: curr)

        XCTAssertEqual(sample.perCore[0], 0.0, "Wrapped core must report 0% rather than underflowing")
        XCTAssertEqual(sample.perCore[1], 50.0, accuracy: 1e-5, "Unwrapped core must compute accurately")
        XCTAssertEqual(sample.perCore[2], 0.0, "Unchanged core must report 0%")

        // Total usage should be derived solely from valid deltas (Core 1: 500 busy / 1000 total = 50%)
        XCTAssertEqual(sample.totalUsage, 50.0, accuracy: 1e-5)
        XCTAssertEqual(sample.user, 25.0, accuracy: 1e-5)
        XCTAssertEqual(sample.system, 25.0, accuracy: 1e-5)
        XCTAssertEqual(sample.idle, 50.0, accuracy: 1e-5)
    }

    func testPropertyExtremeValuesNearUInt64Max() {
        // Property: huge tick counters near UInt64.max compute without overflow or crashing
        let base = UInt64.max - 1_000_000
        let prev = [
            ProcessorTicks(user: base, system: base, idle: base, nice: 0)
        ]
        let curr = [
            ProcessorTicks(user: base + 2000, system: base + 1000, idle: base + 7000, nice: 0)
        ]

        let sample = CPUSampler.calculateSample(previous: prev, current: curr)

        XCTAssertEqual(sample.totalUsage, 30.0, accuracy: 1e-5)
        XCTAssertEqual(sample.user, 20.0, accuracy: 1e-5)
        XCTAssertEqual(sample.system, 10.0, accuracy: 1e-5)
        XCTAssertEqual(sample.idle, 70.0, accuracy: 1e-5)
    }

    func testPropertyFuzzRandomizedSyntheticTicks() {
        // Generative property test: 1,000 deterministic pseudo-random multi-core transition cycles
        // testing all invariants simultaneously.
        var rngState: UInt64 = 0xDEAD_BEEF_CAFE_BABE

        func nextRandom(max: UInt64) -> UInt64 {
            // Linear congruential generator (deterministic and fast)
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return max > 0 ? (rngState >> 16) % max : 0
        }

        for iteration in 0..<1000 {
            let coreCount = Int(nextRandom(max: 16)) + 1 // 1 to 16 cores
            var prev = [ProcessorTicks]()
            var curr = [ProcessorTicks]()

            for _ in 0..<coreCount {
                let pU = nextRandom(max: 1_000_000)
                let pS = nextRandom(max: 1_000_000)
                let pI = nextRandom(max: 1_000_000)
                let pN = nextRandom(max: 100_000)

                let wrapCase = nextRandom(max: 20) == 0 // 5% chance of wrap/reset

                let cU = wrapCase ? nextRandom(max: 100) : pU + nextRandom(max: 10_000)
                let cS = wrapCase ? nextRandom(max: 100) : pS + nextRandom(max: 10_000)
                let cI = wrapCase ? nextRandom(max: 100) : pI + nextRandom(max: 50_000)
                let cN = wrapCase ? nextRandom(max: 50) : pN + nextRandom(max: 1_000)

                prev.append(ProcessorTicks(user: pU, system: pS, idle: pI, nice: pN))
                curr.append(ProcessorTicks(user: cU, system: cS, idle: cI, nice: cN))
            }

            let sample = CPUSampler.calculateSample(previous: prev, current: curr)

            // Invariant 1: Bounds
            XCTAssertGreaterThanOrEqual(sample.totalUsage, 0.0, "Iteration \(iteration): totalUsage < 0")
            XCTAssertLessThanOrEqual(sample.totalUsage, 100.0, "Iteration \(iteration): totalUsage > 100")
            XCTAssertEqual(sample.perCore.count, coreCount)

            for (cIdx, coreUsage) in sample.perCore.enumerated() {
                XCTAssertGreaterThanOrEqual(coreUsage, 0.0, "Iteration \(iteration) Core \(cIdx) < 0")
                XCTAssertLessThanOrEqual(coreUsage, 100.0, "Iteration \(iteration) Core \(cIdx) > 100")
            }

            XCTAssertGreaterThanOrEqual(sample.user, 0.0)
            XCTAssertLessThanOrEqual(sample.user, 100.0)
            XCTAssertGreaterThanOrEqual(sample.system, 0.0)
            XCTAssertLessThanOrEqual(sample.system, 100.0)
            XCTAssertGreaterThanOrEqual(sample.idle, 0.0)
            XCTAssertLessThanOrEqual(sample.idle, 100.0)

            // Invariant 2: Reconciliation
            let totalDelta = sample.user + sample.system + sample.idle
            if sample.totalUsage > 0.0 || sample.idle > 0.0 {
                XCTAssertEqual(totalDelta, 100.0, accuracy: 1e-5, "Iteration \(iteration): partition of unity failed")
                XCTAssertEqual(sample.user + sample.system, sample.totalUsage, accuracy: 1e-5, "Iteration \(iteration): user+system != totalUsage")
            } else {
                XCTAssertEqual(sample.totalUsage, 0.0)
                XCTAssertEqual(sample.user, 0.0)
                XCTAssertEqual(sample.system, 0.0)
                XCTAssertEqual(sample.idle, 0.0)
            }
        }
    }
}
