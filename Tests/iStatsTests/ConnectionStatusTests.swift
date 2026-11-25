import XCTest
import SwiftUI
import AppKit
import iStatsCore
@testable import iStats

final class ConnectionStatusTests: XCTestCase {

    // MARK: - NetworkSampler Integration

    func testCalculateSampleTreatsVirtualTrafficWhenOfflineAsDisconnected() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let t1 = Date(timeIntervalSince1970: 1001.0)

        // Simulates macOS with Wi-Fi disconnected while awdl0 & utun0 still pass local traffic
        let c0 = [
            RawInterfaceCounters(name: "awdl0", bytesIn: 5000, bytesOut: 4000, packetsIn: 20, packetsOut: 18),
            RawInterfaceCounters(name: "utun0", bytesIn: 2000, bytesOut: 2000, packetsIn: 10, packetsOut: 10)
        ]
        let c1 = [
            RawInterfaceCounters(name: "awdl0", bytesIn: 9000, bytesOut: 8000, packetsIn: 35, packetsOut: 30),
            RawInterfaceCounters(name: "utun0", bytesIn: 3500, bytesOut: 3200, packetsIn: 18, packetsOut: 16)
        ]
        let offlineConn = RawNetworkConnectivity(
            primaryInterface: nil,
            routerIPv4: nil,
            primaryDNS: nil,
            interfaceIPs: [:],
            wifiTelemetry: nil,
            isPathSatisfied: false,
            isConstrained: false,
            probeSnapshot: nil
        )

