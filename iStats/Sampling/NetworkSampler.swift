import Foundation
import Darwin
import SystemConfiguration
import CoreWLAN
import iStatsCore

/// Raw byte and packet counter snapshot for a single network interface.
public struct RawInterfaceCounters: Sendable, Equatable {
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let packetsIn: UInt64
    public let packetsOut: UInt64
    public let errorsIn: UInt64
    public let errorsOut: UInt64
    public let dropsIn: UInt64
    public let isLoopback: Bool
    public let isUp: Bool
    public let isRunning: Bool

    public init(
        name: String,
        bytesIn: UInt64,
        bytesOut: UInt64,
        packetsIn: UInt64 = 0,
        packetsOut: UInt64 = 0,
        errorsIn: UInt64 = 0,
        errorsOut: UInt64 = 0,
        dropsIn: UInt64 = 0,
        isLoopback: Bool = false,
        isUp: Bool = true,
        isRunning: Bool = true
    ) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.packetsIn = packetsIn
        self.packetsOut = packetsOut
        self.errorsIn = errorsIn
        self.errorsOut = errorsOut
        self.dropsIn = dropsIn
        self.isLoopback = isLoopback
        self.isUp = isUp
        self.isRunning = isRunning
    }
}

/// Active network connectivity snapshot (primary interface, routing, IP addresses, Wi-Fi link, and reachability probe).
public struct RawNetworkConnectivity: Sendable, Equatable {
    public let primaryInterface: String?
    public let routerIPv4: String?
    public let primaryDNS: String?
    public let interfaceIPs: [String: String]
    public let wifiTelemetry: WiFiLinkTelemetry?
    public let isPathSatisfied: Bool?
    public let isConstrained: Bool
    public let probeSnapshot: NetworkProbeSnapshot?

    public init(
        primaryInterface: String? = nil,
        routerIPv4: String? = nil,
        primaryDNS: String? = nil,
        interfaceIPs: [String: String] = [:],
        wifiTelemetry: WiFiLinkTelemetry? = nil,
        isPathSatisfied: Bool? = nil,
        isConstrained: Bool = false,
        probeSnapshot: NetworkProbeSnapshot? = nil
    ) {
        self.primaryInterface = primaryInterface
        self.routerIPv4 = routerIPv4
        self.primaryDNS = primaryDNS
        self.interfaceIPs = interfaceIPs
        self.wifiTelemetry = wifiTelemetry
        self.isPathSatisfied = isPathSatisfied
        self.isConstrained = isConstrained
        self.probeSnapshot = probeSnapshot
    }
}

/// Abstract provider for reading network interface counters and connectivity.
public protocol NetworkInfoProvider: Sendable {
    /// Returns raw counter snapshots for all network interfaces on the system.
    func interfaceCounters() throws -> [RawInterfaceCounters]

    /// Returns active routing, local IP addresses, and Wi-Fi link telemetry.
    func networkConnectivity() throws -> RawNetworkConnectivity
}

public extension NetworkInfoProvider {
    func networkConnectivity() throws -> RawNetworkConnectivity {
        RawNetworkConnectivity()
    }
}

/// Darwin `sysctl(NET_RT_IFLIST2)` and `getifaddrs` implementation of `NetworkInfoProvider`.
public struct HostNetworkInfoProvider: NetworkInfoProvider {
    private let connectivityMonitor: NetworkConnectivityMonitor

    public init(connectivityMonitor: NetworkConnectivityMonitor = .shared) {
        self.connectivityMonitor = connectivityMonitor
        connectivityMonitor.setOnPathChanged {
            Self.invalidateWiFiCache()
        }
    }

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
                        let isRunning = (flags & UInt32(IFF_RUNNING)) != 0
                        let bytesIn = UInt64(ifm2.ifm_data.ifi_ibytes)
                        let bytesOut = UInt64(ifm2.ifm_data.ifi_obytes)
                        let packetsIn = UInt64(ifm2.ifm_data.ifi_ipackets)
                        let packetsOut = UInt64(ifm2.ifm_data.ifi_opackets)
                        let errorsIn = UInt64(ifm2.ifm_data.ifi_ierrors)
                        let errorsOut = UInt64(ifm2.ifm_data.ifi_oerrors)
                        let dropsIn = UInt64(ifm2.ifm_data.ifi_iqdrops)

