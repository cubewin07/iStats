import XCTest
import iStatsCore
@testable import iStats

final class CPUSamplerTests: XCTestCase {

    final class MockCPUInfoProvider: CPUInfoProvider, @unchecked Sendable {
        private var responses: [[ProcessorTicks]]
        private var index = 0
        private let lock = NSLock()

        init(responses: [[ProcessorTicks]]) {
            self.responses = responses
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
    }

    struct FailingCPUInfoProvider: CPUInfoProvider {
        func processorTicks() throws -> [ProcessorTicks] {
            throw SamplerError.systemCallFailed("Mach host_processor_info kernel error")
        }
    }

    func testFirstSampleReturnsZeroUtilization() throws {
        let core0 = ProcessorTicks(user: 1000, system: 500, idle: 8500, nice: 0)
        let core1 = ProcessorTicks(user: 2000, system: 1000, idle: 7000, nice: 0)

        let provider = MockCPUInfoProvider(responses: [[core0, core1]])
        let sampler = CPUSampler(provider: provider)

        let sample = try sampler.sample()

        XCTAssertEqual(sample.totalUsage, 0.0)
        XCTAssertEqual(sample.perCore, [0.0, 0.0])
        XCTAssertEqual(sample.user, 0.0)
        XCTAssertEqual(sample.system, 0.0)
        XCTAssertEqual(sample.idle, 0.0)
    }

    func testSecondSampleCalculatesCorrectRate() throws {
        let t1Core0 = ProcessorTicks(user: 100, system: 50, idle: 850, nice: 0)
        let t1Core1 = ProcessorTicks(user: 1000, system: 200, idle: 800, nice: 0)

        // Core 0: uDelta=100, sDelta=50, iDelta=850, nDelta=0 -> busy=150, total=1000 (15%)
        // Core 1: uDelta=500, sDelta=100, iDelta=400, nDelta=0 -> busy=600, total=1000 (60%)
        // Total: user=600, sys=150, idle=1250, total=2000 -> totalUsage=37.5%, user=30%, sys=7.5%, idle=62.5%
        let t2Core0 = ProcessorTicks(user: 200, system: 100, idle: 1700, nice: 0)
        let t2Core1 = ProcessorTicks(user: 1500, system: 300, idle: 1200, nice: 0)

        let provider = MockCPUInfoProvider(responses: [[t1Core0, t1Core1], [t2Core0, t2Core1]])
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

        let sampler = CPUSampler(provider: provider)
        let sample1 = try sampler.sample()
        XCTAssertEqual(sample1.totalUsage, 0.0)
        XCTAssertEqual(sample1.perCore.count, ticks.count)

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
    }
}
