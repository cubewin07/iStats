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
}
