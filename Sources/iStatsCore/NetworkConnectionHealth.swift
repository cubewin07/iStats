import Foundation

/// Real-world network connection status reflecting OS path state, active packet
/// reachability, latency, packet loss, interface errors, and Wi-Fi link quality.
///
/// Maps directly to the Connection Status Grid traffic-light semantics:
/// - `.connected`    → Green  ("Connected")
/// - `.degraded`     → Yellow ("Bad Connection")
/// - `.disconnected` → Red    ("Not Connected")
public enum NetworkConnectionStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case connected
    case degraded
    case disconnected

    public var displayName: String {
        switch self {
        case .connected:    return "Connected"
        case .degraded:     return "Bad Connection"
        case .disconnected: return "Not Connected"
        }
    }

    public var shortLabel: String {
        switch self {
        case .connected:    return "Connected"
        case .degraded:     return "Bad"
        case .disconnected: return "Not Connected"
        }
    }

    /// Maps to panel-wide `StatusLevel` (`.fine` = green, `.elevated` = yellow, `.critical` = red).
    public var statusLevel: StatusLevel {
        switch self {
        case .connected:    return .fine
        case .degraded:     return .elevated
        case .disconnected: return .critical
        }
    }
}

/// Result of the latest active packet reachability probe and its rolling window statistics.
public struct NetworkProbeSnapshot: Sendable, Equatable, Codable {
    /// Whether the latest active packet exchange succeeded (packet sent and response received).
    public let isReachable: Bool
    /// Round-trip latency in milliseconds when reachable.
    public let latencyMs: Double?
    /// Endpoint that responded or was probed (e.g. "1.1.1.1:443").
    public let endpoint: String?
    /// Rolling packet loss percentage across the recent probe window (0...100).
    public let packetLossPercent: Double
    /// Mean absolute RTT jitter in milliseconds across consecutive successful probes in the window.
    public let jitterMs: Double?
    /// Number of consecutive failed probes ending at this snapshot.
    public let consecutiveFailures: Int
    /// Total completed probes currently in the rolling window.
    public let windowSampleCount: Int
    /// Optional human-readable reason when unreachable.
    public let failureReason: String?
    /// Timestamp when the latest probe completed.
    public let timestamp: Date

    public init(
        isReachable: Bool,
        latencyMs: Double? = nil,
        endpoint: String? = nil,
        packetLossPercent: Double = 0.0,
        jitterMs: Double? = nil,
        consecutiveFailures: Int = 0,
        windowSampleCount: Int = 1,
        failureReason: String? = nil,
        timestamp: Date = Date()
    ) {
        self.isReachable = isReachable
        self.latencyMs = latencyMs
        self.endpoint = endpoint
        self.packetLossPercent = min(100.0, max(0.0, packetLossPercent))
        self.jitterMs = jitterMs
        self.consecutiveFailures = max(0, consecutiveFailures)
        self.windowSampleCount = max(0, windowSampleCount)
        self.failureReason = failureReason
        self.timestamp = timestamp
    }
}

/// Evaluated connection health attached to a `NetworkSample`.
public struct NetworkConnectionHealth: Sendable, Equatable, Codable {
    /// Overall traffic-light connection status (green / yellow / red).
    public let status: NetworkConnectionStatus
    /// Concise diagnostic explanation of the status.
    public let reason: String
    /// Whether macOS reports a satisfied default network path (`NWPath.Status.satisfied`).
    public let isPathSatisfied: Bool
    /// Whether active packet probing confirmed packets are sent and received (`nil` while initial probe is in flight).
    public let isInternetReachable: Bool?
    /// Whether macOS marks the current path as constrained (e.g., Low Data Mode).
    public let isConstrained: Bool
    /// Latest measured round-trip latency in milliseconds when reachable.
    public let latencyMs: Double?
    /// Rolling packet loss percentage across recent probes (0...100).
    public let packetLossPercent: Double
    /// Rolling RTT jitter in milliseconds, if at least 2 successful probes exist.
    public let jitterMs: Double?
    /// Primary interface packet errors and drops observed in this sample interval.
    public let interfaceErrorDelta: UInt64
    /// Packets received on the primary interface in this sample interval.
    public let primaryPacketsInDelta: UInt64
    /// Packets sent on the primary interface in this sample interval.
    public let primaryPacketsOutDelta: UInt64
    /// `true` only while awaiting the very first active probe result on a newly satisfied path.
    public let isProbing: Bool

