import XCTest
@testable import iStatsCore

final class NetworkConnectionHealthTests: XCTestCase {

    // MARK: - Evaluator: Connected (Green)

    func testHealthyWiFiWithReachableProbeIsConnected() {
        let wifi = WiFiLinkTelemetry(ssid: "Office-5G", rssi: -55, noise: -92, txRate: 866.0, channel: 36, band: "5 GHz")
        let probe = NetworkProbeSnapshot(
            isReachable: true,
            latencyMs: 18.4,
            endpoint: "1.1.1.1:443",
            packetLossPercent: 0.0,
            jitterMs: 3.2,
            consecutiveFailures: 0,
            windowSampleCount: 8
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            isConstrained: false,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            wifiDetails: wifi,
            probe: probe,
            primaryPacketsInDelta: 120,
            primaryPacketsOutDelta: 95,
            interfaceErrorDelta: 0
        )

        XCTAssertEqual(health.status, .connected)
        XCTAssertEqual(health.status.statusLevel, .fine)
        XCTAssertEqual(health.isInternetReachable, true)
        XCTAssertFalse(health.isProbing)
        XCTAssertTrue(health.reason.contains("18 ms"))
    }

    // MARK: - Evaluator: Disconnected (Red)

    func testPathUnsatisfiedIsImmediatelyDisconnected() {
        // Even if background virtual interfaces have local counters, unsatisfied OS path must be Red.
        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: false,
            primaryInterface: nil,
            primaryType: nil,
            localIPv4: nil,
            wifiDetails: nil,
            probe: nil
        )

