import Foundation
import Network
import iStatsCore

/// Snapshot of OS network path state + latest cached active packet reachability probe.
public struct ConnectivityMonitorSnapshot: Sendable, Equatable {
    public let isPathSatisfied: Bool?
    public let isConstrained: Bool
    public let isExpensive: Bool
    public let activeInterfaceName: String?
    public let probe: NetworkProbeSnapshot?

    public init(
        isPathSatisfied: Bool? = nil,
        isConstrained: Bool = false,
        isExpensive: Bool = false,
        activeInterfaceName: String? = nil,
        probe: NetworkProbeSnapshot? = nil
    ) {
        self.isPathSatisfied = isPathSatisfied
        self.isConstrained = isConstrained
        self.isExpensive = isExpensive
        self.activeInterfaceName = activeInterfaceName
        self.probe = probe
    }
}

/// Background-only OS path monitor and non-blocking hedged TCP reachability prober.
///
/// Design invariants:
/// - **Zero main-thread calls** (ADR 0002): `NWPathMonitor` and `NWConnection` run on a dedicated
///   serial `.utility` background `DispatchQueue`.
/// - **Zero blocking on `snapshot()`**: `NetworkSampler.sample()` reads an `NSLock`-protected cache
///   in microseconds and only dispatches an async probe when `probeInterval` has elapsed and the
///   OS path is satisfied. When sampling is paused or Network is disabled, zero probes fire.
/// - **Zero telemetry transmission** (ADR 0006): Performs only a bare TCP handshake (SYN → SYN-ACK
///   → immediate cancel) to public anycast endpoints (`1.1.1.1:443`, hedged fallback `8.8.8.8:443`).
///   Zero application payload, zero HTTP headers, zero user/device data.
public final class NetworkConnectivityMonitor: @unchecked Sendable {

    /// Shared singleton monitor reused by `HostNetworkInfoProvider`.
    public static let shared = NetworkConnectivityMonitor()

    public struct ProbeEndpoint: Sendable, Equatable {
        public let host: String
        public let port: UInt16
        public var label: String { "\(host):\(port)" }

