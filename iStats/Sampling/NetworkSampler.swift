import Foundation
import Darwin
import iStatsCore

/// Raw byte counter snapshot for a single network interface.
public struct RawInterfaceCounters: Sendable, Equatable {
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let isLoopback: Bool
    public let isUp: Bool

    public init(
        name: String,
        bytesIn: UInt64,
        bytesOut: UInt64,
        isLoopback: Bool = false,
        isUp: Bool = true
    ) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.isLoopback = isLoopback
        self.isUp = isUp
    }
}

/// Abstract provider for reading network interface counters.
public protocol NetworkInfoProvider: Sendable {
    /// Returns raw counter snapshots for all network interfaces on the system.
    func interfaceCounters() throws -> [RawInterfaceCounters]
}

/// Darwin `sysctl(NET_RT_IFLIST2)` and `getifaddrs` implementation of `NetworkInfoProvider`.
public struct HostNetworkInfoProvider: NetworkInfoProvider {
    public init() {}

    public func interfaceCounters() throws -> [RawInterfaceCounters] {
        // Attempt 64-bit sysctl NET_RT_IFLIST2 first to prevent 32-bit counter wrap
        if let sysctlCounters = try? readSysctlCounters(), !sysctlCounters.isEmpty {
            return sysctlCounters
        }

        // Fallback to getifaddrs
        return try readGetifaddrsCounters()
    }

    /// Reads network interface counters via `sysctl(CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0)`.
    private func readSysctlCounters() throws -> [RawInterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0

        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else {
            throw SamplerError.systemCallFailed("sysctl NET_RT_IFLIST2 size query failed with errno: \(errno)")
        }

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        defer { buf.deallocate() }

        guard sysctl(&mib, 6, buf, &len, nil, 0) == 0 else {
            throw SamplerError.systemCallFailed("sysctl NET_RT_IFLIST2 data query failed with errno: \(errno)")
        }

        var results: [RawInterfaceCounters] = []
        var ptr = buf
        let end = buf.advanced(by: len)

        while ptr < end {
            let ifm = ptr.withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
            let msgLen = Int(ifm.ifm_msglen)
            guard msgLen > 0 else { break }

            if Int32(ifm.ifm_type) == RTM_IFINFO2 {
                let ifm2 = ptr.withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }
                let sdlOffset = MemoryLayout<if_msghdr2>.size
                let sdlPtr = ptr.advanced(by: sdlOffset)
                let sdl = sdlPtr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                let nameLen = Int(sdl.sdl_nlen)

                if nameLen > 0, let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) {
                    let namePtr = ptr.advanced(by: sdlOffset + dataOffset)
                    let name = String(decoding: UnsafeRawBufferPointer(start: namePtr, count: nameLen), as: UTF8.self)

                    if !name.isEmpty {
                        let flags = UInt32(ifm2.ifm_flags)
                        let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
                        let isUp = (flags & UInt32(IFF_UP)) != 0
                        let bytesIn = UInt64(ifm2.ifm_data.ifi_ibytes)
                        let bytesOut = UInt64(ifm2.ifm_data.ifi_obytes)

                        results.append(
                            RawInterfaceCounters(
                                name: name,
                                bytesIn: bytesIn,
                                bytesOut: bytesOut,
                                isLoopback: isLoopback,
                                isUp: isUp
                            )
                        )
                    }
                }
            }
            ptr = ptr.advanced(by: msgLen)
        }

        return results
    }

    /// Fallback reader using standard BSD `getifaddrs`.
    private func readGetifaddrsCounters() throws -> [RawInterfaceCounters] {
        var ifap: UnsafeMutablePointer<ifaddrs>? = nil
        let result = getifaddrs(&ifap)

        guard result == 0, let first = ifap else {
            throw SamplerError.systemCallFailed("getifaddrs failed with errno: \(errno)")
        }
        defer { freeifaddrs(ifap) }

        var results: [RawInterfaceCounters] = []
        var cur: UnsafeMutablePointer<ifaddrs>? = first

        while let ptr = cur {
            let ifa = ptr.pointee
            let flags = ifa.ifa_flags
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            let isUp = (flags & UInt32(IFF_UP)) != 0

            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                let ifd = data.assumingMemoryBound(to: if_data.self).pointee
                results.append(
                    RawInterfaceCounters(
                        name: name,
                        bytesIn: UInt64(ifd.ifi_ibytes),
                        bytesOut: UInt64(ifd.ifi_obytes),
                        isLoopback: isLoopback,
                        isUp: isUp
                    )
                )
            }
            cur = ifa.ifa_next
        }

        return results
    }
}