    public init(
        status: NetworkConnectionStatus,
        reason: String,
        isPathSatisfied: Bool,
        isInternetReachable: Bool? = nil,
        isConstrained: Bool = false,
        latencyMs: Double? = nil,
        packetLossPercent: Double = 0.0,
        jitterMs: Double? = nil,
        interfaceErrorDelta: UInt64 = 0,
        primaryPacketsInDelta: UInt64 = 0,
        primaryPacketsOutDelta: UInt64 = 0,
        isProbing: Bool = false
    ) {
        self.status = status
        self.reason = reason
        self.isPathSatisfied = isPathSatisfied
        self.isInternetReachable = isInternetReachable
        self.isConstrained = isConstrained
        self.latencyMs = latencyMs
        self.packetLossPercent = min(100.0, max(0.0, packetLossPercent))
        self.jitterMs = jitterMs
        self.interfaceErrorDelta = interfaceErrorDelta
        self.primaryPacketsInDelta = primaryPacketsInDelta
        self.primaryPacketsOutDelta = primaryPacketsOutDelta
        self.isProbing = isProbing
    }
}

/// A single chronological cell in the Network Connection Status Grid (in-memory only; ADR 0006).
public struct ConnectionStatusPoint: Sendable, Equatable, Codable, Identifiable {
    public let timestamp: Date
    public let status: NetworkConnectionStatus
    public let latencyMs: Double?
    public let packetLossPercent: Double
    public let reason: String

    public var id: TimeInterval { timestamp.timeIntervalSince1970 }

    public init(
        timestamp: Date = Date(),
        status: NetworkConnectionStatus,
        latencyMs: Double? = nil,
        packetLossPercent: Double = 0.0,
        reason: String
    ) {
        self.timestamp = timestamp
        self.status = status
        self.latencyMs = latencyMs
        self.packetLossPercent = min(100.0, max(0.0, packetLossPercent))
        self.reason = reason
    }
}

/// Canonical thresholds for classifying a live network connection as degraded (yellow).
public enum NetworkConnectionThresholds {
    /// Round-trip latency at or above this threshold (ms) is considered a bad connection.
    public static let degradedLatencyMs: Double = 150.0
    /// Mean absolute RTT jitter at or above this threshold (ms) is considered unstable.
    public static let degradedJitterMs: Double = 60.0
    /// Rolling packet loss percentage at or above this threshold is considered a bad connection.
    public static let degradedPacketLossPercent: Double = 10.0
    /// Consecutive failed probes required to classify a satisfied path as disconnected.
    public static let disconnectedConsecutiveFailures: Int = 2
    /// Wi-Fi signal percentage strictly below this threshold is considered weak.
    public static let weakWiFiSignalPercent: Int = 30
    /// Wi-Fi SNR strictly below this threshold (dB) is considered weak.
    public static let weakWiFiSNR: Int = 12
    /// Primary interface error/drop delta at or above this count in one interval signals degradation.
    public static let degradedInterfaceErrorCount: UInt64 = 5
}

/// Pure, deterministic evaluator that classifies real-world network connectivity into
/// `.connected` (green), `.degraded` (yellow), or `.disconnected` (red).
public enum NetworkConnectionEvaluator {

