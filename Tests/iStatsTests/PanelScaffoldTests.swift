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
        var receivedCommand: PanelCommand?

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
}