        let (_, prev0, totals0) = NetworkSampler.calculateSample(
            previous: nil,
            current: c0,
            currentTimestamp: t0,
            sessionTotals: nil,
            connectivity: offlineConn
        )
        let (sample1, _, _) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c1,
            currentTimestamp: t1,
            sessionTotals: totals0,
            connectivity: offlineConn
        )

        // Bytes are moving on virtual interfaces, yet connectionHealth MUST be .disconnected (Red)
        XCTAssertGreaterThan(sample1.totalBytesInPerSec, 0.0)
        XCTAssertGreaterThan(sample1.totalBytesOutPerSec, 0.0)
        XCTAssertEqual(sample1.connectionHealth?.status, .disconnected)
        XCTAssertEqual(sample1.connectionHealth?.isPathSatisfied, false)
    }

    func testCalculateSampleDetectsWiFiConnectedWithNoIncomingPacketsAndFailedProbe() {
        let t0 = Date(timeIntervalSince1970: 2000.0)
        let t1 = Date(timeIntervalSince1970: 2001.0)

        let c0 = [RawInterfaceCounters(name: "en0", bytesIn: 10_000, bytesOut: 10_000, packetsIn: 100, packetsOut: 100)]
        let c1 = [RawInterfaceCounters(name: "en0", bytesIn: 10_000, bytesOut: 12_400, packetsIn: 100, packetsOut: 118)]

        let brokenWiFiConn = RawNetworkConnectivity(
            primaryInterface: "en0",
            routerIPv4: "192.168.1.1",
            primaryDNS: "192.168.1.1",
            interfaceIPs: ["en0": "192.168.1.50"],
            wifiTelemetry: WiFiLinkTelemetry(ssid: "DeadISP-WiFi", rssi: -55, noise: -90, txRate: 600, channel: 36, band: "5 GHz"),
            isPathSatisfied: true,
            isConstrained: false,
            probeSnapshot: NetworkProbeSnapshot(
                isReachable: false,
                packetLossPercent: 100.0,
                consecutiveFailures: 1,
                windowSampleCount: 1,
                failureReason: "Timeout — no packet response"
            )
        )

        let (_, prev0, totals0) = NetworkSampler.calculateSample(
            previous: nil,
            current: c0,
            currentTimestamp: t0,
            sessionTotals: nil,
            connectivity: brokenWiFiConn
        )
        let (sample1, _, _) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c1,
            currentTimestamp: t1,
            sessionTotals: totals0,
            connectivity: brokenWiFiConn
        )

        XCTAssertEqual(sample1.connectionHealth?.status, .disconnected)
        XCTAssertEqual(sample1.connectionHealth?.primaryPacketsOutDelta, 18)
        XCTAssertEqual(sample1.connectionHealth?.primaryPacketsInDelta, 0)
        XCTAssertEqual(sample1.connectionHealth?.reason, "Wi-Fi connected · No packets received")
    }

    func testCalculateSamplePropagatesInterfaceErrorDeltasToDegradedStatus() {
        let t0 = Date(timeIntervalSince1970: 3000.0)
        let t1 = Date(timeIntervalSince1970: 3001.0)

        let c0 = [RawInterfaceCounters(name: "en0", bytesIn: 10_000, bytesOut: 10_000, packetsIn: 200, packetsOut: 200, errorsIn: 0, errorsOut: 0, dropsIn: 0)]
        let c1 = [RawInterfaceCounters(name: "en0", bytesIn: 20_000, bytesOut: 15_000, packetsIn: 250, packetsOut: 240, errorsIn: 4, errorsOut: 2, dropsIn: 1)]

        let conn = RawNetworkConnectivity(
            primaryInterface: "en0",
            routerIPv4: "192.168.1.1",
            primaryDNS: "1.1.1.1",
            interfaceIPs: ["en0": "192.168.1.50"],
            wifiTelemetry: WiFiLinkTelemetry(ssid: "Office-5G", rssi: -60, noise: -92, txRate: 600, channel: 36, band: "5 GHz"),
            isPathSatisfied: true,
            probeSnapshot: NetworkProbeSnapshot(isReachable: true, latencyMs: 16.0, packetLossPercent: 0.0)
        )

        let (_, prev0, totals0) = NetworkSampler.calculateSample(
            previous: nil,
            current: c0,
            currentTimestamp: t0,
            sessionTotals: nil,
            connectivity: conn
        )
        let (sample1, _, _) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c1,
            currentTimestamp: t1,
            sessionTotals: totals0,
            connectivity: conn
        )

        XCTAssertEqual(sample1.connectionHealth?.interfaceErrorDelta, 7)
        XCTAssertEqual(sample1.connectionHealth?.status, .degraded)
    }

    // MARK: - NetworkConnectivityMonitor State Machine

    func testMonitorInstantDisconnectAndRollingProbeWindow() {
        let monitor = NetworkConnectivityMonitor(
            windowCapacity: 4,
            enableSystemPathMonitor: false,
            enableActiveProbing: false
        )

        // Path comes up on en0
        monitor.handlePathUpdate(isSatisfied: true, activeInterfaceName: "en0")
        XCTAssertEqual(monitor.snapshot(triggerProbeIfDue: false).isPathSatisfied, true)
        XCTAssertNil(monitor.snapshot(triggerProbeIfDue: false).probe)

        // 3 good probes + 1 failed probe -> 25% packet loss
        monitor.recordProbeOutcome(isReachable: true, latencyMs: 15.0, endpoint: "1.1.1.1:443")
        monitor.recordProbeOutcome(isReachable: true, latencyMs: 25.0, endpoint: "1.1.1.1:443")
        monitor.recordProbeOutcome(isReachable: false, endpoint: "1.1.1.1:443", failureReason: "Timeout")
        monitor.recordProbeOutcome(isReachable: true, latencyMs: 20.0, endpoint: "1.1.1.1:443")

        let midSnap = monitor.snapshot(triggerProbeIfDue: false)
        XCTAssertEqual(midSnap.probe?.isReachable, true)
        XCTAssertEqual(midSnap.probe?.packetLossPercent ?? -1, 25.0, accuracy: 0.001)
        XCTAssertEqual(midSnap.probe?.windowSampleCount, 4)

        // Path drops -> immediate disconnected probe snapshot, window reset
        monitor.handlePathUpdate(isSatisfied: false, activeInterfaceName: nil)
        let downSnap = monitor.snapshot(triggerProbeIfDue: false)
        XCTAssertEqual(downSnap.isPathSatisfied, false)
        XCTAssertEqual(downSnap.probe?.isReachable, false)
        XCTAssertEqual(downSnap.probe?.packetLossPercent, 100.0)

        // Reconnects on en1 -> old failure state cleared, awaits fresh probe
        monitor.handlePathUpdate(isSatisfied: true, activeInterfaceName: "en1")
        let upSnap = monitor.snapshot(triggerProbeIfDue: false)
        XCTAssertEqual(upSnap.isPathSatisfied, true)
        XCTAssertEqual(upSnap.activeInterfaceName, "en1")
        XCTAssertNil(upSnap.probe)
    }

    func testMonitorGatesProbingBeforePathSatisfiedAndWhenBackgrounded() {
        let monitor = NetworkConnectivityMonitor(
            probeInterval: 5.0,
            backgroundProbeInterval: 60.0,
            enableSystemPathMonitor: false,
            enableActiveProbing: true,
            foregroundProbing: false
        )

        // Before NWPathMonitor reports pathSatisfied == true, periodic probing must NOT fire (gen-0 race fix)
        XCTAssertFalse(monitor.wouldTriggerProbe())

        // Once satisfied in background mode (panel closed), path transition fires 1 initial probe;
        // once that finishes, periodic 2s/5s probing stays suppressed unless stalled.
        monitor.handlePathUpdate(isSatisfied: true, activeInterfaceName: "en0")
        monitor.recordProbeOutcome(isReachable: true, latencyMs: 12.0)
        let future = Date().addingTimeInterval(10.0)
        XCTAssertFalse(monitor.wouldTriggerProbe(now: future, isTrafficStalled: false))
        XCTAssertFalse(monitor.wouldTriggerProbe(now: future, isTrafficStalled: true))
        XCTAssertTrue(monitor.wouldTriggerProbe(now: Date().addingTimeInterval(120.0), isTrafficStalled: true))

        // Opening Network panel enables foreground probing at probeInterval
        monitor.setForegroundProbing(true)
        XCTAssertTrue(monitor.wouldTriggerProbe(now: future, isTrafficStalled: false))
        monitor.stop()
    }

    func testHostNetworkInfoProviderDoesNotClobberExistingPathObservers() {
        final class CounterBox: @unchecked Sendable {
            let lock = NSLock()
            var count = 0
            func increment() {
                lock.lock()
                count += 1
                lock.unlock()
            }
            func value() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return count
            }
        }

        let monitor = NetworkConnectivityMonitor(
            enableSystemPathMonitor: false,
            enableActiveProbing: false
        )
        let box = CounterBox()
        let token = monitor.addOnPathChanged {
            box.increment()
        }

        // Initializing HostNetworkInfoProvider must not overwrite our registered observer
        _ = HostNetworkInfoProvider(connectivityMonitor: monitor)
        monitor.handlePathUpdate(isSatisfied: true, activeInterfaceName: "en0")

        XCTAssertEqual(box.value(), 1)

        monitor.removeOnPathChanged(token)
    }

    func testSustainedBidirectionalTrafficFallsBackWhenDirectTCPProbeBlocked() {
        let t0 = Date(timeIntervalSince1970: 4000.0)
        let t1 = Date(timeIntervalSince1970: 4001.0)
        let t2 = Date(timeIntervalSince1970: 4002.0)

        let c0 = [RawInterfaceCounters(name: "en0", bytesIn: 10_000, bytesOut: 10_000, packetsIn: 100, packetsOut: 100)]
        let c1 = [RawInterfaceCounters(name: "en0", bytesIn: 15_000, bytesOut: 12_000, packetsIn: 120, packetsOut: 115)]
        let c2 = [RawInterfaceCounters(name: "en0", bytesIn: 25_000, bytesOut: 16_000, packetsIn: 160, packetsOut: 140)]

        let blockedProbeConn = RawNetworkConnectivity(
            primaryInterface: "en0",
            routerIPv4: "10.0.0.1",
            primaryDNS: "10.0.0.2",
            interfaceIPs: ["en0": "10.0.1.5"],
            isPathSatisfied: true,
            probeSnapshot: NetworkProbeSnapshot(
                isReachable: false,
                packetLossPercent: 100.0,
                consecutiveFailures: 2,
                windowSampleCount: 2,
                failureReason: "Connection refused"
            )
        )

        let (_, prev0, totals0) = NetworkSampler.calculateSample(
            previous: nil,
            current: c0,
            currentTimestamp: t0,
            sessionTotals: nil,
            connectivity: blockedProbeConn,
            priorPrimaryTrafficIntervals: 0
        )
        let (_, prev1, totals1) = NetworkSampler.calculateSample(
            previous: prev0,
            current: c1,
            currentTimestamp: t1,
            sessionTotals: totals0,
            connectivity: blockedProbeConn,
            priorPrimaryTrafficIntervals: 0
        )
        let (sample2, _, _) = NetworkSampler.calculateSample(
            previous: prev1,
            current: c2,
            currentTimestamp: t2,
            sessionTotals: totals1,
            connectivity: blockedProbeConn,
            priorPrimaryTrafficIntervals: 1
        )

        XCTAssertEqual(sample2.connectionHealth?.status, .connected)
        XCTAssertEqual(sample2.connectionHealth?.isInternetReachable, true)
        XCTAssertEqual(sample2.connectionHealth?.reason, "Active traffic (probe blocked)")
    }

    // MARK: - ConnectionStatusGridView & NetworkPanel Rendering

    @MainActor
    func testConnectionStatusGridSlotsRightAlignedAndRendersAllStates() {
        let base = Date(timeIntervalSince1970: 50_000)
        let history: [ConnectionStatusPoint] = [
            ConnectionStatusPoint(timestamp: base, status: .connected, latencyMs: 14, reason: "14 ms · 0% loss"),
            ConnectionStatusPoint(timestamp: base.addingTimeInterval(1), status: .degraded, latencyMs: 210, reason: "High latency (210 ms)"),
            ConnectionStatusPoint(timestamp: base.addingTimeInterval(2), status: .disconnected, latencyMs: nil, packetLossPercent: 100, reason: "Wi-Fi connected · No internet response")
        ]

        let states: [NetworkConnectionHealth] = [
            NetworkConnectionHealth(status: .connected, reason: "14 ms · 0% loss", isPathSatisfied: true, isInternetReachable: true, latencyMs: 14),
            NetworkConnectionHealth(status: .degraded, reason: "High latency (210 ms)", isPathSatisfied: true, isInternetReachable: true, latencyMs: 210, packetLossPercent: 20),
            NetworkConnectionHealth(status: .disconnected, reason: "Wi-Fi connected · No internet response", isPathSatisfied: true, isInternetReachable: false, packetLossPercent: 100),
            NetworkConnectionHealth(status: .connected, reason: "Checking connection…", isPathSatisfied: true, isInternetReachable: nil, isProbing: true)
        ]

        for health in states {
            let grid = ConnectionStatusGridView(
                health: health,
                history: history,
                primaryInterface: "en0",
                primaryType: .wifi,
                wifiDetails: WiFiLinkTelemetry(ssid: "TestNet", rssi: -62, noise: -90, txRate: 400, channel: 36, band: "5 GHz")
            )

            // Verify right-aligned slot mapping
            let slots = grid.gridSlots
            XCTAssertEqual(slots.count, ConnectionStatusGridView.totalSlots)
            XCTAssertNil(slots.first!)
            XCTAssertEqual(slots.last??.status, .disconnected)
            XCTAssertEqual(slots[slots.count - 2]?.status, .degraded)
            XCTAssertEqual(slots[slots.count - 3]?.status, .connected)

            let hosting = NSHostingView(rootView: grid)
            hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.contentWidth, height: 220)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.height, 80)
        }
    }

    @MainActor
    func testNetworkPanelDetailsTabDisplaysConnectionGridCleanly() {
        let suiteName = "iStats.test.conngrid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        let base = Date()

        for i in 0..<15 {
            let status: NetworkConnectionStatus = i % 5 == 0 ? .disconnected : (i % 3 == 0 ? .degraded : .connected)
            let health = NetworkConnectionHealth(
                status: status,
                reason: status.displayName,
                isPathSatisfied: status != .disconnected,
                isInternetReachable: status != .disconnected,
                latencyMs: status == .connected ? 18 : (status == .degraded ? 240 : nil),
                packetLossPercent: status == .disconnected ? 100 : (status == .degraded ? 20 : 0)
            )
            let sample = NetworkSample(
                interfaces: [
                    InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 120_000, bytesOutPerSec: 40_000, totalBytesIn: 1_000_000, totalBytesOut: 300_000, ipv4Address: "192.168.1.42", type: .wifi)
                ],
                primaryInterface: "en0",
                primaryType: .wifi,
                localIPv4: "192.168.1.42",
                gatewayIPv4: "192.168.1.1",
                primaryDNS: "1.1.1.1",
                wifiDetails: WiFiLinkTelemetry(ssid: "Lab-5G", rssi: -58, noise: -90, txRate: 650, channel: 36, band: "5 GHz"),
                connectionHealth: health
            )
            coord.handleReading(.network(Sample(value: sample, timestamp: base.addingTimeInterval(Double(i)))))
        }

        XCTAssertEqual(coord.networkConnectionHistory.count, 15)

        let panel = NetworkPanel(initialTab: .detail, rememberLastTab: false, coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: panel)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 520)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(hosting.fittingSize.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(hosting.fittingSize.height, 200)
    }
}