                        results.append(
                            RawInterfaceCounters(
                                name: name,
                                bytesIn: bytesIn,
                                bytesOut: bytesOut,
                                packetsIn: packetsIn,
                                packetsOut: packetsOut,
                                errorsIn: errorsIn,
                                errorsOut: errorsOut,
                                dropsIn: dropsIn,
                                isLoopback: isLoopback,
                                isUp: isUp,
                                isRunning: isRunning
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
            let isRunning = (flags & UInt32(IFF_RUNNING)) != 0

            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                let ifd = data.assumingMemoryBound(to: if_data.self).pointee
                results.append(
                    RawInterfaceCounters(
                        name: name,
                        bytesIn: UInt64(ifd.ifi_ibytes),
                        bytesOut: UInt64(ifd.ifi_obytes),
                        packetsIn: UInt64(ifd.ifi_ipackets),
                        packetsOut: UInt64(ifd.ifi_opackets),
                        errorsIn: UInt64(ifd.ifi_ierrors),
                        errorsOut: UInt64(ifd.ifi_oerrors),
                        dropsIn: UInt64(ifd.ifi_iqdrops),
                        isLoopback: isLoopback,
                        isUp: isUp,
                        isRunning: isRunning
                    )
                )
            }
            cur = ifa.ifa_next
        }

