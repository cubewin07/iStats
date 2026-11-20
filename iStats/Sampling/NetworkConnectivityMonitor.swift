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
    private let backgroundProbeInterval: TimeInterval
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
    private var isForegroundProbing: Bool = false
    private var probeInFlight: Bool = false
    private var lastProbeStart: Date = .distantPast
    private var probeWindow: [Double?] = [] // nil = failed probe, Double = RTT ms
    private var latestProbe: NetworkProbeSnapshot? = nil
    private var pathGeneration: UInt64 = 0
    private var activeRunner: HedgedProbeRunner?
    private var onPathChangedHandlers: [String: @Sendable () -> Void] = [:]

    public init(
        endpoints: [ProbeEndpoint] = NetworkConnectivityMonitor.defaultEndpoints,
        probeInterval: TimeInterval = 5.0,
        backgroundProbeInterval: TimeInterval = 60.0,
        hedgeDelay: TimeInterval = 0.75,
        probeTimeout: TimeInterval = 2.0,
        windowCapacity: Int = 8,
        enableSystemPathMonitor: Bool = true,
        enableActiveProbing: Bool = true,
        foregroundProbing: Bool = false
    ) {
        self.endpoints = endpoints.isEmpty ? Self.defaultEndpoints : endpoints
        self.probeInterval = max(0.5, probeInterval)
        self.backgroundProbeInterval = max(5.0, backgroundProbeInterval)
        self.hedgeDelay = max(0.1, hedgeDelay)
        self.probeTimeout = max(0.5, probeTimeout)
        self.windowCapacity = max(1, windowCapacity)
        self.enableSystemPathMonitor = enableSystemPathMonitor
        self.enableActiveProbing = enableActiveProbing
        self.isForegroundProbing = foregroundProbing
    }

    deinit {
        stop()
    }

    /// Enables or disables periodic active TCP probing while the Network panel is visible.
    /// When `false`, periodic 24/7 probing is suppressed; probes only run on path transitions or stalled traffic.
    public func setForegroundProbing(_ active: Bool) {
        lock.lock()
        self.isForegroundProbing = active
        lock.unlock()
    }

    /// Registers a keyed callback invoked off-main-thread whenever `NWPathMonitor` reports a path change.
    public func addOnPathChanged(key: String, handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.onPathChangedHandlers[key] = handler
        lock.unlock()
    }

    /// Registers an anonymous path-change callback and returns its removal token.
    @discardableResult
    public func addOnPathChanged(_ handler: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        self.onPathChangedHandlers[id.uuidString] = handler
        lock.unlock()
        return id
    }

    /// Removes a previously registered path-change callback.
    public func removeOnPathChanged(_ id: UUID) {
        lock.lock()
        self.onPathChangedHandlers.removeValue(forKey: id.uuidString)
        lock.unlock()
    }

    /// Replaces the legacy unnamed path-change callback without disturbing keyed observers.
    public func setOnPathChanged(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        if let handler {
            self.onPathChangedHandlers["__legacy__"] = handler
        } else {
            self.onPathChangedHandlers.removeValue(forKey: "__legacy__")
        }
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

    /// Stops the background `NWPathMonitor` and cancels any in-flight probe connections.
    public func stop() {
        lock.lock()
        let monitor = pathMonitor
        let runner = activeRunner
        pathMonitor = nil
        activeRunner = nil
        probeInFlight = false
        isStarted = false
        lock.unlock()
        runner?.cancel()
        monitor?.cancel()
    }

    /// Non-blocking snapshot read for `NetworkSampler`.
    /// Dispatches an asynchronous reachability probe only when `NWPathMonitor` has confirmed a satisfied
    /// path and either the Network panel is actively open or traffic appears stalled.
    public func snapshot(triggerProbeIfDue: Bool = true, isTrafficStalled: Bool = false) -> ConnectivityMonitorSnapshot {
        startIfNeeded()

        lock.lock()
        let snap = ConnectivityMonitorSnapshot(
            isPathSatisfied: pathSatisfied,
            isConstrained: isConstrained,
            isExpensive: isExpensive,
            activeInterfaceName: activeInterfaceName,
            probe: latestProbe
        )

        var runnerToStart: HedgedProbeRunner?
        if triggerProbeIfDue && enableActiveProbing {
            let canProbe = (pathSatisfied == true)
            let now = Date()
            let requiredInterval: TimeInterval?
            if isForegroundProbing {
                requiredInterval = probeInterval
            } else if isTrafficStalled {
                requiredInterval = backgroundProbeInterval
            } else {
                requiredInterval = nil
            }

            if canProbe,
               let requiredInterval,
               !probeInFlight,
               now.timeIntervalSince(lastProbeStart) >= requiredInterval {
                probeInFlight = true
                lastProbeStart = now
                let runner = makeRunner(generation: pathGeneration)
                activeRunner = runner
                runnerToStart = runner
            }
        }
        lock.unlock()

        if let runnerToStart {
            queue.async {
                runnerToStart.start()
            }
        }

        return snap
    }

    /// Returns whether a periodic probe would be eligible to fire right now under current gating rules (for tests).
    internal func wouldTriggerProbe(now: Date = Date(), isTrafficStalled: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard enableActiveProbing, pathSatisfied == true, !probeInFlight else { return false }
        if isForegroundProbing {
            return now.timeIntervalSince(lastProbeStart) >= probeInterval
        }
        if isTrafficStalled {
            return now.timeIntervalSince(lastProbeStart) >= backgroundProbeInterval
        }
        return false
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

        var runnerToCancel: HedgedProbeRunner?
        var runnerToStart: HedgedProbeRunner?

        if !isSatisfied {
            // Instant disconnect: cancel any in-flight probe and clear stale probe success so UI turns red immediately.
            self.pathGeneration &+= 1
            runnerToCancel = self.activeRunner
            self.activeRunner = nil
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
            // Newly connected or switched interface (e.g. Wi-Fi -> Ethernet): cancel old runner, reset window & probe once.
            self.pathGeneration &+= 1
            runnerToCancel = self.activeRunner
            self.activeRunner = nil
            self.probeWindow.removeAll(keepingCapacity: true)
            self.latestProbe = nil
            self.lastProbeStart = .distantPast
            if enableActiveProbing {
                self.probeInFlight = true
                self.lastProbeStart = Date()
                let runner = makeRunner(generation: self.pathGeneration)
                self.activeRunner = runner
                runnerToStart = runner
            }
        }

        let callbacks = changed ? Array(onPathChangedHandlers.values) : []
        lock.unlock()

        runnerToCancel?.cancel()

        for callback in callbacks {
            callback()
        }

        if let runnerToStart {
            queue.async {
                runnerToStart.start()
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

    private func makeRunner(generation: UInt64) -> HedgedProbeRunner {
        let primaryEndpoint = endpoints[0]
        let fallbackEndpoint = endpoints.count > 1 ? endpoints[1] : nil
        return HedgedProbeRunner(
            monitor: self,
            queue: queue,
            primaryEndpoint: primaryEndpoint,
            fallbackEndpoint: fallbackEndpoint,
            hedgeDelay: hedgeDelay,
            probeTimeout: probeTimeout,
            generation: generation
        )
    }

    private func clearActiveRunner(_ runner: HedgedProbeRunner, generation: UInt64) {
        lock.lock()
        if generation == pathGeneration && activeRunner === runner {
            activeRunner = nil
        }
        lock.unlock()
    }

    private final class HedgedProbeRunner: @unchecked Sendable {
        private weak var monitor: NetworkConnectivityMonitor?
        private let queue: DispatchQueue
        private let primaryEndpoint: ProbeEndpoint
        private let fallbackEndpoint: ProbeEndpoint?
        private let hedgeDelay: TimeInterval
        private let probeTimeout: TimeInterval
        private let generation: UInt64
        private let stateLock = NSLock()

        private var finished = false
        private var primaryFailed = false
        private var fallbackStarted = false
        private var fallbackFailed = false
        private var lastWaitingReason: String?
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
            stateLock.lock()
            if finished {
                stateLock.unlock()
                return
            }
            guard let conn = makeConnection(to: primaryEndpoint) else {
                stateLock.unlock()
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
                case .waiting(let err):
                    // `.waiting` is non-terminal (e.g. waiting for route/ARP readiness); do not fail or cancel here.
                    stateLock.lock()
                    lastWaitingReason = NetworkConnectivityMonitor.describeNWError(err)
                    stateLock.unlock()
                case .failed(let err):
                    var shouldFinish = false
                    var shouldStartFallback = false
                    stateLock.lock()
                    if !finished {
                        primaryFailed = true
                        if fallbackEndpoint == nil || fallbackFailed {
                            shouldFinish = true
                        } else {
                            shouldStartFallback = true
                        }
                    }
                    stateLock.unlock()
                    conn.cancel()
                    if shouldFinish {
                        finish(isReachable: false, latencyMs: nil, endpoint: primaryEndpoint.label, failureReason: NetworkConnectivityMonitor.describeNWError(err))
                    } else if shouldStartFallback {
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
                stateLock.lock()
                let waitingReason = lastWaitingReason
                stateLock.unlock()
                finish(
                    isReachable: false,
                    latencyMs: nil,
                    endpoint: primaryEndpoint.label,
                    failureReason: waitingReason ?? "Timeout — no packet response"
                )
            }
            timeoutWorkItem = timeoutItem
            queue.asyncAfter(deadline: .now() + probeTimeout, execute: timeoutItem)
            stateLock.unlock()

            conn.start(queue: queue)
        }

        func cancel() {
            stateLock.lock()
            guard !finished else {
                stateLock.unlock()
                return
            }
            finished = true
            let hedge = hedgeWorkItem
            let timeout = timeoutWorkItem
            let pConn = primaryConn
            let fConn = fallbackConn
            hedgeWorkItem = nil
            timeoutWorkItem = nil
            primaryConn = nil
            fallbackConn = nil
            stateLock.unlock()

            hedge?.cancel()
            timeout?.cancel()
            pConn?.stateUpdateHandler = nil
            fConn?.stateUpdateHandler = nil
            pConn?.cancel()
            fConn?.cancel()
        }

        private func startFallback() {
            stateLock.lock()
            guard !finished, !fallbackStarted else {
                stateLock.unlock()
                return
            }
            guard let fallback = fallbackEndpoint, let conn = makeConnection(to: fallback) else {
                fallbackFailed = true
                let shouldFinish = primaryFailed
                stateLock.unlock()
                if shouldFinish {
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
                case .waiting(let err):
                    stateLock.lock()
                    if lastWaitingReason == nil {
                        lastWaitingReason = NetworkConnectivityMonitor.describeNWError(err)
                    }
                    stateLock.unlock()
                case .failed(let err):
                    var shouldFinish = false
                    stateLock.lock()
                    if !finished {
                        fallbackFailed = true
                        shouldFinish = primaryFailed
                    }
                    stateLock.unlock()
                    conn.cancel()
                    if shouldFinish {
                        finish(isReachable: false, latencyMs: nil, endpoint: fallback.label, failureReason: NetworkConnectivityMonitor.describeNWError(err))
                    }
                default:
                    break
                }
            }
            stateLock.unlock()
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
            stateLock.lock()
            guard !finished else {
                stateLock.unlock()
                return
            }
            finished = true
            let hedge = hedgeWorkItem
            let timeout = timeoutWorkItem
            let pConn = primaryConn
            let fConn = fallbackConn
            hedgeWorkItem = nil
            timeoutWorkItem = nil
            primaryConn = nil
            fallbackConn = nil
            stateLock.unlock()

            hedge?.cancel()
            timeout?.cancel()
            pConn?.stateUpdateHandler = nil
            fConn?.stateUpdateHandler = nil
            pConn?.cancel()
            fConn?.cancel()

            monitor?.clearActiveRunner(self, generation: generation)
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
