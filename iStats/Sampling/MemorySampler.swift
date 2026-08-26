import Foundation
import Darwin
import iStatsCore

/// Raw page counts from Mach `host_statistics64(HOST_VM_INFO64)`.
public struct RawVMStatistics: Sendable, Equatable {
    public let freePages: UInt64
    public let activePages: UInt64
    public let inactivePages: UInt64
    public let wirePages: UInt64
    public let compressedPages: UInt64
    public let purgeablePages: UInt64
    public let externalPages: UInt64
    public let internalPages: UInt64

    public init(
        freePages: UInt64,
        activePages: UInt64,
        inactivePages: UInt64,
        wirePages: UInt64,
        compressedPages: UInt64,
        purgeablePages: UInt64,
        externalPages: UInt64,
        internalPages: UInt64
    ) {
        self.freePages = freePages
        self.activePages = activePages
        self.inactivePages = inactivePages
        self.wirePages = wirePages
        self.compressedPages = compressedPages
        self.purgeablePages = purgeablePages
        self.externalPages = externalPages
        self.internalPages = internalPages
    }
}

/// System swap usage statistics from `sysctl vm.swapusage`.
public struct SwapUsageData: Sendable, Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64

    public init(totalBytes: UInt64, usedBytes: UInt64, freeBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
    }
}

/// Abstract provider for reading Mach VM statistics, host page size, physical memory, swap, and pressure.
public protocol MemoryInfoProvider: Sendable {
    /// Returns raw Mach virtual memory statistics and host page size in bytes.
    func vmStatistics() throws -> (stats: RawVMStatistics, pageSize: UInt64)
    /// Returns total installed physical memory in bytes via `hw.memsize`.
    func physicalMemoryBytes() throws -> UInt64
    /// Returns current swap space metrics via `vm.swapusage`.
    func swapUsage() throws -> SwapUsageData
    /// Returns current memory pressure level.
    func memoryPressure() throws -> MemoryPressure
}

public extension MemoryInfoProvider {
    func memoryPressure() throws -> MemoryPressure { .normal }
}

/// Darwin Mach and sysctl implementation of `MemoryInfoProvider`.
public struct HostMemoryInfoProvider: MemoryInfoProvider {
    public init() {}

    public func vmStatistics() throws -> (stats: RawVMStatistics, pageSize: UInt64) {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw SamplerError.systemCallFailed("host_statistics64(HOST_VM_INFO64) failed with kern_return_t: \(result)")
        }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(mach_host_self(), &pageSize)
        guard pageResult == KERN_SUCCESS, pageSize > 0 else {
            throw SamplerError.systemCallFailed("host_page_size failed with kern_return_t: \(pageResult)")
        }

        let raw = RawVMStatistics(
            freePages: UInt64(vmStats.free_count),
            activePages: UInt64(vmStats.active_count),
            inactivePages: UInt64(vmStats.inactive_count),
            wirePages: UInt64(vmStats.wire_count),
            compressedPages: UInt64(vmStats.compressor_page_count),
            purgeablePages: UInt64(vmStats.purgeable_count),
            externalPages: UInt64(vmStats.external_page_count),
            internalPages: UInt64(vmStats.internal_page_count)
        )

        return (raw, UInt64(pageSize))
    }

    public func physicalMemoryBytes() throws -> UInt64 {
        var memsize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        let result = sysctlbyname("hw.memsize", &memsize, &size, nil, 0)
        guard result == 0, memsize > 0 else {
            throw SamplerError.systemCallFailed("sysctl hw.memsize failed with errno: \(errno)")
        }
        return memsize
    }

    public func swapUsage() throws -> SwapUsageData {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        guard result == 0 else {
            throw SamplerError.systemCallFailed("sysctl vm.swapusage failed with errno: \(errno)")
        }
        return SwapUsageData(
            totalBytes: UInt64(swap.xsu_total),
            usedBytes: UInt64(swap.xsu_used),
            freeBytes: UInt64(swap.xsu_avail)
        )
    }

    public func memoryPressure() throws -> MemoryPressure {
        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 {
            switch pressureLevel {
            case 2: // NOTE_MEMORYSTATUS_PRESSURE_WARN
                return .warning
            case 4: // NOTE_MEMORYSTATUS_PRESSURE_CRITICAL
                return .critical
            default:
                return .normal
            }
        }
        return .normal
    }
}

/// Concrete sampler for host memory (used, free, wired, compressed, cached, swap, pressure).
///
/// Conforms to `Sampler` (Requirements 2.1, 2.2, 2.3, 2.4). Runs on background queues via `SampleScheduler`.
public final class MemorySampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .memory

    private let provider: any MemoryInfoProvider

    public init(provider: any MemoryInfoProvider = HostMemoryInfoProvider()) {
        self.provider = provider
    }

    /// Samples memory statistics. Runs off the main thread.
    public func sample() throws -> MemorySample {
        let (stats, pageSize) = try provider.vmStatistics()
        let totalRAM = try provider.physicalMemoryBytes()
        let swap = try provider.swapUsage()
        let pressure = (try? provider.memoryPressure()) ?? .normal

        return Self.calculateSample(
            stats: stats,
            pageSize: pageSize,
            totalPhysicalMemory: totalRAM,
            swapUsage: swap,
            pressure: pressure
        )
    }

    /// Pure calculation function deriving memory breakdown and metrics from raw VM stats.
    public static func calculateSample(
        stats: RawVMStatistics,
        pageSize: UInt64,
        totalPhysicalMemory: UInt64,
        swapUsage: SwapUsageData,
        pressure: MemoryPressure
    ) -> MemorySample {
        let wiredBytes = stats.wirePages * pageSize
        let compressedBytes = stats.compressedPages * pageSize
        let activeBytes = stats.activePages * pageSize
        let inactiveBytes = stats.inactivePages * pageSize
        let freeBytes = stats.freePages * pageSize

        // App memory (macOS Activity Monitor standard: internal anonymous pages minus purgeable pages)
        let appMemoryBytes: UInt64
        if stats.internalPages == 0 && stats.purgeablePages == 0 {
            appMemoryBytes = activeBytes
        } else if stats.internalPages >= stats.purgeablePages {
            appMemoryBytes = (stats.internalPages - stats.purgeablePages) * pageSize
        } else {
            appMemoryBytes = 0
        }

        // Memory Used (Activity Monitor standard: App Memory + Wired Memory + Compressed)
        let usedBytes = appMemoryBytes + wiredBytes + compressedBytes

        // Cached Files (Activity Monitor standard: Purgeable pages + External file-backed pages)
        let cachedBytes = (stats.purgeablePages + stats.externalPages) * pageSize

        return MemorySample(
            total: totalPhysicalMemory,
            used: usedBytes,
            free: freeBytes,
            wired: wiredBytes,
            compressed: compressedBytes,
            cached: cachedBytes,
            swapUsed: swapUsage.usedBytes,
            pressure: pressure,
            appMemory: appMemoryBytes,
            active: activeBytes,
            inactive: inactiveBytes,
            swapTotal: swapUsage.totalBytes,
            swapFree: swapUsage.freeBytes
        )
    }
}