    /// Evaluates connection health from OS path state, active packet probe results,
    /// Wi-Fi radio telemetry, and primary interface packet/error counters.
    public static func evaluate(
        isPathSatisfied: Bool,
        isConstrained: Bool = false,
        primaryInterface: String? = nil,
        primaryType: NetworkConnectionType? = nil,
        localIPv4: String? = nil,
        wifiDetails: WiFiLinkTelemetry? = nil,
        probe: NetworkProbeSnapshot? = nil,
        primaryPacketsInDelta: UInt64 = 0,
        primaryPacketsOutDelta: UInt64 = 0,
        interfaceErrorDelta: UInt64 = 0
    ) -> NetworkConnectionHealth {
        // 1. OS path unsatisfied (Wi-Fi off, not associated, Ethernet unplugged) -> Red immediately.
        if !isPathSatisfied {
            let reason = (primaryInterface == nil && localIPv4 == nil)
                ? "No active network"
                : "Network path unavailable"
            return NetworkConnectionHealth(
                status: .disconnected,
                reason: reason,
                isPathSatisfied: false,
                isInternetReachable: false,
                isConstrained: isConstrained,
                latencyMs: nil,
                packetLossPercent: 100.0,
                jitterMs: nil,
                interfaceErrorDelta: interfaceErrorDelta,
                primaryPacketsInDelta: primaryPacketsInDelta,
                primaryPacketsOutDelta: primaryPacketsOutDelta,
                isProbing: false
            )
        }

        // 2. Sustained probe failure while locally associated -> Red ("Not Connected").
        // A single transient drop when prior probes in the window succeeded degrades to Yellow in Step 5.
        if let probe, !probe.isReachable {
            let isSustainedFailure =
                probe.consecutiveFailures >= NetworkConnectionThresholds.disconnectedConsecutiveFailures
                || (probe.windowSampleCount > 0 && probe.consecutiveFailures >= probe.windowSampleCount)
                || (probe.consecutiveFailures == 0 && probe.packetLossPercent >= 100.0)

            if isSustainedFailure {
                let isWiFi = (primaryType == .wifi) || (wifiDetails != nil)
                let reason: String
                if isWiFi {
                    if primaryPacketsOutDelta > 0 && primaryPacketsInDelta == 0 {
                        reason = "Wi-Fi connected · No packets received"
                    } else {
                        reason = "Wi-Fi connected · No internet response"
                    }
                } else if let iface = primaryInterface {
                    reason = "No internet response on \(iface)"
                } else {
                    reason = probe.failureReason ?? "No packet response"
                }

                return NetworkConnectionHealth(
                    status: .disconnected,
                    reason: reason,
                    isPathSatisfied: true,
                    isInternetReachable: false,
                    isConstrained: isConstrained,
                    latencyMs: nil,
                    packetLossPercent: max(probe.packetLossPercent, 100.0),
                    jitterMs: probe.jitterMs,
                    interfaceErrorDelta: interfaceErrorDelta,
                    primaryPacketsInDelta: primaryPacketsInDelta,
                    primaryPacketsOutDelta: primaryPacketsOutDelta,
                    isProbing: false
                )
            }
        }

        // 3. No route/interface and no reachable probe -> Red.
        if primaryInterface == nil && localIPv4 == nil && probe?.isReachable != true {
            return NetworkConnectionHealth(
                status: .disconnected,
                reason: "No active network",
                isPathSatisfied: false,
                isInternetReachable: false,
                isConstrained: isConstrained,
                latencyMs: nil,
                packetLossPercent: 100.0,
                jitterMs: nil,
                interfaceErrorDelta: interfaceErrorDelta,
                primaryPacketsInDelta: primaryPacketsInDelta,
                primaryPacketsOutDelta: primaryPacketsOutDelta,
                isProbing: false
            )
        }

        // 4. Initial probe still in flight on a satisfied path.
        guard let probe else {
            let weakWiFiReason = evaluateWeakWiFiReason(wifiDetails)
            if let weakWiFiReason {
                return NetworkConnectionHealth(
                    status: .degraded,
                    reason: weakWiFiReason,
                    isPathSatisfied: true,
                    isInternetReachable: nil,
                    isConstrained: isConstrained,
                    latencyMs: nil,
                    packetLossPercent: 0.0,
                    jitterMs: nil,
                    interfaceErrorDelta: interfaceErrorDelta,
                    primaryPacketsInDelta: primaryPacketsInDelta,
                    primaryPacketsOutDelta: primaryPacketsOutDelta,
                    isProbing: true
                )
            }
            return NetworkConnectionHealth(
                status: isConstrained ? .degraded : .connected,
                reason: isConstrained ? "Constrained connection" : "Checking connection…",
                isPathSatisfied: true,
                isInternetReachable: nil,
                isConstrained: isConstrained,
                latencyMs: nil,
                packetLossPercent: 0.0,
                jitterMs: nil,
                interfaceErrorDelta: interfaceErrorDelta,
                primaryPacketsInDelta: primaryPacketsInDelta,
                primaryPacketsOutDelta: primaryPacketsOutDelta,
                isProbing: true
            )
        }

        // 5. Probe succeeded (or suffered a single transient drop). Check for degraded (Yellow) conditions.
        var degradationReasons: [String] = []

        if probe.packetLossPercent >= NetworkConnectionThresholds.degradedPacketLossPercent {
            degradationReasons.append("Packet loss (\(Int(round(probe.packetLossPercent)))%)")
        } else if !probe.isReachable {
            degradationReasons.append("Packet loss (\(Int(round(probe.packetLossPercent)))%)")
        }

        if let rtt = probe.latencyMs, rtt >= NetworkConnectionThresholds.degradedLatencyMs {
            degradationReasons.append("High latency (\(Int(round(rtt))) ms)")
        }

        if let jitter = probe.jitterMs, jitter >= NetworkConnectionThresholds.degradedJitterMs {
            degradationReasons.append("Unstable latency (\(Int(round(jitter))) ms jitter)")
        }

        if let weakWiFi = evaluateWeakWiFiReason(wifiDetails) {
            degradationReasons.append(weakWiFi)
        }

        if interfaceErrorDelta >= NetworkConnectionThresholds.degradedInterfaceErrorCount {
            degradationReasons.append("Packet errors (\(interfaceErrorDelta))")
        }

        if isConstrained {
            degradationReasons.append("Constrained link")
        }

        if !degradationReasons.isEmpty {
            let summary = degradationReasons.prefix(2).joined(separator: " · ")
            return NetworkConnectionHealth(
                status: .degraded,
                reason: summary,
                isPathSatisfied: true,
                isInternetReachable: true,
                isConstrained: isConstrained,
                latencyMs: probe.latencyMs,
                packetLossPercent: probe.packetLossPercent,
                jitterMs: probe.jitterMs,
                interfaceErrorDelta: interfaceErrorDelta,
                primaryPacketsInDelta: primaryPacketsInDelta,
                primaryPacketsOutDelta: primaryPacketsOutDelta,
                isProbing: false
            )
        }

        // 6. All checks healthy -> Green ("Connected").
        let healthyReason: String
        if let rtt = probe.latencyMs {
            healthyReason = "\(Int(round(rtt))) ms · \(Int(round(probe.packetLossPercent)))% loss"
        } else {
            healthyReason = "Connected"
        }

        return NetworkConnectionHealth(
            status: .connected,
            reason: healthyReason,
            isPathSatisfied: true,
            isInternetReachable: true,
            isConstrained: false,
            latencyMs: probe.latencyMs,
            packetLossPercent: probe.packetLossPercent,
            jitterMs: probe.jitterMs,
            interfaceErrorDelta: interfaceErrorDelta,
            primaryPacketsInDelta: primaryPacketsInDelta,
            primaryPacketsOutDelta: primaryPacketsOutDelta,
            isProbing: false
        )
    }