        public init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }
    }

    public static let defaultEndpoints: [ProbeEndpoint] = [
        ProbeEndpoint(host: "1.1.1.1", port: 443),
        ProbeEndpoint(host: "8.8.8.8", port: 443)
    ]

    private let queue = DispatchQueue(label: "com.istats.network.connectivity", qos: .utility)
    private let lock = NSLock()
    private let endpoints: [ProbeEndpoint]
    private let probeInterval: TimeInterval
    private let hedgeDelay: TimeInterval
    private let probeTimeout: TimeInterval
    private let windowCapacity: Int
    private let enableSystemPathMonitor: Bool
    private let enableActiveProbing: Bool

    private var pathMonitor: NWPathMonitor?
    private var isStarted: Bool = false

    // Lock-protected cached state
    private var pathSatisfied: Bool? = nil
    private var isConstrained: Bool = false
    private var isExpensive: Bool = false
    private var activeInterfaceName: String? = nil
    private var probeInFlight: Bool = false
    private var lastProbeStart: Date = .distantPast
    private var probeWindow: [Double?] = [] // nil = failed probe, Double = RTT ms
    private var latestProbe: NetworkProbeSnapshot? = nil
    private var pathGeneration: UInt64 = 0
    private var onPathChangedHandler: (@Sendable () -> Void)?

    public init(
        endpoints: [ProbeEndpoint] = NetworkConnectivityMonitor.defaultEndpoints,
        probeInterval: TimeInterval = 2.0,
        hedgeDelay: TimeInterval = 0.75,
        probeTimeout: TimeInterval = 2.0,
        windowCapacity: Int = 8,
        enableSystemPathMonitor: Bool = true,
        enableActiveProbing: Bool = true
    ) {
        self.endpoints = endpoints.isEmpty ? Self.defaultEndpoints : endpoints
        self.probeInterval = max(0.5, probeInterval)
        self.hedgeDelay = max(0.1, hedgeDelay)
        self.probeTimeout = max(0.5, probeTimeout)
        self.windowCapacity = max(1, windowCapacity)
        self.enableSystemPathMonitor = enableSystemPathMonitor
        self.enableActiveProbing = enableActiveProbing
    }

    deinit {
        stop()
    }

    /// Registers a callback invoked off-main-thread whenever `NWPathMonitor` reports a path change.
    public func setOnPathChanged(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        self.onPathChangedHandler = handler
        lock.unlock()
    }

    /// Starts the background `NWPathMonitor` if not already running. Safe to call multiple times.
    public func startIfNeeded() {
        lock.lock()
        if isStarted || !enableSystemPathMonitor {
            lock.unlock()
            return
        }
        isStarted = true
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(
                isSatisfied: path.status == .satisfied,
                isConstrained: path.isConstrained,
                isExpensive: path.isExpensive,
                activeInterfaceName: path.availableInterfaces.first?.name
            )
        }
        monitor.start(queue: queue)
    }

    /// Stops the background `NWPathMonitor`.
    public func stop() {
        lock.lock()
        let monitor = pathMonitor
        pathMonitor = nil
        isStarted = false
        lock.unlock()
        monitor?.cancel()
    }

    /// Non-blocking snapshot read for `NetworkSampler`.
    /// Optionally dispatches an asynchronous reachability probe off the calling thread when due.
    public func snapshot(triggerProbeIfDue: Bool = true) -> ConnectivityMonitorSnapshot {
        startIfNeeded()

        lock.lock()
        let snap = ConnectivityMonitorSnapshot(
            isPathSatisfied: pathSatisfied,
            isConstrained: isConstrained,
            isExpensive: isExpensive,
            activeInterfaceName: activeInterfaceName,
            probe: latestProbe
        )

        var shouldDispatchProbe = false
        var generation: UInt64 = 0
        if triggerProbeIfDue && enableActiveProbing {
            let canProbe = (pathSatisfied ?? true)
            let now = Date()
            if canProbe && !probeInFlight && now.timeIntervalSince(lastProbeStart) >= probeInterval {
                probeInFlight = true
                lastProbeStart = now
                generation = pathGeneration
                shouldDispatchProbe = true
            }
        }
        lock.unlock()

        if shouldDispatchProbe {
            let capturedGeneration = generation
            queue.async { [weak self] in
                self?.runHedgedTCPProbe(generation: capturedGeneration)
            }
        }

        return snap
    }

    // MARK: - Testable State Transitions

    /// Applies an OS path transition (called by `NWPathMonitor` or directly in unit tests).
    public func handlePathUpdate(
        isSatisfied: Bool,
        isConstrained: Bool = false,
        isExpensive: Bool = false,
        activeInterfaceName: String? = nil
    ) {
        lock.lock()
        let previousSatisfied = self.pathSatisfied
        let previousInterface = self.activeInterfaceName
        let changed = (previousSatisfied != isSatisfied) || (previousInterface != activeInterfaceName)

        self.pathSatisfied = isSatisfied
        self.isConstrained = isConstrained
        self.isExpensive = isExpensive
        self.activeInterfaceName = activeInterfaceName

        var shouldTriggerImmediateProbe = false
        var generation = self.pathGeneration

        if !isSatisfied {
            // Instant disconnect: clear stale probe success so UI turns red immediately.
            self.pathGeneration &+= 1
            generation = self.pathGeneration
            self.probeInFlight = false
            self.probeWindow.removeAll(keepingCapacity: true)
            self.latestProbe = NetworkProbeSnapshot(
                isReachable: false,
                latencyMs: nil,
                endpoint: nil,
                packetLossPercent: 100.0,
                jitterMs: nil,
                consecutiveFailures: 1,
                windowSampleCount: 1,
                failureReason: "Network path unavailable",
                timestamp: Date()
            )
        } else if changed {
            // Newly connected or switched interface (e.g. Wi-Fi -> Ethernet): reset old window & probe immediately.
            self.pathGeneration &+= 1
            generation = self.pathGeneration
            self.probeWindow.removeAll(keepingCapacity: true)
            self.latestProbe = nil
            self.lastProbeStart = .distantPast
            if enableActiveProbing {
                self.probeInFlight = true
                self.lastProbeStart = Date()
                shouldTriggerImmediateProbe = true
            }
        }

        let callback = changed ? onPathChangedHandler : nil
        lock.unlock()

        callback?()

        if shouldTriggerImmediateProbe {
            let capturedGeneration = generation
            queue.async { [weak self] in
                self?.runHedgedTCPProbe(generation: capturedGeneration)
            }
        }
    }

    /// Records a completed probe outcome into the rolling window and updates `latestProbe`.
    /// Exposed internally/publicly for deterministic unit testing of loss/jitter/recovery.
    public func recordProbeOutcome(
        isReachable: Bool,
        latencyMs: Double? = nil,
        endpoint: String? = nil,
        failureReason: String? = nil,
        generation: UInt64? = nil,
        timestamp: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        if let expectedGen = generation, expectedGen != self.pathGeneration {
            // Stale probe from before a network interface switch / disconnect; discard.
            self.probeInFlight = false
            return
        }

        self.probeInFlight = false

        // If path is now unsatisfied, keep disconnected snapshot rather than recording stale success.
        if self.pathSatisfied == false {
            return
        }

        let rttEntry: Double? = isReachable ? max(0.1, latencyMs ?? 1.0) : nil
        self.probeWindow.append(rttEntry)
        if self.probeWindow.count > windowCapacity {
            self.probeWindow.removeFirst(self.probeWindow.count - windowCapacity)
        }

        let stats = NetworkConnectionEvaluator.computeWindowStats(from: self.probeWindow)
        self.latestProbe = NetworkProbeSnapshot(
            isReachable: isReachable,
            latencyMs: rttEntry,
            endpoint: endpoint,
            packetLossPercent: stats.packetLossPercent,
            jitterMs: stats.jitterMs,
            consecutiveFailures: stats.consecutiveFailures,
            windowSampleCount: self.probeWindow.count,
            failureReason: isReachable ? nil : (failureReason ?? "No packet response"),
            timestamp: timestamp
        )
    }

    // MARK: - Hedged Non-Blocking TCP Handshake Probe (Serial Queue Only)

    /// Executes a lightweight TCP SYN/SYN-ACK probe on `self.queue`.
    /// Starts primary endpoint immediately; hedges to fallback after `hedgeDelay` (or immediately on primary error).
    private func runHedgedTCPProbe(generation: UInt64) {
        let primaryEndpoint = endpoints[0]
        let fallbackEndpoint = endpoints.count > 1 ? endpoints[1] : nil
        let runner = HedgedProbeRunner(
            monitor: self,
            queue: queue,
            primaryEndpoint: primaryEndpoint,
            fallbackEndpoint: fallbackEndpoint,
            hedgeDelay: hedgeDelay,
            probeTimeout: probeTimeout,
            generation: generation
        )
        runner.start()
    }

    private final class HedgedProbeRunner: @unchecked Sendable {
        private weak var monitor: NetworkConnectivityMonitor?
        private let queue: DispatchQueue
        private let primaryEndpoint: ProbeEndpoint
        private let fallbackEndpoint: ProbeEndpoint?
        private let hedgeDelay: TimeInterval
        private let probeTimeout: TimeInterval
        private let generation: UInt64

        private var finished = false
        private var primaryFailed = false
        private var fallbackStarted = false
        private var fallbackFailed = false
        private var primaryConn: NWConnection?
        private var fallbackConn: NWConnection?
        private var hedgeWorkItem: DispatchWorkItem?
        private var timeoutWorkItem: DispatchWorkItem?

        init(
            monitor: NetworkConnectivityMonitor,
            queue: DispatchQueue,
            primaryEndpoint: ProbeEndpoint,
            fallbackEndpoint: ProbeEndpoint?,
            hedgeDelay: TimeInterval,
            probeTimeout: TimeInterval,
            generation: UInt64
        ) {
            self.monitor = monitor
            self.queue = queue
            self.primaryEndpoint = primaryEndpoint
            self.fallbackEndpoint = fallbackEndpoint
            self.hedgeDelay = hedgeDelay
            self.probeTimeout = probeTimeout
            self.generation = generation
        }

        func start() {
            guard let conn = makeConnection(to: primaryEndpoint) else {
                finish(isReachable: false, latencyMs: nil, endpoint: primaryEndpoint.label, failureReason: "Invalid probe endpoint")
                return
            }

            primaryConn = conn
            let primaryStart = CFAbsoluteTimeGetCurrent()

            conn.stateUpdateHandler = { [self] connState in
                switch connState {
                case .ready:
                    let rttMs = (CFAbsoluteTimeGetCurrent() - primaryStart) * 1000.0
                    finish(isReachable: true, latencyMs: rttMs, endpoint: primaryEndpoint.label, failureReason: nil)
                case .waiting(let err), .failed(let err):
                    primaryFailed = true
                    conn.cancel()
                    if fallbackEndpoint == nil || fallbackFailed {
                        finish(isReachable: false, latencyMs: nil, endpoint: primaryEndpoint.label, failureReason: NetworkConnectivityMonitor.describeNWError(err))
                    } else {
                        startFallback()
                    }
                default:
                    break
                }
            }

            if fallbackEndpoint != nil {
                let hedgeItem = DispatchWorkItem { [self] in
                    startFallback()
                }
                hedgeWorkItem = hedgeItem
                queue.asyncAfter(deadline: .now() + hedgeDelay, execute: hedgeItem)
            }

            let timeoutItem = DispatchWorkItem { [self] in
                finish(isReachable: false, latencyMs: nil, endpoint: primaryEndpoint.label, failureReason: "Timeout — no packet response")
            }
            timeoutWorkItem = timeoutItem
            queue.asyncAfter(deadline: .now() + probeTimeout, execute: timeoutItem)

            conn.start(queue: queue)
        }

        private func startFallback() {
            guard !finished, !fallbackStarted else { return }
            guard let fallback = fallbackEndpoint, let conn = makeConnection(to: fallback) else {
                fallbackFailed = true
                if primaryFailed {
                    finish(isReachable: false, latencyMs: nil, endpoint: primaryEndpoint.label, failureReason: "No packet response")
                }
                return
            }

            fallbackStarted = true
            fallbackConn = conn
            let fallbackStart = CFAbsoluteTimeGetCurrent()

            conn.stateUpdateHandler = { [self] connState in
                switch connState {
                case .ready:
                    let rttMs = (CFAbsoluteTimeGetCurrent() - fallbackStart) * 1000.0
                    finish(isReachable: true, latencyMs: rttMs, endpoint: fallback.label, failureReason: nil)
                case .waiting(let err), .failed(let err):
                    fallbackFailed = true
                    conn.cancel()
                    if primaryFailed {
                        finish(isReachable: false, latencyMs: nil, endpoint: fallback.label, failureReason: NetworkConnectivityMonitor.describeNWError(err))
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }

        private func makeConnection(to target: ProbeEndpoint) -> NWConnection? {
            guard let port = NWEndpoint.Port(rawValue: target.port) else { return nil }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let host = NWEndpoint.Host(target.host)
            return NWConnection(host: host, port: port, using: params)
        }

        private func finish(isReachable: Bool, latencyMs: Double?, endpoint: String?, failureReason: String?) {
            guard !finished else { return }
            finished = true
            hedgeWorkItem?.cancel()
            timeoutWorkItem?.cancel()
            hedgeWorkItem = nil
            timeoutWorkItem = nil
            primaryConn?.stateUpdateHandler = nil
            fallbackConn?.stateUpdateHandler = nil
            primaryConn?.cancel()
            fallbackConn?.cancel()
            primaryConn = nil
            fallbackConn = nil

            monitor?.recordProbeOutcome(
                isReachable: isReachable,
                latencyMs: latencyMs,
                endpoint: endpoint,
                failureReason: failureReason,
                generation: generation
            )
        }
    }

    private static func describeNWError(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ENETDOWN, .ENETUNREACH:
                return "Network unreachable"
            case .EHOSTDOWN, .EHOSTUNREACH:
                return "Host unreachable"
            case .ECONNREFUSED, .ECONNRESET:
                return "Connection refused"
            case .ETIMEDOUT:
                return "Connection timed out"
            default:
                return "No packet response"
            }
        default:
            return "No packet response"
        }
    }
}
