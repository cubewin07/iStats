import Foundation
import Darwin
import iStatsCore

/// Cumulative tick counter snapshot for a single CPU core.
public struct ProcessorTicks: Sendable, Equatable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Abstract provider for reading CPU processor tick counters.
public protocol CPUInfoProvider: Sendable {
    /// Returns cumulative tick snapshots across all cores on the system.
    func processorTicks() throws -> [ProcessorTicks]
}

/// Darwin Mach implementation of `CPUInfoProvider` using `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`.
public struct HostProcessorInfoProvider: CPUInfoProvider {
    public init() {}

    public func processorTicks() throws -> [ProcessorTicks] {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t? = nil
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS else {
            throw SamplerError.systemCallFailed("host_processor_info failed with kern_return_t: \(result)")
        }

        guard let info = processorInfo else {
            throw SamplerError.systemCallFailed("host_processor_info returned null pointer")
        }

        defer {
            let size = vm_size_t(Int(processorInfoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let expectedCount = processorCount * natural_t(CPU_STATE_MAX)
        guard processorInfoCount >= expectedCount else {
            throw SamplerError.systemCallFailed(
                "host_processor_info returned insufficient data: \(processorInfoCount) < \(expectedCount)"
            )
        }

        var ticks = [ProcessorTicks]()
        ticks.reserveCapacity(Int(processorCount))

        for i in 0..<Int(processorCount) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            ticks.append(ProcessorTicks(user: user, system: system, idle: idle, nice: nice))
        }

        return ticks
    }
}

/// Concrete sampler for CPU utilization (aggregate, per-core, and user/system/idle breakdown).
///
/// Conforms to `Sampler` (Requirement 1.1, 1.2, 1.4). Keeps previous tick snapshot and computes
/// rates via pure rate math (`RateMath`).
public final class CPUSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .cpu

    private let provider: any CPUInfoProvider
    private let lock = NSLock()
    private var previousTicks: [ProcessorTicks]?

    public init(provider: any CPUInfoProvider = HostProcessorInfoProvider()) {
        self.provider = provider
    }

    /// Samples CPU metrics. Runs off the main thread.
    public func sample() throws -> CPUSample {
        let currentTicks = try provider.processorTicks()

        lock.lock()
        let previous = previousTicks
        previousTicks = currentTicks
        lock.unlock()

        return Self.calculateSample(previous: previous, current: currentTicks)
    }

    /// Pure calculation function deriving utilization percentages from tick snapshots.
    public static func calculateSample(
        previous: [ProcessorTicks]?,
        current: [ProcessorTicks]
    ) -> CPUSample {
        guard let previous, previous.count == current.count, !current.isEmpty else {
            // First sample or mismatched topology: return 0% utilization without negative spikes
            return CPUSample(
                totalUsage: 0.0,
                perCore: Array(repeating: 0.0, count: current.count),
                user: 0.0,
                system: 0.0,
                idle: 0.0
            )
        }

        var totalUserDelta: UInt64 = 0
        var totalSystemDelta: UInt64 = 0
        var totalIdleDelta: UInt64 = 0
        var totalNiceDelta: UInt64 = 0
        var perCoreUsages = [Double]()
        perCoreUsages.reserveCapacity(current.count)

        for i in 0..<current.count {
            let prev = previous[i]
            let curr = current[i]

            let uDelta = RateMath.counterDelta(previous: prev.user, current: curr.user)
            let sDelta = RateMath.counterDelta(previous: prev.system, current: curr.system)
            let iDelta = RateMath.counterDelta(previous: prev.idle, current: curr.idle)
            let nDelta = RateMath.counterDelta(previous: prev.nice, current: curr.nice)

            totalUserDelta += uDelta
            totalSystemDelta += sDelta
            totalIdleDelta += iDelta
            totalNiceDelta += nDelta

            let coreBusy = uDelta + sDelta + nDelta
            let coreTotal = coreBusy + iDelta
            let coreUsage = RateMath.cpuUsagePercent(busyDelta: Double(coreBusy), totalDelta: Double(coreTotal))
            perCoreUsages.append(coreUsage)
        }

        let totalBusyDelta = totalUserDelta + totalSystemDelta + totalNiceDelta
        let totalDelta = totalBusyDelta + totalIdleDelta

        let totalUsage = RateMath.cpuUsagePercent(busyDelta: Double(totalBusyDelta), totalDelta: Double(totalDelta))
        let userPercent = RateMath.cpuUsagePercent(
            busyDelta: Double(totalUserDelta + totalNiceDelta),
            totalDelta: Double(totalDelta)
        )
        let systemPercent = RateMath.cpuUsagePercent(
            busyDelta: Double(totalSystemDelta),
            totalDelta: Double(totalDelta)
        )
        let idlePercent = RateMath.cpuUsagePercent(
            busyDelta: Double(totalIdleDelta),
            totalDelta: Double(totalDelta)
        )

        return CPUSample(
            totalUsage: totalUsage,
            perCore: perCoreUsages,
            user: userPercent,
            system: systemPercent,
            idle: idlePercent
        )
    }
}
