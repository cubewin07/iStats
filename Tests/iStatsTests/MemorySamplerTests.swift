import XCTest
import iStatsCore
@testable import iStats

final class MemorySamplerTests: XCTestCase {

    final class MockMemoryInfoProvider: MemoryInfoProvider, @unchecked Sendable {
        var mockStats: RawVMStatistics
        var mockPageSize: UInt64
        var mockTotalRAM: UInt64
        var mockSwap: SwapUsageData
        var mockPressure: MemoryPressure

        init(
            stats: RawVMStatistics = RawVMStatistics(
                freePages: 100_000,
                activePages: 400_000,
                inactivePages: 300_000,
                wirePages: 200_000,
                compressedPages: 50_000,
                purgeablePages: 20_000,
                externalPages: 150_000,
                internalPages: 420_000
            ),
            pageSize: UInt64 = 16384,
            totalRAM: UInt64 = 16 * 1024 * 1024 * 1024,
            swap: SwapUsageData = SwapUsageData(
                totalBytes: 2 * 1024 * 1024 * 1024,
                usedBytes: 512 * 1024 * 1024,
                freeBytes: 1536 * 1024 * 1024
            ),
            pressure: MemoryPressure = .normal
        ) {
            self.mockStats = stats
            self.mockPageSize = pageSize
            self.mockTotalRAM = totalRAM
            self.mockSwap = swap
            self.mockPressure = pressure
        }

        func vmStatistics() throws -> (stats: RawVMStatistics, pageSize: UInt64) {
            (mockStats, mockPageSize)
        }

        func physicalMemoryBytes() throws -> UInt64 {
            mockTotalRAM
        }

        func swapUsage() throws -> SwapUsageData {
            mockSwap
        }

        func memoryPressure() throws -> MemoryPressure {
            mockPressure
        }
    }

    struct FailingMemoryInfoProvider: MemoryInfoProvider {
        let failVM: Bool
        let failRAM: Bool
        let failSwap: Bool

        init(failVM: Bool = false, failRAM: Bool = false, failSwap: Bool = false) {
            self.failVM = failVM
            self.failRAM = failRAM
            self.failSwap = failSwap
        }

        func vmStatistics() throws -> (stats: RawVMStatistics, pageSize: UInt64) {
            if failVM {
                throw SamplerError.systemCallFailed("host_statistics64 failed")
            }
            return (RawVMStatistics(freePages: 1, activePages: 1, inactivePages: 1, wirePages: 1,
                                    compressedPages: 1, purgeablePages: 0, externalPages: 1, internalPages: 1), 16384)
        }

        func physicalMemoryBytes() throws -> UInt64 {
            if failRAM {
                throw SamplerError.systemCallFailed("sysctl hw.memsize failed")
            }
            return 16 * 1024 * 1024 * 1024
        }

        func swapUsage() throws -> SwapUsageData {
            if failSwap {
                throw SamplerError.systemCallFailed("sysctl vm.swapusage failed")
            }
            return SwapUsageData(totalBytes: 0, usedBytes: 0, freeBytes: 0)
        }

        func memoryPressure() throws -> MemoryPressure {
            .normal
        }
    }

    func testMemorySamplerCategory() {
        let sampler = MemorySampler(provider: MockMemoryInfoProvider())
        XCTAssertEqual(sampler.category, .memory)
    }

    func testMemorySamplerBasicSample() throws {
        let provider = MockMemoryInfoProvider()
        let sampler = MemorySampler(provider: provider)

        let sample = try sampler.sample()

        XCTAssertEqual(sample.total, 16 * 1024 * 1024 * 1024)
        XCTAssertEqual(sample.pressure, .normal)

        // Page calculations:
        // pageSize = 16384
        // appPages = 420_000 - 20_000 = 400_000 -> appMemory = 400_000 * 16384 = 6_553_600_000
        // wired = 200_000 * 16384 = 3_276_800_000
        // compressed = 50_000 * 16384 = 819_200_000
        // used = appMemory + wired + compressed = 10_649_600_000
        // cached = (purgeable 20_000 + external 150_000) * 16384 = 170_000 * 16384 = 2_785_280_000
        // free = 100_000 * 16384 = 1_638_400_000
        // swapUsed = 512 * 1024 * 1024 = 536_870_912

        XCTAssertEqual(sample.wired, 200_000 * 16384)
        XCTAssertEqual(sample.compressed, 50_000 * 16384)
        XCTAssertEqual(sample.appMemory, 400_000 * 16384)
        XCTAssertEqual(sample.used, (400_000 + 200_000 + 50_000) * 16384)
        XCTAssertEqual(sample.cached, 170_000 * 16384)
        XCTAssertEqual(sample.free, 100_000 * 16384)
        XCTAssertEqual(sample.swapUsed, 512 * 1024 * 1024)
        XCTAssertEqual(sample.swapTotal, 2 * 1024 * 1024 * 1024)
        XCTAssertEqual(sample.swapFree, 1536 * 1024 * 1024)
    }

