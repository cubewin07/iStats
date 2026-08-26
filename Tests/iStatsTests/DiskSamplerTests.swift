import XCTest
import Darwin
@testable import iStatsCore
@testable import iStats

final class DiskSamplerTests: XCTestCase {

    // MARK: - Mocks

    final class MockDiskInfoProvider: DiskInfoProvider, @unchecked Sendable {
        var mockVolumes: [VolumeCapacity] = []
        var mockIOCounters: RawDiskIOCounters? = nil
        var shouldThrowVolumes: Bool = false
        var shouldThrowIO: Bool = false

        func mountedVolumes() throws -> [VolumeCapacity] {
            if shouldThrowVolumes {
                throw SamplerError.systemCallFailed("Mock disk volume error")
            }
            return mockVolumes
        }

        func diskIOCounters() throws -> RawDiskIOCounters? {
            if shouldThrowIO {
                throw SamplerError.systemCallFailed("Mock disk IO error")
            }
            return mockIOCounters
        }
    }

    // MARK: - Capacity Tests (Task 3.3)

    func testDiskSamplerCategory() {
        let sampler = DiskSampler(provider: MockDiskInfoProvider())
        XCTAssertEqual(sampler.category, .disk)
    }

    func testDiskSamplerReturnsMountedVolumes() throws {
        let mock = MockDiskInfoProvider()
        mock.mockVolumes = [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 300_000_000_000, free: 200_000_000_000),
            VolumeCapacity(name: "Backup", mountPoint: "/Volumes/Backup", total: 1_000_000_000_000, used: 400_000_000_000, free: 600_000_000_000)
        ]

        let sampler = DiskSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertEqual(sample.volumes.count, 2)
        XCTAssertEqual(sample.volumes[0].name, "Macintosh HD")
        XCTAssertEqual(sample.volumes[0].mountPoint, "/")
        XCTAssertEqual(sample.volumes[0].total, 500_000_000_000)
        XCTAssertEqual(sample.volumes[0].used, 300_000_000_000)
        XCTAssertEqual(sample.volumes[0].free, 200_000_000_000)

