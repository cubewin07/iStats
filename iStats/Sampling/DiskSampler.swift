import Foundation
import Darwin
import IOKit
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

/// Darwin `getfsstat` and IOKit `IOBlockStorageDriver` implementation of `DiskInfoProvider`.
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

    /// Queries IOKit registry for all `IOBlockStorageDriver` services and sums their statistics.
    public func diskIOCounters() throws -> RawDiskIOCounters? {
        var iterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching("IOBlockStorageDriver")
        guard let matchingDict = matchingDict else {
            return nil
        }

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS, iterator != 0 else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var totalReadBytes: UInt64 = 0
        var totalWriteBytes: UInt64 = 0
        var totalReadOps: UInt64 = 0
        var totalWriteOps: UInt64 = 0
        var foundAnyStats = false

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }

            guard let props = IORegistryEntryCreateCFProperty(
                entry,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            let readBytes = (props["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let writeBytes = (props["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            let readOps = (props["Operations (Read)"] as? NSNumber)?.uint64Value ?? 0
            let writeOps = (props["Operations (Write)"] as? NSNumber)?.uint64Value ?? 0

            totalReadBytes += readBytes
            totalWriteBytes += writeBytes
            totalReadOps += readOps
            totalWriteOps += writeOps
            foundAnyStats = true
        }

        guard foundAnyStats else { return nil }

        return RawDiskIOCounters(
            bytesRead: totalReadBytes,
            bytesWritten: totalWriteBytes,
            readOps: totalReadOps,
            writeOps: totalWriteOps
        )
    }
}

/// Historical disk I/O state for rate calculation.
public struct DiskIOState: Sendable, Equatable {
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    public let readOps: UInt64
    public let writeOps: UInt64
    public let timestamp: Date

    public init(bytesRead: UInt64, bytesWritten: UInt64, readOps: UInt64, writeOps: UInt64, timestamp: Date) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.readOps = readOps
        self.writeOps = writeOps
        self.timestamp = timestamp
    }
}

/// Concrete sampler for mounted disk volume capacity and I/O metrics.
///
/// Conforms to `Sampler` (Requirements 7.1, 7.2, 7.3). All Darwin filesystem and IOKit calls
/// run off the main thread under `SampleScheduler`. When I/O statistics are unavailable,
/// degrades gracefully with `io: nil` without blocking capacity reporting.
public final class DiskSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .disk

    private let provider: any DiskInfoProvider
    private let lock = NSLock()
    private var previousIOState: DiskIOState?

    public init(provider: any DiskInfoProvider = HostDiskInfoProvider()) {
        self.provider = provider
    }

    /// Samples disk metrics for all currently mounted volumes and I/O rates. Runs off the main thread.
    public func sample() throws -> DiskSample {
        let volumes = try provider.mountedVolumes()
        let currentTimestamp = Date()

        let rawIO: RawDiskIOCounters?
        do {
            rawIO = try provider.diskIOCounters()
        } catch {
            rawIO = nil
        }

        lock.lock()
        let prev = previousIOState
        let (diskIO, newPrev) = Self.calculateIOSample(
            previous: prev,
            current: rawIO,
            currentTimestamp: currentTimestamp
        )
        self.previousIOState = newPrev
        lock.unlock()

        return DiskSample(volumes: volumes, io: diskIO)
    }

    /// Pure calculation function deriving throughput rates from I/O counter snapshots.
    public static func calculateIOSample(
        previous: DiskIOState?,
        current: RawDiskIOCounters?,
        currentTimestamp: Date
    ) -> (io: DiskIO?, newPrevious: DiskIOState?) {
        guard let current = current else {
            return (io: nil, newPrevious: previous)
        }

        let io: DiskIO
        if let previous = previous, currentTimestamp > previous.timestamp {
            let elapsed = currentTimestamp.timeIntervalSince(previous.timestamp)
            let readBytesRate = RateMath.bytesPerSecond(
                previous: previous.bytesRead,
                current: current.bytesRead,
                elapsedSeconds: elapsed
            )
            let writeBytesRate = RateMath.bytesPerSecond(
                previous: previous.bytesWritten,
                current: current.bytesWritten,
                elapsedSeconds: elapsed
            )
            let deltaReadOps = Double(RateMath.counterDelta(previous: previous.readOps, current: current.readOps))
            let deltaWriteOps = Double(RateMath.counterDelta(previous: previous.writeOps, current: current.writeOps))
            let readOpsRate = elapsed > 0 ? (deltaReadOps / elapsed) : 0.0
            let writeOpsRate = elapsed > 0 ? (deltaWriteOps / elapsed) : 0.0

            io = DiskIO(
                bytesReadPerSec: readBytesRate,
                bytesWrittenPerSec: writeBytesRate,
                readOpsPerSec: readOpsRate,
                writeOpsPerSec: writeOpsRate
            )
        } else {
            // First sample or non-forward clock: 0 rates
            io = DiskIO(
                bytesReadPerSec: 0.0,
                bytesWrittenPerSec: 0.0,
                readOpsPerSec: 0.0,
                writeOpsPerSec: 0.0
            )
        }

        let newPrevious = DiskIOState(
            bytesRead: current.bytesRead,
            bytesWritten: current.bytesWritten,
            readOps: current.readOps,
            writeOps: current.writeOps,
            timestamp: currentTimestamp
        )

        return (io: io, newPrevious: newPrevious)
    }
}