        XCTAssertEqual(health.status, .disconnected)
        XCTAssertEqual(health.status.statusLevel, .critical)
        XCTAssertFalse(health.isPathSatisfied)
        XCTAssertEqual(health.isInternetReachable, false)
        XCTAssertFalse(health.isProbing)
    }

    func testConnectedWiFiWithFailedProbeIsTreatedAsNotConnected() {
        let wifi = WiFiLinkTelemetry(ssid: "BrokenRouter", rssi: -52, noise: -90, txRate: 600.0, channel: 44, band: "5 GHz")
        let failedProbe = NetworkProbeSnapshot(
            isReachable: false,
            latencyMs: nil,
            endpoint: "1.1.1.1:443",
            packetLossPercent: 100.0,
            consecutiveFailures: 1,
            windowSampleCount: 1,
            failureReason: "Timeout — no packet response"
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.104",
            wifiDetails: wifi,
            probe: failedProbe,
            primaryPacketsInDelta: 10,
            primaryPacketsOutDelta: 12
        )

        XCTAssertEqual(health.status, .disconnected)
        XCTAssertEqual(health.status.statusLevel, .critical)
        XCTAssertEqual(health.isInternetReachable, false)
        XCTAssertTrue(health.reason.contains("Wi-Fi connected"))
    }

    func testConnectedWiFiWithPacketsSentButNoneReceivedReportsSpecificReason() {
        let wifi = WiFiLinkTelemetry(ssid: "StalledWiFi", rssi: -60, noise: -90, txRate: 300.0, channel: 36, band: "5 GHz")
        let failedProbe = NetworkProbeSnapshot(
            isReachable: false,
            packetLossPercent: 100.0,
            consecutiveFailures: 2,
            windowSampleCount: 2
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.104",
            wifiDetails: wifi,
            probe: failedProbe,
            primaryPacketsInDelta: 0,
            primaryPacketsOutDelta: 25
        )

        XCTAssertEqual(health.status, .disconnected)
        XCTAssertEqual(health.reason, "Wi-Fi connected · No packets received")
    }

    // MARK: - Evaluator: Bad Connection (Yellow)

    func testHighLatencyIsDegraded() {
        let probe = NetworkProbeSnapshot(
            isReachable: true,
            latencyMs: 245.0,
            packetLossPercent: 0.0,
            jitterMs: 10.0
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: probe
        )

        XCTAssertEqual(health.status, .degraded)
        XCTAssertEqual(health.status.statusLevel, .elevated)
        XCTAssertTrue(health.reason.contains("High latency"))
        XCTAssertTrue(health.reason.contains("245 ms"))
    }

    func testRollingPacketLossIsDegraded() {
        let probe = NetworkProbeSnapshot(
            isReachable: true,
            latencyMs: 28.0,
            packetLossPercent: 25.0,
            jitterMs: 5.0
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: probe
        )

        XCTAssertEqual(health.status, .degraded)
        XCTAssertTrue(health.reason.contains("Packet loss (25%)"))
    }

    func testSingleTransientDroppedProbeWithPriorSuccessesIsDegradedNotDisconnected() {
        let probe12_5 = NetworkProbeSnapshot(
            isReachable: false,
            latencyMs: nil,
            packetLossPercent: 12.5,
            jitterMs: 4.0,
            consecutiveFailures: 1,
            windowSampleCount: 8,
            failureReason: "Timeout"
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: probe12_5
        )

        XCTAssertEqual(health.status, .degraded)
        XCTAssertEqual(health.packetLossPercent, 12.5, accuracy: 0.001)
        XCTAssertTrue(health.reason.contains("Packet loss (13%)"))

        // Even below 10% rolling threshold (1/12 = 8.33%), a single dropped latest probe is still degraded
        let probe8_3 = NetworkProbeSnapshot(
            isReachable: false,
            latencyMs: nil,
            packetLossPercent: 100.0 / 12.0,
            jitterMs: 3.0,
            consecutiveFailures: 1,
            windowSampleCount: 12,
            failureReason: "Timeout"
        )
        let healthLowLoss = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: probe8_3
        )
        XCTAssertEqual(healthLowLoss.status, .degraded)
        XCTAssertEqual(healthLowLoss.packetLossPercent, 100.0 / 12.0, accuracy: 0.001)
        XCTAssertTrue(healthLowLoss.reason.contains("Packet loss (8%)"))
    }

    func testTwoConsecutiveFailedProbesWithPriorSuccessesIsDisconnected() {
        let probe = NetworkProbeSnapshot(
            isReachable: false,
            latencyMs: nil,
            packetLossPercent: 25.0,
            consecutiveFailures: 2,
            windowSampleCount: 8,
            failureReason: "Timeout"
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: probe
        )

        XCTAssertEqual(health.status, .disconnected)
        XCTAssertEqual(health.isInternetReachable, false)
    }

    func testHealthyReasonFormatsNonZeroRollingPacketLossUnderThreshold() {
        let probe = NetworkProbeSnapshot(
            isReachable: true,
            latencyMs: 20.0,
            packetLossPercent: 100.0 / 12.0, // ~8.3% < 10% degraded threshold
            jitterMs: 2.0,
            consecutiveFailures: 0,
            windowSampleCount: 12
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: probe
        )

        XCTAssertEqual(health.status, .connected)
        XCTAssertEqual(health.reason, "20 ms · 8% loss")
    }

    func testHighJitterIsDegraded() {
        let probe = NetworkProbeSnapshot(
            isReachable: true,
            latencyMs: 55.0,
            packetLossPercent: 0.0,
            jitterMs: 82.0
        )

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en1",
            primaryType: .ethernet,
            localIPv4: "10.0.0.5",
            probe: probe
        )

        XCTAssertEqual(health.status, .degraded)
        XCTAssertTrue(health.reason.contains("Unstable latency"))
    }

    func testWeakWiFiSignalIsDegraded() {
        let weakWifi = WiFiLinkTelemetry(ssid: "FarAP", rssi: -89, noise: -92, txRate: 24.0, channel: 1, band: "2.4 GHz")
        let probe = NetworkProbeSnapshot(isReachable: true, latencyMs: 32.0, packetLossPercent: 0.0)

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            wifiDetails: weakWifi,
            probe: probe
        )

        XCTAssertEqual(health.status, .degraded)
        XCTAssertTrue(health.reason.contains("Weak Wi-Fi signal"))
    }

    func testInterfacePacketErrorsIsDegraded() {
        let probe = NetworkProbeSnapshot(isReachable: true, latencyMs: 14.0, packetLossPercent: 0.0)

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: probe,
            interfaceErrorDelta: 9
        )

        XCTAssertEqual(health.status, .degraded)
        XCTAssertTrue(health.reason.contains("Packet errors (9)"))
    }

    func testConstrainedPathIsDegraded() {
        let probe = NetworkProbeSnapshot(isReachable: true, latencyMs: 22.0, packetLossPercent: 0.0)

        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            isConstrained: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: probe
        )

        XCTAssertEqual(health.status, .degraded)
        XCTAssertTrue(health.reason.contains("Constrained"))
    }

    // MARK: - Initial Probing & Rolling Window Stats

    func testInitialProbingSetsIsProbingTrue() {
        let health = NetworkConnectionEvaluator.evaluate(
            isPathSatisfied: true,
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            probe: nil
        )

        XCTAssertTrue(health.isProbing)
        XCTAssertNil(health.isInternetReachable)
    }

    func testComputeWindowStatsCalculatesLossJitterAndConsecutiveFailures() {
        let stats = NetworkConnectionEvaluator.computeWindowStats(from: [20.0, 40.0, nil, 30.0, nil, nil])
        XCTAssertEqual(stats.packetLossPercent, 50.0, accuracy: 0.001)
        // Successes: [20, 40, 30] -> diffs |40-20|=20, |30-40|=10 -> mean 15.0
        XCTAssertEqual(stats.jitterMs ?? -1, 15.0, accuracy: 0.001)
        XCTAssertEqual(stats.consecutiveFailures, 2)
    }

    // MARK: - MetricsStore Connection Status Ring Buffer

    func testMetricsStoreRecordsConnectionHistoryAndSkipsProbing() {
        var store = MetricsStore(defaultCapacity: 60)
        let base = Date(timeIntervalSince1970: 10_000)

        // Probing sample must NOT be recorded into grid history
        let probingSample = NetworkSample(
            primaryInterface: "en0",
            localIPv4: "192.168.1.42",
            connectionHealth: NetworkConnectionHealth(
                status: .connected,
                reason: "Checking connection…",
                isPathSatisfied: true,
                isInternetReachable: nil,
                isProbing: true
            )
        )
        store.append(.network(Sample(value: probingSample, timestamp: base)))
        XCTAssertTrue(store.networkConnectionHistory().isEmpty)

        // Record connected, degraded, and disconnected samples
        let statuses: [NetworkConnectionStatus] = [.connected, .degraded, .disconnected]
        for (idx, st) in statuses.enumerated() {
            let sample = NetworkSample(
                primaryInterface: st == .disconnected ? nil : "en0",
                localIPv4: st == .disconnected ? nil : "192.168.1.42",
                connectionHealth: NetworkConnectionHealth(
                    status: st,
                    reason: st.displayName,
                    isPathSatisfied: st != .disconnected,
                    isInternetReachable: st != .disconnected,
                    latencyMs: st == .connected ? 15.0 : (st == .degraded ? 220.0 : nil),
                    packetLossPercent: st == .disconnected ? 100.0 : 0.0,
                    isProbing: false
                )
            )
            store.append(.network(Sample(value: sample, timestamp: base.addingTimeInterval(Double(idx + 1)))))
        }

        let history = store.networkConnectionHistory()
        XCTAssertEqual(history.map(\.status), [.connected, .degraded, .disconnected])

        // Clearing network clears connection status history
        store.clear(category: .network)
        XCTAssertTrue(store.networkConnectionHistory().isEmpty)
    }

    func testNetworkSampleCodableWithConnectionHealth() throws {
        let health = NetworkConnectionHealth(
            status: .degraded,
            reason: "Packet loss (25%)",
            isPathSatisfied: true,
            isInternetReachable: true,
            latencyMs: 62.5,
            packetLossPercent: 25.0,
            jitterMs: 14.0,
            interfaceErrorDelta: 2,
            primaryPacketsInDelta: 50,
            primaryPacketsOutDelta: 60,
            isProbing: false
        )
        let sample = NetworkSample(
            interfaces: [
                InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1200, bytesOutPerSec: 800, totalBytesIn: 1200, totalBytesOut: 800, ipv4Address: "192.168.1.42", type: .wifi)
            ],
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            connectionHealth: health
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(NetworkSample.self, from: data)
        XCTAssertEqual(decoded, sample)
        XCTAssertEqual(decoded.connectionHealth, health)
    }
}