        XCTAssertEqual(sample.volumes[1].name, "Backup")
        XCTAssertEqual(sample.volumes[1].mountPoint, "/Volumes/Backup")
        XCTAssertEqual(sample.volumes[1].total, 1_000_000_000_000)
        XCTAssertEqual(sample.volumes[1].used, 400_000_000_000)
        XCTAssertEqual(sample.volumes[1].free, 600_000_000_000)
    }

    func testDiskSamplerDynamicVolumeAddAndRemove() throws {
        let mock = MockDiskInfoProvider()
        let mainVol = VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 300_000_000_000, free: 200_000_000_000)
        let usbVol = VolumeCapacity(name: "USB Drive", mountPoint: "/Volumes/USB", total: 64_000_000_000, used: 10_000_000_000, free: 54_000_000_000)

        mock.mockVolumes = [mainVol]
        let sampler = DiskSampler(provider: mock)

        // 1. Initial sample with only main volume
        let sample1 = try sampler.sample()
        XCTAssertEqual(sample1.volumes.count, 1)
        XCTAssertEqual(sample1.volumes.first?.name, "Macintosh HD")

        // 2. USB drive plugged in
        mock.mockVolumes = [mainVol, usbVol]
        let sample2 = try sampler.sample()
        XCTAssertEqual(sample2.volumes.count, 2)
        XCTAssertEqual(sample2.volumes.map(\.name), ["Macintosh HD", "USB Drive"])

        // 3. USB drive unplugged / unmounted
        mock.mockVolumes = [mainVol]
        let sample3 = try sampler.sample()
        XCTAssertEqual(sample3.volumes.count, 1)
        XCTAssertEqual(sample3.volumes.first?.name, "Macintosh HD")
    }

    func testDiskSamplerThrowsWhenVolumeProviderFails() {
        let mock = MockDiskInfoProvider()
        mock.shouldThrowVolumes = true

        let sampler = DiskSampler(provider: mock)
        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError but got \(error)")
                return
            }
            if case .systemCallFailed(let reason) = samplerError {
                XCTAssertTrue(reason.contains("Mock disk volume error"))
            } else {
                XCTFail("Expected systemCallFailed but got \(samplerError)")
            }
        }
    }

    func testLiveHostDiskInfoProviderAndSampler() throws {
        let provider = HostDiskInfoProvider()
        let volumes = try provider.mountedVolumes()

        XCTAssertFalse(volumes.isEmpty, "Live host provider should return at least one mounted volume")

        // Find root mount
        let root = volumes.first(where: { $0.mountPoint == "/" })
        XCTAssertNotNil(root, "Root filesystem '/' must be present in mounted volumes")

        if let root = root {
            XCTAssertFalse(root.name.isEmpty, "Root volume name should not be empty")
            XCTAssertGreaterThan(root.total, 0, "Root volume total bytes must be > 0")
            XCTAssertGreaterThan(root.free, 0, "Root volume free bytes must be > 0")
            XCTAssertGreaterThan(root.used, 0, "Root volume used bytes must be > 0")
        }

        let sampler = DiskSampler(provider: provider)
        let sample = try sampler.sample()
        XCTAssertFalse(sample.volumes.isEmpty)
    }

    // MARK: - Disk I/O Tests (Task 3.4)

    func testDiskSamplerInitialSampleZeroIORates() throws {
        let mock = MockDiskInfoProvider()
        mock.mockVolumes = [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 250_000_000_000, free: 250_000_000_000)]
        mock.mockIOCounters = RawDiskIOCounters(bytesRead: 10_000_000, bytesWritten: 5_000_000, readOps: 1_000, writeOps: 500)

        let sampler = DiskSampler(provider: mock)
        let sample = try sampler.sample()

        XCTAssertNotNil(sample.io, "DiskIO should be present when counters are available")
        guard let io = sample.io else { return }

        // Initial sample must report 0 rates
        XCTAssertEqual(io.bytesReadPerSec, 0.0)
        XCTAssertEqual(io.bytesWrittenPerSec, 0.0)
        XCTAssertEqual(io.readOpsPerSec, 0.0)
        XCTAssertEqual(io.writeOpsPerSec, 0.0)
    }

    func testDiskSamplerSubsequentSampleCalculatesIORates() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let t1 = Date(timeIntervalSince1970: 1002.0) // 2.0s later

        let c0 = RawDiskIOCounters(bytesRead: 10_000_000, bytesWritten: 5_000_000, readOps: 1_000, writeOps: 500)
        let c1 = RawDiskIOCounters(bytesRead: 12_000_000, bytesWritten: 6_000_000, readOps: 1_200, writeOps: 600)

        let (firstIO, state0) = DiskSampler.calculateIOSample(previous: nil, current: c0, currentTimestamp: t0)
        XCTAssertEqual(firstIO?.bytesReadPerSec, 0.0)
        XCTAssertEqual(firstIO?.bytesWrittenPerSec, 0.0)
        XCTAssertEqual(firstIO?.readOpsPerSec, 0.0)
        XCTAssertEqual(firstIO?.writeOpsPerSec, 0.0)

        let (secondIO, state1) = DiskSampler.calculateIOSample(previous: state0, current: c1, currentTimestamp: t1)
        XCTAssertNotNil(secondIO)
        guard let io = secondIO else { return }

        // Delta: 2,000,000 bytes read / 2s = 1,000,000 B/s
        XCTAssertEqual(io.bytesReadPerSec, 1_000_000.0, accuracy: 0.001)
        // Delta: 1,000,000 bytes written / 2s = 500,000 B/s
        XCTAssertEqual(io.bytesWrittenPerSec, 500_000.0, accuracy: 0.001)
        // Delta: 200 read ops / 2s = 100 ops/s
        XCTAssertEqual(io.readOpsPerSec, 100.0, accuracy: 0.001)
        // Delta: 100 write ops / 2s = 50 ops/s
        XCTAssertEqual(io.writeOpsPerSec, 50.0, accuracy: 0.001)

        XCTAssertEqual(state1?.bytesRead, 12_000_000)
        XCTAssertEqual(state1?.bytesWritten, 6_000_000)
    }

    func testDiskSamplerIOCounterResetClampsRatesToZero() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let t1 = Date(timeIntervalSince1970: 1002.0)

        // Previous state has higher counters
        let prevState = DiskIOState(bytesRead: 100_000_000, bytesWritten: 50_000_000, readOps: 10_000, writeOps: 5_000, timestamp: t0)
        // Counter reset / disk restart -> new counters are lower
        let resetCounters = RawDiskIOCounters(bytesRead: 1_000, bytesWritten: 500, readOps: 10, writeOps: 5)

        let (io, newState) = DiskSampler.calculateIOSample(previous: prevState, current: resetCounters, currentTimestamp: t1)
        XCTAssertNotNil(io)

        // All rates must clamp to 0.0 and never produce negative spikes
        XCTAssertEqual(io?.bytesReadPerSec, 0.0)
        XCTAssertEqual(io?.bytesWrittenPerSec, 0.0)
        XCTAssertEqual(io?.readOpsPerSec, 0.0)
        XCTAssertEqual(io?.writeOpsPerSec, 0.0)

        XCTAssertEqual(newState?.bytesRead, 1_000)
        XCTAssertEqual(newState?.bytesWritten, 500)
    }

    func testDiskSamplerGracefulDegradationWhenIOUnavailable() throws {
        let mock = MockDiskInfoProvider()
        mock.mockVolumes = [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 250_000_000_000, free: 250_000_000_000)]
        mock.mockIOCounters = nil // Unavailable I/O stats

        let sampler = DiskSampler(provider: mock)
        let sample = try sampler.sample()

        // Volumes capacity must NOT be blocked
        XCTAssertEqual(sample.volumes.count, 1)
        XCTAssertEqual(sample.volumes[0].name, "Macintosh HD")
        // I/O degrades to nil
        XCTAssertNil(sample.io)

        // Even if I/O provider throws an error, capacity must still succeed
        mock.shouldThrowIO = true
        let sampleWithError = try sampler.sample()
        XCTAssertEqual(sampleWithError.volumes.count, 1)
        XCTAssertNil(sampleWithError.io)
    }

    func testCalculateIOSampleZeroOrNegativeElapsedTime() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let tPast = Date(timeIntervalSince1970: 998.0)

        let prevState = DiskIOState(bytesRead: 10_000_000, bytesWritten: 5_000_000, readOps: 1_000, writeOps: 500, timestamp: t0)
        let currentCounters = RawDiskIOCounters(bytesRead: 20_000_000, bytesWritten: 10_000_000, readOps: 2_000, writeOps: 1_000)

        // Equal timestamp
        let (ioEqual, _) = DiskSampler.calculateIOSample(previous: prevState, current: currentCounters, currentTimestamp: t0)
        XCTAssertEqual(ioEqual?.bytesReadPerSec, 0.0)
        XCTAssertEqual(ioEqual?.bytesWrittenPerSec, 0.0)
        XCTAssertEqual(ioEqual?.readOpsPerSec, 0.0)
        XCTAssertEqual(ioEqual?.writeOpsPerSec, 0.0)

        // Backwards clock
        let (ioPast, _) = DiskSampler.calculateIOSample(previous: prevState, current: currentCounters, currentTimestamp: tPast)
        XCTAssertEqual(ioPast?.bytesReadPerSec, 0.0)
        XCTAssertEqual(ioPast?.bytesWrittenPerSec, 0.0)
        XCTAssertEqual(ioPast?.readOpsPerSec, 0.0)
        XCTAssertEqual(ioPast?.writeOpsPerSec, 0.0)
    }

    func testLiveHostDiskInfoProviderIOCounters() throws {
        let provider = HostDiskInfoProvider()
        let ioCounters = try provider.diskIOCounters()

        // On physical/VM macOS host with block storage, IOKit IOBlockStorageDriver counters are available
        if let io = ioCounters {
            XCTAssertGreaterThanOrEqual(io.bytesRead, 0)
            XCTAssertGreaterThanOrEqual(io.bytesWritten, 0)
            XCTAssertGreaterThanOrEqual(io.readOps, 0)
            XCTAssertGreaterThanOrEqual(io.writeOps, 0)
        }

        let sampler = DiskSampler(provider: provider)
        let sample1 = try sampler.sample()
        XCTAssertFalse(sample1.volumes.isEmpty)

        // Sample twice to exercise rate math on live host
        Thread.sleep(forTimeInterval: 0.05)
        let sample2 = try sampler.sample()
        XCTAssertFalse(sample2.volumes.isEmpty)
        if let io2 = sample2.io {
            XCTAssertGreaterThanOrEqual(io2.bytesReadPerSec, 0.0)
            XCTAssertGreaterThanOrEqual(io2.bytesWrittenPerSec, 0.0)
            XCTAssertGreaterThanOrEqual(io2.readOpsPerSec, 0.0)
            XCTAssertGreaterThanOrEqual(io2.writeOpsPerSec, 0.0)
        }
    }
}