    func testMemorySamplerPageMathIntel4KB() {
        let stats = RawVMStatistics(
            freePages: 50_000,
            activePages: 200_000,
            inactivePages: 100_000,
            wirePages: 80_000,
            compressedPages: 20_000,
            purgeablePages: 10_000,
            externalPages: 50_000,
            internalPages: 190_000
        )
        let swap = SwapUsageData(totalBytes: 1000, usedBytes: 100, freeBytes: 900)

        let sample = MemorySampler.calculateSample(
            stats: stats,
            pageSize: 4096,
            totalPhysicalMemory: 8 * 1024 * 1024 * 1024,
            swapUsage: swap,
            pressure: .warning
        )

        // appPages = 190_000 - 10_000 = 180_000
        let appMemory = UInt64(180_000) * 4096
        let wired = UInt64(80_000) * 4096
        let compressed = UInt64(20_000) * 4096
        let expectedUsed = appMemory + wired + compressed
        let expectedCached = UInt64(10_000 + 50_000) * 4096
        let expectedFree = UInt64(50_000) * 4096

        XCTAssertEqual(sample.total, 8 * 1024 * 1024 * 1024)
        XCTAssertEqual(sample.used, expectedUsed)
        XCTAssertEqual(sample.wired, wired)
        XCTAssertEqual(sample.compressed, compressed)
        XCTAssertEqual(sample.cached, expectedCached)
        XCTAssertEqual(sample.free, expectedFree)
        XCTAssertEqual(sample.swapUsed, 100)
        XCTAssertEqual(sample.pressure, .warning)
    }

    func testMemorySamplerPurgeableGreaterThanInternalEdgeCase() {
        let stats = RawVMStatistics(
            freePages: 100,
            activePages: 500,
            inactivePages: 200,
            wirePages: 100,
            compressedPages: 50,
            purgeablePages: 600,
            externalPages: 100,
            internalPages: 400
        )
        let swap = SwapUsageData(totalBytes: 0, usedBytes: 0, freeBytes: 0)

        let sample = MemorySampler.calculateSample(
            stats: stats,
            pageSize: 16384,
            totalPhysicalMemory: 16 * 1024 * 1024 * 1024,
            swapUsage: swap,
            pressure: .critical
        )

        XCTAssertEqual(sample.pressure, .critical)
        XCTAssertEqual(sample.appMemory, 0)
        XCTAssertEqual(sample.used, (100 + 50) * 16384) // wired + compressed
        XCTAssertEqual(sample.cached, (600 + 100) * 16384)
    }

    func testMemorySamplerPressureMapping() throws {
        let provider = MockMemoryInfoProvider(pressure: .critical)
        let sampler = MemorySampler(provider: provider)
        let sample = try sampler.sample()
        XCTAssertEqual(sample.pressure, .critical)

        provider.mockPressure = .warning
        let warningSample = try sampler.sample()
        XCTAssertEqual(warningSample.pressure, .warning)

        provider.mockPressure = .normal
        let normalSample = try sampler.sample()
        XCTAssertEqual(normalSample.pressure, .normal)
    }

    func testMemorySamplerFailingVMStatisticsThrows() {
        let provider = FailingMemoryInfoProvider(failVM: true)
        let sampler = MemorySampler(provider: provider)
        XCTAssertThrowsError(try sampler.sample()) { error in
            guard case SamplerError.systemCallFailed(let msg) = error else {
                XCTFail("Expected SamplerError.systemCallFailed, got: \(error)")
                return
            }
            XCTAssertTrue(msg.contains("host_statistics64"))
        }
    }

    func testMemorySamplerFailingRAMSizeThrows() {
        let provider = FailingMemoryInfoProvider(failRAM: true)
        let sampler = MemorySampler(provider: provider)
        XCTAssertThrowsError(try sampler.sample()) { error in
            guard case SamplerError.systemCallFailed(let msg) = error else {
                XCTFail("Expected SamplerError.systemCallFailed, got: \(error)")
                return
            }
            XCTAssertTrue(msg.contains("hw.memsize"))
        }
    }

    func testMemorySamplerFailingSwapUsageThrows() {
        let provider = FailingMemoryInfoProvider(failSwap: true)
        let sampler = MemorySampler(provider: provider)
        XCTAssertThrowsError(try sampler.sample()) { error in
            guard case SamplerError.systemCallFailed(let msg) = error else {
                XCTFail("Expected SamplerError.systemCallFailed, got: \(error)")
                return
            }
            XCTAssertTrue(msg.contains("vm.swapusage"))
        }
    }

    func testLiveHostMemoryInfoProviderAndSampler() throws {
        let hostProvider = HostMemoryInfoProvider()
        let (stats, pageSize) = try hostProvider.vmStatistics()
        let totalRAM = try hostProvider.physicalMemoryBytes()
        let swap = try hostProvider.swapUsage()
        let pressure = try hostProvider.memoryPressure()

        XCTAssertTrue(pageSize == 4096 || pageSize == 16384, "Page size must be 4KB or 16KB on macOS, got \(pageSize)")
        XCTAssertEqual(totalRAM, ProcessInfo.processInfo.physicalMemory, "Total RAM must match ProcessInfo.physicalMemory")
        XCTAssertGreaterThan(stats.freePages + stats.activePages + stats.inactivePages + stats.wirePages, 0)
        XCTAssertGreaterThanOrEqual(swap.totalBytes, swap.usedBytes)
        XCTAssertTrue(pressure == .normal || pressure == .warning || pressure == .critical)

        let sampler = MemorySampler(provider: hostProvider)
        let sample = try sampler.sample()

        XCTAssertEqual(sample.total, totalRAM)
        XCTAssertGreaterThan(sample.used, 0)
        XCTAssertGreaterThanOrEqual(sample.free, 0)
        XCTAssertGreaterThanOrEqual(sample.wired, 0)
        XCTAssertGreaterThanOrEqual(sample.compressed, 0)
        XCTAssertGreaterThanOrEqual(sample.cached, 0)
        XCTAssertGreaterThanOrEqual(sample.swapUsed, 0)
    }
}
