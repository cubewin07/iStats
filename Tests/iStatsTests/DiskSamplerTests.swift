import XCTest
import Darwin
@testable import iStatsCore
@testable import iStats

final class DiskSamplerTests: XCTestCase {

    // MARK: - Mocks

    final class MockDiskInfoProvider: DiskInfoProvider, @unchecked Sendable {
        var mockVolumes: [VolumeCapacity] = []
        var mockIOCounters: RawDiskIOCounters? = nil
        var shouldThrow: Bool = false

        func mountedVolumes() throws -> [VolumeCapacity] {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock disk error")
            }
            return mockVolumes
        }

        func diskIOCounters() throws -> RawDiskIOCounters? {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock disk IO error")
            }
            return mockIOCounters
        }
    }

    // MARK: - Tests

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

    func testDiskSamplerThrowsWhenProviderFails() {
        let mock = MockDiskInfoProvider()
        mock.shouldThrow = true

        let sampler = DiskSampler(provider: mock)
        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError but got \(error)")
                return
            }
            if case .systemCallFailed(let reason) = samplerError {
                XCTAssertTrue(reason.contains("Mock disk error"))
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
}
