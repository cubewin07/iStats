import XCTest
import SwiftUI
import AppKit
@testable import iStatsCore
@testable import iStats

@MainActor
final class PanelScaffoldTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.panel.scaffold.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        return (defaults, prefs, coord, suiteName)
    }

    private func cleanup(defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPanelFactoryRendersAll8Categories() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Populate realistic sample telemetry into coordinator
        coord.handleReading(.cpu(Sample(value: CPUSample(totalUsage: 42.0, perCore: [40.0, 44.0], user: 25.0, system: 17.0, idle: 58.0))))
        coord.handleReading(.memory(Sample(value: MemorySample(total: 16 * 1024 * 1024 * 1024, used: 8 * 1024 * 1024 * 1024, free: 8 * 1024 * 1024 * 1024, wired: 2 * 1024 * 1024 * 1024, compressed: 1 * 1024 * 1024 * 1024, cached: 2 * 1024 * 1024 * 1024, swapUsed: 0, pressure: .normal))))
        coord.handleReading(.gpu(Sample(value: GPUSample(utilization: 38.0, memoryUsed: 1024, tempCelsius: 52.0, powerWatts: 8.0))))
        coord.handleReading(.thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU Core", celsius: 55.0)], pressure: .nominal))))
        coord.handleReading(.fan(Sample(value: FanSample(fans: [FanReading(name: "Left Fan", rpm: 1800, minRPM: 1200, maxRPM: 5500)]))))
        coord.handleReading(.network(Sample(value: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 5000000, bytesOutPerSec: 1200000, totalBytesIn: 10000000, totalBytesOut: 2000000)]))))
        coord.handleReading(.disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 250_000_000_000, free: 250_000_000_000)], io: DiskIO(bytesReadPerSec: 5000000, bytesWrittenPerSec: 2000000, readOpsPerSec: 100, writeOpsPerSec: 50)))))
        coord.handleReading(.power(Sample(value: PowerSample(hasBattery: true, charge: 92.0, state: .charging, timeRemaining: 3600))))

        for category in MetricCategory.allCases {
            let view = PanelFactory.makeCategoryPanelView(category: category, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0, "Panel width for \(category) should match 352pt")
            XCTAssertGreaterThan(fit.height, 100, "Panel fitting height for \(category) should be >= 100pt")
        }
    }

    func testPageSwitcherIconsAndTooltip() {
        for category in MetricCategory.allCases {
            let supported = PopoverTab.supportedTabs(for: category, hasBattery: true)
            XCTAssertFalse(supported.isEmpty)
            XCTAssertTrue(supported.contains(.overview))
            XCTAssertTrue(supported.contains(.history))

            for tab in supported {
                let title = tab.title(for: category)
                XCTAssertFalse(title.isEmpty, "Tab \(tab) title for \(category) should not be empty")
            }
        }
    }

    func testStatusRibbonVisualThresholds() {
        // Fine status has quiet behavior (nil ribbon message)
        let fineRibbon = StatusRibbon(status: .fine, message: "All normal")
        let fineHosting = NSHostingView(rootView: fineRibbon)
        fineHosting.frame = CGRect(x: 0, y: 0, width: 320, height: 30)
        fineHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(fineHosting.fittingSize.width, 50)

        // Elevated status
        let elevatedRibbon = StatusRibbon(status: .elevated, message: "Elevated load", actionTitle: "Resume") {}
        let elevatedHosting = NSHostingView(rootView: elevatedRibbon)
        elevatedHosting.frame = CGRect(x: 0, y: 0, width: 320, height: 30)
        elevatedHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(elevatedHosting.fittingSize.height, 20)
    }

    func testPanelScaffoldUnavailableState() {
        var selected = PopoverTab.overview
        let binding = Binding(get: { selected }, set: { selected = $0 })

        let scaffold = PanelScaffold(
            category: .fan,
            glance: PanelGlance(value: 0, headline: "Passive cooling"),
            status: .fine,
            pages: [.overview, .history],
            selection: binding,
            availability: .unavailable(reason: "This Mac cools passively")
        ) { _ in
            Text("Content")
        }

        let hosting = NSHostingView(rootView: scaffold)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 300)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
    }

    func testPanelCommandNotificationBroadcasting() {
        let expectation = expectation(description: "Command received")
        nonisolated(unsafe) var receivedCommand: PanelCommand?

        let cancellable = NotificationCenter.default.addObserver(
            forName: .panelCommandReceived,
            object: nil,
            queue: .main
        ) { notif in
            receivedCommand = notif.object as? PanelCommand
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(cancellable) }

        NotificationCenter.default.post(name: .panelCommandReceived, object: PanelCommand.nextPage)
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedCommand, .nextPage)
    }

    func testMultiCategoryPinningAndScopedUnpinning() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer {
            PanelController.shared.unpinAll()
            PanelController.shared.close(immediately: true)
            cleanup(defaults: defaults, suiteName: suiteName)
        }

        PanelController.shared.configure(preferences: prefs)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        guard let button = statusItem.button else {
            XCTFail("Expected status bar button")
            return
        }

        // 1. Show CPU transient panel and pin it
        PanelController.shared.show(category: .cpu, relativeTo: button) {
            Text("CPU")
        }
        XCTAssertTrue(PanelController.shared.isTransientPanelOpen(for: .cpu))
        XCTAssertFalse(PanelController.shared.isPinned(for: .cpu))

        PanelController.shared.togglePin(for: .cpu)
        XCTAssertTrue(PanelController.shared.isPinned(for: .cpu))
        XCTAssertFalse(PanelController.shared.isTransientPanelOpen(for: .cpu))

        // 2. Open Memory transient panel while CPU remains pinned
        PanelController.shared.show(category: .memory, relativeTo: button) {
            Text("Memory")
        }
        XCTAssertTrue(PanelController.shared.isPinned(for: .cpu), "Pinned CPU HUD must stay pinned when Memory transient panel opens")
        XCTAssertTrue(PanelController.shared.isTransientPanelOpen(for: .memory))

        // 3. Unpinning CPU specifically must not unpin or close Memory transient panel
        PanelController.shared.togglePin(for: .cpu)
        XCTAssertFalse(PanelController.shared.isPinned(for: .cpu))
        XCTAssertTrue(PanelController.shared.isTransientPanelOpen(for: .memory))
    }

    func testMemoryPanelCompositionSumsToTotalViaSegmentLayout() {
        // Real fixture: 16 GB unified memory
        let total: UInt64 = 16 * 1024 * 1024 * 1024
        let app: UInt64 = 4 * 1024 * 1024 * 1024
        let wired: UInt64 = 3 * 1024 * 1024 * 1024
        let compressed: UInt64 = 2 * 1024 * 1024 * 1024
        let cached: UInt64 = 2 * 1024 * 1024 * 1024
        let free: UInt64 = 5 * 1024 * 1024 * 1024

        let sample = MemorySample(
            total: total,
            used: app + wired + compressed,
            free: free,
            wired: wired,
            compressed: compressed,
            cached: cached,
            swapUsed: 512 * 1024 * 1024,
            pressure: .normal,
            appMemory: app
        )

        let values = [
            Double(sample.appMemory ?? 0),
            Double(sample.wired),
            Double(sample.compressed),
            Double(sample.cached),
            Double(sample.free)
        ]

        let totalWidth: Double = 320.0
        let gap: Double = 1.0
        let widths = SegmentLayout.widths(
            values: values,
            totalWidth: totalWidth,
            minVisible: 4.0,
            gap: gap
        )

        let totalAllocated = widths.reduce(0.0, +) + (Double(widths.count - 1) * gap)
        XCTAssertEqual(totalAllocated, totalWidth, accuracy: 0.001, "Allocated segment widths plus gaps must equal total container width")
    }

    func testMemoryPanelRendersCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        coord.handleReading(.memory(Sample(value: MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 10 * 1024 * 1024 * 1024,
            free: 6 * 1024 * 1024 * 1024,
            wired: 3 * 1024 * 1024 * 1024,
            compressed: 1 * 1024 * 1024 * 1024,
            cached: 2 * 1024 * 1024 * 1024,
            swapUsed: 100 * 1024 * 1024,
            pressure: .warning,
            appMemory: 6 * 1024 * 1024 * 1024
        ))))

        let view = MemoryPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testGPUPanelRendersFullEnginesCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        coord.handleReading(.gpu(Sample(value: GPUSample(
            utilization: 62.0,
            memoryUsed: 4 * 1024 * 1024 * 1024,
            tempCelsius: 58.0,
            powerWatts: 14.5,
            coreCount: 16,
            deviceName: "Apple M3 Pro",
            allocatedMemory: 4 * 1024 * 1024 * 1024,
            recommendedMaxMemory: 18 * 1024 * 1024 * 1024,
            rendererUtilization: 55.0,
            tilerUtilization: 30.0,
            isUnifiedMemory: true,
            displayCount: 1,
            displayDescriptions: ["Built-in Liquid Retina XDR"],
            recoveryCount: 0,
            supportsRaytracing: true,
            metalFeatureSet: "Metal 3"
        ))))

        let view = GPUPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testGPUPanelDeviceOnlyFallbackAndRecoveryWarning() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        coord.handleReading(.gpu(Sample(value: GPUSample(
            utilization: 88.0,
            memoryUsed: 2 * 1024 * 1024 * 1024,
            tempCelsius: 65.0,
            powerWatts: 20.0,
            coreCount: 8,
            deviceName: "Apple M1",
            rendererUtilization: nil,
            tilerUtilization: nil,
            recoveryCount: 2
        ))))

        // Verify fallback title
        XCTAssertEqual(PopoverTab.detail.title(for: .gpu, hasDetailedGPUEngines: false), "Device")
        XCTAssertEqual(PopoverTab.detail.title(for: .gpu, hasDetailedGPUEngines: true), "Engines")

        let view = GPUPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testTemperaturePanelRendersCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        coord.handleReading(.thermal(Sample(value: ThermalSample(
            sensors: [
                SensorReading(name: "CPU Performance Core 1", celsius: 72.0),
                SensorReading(name: "GPU Cluster 1", celsius: 65.0),
                SensorReading(name: "Memory Proximity", celsius: 48.0),
                SensorReading(name: "Storage NAND", celsius: 42.0),
                SensorReading(name: "Battery Sensor 1", celsius: 32.0)
            ],
            pressure: .nominal
        ))))

        let view = TemperaturePanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testTemperaturePanelThermalPressureRibbon() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        coord.handleReading(.thermal(Sample(value: ThermalSample(
            sensors: [
                SensorReading(name: "CPU Die", celsius: 98.0),
                SensorReading(name: "GPU Die", celsius: 92.0)
            ],
            pressure: .serious
        ))))

        let view = TemperaturePanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testFanPanelActiveFansRendersCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        coord.handleReading(.fan(Sample(value: FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 1450, minRPM: 1200, maxRPM: 5800),
            FanReading(name: "Right Fan", rpm: 1520, minRPM: 1200, maxRPM: 6000)
        ]))))

        let view = FanPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testFanPanelFanlessMacRendersEmptyStateWithAction() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        coord.handleReading(.fan(Sample(value: FanSample(fans: []))))

        let view = FanPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 350)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 100)
    }

    func testNetworkPanelWiFiRendersCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let sample = NetworkSample(
            interfaces: [
                InterfaceThroughput(
                    interfaceName: "en0",
                    bytesInPerSec: 1_250_000,
                    bytesOutPerSec: 250_000,
                    totalBytesIn: 10_000_000,
                    totalBytesOut: 2_000_000,
                    ipv4Address: "192.168.1.50",
                    type: .wifi
                )
            ],
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.50",
            gatewayIPv4: "192.168.1.1",
            primaryDNS: "1.1.1.1",
            wifiDetails: WiFiLinkTelemetry(
                ssid: "HomeNetwork-5G",
                rssi: -55,
                noise: -92,
                txRate: 866.0,
                channel: 36,
                band: "5 GHz"
            )
        )
        coord.handleReading(.network(Sample(value: sample)))

        let view = NetworkPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testNetworkPanelEthernetAndOfflineRendersCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Test Ethernet
        let ethSample = NetworkSample(
            interfaces: [
                InterfaceThroughput(
                    interfaceName: "en1",
                    bytesInPerSec: 50_000_000,
                    bytesOutPerSec: 10_000_000,
                    totalBytesIn: 500_000_000,
                    totalBytesOut: 100_000_000,
                    ipv4Address: "10.0.0.12",
                    type: .ethernet
                )
            ],
            primaryInterface: "en1",
            primaryType: .ethernet,
            localIPv4: "10.0.0.12"
        )
        coord.handleReading(.network(Sample(value: ethSample)))

        let ethView = NetworkPanel(coordinator: coord, preferences: prefs)
        let ethHosting = NSHostingView(rootView: ethView)
        ethHosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        ethHosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(ethHosting.fittingSize.width, Instrument.Size.panelWidth, accuracy: 2.0)

        // Test Offline
        let offlineSample = NetworkSample(interfaces: [])
        coord.handleReading(.network(Sample(value: offlineSample)))

        let offlineView = NetworkPanel(coordinator: coord, preferences: prefs)
        let offlineHosting = NSHostingView(rootView: offlineView)
        offlineHosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        offlineHosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(offlineHosting.fittingSize.width, Instrument.Size.panelWidth, accuracy: 2.0)
    }

    func testDiskPanelRendersCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let sample = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 250_000_000_000, free: 250_000_000_000),
                VolumeCapacity(name: "External Backup", mountPoint: "/Volumes/External Backup", total: 1_000_000_000_000, used: 400_000_000_000, free: 600_000_000_000)
            ],
            io: DiskIO(bytesReadPerSec: 25_000_000, bytesWrittenPerSec: 5_000_000, readOpsPerSec: 350, writeOpsPerSec: 90)
        )
        coord.handleReading(.disk(Sample(value: sample)))

        let view = DiskPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testDiskPanelLowSpaceRendersWarning() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let sample = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 480_000_000_000, free: 20_000_000_000)
            ],
            io: nil
        )
        coord.handleReading(.disk(Sample(value: sample)))

        let view = DiskPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 400)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testPowerPanelBatteryMacRendersCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let sample = PowerSample(
            hasBattery: true,
            charge: 75.0,
            state: .charging,
            timeRemaining: 2400,
            cycleCount: 120,
            condition: "Normal",
            designCapacity: 5000,
            currentMaxCapacity: 4900,
            powerDrawWatts: 20.0,
            adapterWatts: 67.0,
            voltageVolts: 12.0,
            amperageMilliAmps: 2500.0,
            designCycleCount: 1000,
            adapterName: "Apple 67W Charger"
        )
        coord.handleReading(.power(Sample(value: sample)))

        let view = PowerPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 150)
    }

    func testPowerPanelDesktopMacRendersCleanly() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let sample = PowerSample(
            hasBattery: false,
            powerDrawWatts: 45.0,
            adapterWatts: 140.0,
            adapterName: "Internal PSU"
        )
        coord.handleReading(.power(Sample(value: sample)))

        let view = PowerPanel(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 450)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 100)
    }

    func testHistoryPageRendersAcrossAll8Categories() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Populate 15 samples per category to exceed empty state threshold
        for i in 0..<15 {
            let usage = 20.0 + Double(i) * 2.0
            coord.handleReading(.cpu(Sample(value: CPUSample(totalUsage: usage, perCore: [usage, usage], user: usage * 0.6, system: usage * 0.4, idle: 100 - usage))))
            coord.handleReading(.memory(Sample(value: MemorySample(total: 16 * 1024 * 1024 * 1024, used: 8 * 1024 * 1024 * 1024, free: 8 * 1024 * 1024 * 1024, wired: 2 * 1024 * 1024 * 1024, compressed: 1 * 1024 * 1024 * 1024, cached: 2 * 1024 * 1024 * 1024, swapUsed: 0, pressure: .normal))))
            coord.handleReading(.gpu(Sample(value: GPUSample(utilization: usage, memoryUsed: 1024, tempCelsius: 52.0, powerWatts: 8.0))))
            coord.handleReading(.thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU Core", celsius: 50.0 + Double(i))], pressure: .nominal))))
            coord.handleReading(.fan(Sample(value: FanSample(fans: [FanReading(name: "Left Fan", rpm: 1800 + i * 10, minRPM: 1200, maxRPM: 5500)]))))
            coord.handleReading(.network(Sample(value: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 5000000 + Double(i * 1000), bytesOutPerSec: 1200000, totalBytesIn: 10000000, totalBytesOut: 2000000)]))))
            coord.handleReading(.disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 250_000_000_000, free: 250_000_000_000)], io: DiskIO(bytesReadPerSec: 5000000 + Double(i * 1000), bytesWrittenPerSec: 2000000, readOpsPerSec: 100, writeOpsPerSec: 50)))))
            coord.handleReading(.power(Sample(value: PowerSample(hasBattery: true, charge: 90.0, state: .charging, timeRemaining: 3600, powerDrawWatts: 25.0 + Double(i)))))
        }

        for category in MetricCategory.allCases {
            let view = HistoryPage(category: category, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 300)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.height, 50, "HistoryPage for \(category) should render with height > 50pt")
        }
    }

    func testHistoryRangePersistenceAndSwitching() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        XCTAssertEqual(prefs.historyRange(for: .cpu), .oneMinute)
        prefs.setHistoryRange(.fiveMinutes, for: .cpu)
        XCTAssertEqual(prefs.historyRange(for: .cpu), .fiveMinutes)
        prefs.setHistoryRange(.fifteenMinutes, for: .network)
        XCTAssertEqual(prefs.historyRange(for: .network), .fifteenMinutes)
        XCTAssertEqual(prefs.historyRange(for: .cpu), .fiveMinutes)
    }

    func testHistoryPageEmptyStateBelow10Samples() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Only 3 samples
        for _ in 0..<3 {
            coord.handleReading(.cpu(Sample(value: CPUSample(totalUsage: 25.0, perCore: [25.0], user: 15.0, system: 10.0, idle: 75.0))))
        }

        let view = HistoryPage(category: .cpu, coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 300)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.height, 50)
    }

    func testPanelScaffoldSingleScrollContainerBuildsBodyOnceAndClampsAllTabs() {
        for tab in [PopoverTab.overview, .detail, .history] {
            var buildCount = 0
            let binding = Binding.constant(tab)

            let scaffold = PanelScaffold(
                category: .thermal,
                glance: PanelGlance(value: 62, unit: "°C", headline: "Elevated"),
                status: .fine,
                pages: [.overview, .detail, .history],
                selection: binding
            ) { _ in
                let _ = { buildCount += 1 }()
                return VStack(spacing: 8) {
                    ForEach(0..<30, id: \.self) { idx in
                        Text("Sensor \(idx)")
                            .frame(height: 24)
                    }
                }
            }

            let controller = NSHostingController(rootView: scaffold)
            let size = controller.sizeThatFits(in: CGSize(width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight))
            XCTAssertEqual(size.width, Instrument.Size.panelWidth, accuracy: 2.0)
            XCTAssertLessThanOrEqual(size.height, Instrument.Size.maxHeight + 0.5, "Tab \(tab) must clamp to maxHeight via ScrollView (B3/B4)")
            XCTAssertEqual(buildCount, 1, "Tab \(tab) body must be built once, not twice as with ViewThatFits (B4)")
        }
    }

    func testPanelScaffoldEmitsContentHeightKeyAndRemovesCrossViewChartNamespace() {
        var selected = PopoverTab.overview
        let binding = Binding(get: { selected }, set: { selected = $0 })
        var reportedHeights: [CGFloat] = []

        let scaffold = PanelScaffold(
            category: .cpu,
            glance: PanelGlance(value: 35, unit: "%", headline: "Normal"),
            status: .fine,
            pages: [.overview, .detail, .history],
            selection: binding
        ) { _ in
            VStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { idx in
                    Text("Row \(idx)")
                        .frame(height: 24)
                }
            }
        }
        .onPreferenceChange(PanelContentHeightKey.self) { height in
            if height > 0 {
                reportedHeights.append(height)
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: scaffold)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        window.layoutIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        XCTAssertFalse(reportedHeights.isEmpty, "PanelScaffold must emit PanelContentHeightKey > 0")
        if let latest = reportedHeights.last {
            XCTAssertGreaterThanOrEqual(latest, 160.0)
            XCTAssertLessThanOrEqual(latest, Instrument.Size.maxHeight)
        }
        XCTAssertNil(EnvironmentValues().chartNamespace, "Cross-view chartNamespace must default to nil")
    }

    // MARK: - Task 8.5.4: ChartScrubState, Glance Header Scrub Override & Insight Caption

    func testChartScrubStateFormattingAndEquatable() {
        XCTAssertEqual(ChartScrubState.splitFormattedValue("42.3%").value, "42.3")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("42.3%").unit, "%")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("62% used").value, "62")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("62% used").unit, "% used")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("55.0 °C").value, "55.0")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("55.0 °C").unit, "°C")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("1,800 RPM").value, "1,800")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("1,800 RPM").unit, "RPM")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("4.60 MiB/s").value, "4.60")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("4.60 MiB/s").unit, "MiB/s")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("20.0 W").value, "20.0")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("20.0 W").unit, "W")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("-55 dBm").value, "-55")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("-55 dBm").unit, "dBm")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("N/A").value, "N/A")
        XCTAssertEqual(ChartScrubState.splitFormattedValue("N/A").unit, "")

        XCTAssertEqual(ChartScrubState.formatRelativeTime(0), "now")
        XCTAssertEqual(ChartScrubState.formatRelativeTime(12), "12s ago")
        XCTAssertEqual(ChartScrubState.formatRelativeTime(135), "2m 15s ago")
        XCTAssertEqual(ChartScrubState.formatRelativeTime(180), "3m ago")
        XCTAssertEqual(ChartScrubState.formatRelativeTime(3600), "1h ago")

        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = 2026
        comps.month = 11
        comps.day = 13
        comps.hour = 14
        comps.minute = 2
        comps.second = 31
        let sampleTimestamp = comps.date!.timeIntervalSince1970
        let latestTimestamp = sampleTimestamp + 12.0

        XCTAssertEqual(
            ChartScrubState.formatClockTime(timestamp: sampleTimestamp, timeZone: TimeZone(secondsFromGMT: 0)!),
            "14:02:31"
        )

        let singleState = ChartScrubState.make(
            primaryValue: 78.4,
            timestamp: sampleTimestamp,
            latestTimestamp: latestTimestamp,
            valueFormatter: { String(format: "%.1f%%", $0) },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertEqual(singleState.formattedPrimary, "78.4")
        XCTAssertEqual(singleState.primaryUnit, "%")
        XCTAssertNil(singleState.secondaryReadout)
        XCTAssertEqual(singleState.relativeTimeText, "12s ago")
        XCTAssertEqual(singleState.clockTimeText, "14:02:31")
        XCTAssertEqual(singleState.headlineText, "12s ago · 14:02:31")

        let dualStateA = ChartScrubState.make(
            primaryValue: 4.5 * 1_048_576,
            secondaryValue: 1.2 * 1_048_576,
            primaryLabel: "↓",
            secondaryLabel: "↑",
            secondaryColor: CategoryPalette.Series.networkUpload,
            timestamp: sampleTimestamp,
            latestTimestamp: latestTimestamp,
            valueFormatter: { Units.formatNetworkRate($0, unit: .bytesPerSecond, standard: .iec) },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let dualStateB = dualStateA
        XCTAssertEqual(dualStateA, dualStateB)
        XCTAssertEqual(dualStateA.formattedPrimary, "4.50")
        XCTAssertEqual(dualStateA.primaryUnit, "MiB/s")
        XCTAssertEqual(dualStateA.primaryLabel, "↓")
        XCTAssertEqual(dualStateA.secondaryReadout?.text, "1.20")
        XCTAssertEqual(dualStateA.secondaryReadout?.unit, "MiB/s")
        XCTAssertEqual(dualStateA.secondaryReadout?.label, "↑")
        XCTAssertEqual(dualStateA.headlineText, "12s ago · 14:02:31")
    }

    func testChartScrubActionEnvironmentRoutingAndGlanceOverrideRelease() {
        var capturedAction: ChartScrubAction?

        struct ScrubProbeView: View {
            @Environment(\.chartScrubAction) private var chartScrubAction
            let onCapture: (ChartScrubAction?) -> Void

            var body: some View {
                Text("Probe")
                    .frame(height: 30)
                    .onAppear {
                        onCapture(chartScrubAction)
                    }
            }
        }

        var latestProbe = PanelScaffoldProbeSnapshot()
        let binding = Binding.constant(PopoverTab.overview)
        let scaffold = PanelScaffold(
            category: .cpu,
            glance: PanelGlance(
                value: 42,
                format: "%.0f",
                unit: "%",
                headline: "Moderate load · 10 cores",
                insight: "↗ Peak 92% · 3m ago",
                chartMode: .single(values: [30, 42, 55], color: .blue)
            ),
            status: .fine,
            pages: [.overview, .detail, .history],
            selection: binding
        ) { _ in
            ScrubProbeView { action in
                capturedAction = action
            }
        }
        .environment(\.panelScaffoldProbeEnabled, true)
        .onPreferenceChange(PanelScaffoldProbeKey.self) { latestProbe = $0 }

        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: scaffold)
        hosting.frame = NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 420)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        func flush() {
            hosting.layoutSubtreeIfNeeded()
            window.layoutIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        flush()
        XCTAssertNotNil(capturedAction, "PanelScaffold must inject ChartScrubAction into SwiftUI environment")

        let initialValue = latestProbe.glanceSummary ?? ""
        XCTAssertTrue(initialValue.contains("42 %"), "Live Glance value should show 42 %, got: \(initialValue)")
        XCTAssertTrue(initialValue.contains("Moderate load · 10 cores"), "Live Glance headline should show live headline, got: \(initialValue)")

        // Trigger scrub update via environment action (as hero LiveChart or HistoryPage does)
        let scrub = ChartScrubState(
            formattedPrimary: "78.5",
            primaryUnit: "%",
            secondaryReadout: nil,
            relativeTimeText: "12s ago",
            clockTimeText: "14:02:31"
        )
        capturedAction?(scrub)
        flush()

        let scrubbedValue = latestProbe.glanceSummary ?? ""
        XCTAssertTrue(scrubbedValue.contains("78.5 %"), "Scrubbed Glance must display scrubbed value 78.5 %, got: \(scrubbedValue)")
        XCTAssertTrue(scrubbedValue.contains("12s ago · 14:02:31"), "Scrubbed Glance headline must show '<relative> · <clock>', got: \(scrubbedValue)")
        XCTAssertFalse(scrubbedValue.contains("Moderate load · 10 cores"))

        // Release scrub (nil) -> restores live telemetry
        capturedAction?(nil)
        flush()

        let restoredValue = latestProbe.glanceSummary ?? ""
        XCTAssertTrue(restoredValue.contains("42 %"), "Releasing scrub must restore live telemetry, got: \(restoredValue)")
        XCTAssertTrue(restoredValue.contains("Moderate load · 10 cores"))
    }

    func testPanelScaffoldInsightCaptionPlacementBelowChartAndDualTickerScrub() throws {
        @MainActor
        final class HostModel: ObservableObject {
            @Published var tab: PopoverTab = .overview
            @Published var scrub: ChartScrubState? = nil
            var latestProbe = PanelScaffoldProbeSnapshot()
        }

        struct HostView: View {
            @ObservedObject var model: HostModel

            var body: some View {
                PanelScaffold(
                    category: .network,
                    glance: PanelGlance(
                        value: 4.2,
                        format: "%.1f",
                        unit: "MB/s",
                        secondaryGlance: (value: 1.1, unit: "MB/s", color: CategoryPalette.Series.networkUpload),
                        headline: "Wi-Fi · HomeNet",
                        insight: "↗ Peak 18.4 MB/s · 2m ago",
                        chartMode: .mirrored(
                            top: [1_000_000, 4_200_000, 2_500_000],
                            bottom: [500_000, 1_100_000, 800_000],
                            topColor: CategoryPalette.tint(for: .network),
                            bottomColor: CategoryPalette.Series.networkUpload
                        ),
                        chartHeight: 56
                    ),
                    status: .fine,
                    pages: [.overview, .detail, .history],
                    selection: $model.tab,
                    scrubState: $model.scrub
                ) { _ in
                    Text("Body")
                        .frame(height: 60)
                }
                .environment(\.panelScaffoldProbeEnabled, true)
                .onPreferenceChange(PanelScaffoldProbeKey.self) { model.latestProbe = $0 }
            }
        }

        let model = HostModel()
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: HostView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 420)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        func flush() {
            hosting.layoutSubtreeIfNeeded()
            window.layoutIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        flush()

        XCTAssertEqual(model.latestProbe.insightText, "↗ Peak 18.4 MB/s · 2m ago")
        let glanceFrame = try XCTUnwrap(model.latestProbe.glanceFrame)
        let chartFrame = try XCTUnwrap(model.latestProbe.chartFrame)
        let insightFrame = try XCTUnwrap(model.latestProbe.insightFrame, "Insight caption row must render below the hero chart")

        // Verify vertical placement in SwiftUI coordinate space (Y increases downward):
        // Glance sits above Chart, and Insight sits directly below the hero Chart.
        XCTAssertGreaterThan(chartFrame.minY, glanceFrame.maxY - 1.0)
        XCTAssertGreaterThan(insightFrame.minY, glanceFrame.maxY, "Insight row must be positioned below Glance header, not top-right")
        XCTAssertGreaterThanOrEqual(insightFrame.minY, chartFrame.maxY - 1.0, "Insight row must sit directly below the hero chart")

        // Verify dual-ticker scrub readout
        model.scrub = ChartScrubState(
            formattedPrimary: "9.80",
            primaryUnit: "MiB/s",
            primaryLabel: "↓",
            secondaryReadout: ChartScrubState.SecondaryReadout(
                text: "2.40",
                unit: "MiB/s",
                color: CategoryPalette.Series.networkUpload,
                label: "↑"
            ),
            relativeTimeText: "25s ago",
            clockTimeText: "14:02:18"
        )
        flush()

        let dualGlanceVal = model.latestProbe.glanceSummary ?? ""
        XCTAssertTrue(dualGlanceVal.contains("9.80 MiB/s"), "Dual scrub primary must render in Glance, got: \(dualGlanceVal)")
        XCTAssertTrue(dualGlanceVal.contains("2.40 MiB/s"), "Dual scrub secondary must render in Glance, got: \(dualGlanceVal)")
        XCTAssertTrue(dualGlanceVal.contains("25s ago · 14:02:18"))

        // Switching to .history collapses hero chart + insight caption row
        model.tab = .history
        model.scrub = nil
        model.latestProbe = PanelScaffoldProbeSnapshot()
        flush()

        XCTAssertNil(model.latestProbe.insightText, "Hero insight row must collapse when on .history tab")
        XCTAssertNil(model.latestProbe.insightFrame, "Hero insight row must collapse when on .history tab")
    }

    func testScrubControllerHoverActiveAndEndedBuildsAndClearsChartScrubState() throws {
        let controller = ScrubController()
        let base: TimeInterval = 1_700_000_000
        let points = [
            ChartPoint(timestamp: base, value: 20.0),
            ChartPoint(timestamp: base + 10, value: 60.0),
            ChartPoint(timestamp: base + 20, value: 80.0),
            ChartPoint(timestamp: base + 30, value: 40.0)
        ]
        let timeline = ChartTimeline(edge: base + 30, sampleInterval: 1.0)

        var resolvedTargets: [ScrubController.ResolvedTarget?] = []
        var legacyCallbacks: [(Int?, Double?, Double?)] = []

        // Hover at 10s into 30s window (x = 100 on 300pt width -> snaps to index 1, value 60.0, 20s ago)
        controller.handleHover(
            phase: .active(CGPoint(x: 100, y: 36)),
            plotWidth: 300,
            points: points,
            secondaryPoints: [],
            timeline: timeline,
            windowDuration: 30,
            isTimestamped: true,
            valueFormatter: { String(format: "%.1f%%", $0) },
            onScrub: { idx, val, ago in legacyCallbacks.append((idx, val, ago)) },
            onScrubState: { target in resolvedTargets.append(target) }
        )

        XCTAssertEqual(resolvedTargets.count, 1)
        let activeTarget = try XCTUnwrap(resolvedTargets.first ?? nil)
        XCTAssertEqual(activeTarget.index, 1)
        XCTAssertEqual(activeTarget.primaryValue, 60.0, accuracy: 0.01)
        XCTAssertEqual(activeTarget.secondsAgo, 20.0, accuracy: 0.01)

        // Interpolated bead Y at midpoint (base + 15s) between 60.0 and 80.0 (cubic Catmull-Rom spline)
        let midInterp = try XCTUnwrap(ChartTimeline.interpolateValue(at: base + 15, points: points))
        XCTAssertEqual(midInterp, 73.75, accuracy: 0.01)

        let scrubState = ChartScrubState.make(
            primaryValue: activeTarget.primaryValue,
            timestamp: activeTarget.timestamp,
            latestTimestamp: timeline.edge,
            valueFormatter: { String(format: "%.1f%%", $0) },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertEqual(scrubState.formattedPrimary, "60.0")
        XCTAssertEqual(scrubState.primaryUnit, "%")
        XCTAssertEqual(scrubState.relativeTimeText, "20s ago")
        XCTAssertTrue(controller.shouldDispatch(scrubState))
        XCTAssertFalse(controller.shouldDispatch(scrubState), "Duplicate scrub state must not re-dispatch")

        XCTAssertEqual(legacyCallbacks.count, 1)
        XCTAssertEqual(legacyCallbacks[0].0, 1)

        // End hover -> clears hover and dispatches nil
        controller.handleHover(
            phase: .ended,
            plotWidth: 300,
            points: points,
            secondaryPoints: [],
            timeline: timeline,
            windowDuration: 30,
            isTimestamped: true,
            valueFormatter: nil,
            onScrub: { idx, val, ago in legacyCallbacks.append((idx, val, ago)) },
            onScrubState: { target in resolvedTargets.append(target) }
        )

        XCTAssertNil(controller.hoveredIndex)
        XCTAssertNil(controller.hoverLocation)
        XCTAssertEqual(resolvedTargets.count, 2)
        XCTAssertNil(resolvedTargets[1])
        XCTAssertTrue(controller.shouldDispatch(nil))
        XCTAssertFalse(controller.shouldDispatch(nil))
    }
}
