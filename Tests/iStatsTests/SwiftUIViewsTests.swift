import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class SwiftUIViewsTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.swiftui.views.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        return (defaults, prefs, coord, suiteName)
    }

    private func cleanup(defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 1. PanelFactory Layout and Data Binding

    func testPanelFactoryAllCategoriesWithData() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Populate sample telemetry into coordinator
        coord.handleReading(.cpu(Sample(value: CPUSample(totalUsage: 35.0, perCore: [30.0, 40.0], user: 20.0, system: 15.0, idle: 65.0))))
        coord.handleReading(.memory(Sample(value: MemorySample(total: 16000, used: 8000, free: 8000, wired: 2000, compressed: 1000, cached: 2000, swapUsed: 0, pressure: .normal))))
        coord.handleReading(.gpu(Sample(value: GPUSample(utilization: 45.0, memoryUsed: 1024, tempCelsius: 50.0, powerWatts: 5.0))))
        coord.handleReading(.thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU Package", celsius: 48.0)], pressure: .nominal))))
        coord.handleReading(.fan(Sample(value: FanSample(fans: [FanReading(name: "Fan 1", rpm: 2500, minRPM: 2000, maxRPM: 6000)]))))
        coord.handleReading(.network(Sample(value: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1000, bytesOutPerSec: 500, totalBytesIn: 1000, totalBytesOut: 500)]))))
        coord.handleReading(.disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 1000, used: 500, free: 500)], io: DiskIO(bytesReadPerSec: 2000, bytesWrittenPerSec: 1000, readOpsPerSec: 20, writeOpsPerSec: 10)))))
        coord.handleReading(.power(Sample(value: PowerSample(hasBattery: true, charge: 85.0, state: .discharging, timeRemaining: 7200))))

        for category in MetricCategory.allCases {
            let view = PanelFactory.makeCategoryPanelView(category: category, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = CGRect(x: 0, y: 0, width: 352, height: 500)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 200, "Fitting width for \(category) should be >= 200pt")
            XCTAssertGreaterThan(fit.height, 100, "Fitting height for \(category) should be >= 100pt")
        }
    }

    func testPanelFactoryColdStartPlaceholders() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Empty coordinator (cold start) -> all categories should calculate valid layout
        for category in MetricCategory.allCases {
            let view = PanelFactory.makeCategoryPanelView(category: category, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = CGRect(x: 0, y: 0, width: 352, height: 500)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 0)
            XCTAssertGreaterThan(fit.height, 0)
        }
    }

    // MARK: - 2. PanelFactory Exhaustive 32-Widget Permutations Test

    func testPanelFactoryExhaustiveRenderAcrossAllCatalogWidgets() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Populate live samples
        coord.handleReading(.cpu(Sample(value: CPUSample(totalUsage: 42.0, perCore: [30.0, 54.0], user: 22.0, system: 20.0, idle: 58.0, efficiencyCoreCount: 2, performanceCoreCount: 2))))
        coord.handleReading(.memory(Sample(value: MemorySample(total: 16 * 1024 * 1024 * 1024, used: 10 * 1024 * 1024 * 1024, free: 6 * 1024 * 1024 * 1024, wired: 3 * 1024 * 1024 * 1024, compressed: 1 * 1024 * 1024 * 1024, cached: 2 * 1024 * 1024 * 1024, swapUsed: 512 * 1024 * 1024, pressure: .normal))))
        coord.handleReading(.gpu(Sample(value: GPUSample(utilization: 60.0, memoryUsed: 2048, tempCelsius: 58.0, powerWatts: 8.5))))
        coord.handleReading(.thermal(Sample(value: ThermalSample(sensors: [
            SensorReading(name: "CPU Package", celsius: 52.0),
            SensorReading(name: "GPU Cluster 1", celsius: 50.0),
            SensorReading(name: "Memory Module A", celsius: 48.0),
            SensorReading(name: "Storage NAND", celsius: 39.0),
            SensorReading(name: "Battery", celsius: 31.0)
        ], pressure: .nominal))))
        coord.handleReading(.fan(Sample(value: FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 2100, minRPM: 1800, maxRPM: 6000),
            FanReading(name: "Right Fan", rpm: 2200, minRPM: 1800, maxRPM: 6000)
        ]))))
        coord.handleReading(.network(Sample(value: NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 500_000, bytesOutPerSec: 250_000, totalBytesIn: 10_000_000, totalBytesOut: 5_000_000)
        ]))))
        coord.handleReading(.disk(Sample(value: DiskSample(
            volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 300_000_000_000, free: 200_000_000_000)],
            io: DiskIO(bytesReadPerSec: 50_000_000, bytesWrittenPerSec: 25_000_000, readOpsPerSec: 150, writeOpsPerSec: 80)
        ))))
        coord.handleReading(.power(Sample(value: PowerSample(hasBattery: true, charge: 75.0, state: .discharging, timeRemaining: 5400, powerDrawWatts: 18.0, adapterWatts: 0.0))))

        for config in MenuBarItemConfig.allAvailableItems {
            let view = PanelFactory.makePanelView(
                config: config,
                coordinator: coord,
                preferences: prefs
            )
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = CGRect(x: 0, y: 0, width: 352, height: 500)
            hosting.layoutSubtreeIfNeeded()
            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 100, "Populated width for \(config.category) - \(config.style) should be >= 100pt")
            XCTAssertGreaterThan(fit.height, 50, "Populated height for \(config.category) - \(config.style) should be >= 50pt")
        }
    }

    // MARK: - 3. 8 Purpose-Driven Panels Concrete Layout & Tabs

    func test8PurposeDrivenPopoversLayout() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let cpu = CPUPanel(coordinator: coord, preferences: prefs)
        let mem = MemoryPanel(coordinator: coord, preferences: prefs)
        let gpu = GPUPanel(coordinator: coord, preferences: prefs)
        let temp = TemperaturePanel(coordinator: coord, preferences: prefs)
        let fan = FanPanel(coordinator: coord, preferences: prefs)
        let net = NetworkPanel(coordinator: coord, preferences: prefs)
        let disk = DiskPanel(coordinator: coord, preferences: prefs)
        let power = PowerPanel(coordinator: coord, preferences: prefs)

        let popovers: [AnyView] = [
            AnyView(cpu), AnyView(mem), AnyView(gpu), AnyView(temp),
            AnyView(fan), AnyView(net), AnyView(disk), AnyView(power)
        ]

        for popover in popovers {
            let hosting = NSHostingView(rootView: popover)
            hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 450)
            hosting.layoutSubtreeIfNeeded()
            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 200)
            XCTAssertGreaterThan(fit.height, 100)
        }
    }

    // MARK: - 4. PreferencesView and Panes Layout

    func testPreferencesViewLayout() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let prefsView = PreferencesView(store: prefs, coordinator: coord)
        let hosting = NSHostingView(rootView: prefsView)
        hosting.frame = CGRect(x: 0, y: 0, width: 880, height: 600)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 400)
        XCTAssertGreaterThan(fit.height, 300)
    }

    func testPreferencesMenuBarPaneLayout() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let pane = PreferencesMenuBarPane(store: prefs, coordinator: coord)
        let hosting = NSHostingView(rootView: pane)
        hosting.frame = CGRect(x: 0, y: 0, width: 700, height: 500)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 100)
        XCTAssertGreaterThan(fit.height, 50)
    }

    func testPreferencesMenuBarPaneWithMultiSourceThermalAndFanlessState() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Configure multi-source temperature widgets
        prefs.menuBarItems = [
            MenuBarItemConfig(category: .thermal, style: .text, source: .cpu),
            MenuBarItemConfig(category: .thermal, style: .glyph, source: .gpu),
            MenuBarItemConfig(category: .network, style: .throughput, throughputLayout: .singleLine),
            MenuBarItemConfig(category: .cpu, style: .gauge, showLabel: true)
        ]

        // Fanless hardware sample
        coord.handleReading(.fan(Sample(value: FanSample(fans: []))))
        coord.handleReading(.thermal(Sample(value: ThermalSample(sensors: [
            SensorReading(name: "CPU Core", celsius: 48.0),
            SensorReading(name: "GPU MESA", celsius: 52.0)
        ], pressure: .nominal))))

        let pane = PreferencesMenuBarPane(store: prefs, coordinator: coord)
        let hosting = NSHostingView(rootView: pane)
        hosting.frame = CGRect(x: 0, y: 0, width: 700, height: 500)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 100)
        XCTAssertGreaterThan(fit.height, 50)

        // Verify active items retained in store
        XCTAssertTrue(prefs.isExactItemEnabled(category: .thermal, style: .text, source: .cpu))
        XCTAssertTrue(prefs.isExactItemEnabled(category: .thermal, style: .glyph, source: .gpu))
    }

    func testPreferencesGeneralPaneLayout() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let pane = PreferencesGeneralPane(store: prefs, coordinator: coord)
        let hosting = NSHostingView(rootView: pane)
        hosting.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 100)
        XCTAssertGreaterThan(fit.height, 50)
    }

    func testPreferencesAlertsPaneLayout() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let pane = PreferencesAlertsPane(store: prefs, coordinator: coord)
        let hosting = NSHostingView(rootView: pane)
        hosting.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 100)
        XCTAssertGreaterThan(fit.height, 50)
    }

    func testPreferencesAboutPaneLayout() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let pane = PreferencesAboutPane(store: prefs, coordinator: coord)
        let hosting = NSHostingView(rootView: pane)
        hosting.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 100)
        XCTAssertGreaterThan(fit.height, 50)
    }

    // MARK: - 6. Instrument Kit Components Smoke Tests

    func testDesignPrimitivesRenderCleanly() {
        let eyebrow = SectionEyebrow("CORE UTILIZATION")
        let eyebrowHosting = NSHostingView(rootView: eyebrow)
        eyebrowHosting.frame = CGRect(x: 0, y: 0, width: 352, height: 20)
        eyebrowHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(eyebrowHosting.fittingSize.width, 50)

        let row = MetricRow(label: "CPU Usage", valueText: "42%", statusLevel: .fine)
        let rowHosting = NSHostingView(rootView: row)
        rowHosting.frame = CGRect(x: 0, y: 0, width: 352, height: 24)
        rowHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(rowHosting.fittingSize.width, 50)

        let meter = Meter(progress: 0.42, tint: .cyan)
        let meterHosting = NSHostingView(rootView: meter)
        meterHosting.frame = CGRect(x: 0, y: 0, width: 352, height: 6)
        meterHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(meterHosting.fittingSize.height, 0)

        let capsule = SplitCapsule(segments: [
            CapsuleSegment(value: 0.6, color: .blue, label: "User"),
            CapsuleSegment(value: 0.4, color: .orange, label: "System")
        ])
        let capHosting = NSHostingView(rootView: capsule)
        capHosting.frame = CGRect(x: 0, y: 0, width: 352, height: 10)
        capHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(capHosting.fittingSize.height, 0)

        let ribbon = StatusRibbon(status: .warning, message: "High workload active")
        let ribHosting = NSHostingView(rootView: ribbon)
        ribHosting.frame = CGRect(x: 0, y: 0, width: 352, height: 24)
        ribHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(ribHosting.fittingSize.width, 50)
    }
}