    /// Derives fallback connection health for legacy `NetworkSample` values that do not carry `connectionHealth`.
    public static func fallbackHealth(for sample: NetworkSample) -> NetworkConnectionHealth {
        if let explicit = sample.connectionHealth {
            return explicit
        }

        let hasRoute = sample.primaryInterface != nil || sample.localIPv4 != nil
        if !hasRoute {
            return NetworkConnectionHealth(
                status: .disconnected,
                reason: "No active network",
                isPathSatisfied: false,
                isInternetReachable: false,
                packetLossPercent: 100.0
            )
        }

        if let weakWiFi = evaluateWeakWiFiReason(sample.wifiDetails) {
            return NetworkConnectionHealth(
                status: .degraded,
                reason: weakWiFi,
                isPathSatisfied: true,
                isInternetReachable: true
            )
        }

        return NetworkConnectionHealth(
            status: .connected,
            reason: "Connected",
            isPathSatisfied: true,
            isInternetReachable: true
        )
    }

    /// Computes rolling packet loss percentage (0...100) and mean absolute RTT jitter (ms)
    /// from a chronological list of probe outcomes (`nil` RTT = failed probe).
    public static func computeWindowStats(from rttSamplesMs: [Double?]) -> (packetLossPercent: Double, jitterMs: Double?, consecutiveFailures: Int) {
        guard !rttSamplesMs.isEmpty else {
            return (0.0, nil, 0)
        }

        let failures = rttSamplesMs.filter { $0 == nil }.count
        let lossPercent = (Double(failures) / Double(rttSamplesMs.count)) * 100.0

        var consecutive = 0
        for sample in rttSamplesMs.reversed() {
            if sample == nil {
                consecutive += 1
            } else {
                break
            }
        }

        let successes = rttSamplesMs.compactMap { $0 }
        let jitter: Double?
        if successes.count >= 2 {
            var diffSum = 0.0
            for idx in 1..<successes.count {
                diffSum += abs(successes[idx] - successes[idx - 1])
            }
            jitter = diffSum / Double(successes.count - 1)
        } else {
            jitter = nil
        }

        return (lossPercent, jitter, consecutive)
    }

    private static func evaluateWeakWiFiReason(_ wifi: WiFiLinkTelemetry?) -> String? {
        guard let wifi else { return nil }
        if let pct = wifi.signalPercent, pct < NetworkConnectionThresholds.weakWiFiSignalPercent {
            return "Weak Wi-Fi signal (\(pct)%)"
        }
        if wifi.qualityRating == "Weak" {
            return "Weak Wi-Fi signal"
        }
        if let snr = wifi.snr, snr < NetworkConnectionThresholds.weakWiFiSNR {
            return "Low Wi-Fi SNR (\(snr) dB)"
        }
        return nil
    }
}
