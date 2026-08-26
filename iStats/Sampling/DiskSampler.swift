import Foundation
import Darwin
import iStatsCore

/// Raw disk I/O counter snapshot across block storage devices.
public struct RawDiskIOCounters: Sendable, Equatable {
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    public let readOps: UInt64
    public let writeOps: UInt64

    public init(bytesRead: UInt64, bytesWritten: UInt64, readOps: UInt64, writeOps: UInt64) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.readOps = readOps
        self.writeOps = writeOps
    }
}

/// Abstract provider for reading disk capacity and block storage statistics.
public protocol DiskInfoProvider: Sendable {
    /// Returns capacity information for all currently mounted volumes.
    func mountedVolumes() throws -> [VolumeCapacity]

    /// Returns aggregate raw disk I/O counters, or nil if unavailable.
    func diskIOCounters() throws -> RawDiskIOCounters?
}

/// Darwin `getfsstat` implementation of `DiskInfoProvider`.
public struct HostDiskInfoProvider: DiskInfoProvider {
    public init() {}

    public func mountedVolumes() throws -> [VolumeCapacity] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else {
            throw SamplerError.systemCallFailed("getfsstat count query returned \(count), errno: \(errno)")
        }

        var buffer = Array<Darwin.statfs>(unsafeUninitializedCapacity: Int(count)) { buf, initializedCount in
            let result = getfsstat(buf.baseAddress, Int32(MemoryLayout<Darwin.statfs>.size * Int(count)), MNT_NOWAIT)
            initializedCount = result >= 0 ? Int(result) : 0
        }

        guard !buffer.isEmpty else {
            throw SamplerError.systemCallFailed("getfsstat data retrieval failed with errno: \(errno)")
        }

        var volumes: [VolumeCapacity] = []

        for i in 0..<buffer.count {
            var fs = buffer[i]

            let mountPoint = withUnsafePointer(to: &fs.f_mntonname) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                    String(cString: cStr)
                }
            }

            guard !mountPoint.isEmpty else { continue }

            let blockSize = UInt64(fs.f_bsize)
            let totalBlocks = UInt64(fs.f_blocks)
            let freeBlocks = UInt64(fs.f_bavail)

            let totalBytes = totalBlocks * blockSize
            let freeBytes = freeBlocks * blockSize
            let usedBytes = totalBytes >= freeBytes ? (totalBytes - freeBytes) : UInt64(0)

            // Ignore 0-byte pseudo/virtual mounts
            guard totalBytes > 0 else { continue }

            let url = URL(fileURLWithPath: mountPoint)
            let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeLocalizedNameKey]
            let resValues = try? url.resourceValues(forKeys: keys)
            let rawName = resValues?.volumeLocalizedName ?? resValues?.volumeName ?? FileManager.default.displayName(atPath: mountPoint)

            let name: String
            if !rawName.isEmpty {
                name = rawName
            } else if mountPoint == "/" {
                name = "Macintosh HD"
            } else {
                name = url.lastPathComponent.isEmpty ? mountPoint : url.lastPathComponent
            }

            volumes.append(
                VolumeCapacity(
                    name: name,
                    mountPoint: mountPoint,
                    total: totalBytes,
                    used: usedBytes,
                    free: freeBytes
                )
            )
        }

        // Sort deterministically: root first, then by mount point
        return volumes.sorted { v1, v2 in
            if v1.mountPoint == "/" { return true }
            if v2.mountPoint == "/" { return false }
            return v1.mountPoint < v2.mountPoint
        }
    }

    public func diskIOCounters() throws -> RawDiskIOCounters? {
        // Disk I/O provider implementation is added in Task 3.4
        return nil
    }
}

/// Concrete sampler for mounted disk volume capacity and I/O metrics.
///
/// Conforms to `Sampler` (Requirements 7.1, 7.3). All Darwin filesystem calls
/// run off the main thread under `SampleScheduler`.
public final class DiskSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .disk

    private let provider: any DiskInfoProvider
    private let lock = NSLock()

    public init(provider: any DiskInfoProvider = HostDiskInfoProvider()) {
        self.provider = provider
    }

    /// Samples disk metrics for all currently mounted volumes. Runs off the main thread.
    public func sample() throws -> DiskSample {
        let volumes = try provider.mountedVolumes()
        return DiskSample(volumes: volumes, io: nil)
    }
}