        return results
    }

    /// Reads active network routing, local IP addresses, Wi-Fi link parameters, and non-blocking reachability probe state.
    public func networkConnectivity() throws -> RawNetworkConnectivity {
        let monitorSnapshot = connectivityMonitor.snapshot(triggerProbeIfDue: true)

        var primaryInterface: String? = nil
        var routerIPv4: String? = nil
        var primaryDNS: String? = nil

        if let store = Self.getSCStore() {
            if let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
                primaryInterface = ipv4["PrimaryInterface"] as? String
                routerIPv4 = ipv4["Router"] as? String
            }
            if primaryInterface == nil,
               let ipv6 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any] {
                primaryInterface = ipv6["PrimaryInterface"] as? String
            }
            if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
                if let servers = dns["ServerAddresses"] as? [String], let first = servers.first {
                    primaryDNS = first
                }
            }
        }

        if primaryInterface == nil, monitorSnapshot.isPathSatisfied == true {
            primaryInterface = monitorSnapshot.activeInterfaceName
        }

        var interfaceIPs: [String: String] = [:]
        var ifap: UnsafeMutablePointer<ifaddrs>? = nil
        if getifaddrs(&ifap) == 0, let first = ifap {
            defer { freeifaddrs(ifap) }
            var cur: UnsafeMutablePointer<ifaddrs>? = first
            while let p = cur {
                let name = String(cString: p.pointee.ifa_name)
                if let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if !ip.hasPrefix("127.") && interfaceIPs[name] == nil {
                            interfaceIPs[name] = ip
                        }
                    }
                }
                cur = p.pointee.ifa_next
            }
        }

        // Invalidate Wi-Fi telemetry cache immediately if path became unsatisfied or primary interface disappeared.
        let wifiTelemetry: WiFiLinkTelemetry?
        if monitorSnapshot.isPathSatisfied == false {
            Self.invalidateWiFiCache()
            wifiTelemetry = nil
        } else {
            wifiTelemetry = Self.queryWiFiTelemetryThrottled(primaryInterface: primaryInterface)
        }

        return RawNetworkConnectivity(
            primaryInterface: primaryInterface,
            routerIPv4: routerIPv4,
            primaryDNS: primaryDNS,
            interfaceIPs: interfaceIPs,
            wifiTelemetry: wifiTelemetry,
            isPathSatisfied: monitorSnapshot.isPathSatisfied,
            isConstrained: monitorSnapshot.isConstrained,
            probeSnapshot: monitorSnapshot.probe
        )
    }

    // MARK: - Caching & Throttling Helpers

    private static let scStoreLock = NSLock()
    nonisolated(unsafe) private static var cachedSCStore: SCDynamicStore? = {
        SCDynamicStoreCreate(nil, "iStatsNetworkSampler" as CFString, nil, nil)
    }()

    private static func getSCStore() -> SCDynamicStore? {
        scStoreLock.lock()
        defer { scStoreLock.unlock() }
        if let store = cachedSCStore {
            return store
        }
        let store = SCDynamicStoreCreate(nil, "iStatsNetworkSampler" as CFString, nil, nil)
        cachedSCStore = store
        return store
    }

    private static let wifiCacheLock = NSLock()
    nonisolated(unsafe) private static var lastWiFiQuery: Date?
    nonisolated(unsafe) private static var lastWiFiPrimaryInterface: String?
    nonisolated(unsafe) private static var cachedWiFiTelemetry: WiFiLinkTelemetry?

    private static func invalidateWiFiCache() {
        wifiCacheLock.lock()
        lastWiFiQuery = nil
        cachedWiFiTelemetry = nil
        wifiCacheLock.unlock()
    }

    private static func queryWiFiTelemetryThrottled(primaryInterface: String?) -> WiFiLinkTelemetry? {
        wifiCacheLock.lock()
        defer { wifiCacheLock.unlock() }

        let now = Date()
        if lastWiFiPrimaryInterface == primaryInterface,
           let last = lastWiFiQuery,
           now.timeIntervalSince(last) < 10.0 {
            return cachedWiFiTelemetry
        }

        let telemetry = queryWiFiTelemetryDirect()
        cachedWiFiTelemetry = telemetry
        lastWiFiPrimaryInterface = primaryInterface
        lastWiFiQuery = now
        return telemetry
    }

    private static func queryWiFiTelemetryDirect() -> WiFiLinkTelemetry? {
        guard let iface = CWWiFiClient.shared().interface(), iface.powerOn() else {
            return nil
        }
        let rawRssi = iface.rssiValue()
        let rssi: Int? = rawRssi != 0 ? rawRssi : nil
        let rawNoise = iface.noiseMeasurement()
        let noise: Int? = rawNoise != 0 ? rawNoise : nil
        let rawRate = iface.transmitRate()
        let txRate: Double? = rawRate > 0 ? rawRate : nil
        let channelNum = iface.wlanChannel()?.channelNumber
        let rawBand = iface.wlanChannel()?.channelBand
        let bandStr: String?
        if let band = rawBand {
            switch band {
            case .band2GHz: bandStr = "2.4 GHz"
            case .band5GHz: bandStr = "5 GHz"
            case .band6GHz: bandStr = "6 GHz"
            default: bandStr = nil
            }
        } else {
            bandStr = nil
        }
        let rawSSID = iface.ssid()
        let ssid: String? = (rawSSID != nil && !rawSSID!.trimmingCharacters(in: .whitespaces).isEmpty) ? rawSSID : nil

        if rssi != nil || txRate != nil || channelNum != nil {
            return WiFiLinkTelemetry(
                ssid: ssid,
                rssi: rssi,
                noise: noise,
                txRate: txRate,
                channel: channelNum,
                band: bandStr
            )
        }
        return nil
    }
}

/// Interface historical state for rate and packet-error delta calculation.
public struct InterfaceState: Sendable, Equatable {
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let packetsIn: UInt64
    public let packetsOut: UInt64
    public let errorsIn: UInt64
    public let errorsOut: UInt64
    public let dropsIn: UInt64
    public let timestamp: Date

    public init(
        bytesIn: UInt64,
        bytesOut: UInt64,
        packetsIn: UInt64 = 0,
        packetsOut: UInt64 = 0,
        errorsIn: UInt64 = 0,
        errorsOut: UInt64 = 0,
        dropsIn: UInt64 = 0,
        timestamp: Date
    ) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.packetsIn = packetsIn
        self.packetsOut = packetsOut
        self.errorsIn = errorsIn
        self.errorsOut = errorsOut
        self.dropsIn = dropsIn
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
        let connectivity = (try? provider.networkConnectivity()) ?? RawNetworkConnectivity()
        let currentTimestamp = Date()

        lock.lock()
        let prev = previousStates
        let totals = sessionTotals