/// Interface historical state for rate calculation.
public struct InterfaceState: Sendable, Equatable {
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let timestamp: Date

    public init(bytesIn: UInt64, bytesOut: UInt64, timestamp: Date) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.timestamp = timestamp
    }
}

/// Cumulative session bytes for a network interface.
public struct InterfaceSessionTotal: Sendable, Equatable {
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(bytesIn: UInt64, bytesOut: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Concrete sampler for network throughput and session totals.
///
/// Conforms to `Sampler` (Requirements 6.1, 6.2, 6.3, 6.4). Computes rates using pure `RateMath`
/// and isolates all Darwin system calls off the main thread.
public final class NetworkSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .network

    private let provider: any NetworkInfoProvider
    private let includeLoopback: Bool
    private let lock = NSLock()

    private var previousStates: [String: InterfaceState] = [:]
    private var sessionTotals: [String: InterfaceSessionTotal] = [:]

    public init(
        provider: any NetworkInfoProvider = HostNetworkInfoProvider(),
        includeLoopback: Bool = false
    ) {
        self.provider = provider
        self.includeLoopback = includeLoopback
    }

    /// Samples network metrics. Runs off the main thread.
    public func sample() throws -> NetworkSample {
        let currentCounters = try provider.interfaceCounters()
        let currentTimestamp = Date()

        lock.lock()
        let prev = previousStates
        let totals = sessionTotals

        let (sample, newPrev, newTotals) = Self.calculateSample(
            previous: prev,
            current: currentCounters,
            currentTimestamp: currentTimestamp,
            sessionTotals: totals,
            includeLoopback: includeLoopback
        )

        self.previousStates = newPrev
        self.sessionTotals = newTotals
        lock.unlock()

        return sample
    }

    /// Pure calculation function deriving throughput rates and session totals from counter snapshots.
    public static func calculateSample(
        previous: [String: InterfaceState]?,
        current: [RawInterfaceCounters],
        currentTimestamp: Date,
        sessionTotals: [String: InterfaceSessionTotal]?,
        includeLoopback: Bool = false
    ) -> (sample: NetworkSample, newPrevious: [String: InterfaceState], newSessionTotals: [String: InterfaceSessionTotal]) {
        var newPrevious = previous ?? [:]
        var newSessionTotals = sessionTotals ?? [:]
        var throughputs: [InterfaceThroughput] = []

        // Filter and sort interfaces deterministically
        let activeInterfaces = current
            .filter { includeLoopback || !$0.isLoopback }
            .sorted { $0.name < $1.name }

        for counter in activeInterfaces {
            let name = counter.name
            let currIn = counter.bytesIn
            let currOut = counter.bytesOut

            let rateIn: Double
            let rateOut: Double
            let currentSessionIn: UInt64
            let currentSessionOut: UInt64

            let prevSessionIn = newSessionTotals[name]?.bytesIn ?? 0
            let prevSessionOut = newSessionTotals[name]?.bytesOut ?? 0

            if let prevState = previous?[name], currentTimestamp > prevState.timestamp {
                let elapsed = currentTimestamp.timeIntervalSince(prevState.timestamp)
                let deltaIn = RateMath.counterDelta(previous: prevState.bytesIn, current: currIn)
                let deltaOut = RateMath.counterDelta(previous: prevState.bytesOut, current: currOut)

                rateIn = RateMath.bytesPerSecond(previous: prevState.bytesIn, current: currIn, elapsedSeconds: elapsed)
                rateOut = RateMath.bytesPerSecond(previous: prevState.bytesOut, current: currOut, elapsedSeconds: elapsed)

                currentSessionIn = prevSessionIn + deltaIn
                currentSessionOut = prevSessionOut + deltaOut
            } else {
                // First sample or non-forward clock: rate is 0, session total starts at 0 (or retains previous)
                rateIn = 0.0
                rateOut = 0.0
                currentSessionIn = prevSessionIn
                currentSessionOut = prevSessionOut
            }

            newPrevious[name] = InterfaceState(bytesIn: currIn, bytesOut: currOut, timestamp: currentTimestamp)
            newSessionTotals[name] = InterfaceSessionTotal(bytesIn: currentSessionIn, bytesOut: currentSessionOut)

            throughputs.append(
                InterfaceThroughput(
                    interfaceName: name,
                    bytesInPerSec: rateIn,
                    bytesOutPerSec: rateOut,
                    totalBytesIn: currentSessionIn,
                    totalBytesOut: currentSessionOut
                )
            )
        }

        let sample = NetworkSample(interfaces: throughputs)
        return (sample: sample, newPrevious: newPrevious, newSessionTotals: newSessionTotals)
    }
}