        let (sample, newPrev, newTotals) = Self.calculateSample(
            previous: prev,
            current: currentCounters,
            currentTimestamp: currentTimestamp,
            sessionTotals: totals,
            includeLoopback: includeLoopback,
            connectivity: connectivity
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
        includeLoopback: Bool = false,
        connectivity: RawNetworkConnectivity = RawNetworkConnectivity()
    ) -> (sample: NetworkSample, newPrevious: [String: InterfaceState], newSessionTotals: [String: InterfaceSessionTotal]) {
        var newPrevious = previous ?? [:]
        var newSessionTotals = sessionTotals ?? [:]
        var throughputs: [InterfaceThroughput] = []

        // Filter and sort interfaces deterministically
        let activeInterfaces = current
            .filter { includeLoopback || !$0.isLoopback }
            .sorted { $0.name < $1.name }

        let primaryIface = connectivity.primaryInterface
        var primaryPacketsInDelta: UInt64 = 0
        var primaryPacketsOutDelta: UInt64 = 0
        var primaryErrorDelta: UInt64 = 0

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

                if name == primaryIface {
                    primaryPacketsInDelta = RateMath.counterDelta(previous: prevState.packetsIn, current: counter.packetsIn)
                    primaryPacketsOutDelta = RateMath.counterDelta(previous: prevState.packetsOut, current: counter.packetsOut)
                    primaryErrorDelta = RateMath.counterDelta(previous: prevState.errorsIn, current: counter.errorsIn)
                        + RateMath.counterDelta(previous: prevState.errorsOut, current: counter.errorsOut)
                        + RateMath.counterDelta(previous: prevState.dropsIn, current: counter.dropsIn)
                }
            } else {
                // First sample or non-forward clock: rate is 0, session total starts at 0 (or retains previous)
                rateIn = 0.0
                rateOut = 0.0
                currentSessionIn = prevSessionIn
                currentSessionOut = prevSessionOut
            }

            newPrevious[name] = InterfaceState(
                bytesIn: currIn,
                bytesOut: currOut,
                packetsIn: counter.packetsIn,
                packetsOut: counter.packetsOut,
                errorsIn: counter.errorsIn,
                errorsOut: counter.errorsOut,
                dropsIn: counter.dropsIn,
                timestamp: currentTimestamp
            )
            newSessionTotals[name] = InterfaceSessionTotal(bytesIn: currentSessionIn, bytesOut: currentSessionOut)

            let ip = connectivity.interfaceIPs[name]
            throughputs.append(
                InterfaceThroughput(
                    interfaceName: name,
                    bytesInPerSec: rateIn,
                    bytesOutPerSec: rateOut,
                    totalBytesIn: currentSessionIn,
                    totalBytesOut: currentSessionOut,
                    ipv4Address: ip,
                    type: NetworkConnectionType.infer(from: name)
                )
            )
        }

        let primaryIP = primaryIface != nil ? connectivity.interfaceIPs[primaryIface!] : nil
        let primaryType = primaryIface != nil ? NetworkConnectionType.infer(from: primaryIface!) : nil
        let resolvedPathSatisfied = connectivity.isPathSatisfied ?? (primaryIface != nil && primaryIP != nil)

        let connectionHealth = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: resolvedPathSatisfied,
            isConstrained: connectivity.isConstrained,
            primaryInterface: primaryIface,
            primaryType: primaryType,
            localIPv4: primaryIP,
            wifiDetails: connectivity.wifiTelemetry,
            probe: connectivity.probeSnapshot,
            primaryPacketsInDelta: primaryPacketsInDelta,
            primaryPacketsOutDelta: primaryPacketsOutDelta,
            interfaceErrorDelta: primaryErrorDelta
        )

        let sample = NetworkSample(
            interfaces: throughputs,
            primaryInterface: primaryIface,
            primaryType: primaryType,
            localIPv4: primaryIP,
            gatewayIPv4: connectivity.routerIPv4,
            primaryDNS: connectivity.primaryDNS,
            wifiDetails: connectivity.wifiTelemetry,
            connectionHealth: connectionHealth
        )
        return (sample: sample, newPrevious: newPrevious, newSessionTotals: newSessionTotals)
    }
}
