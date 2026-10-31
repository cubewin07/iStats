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

    // MARK: - 1. PopoverFactory Layout and Data Binding

    func testPopoverFactoryAllCategoriesWithData() {
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
            let view = PopoverFactory.makeCategoryPopoverView(category: category, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 200, "Fitting width for \(category) should be >= 200pt")
            XCTAssertGreaterThan(fit.height, 100, "Fitting height for \(category) should be >= 100pt")
        }
    }

    func testPopoverFactoryColdStartPlaceholders() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Empty coordinator (cold start) -> all categories should calculate valid layout
        for category in MetricCategory.allCases {
            let view = PopoverFactory.makeCategoryPopoverView(category: category, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 0)
            XCTAssertGreaterThan(fit.height, 0)
        }
    }

    // MARK: - 2. PopoverFactory Exhaustive 32-Widget Permutations Test

    func testPopoverFactoryExhaustiveRenderAcrossAllCatalogWidgets() {
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
            let view = PopoverFactory.makePopoverView(
                config: config,
                coordinator: coord,
                preferences: prefs
            )
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
            hosting.layoutSubtreeIfNeeded()
            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 100, "Populated width for \(config.category) - \(config.style) should be >= 100pt")
            XCTAssertGreaterThan(fit.height, 50, "Populated height for \(config.category) - \(config.style) should be >= 50pt")

            let controller = PopoverFactory.makeHostingController(
                config: config,
                coordinator: coord,
                preferences: prefs
            )
            XCTAssertNotNil(controller.view)
        }
    }

    // MARK: - 3. 8 Purpose-Driven Popovers Concrete Layout & Tabs

    func test8PurposeDrivenPopoversLayout() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let cpu = CPUPopover(coordinator: coord, preferences: prefs)
        let mem = MemoryPopover(coordinator: coord, preferences: prefs)
        let gpu = GPUPopover(coordinator: coord, preferences: prefs)
        let temp = TemperaturePopover(coordinator: coord, preferences: prefs)
        let fan = FanPopover(coordinator: coord, preferences: prefs)
        let net = NetworkPopover(coordinator: coord, preferences: prefs)
        let disk = DiskPopover(coordinator: coord, preferences: prefs)
        let power = PowerPopover(coordinator: coord, preferences: prefs)

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

    // MARK: - 6. Design System Components Smoke Tests

    func testDesignPrimitivesRenderCleanly() {
        let header = PopoverHeader(
            category: .cpu,
            subtitle: "Working normally",
            statusLevel: .fine,
            badgeText: "Fine"
        )
        let headerHosting = NSHostingView(rootView: header)
        headerHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 40)
        headerHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(headerHosting.fittingSize.width, 100)

        let tabBar = TabBar(
            category: .cpu,
            tabs: [.overview, .detail, .history],
            selectedTab: .constant(.overview)
        )
        let tabHosting = NSHostingView(rootView: tabBar)
        tabHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 30)
        tabHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(tabHosting.fittingSize.width, 100)

        let hero = HeroMetric(
            primaryValue: "42",
            unit: "%",
            contextLine: "on 10 cores"
        )
        let heroHosting = NSHostingView(rootView: hero)
        heroHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 60)
        heroHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(heroHosting.fittingSize.width, 50)

        let segmented = SegmentedBar(segments: [
            .init(value: 50, color: .blue, label: "A"),
            .init(value: 50, color: .red, label: "B")
        ])
        let segHosting = NSHostingView(rootView: segmented)
        segHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 10)
        segHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(segHosting.fittingSize.height, 0)

        let legend = LegendRow(color: .mint, label: "App", value: "4 GB", shareText: "50%")
        let stat = StatRow(label: "Key", value: "Val", statusLevel: .warning)
        let range = RangeBar(value: 50, min: 0, max: 100)
        let copy = CopyableValue(label: "IP", value: "127.0.0.1")
        let banner = StatusBanner(iconName: "info.circle", message: "Notice", level: .elevated)
        let skeleton = SkeletonView(width: 100, height: 16)

        let stack = VStack {
            legend
            stat
            range
            copy
            banner
            skeleton
        }
        let stackHosting = NSHostingView(rootView: stack)
        stackHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 200)
        stackHosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(stackHosting.fittingSize.height, 50)
    }

    func testPopoverScaffoldSharedStatesAndTransitions() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // 1. Normal state with content
        let normalScaffold = PopoverScaffold(
            category: .cpu,
            subtitle: "Normal operation",
            statusLevel: .fine,
            badgeText: "Fine",
            tabs: [.overview, .detail, .history],
            selectedTab: .constant(.overview),
            preferences: prefs,
            coordinator: coord
        ) {
            Text("CPU Overview Content")
        }
        let normalHosting = NSHostingView(rootView: normalScaffold)
        normalHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 350)
        normalHosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(normalHosting.fittingSize.width, 330, "PopoverScaffold width must be exactly 330pt")
        XCTAssertGreaterThan(normalHosting.fittingSize.height, 100)

        // 2. Loading state (cold start / nil sample)
        let loadingScaffold = PopoverScaffold(
            category: .memory,
            subtitle: "Loading...",
            statusLevel: .fine,
            badgeText: "Loading",
            tabs: [.overview, .detail, .history],
            selectedTab: .constant(.overview),
            isLoading: true,
            preferences: prefs,
            coordinator: coord
        ) {
            Text("Should not be visible")
        }
        let loadingHosting = NSHostingView(rootView: loadingScaffold)
        loadingHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 350)
        loadingHosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(loadingHosting.fittingSize.width, 330)

        // 3. Unavailable state (.unavailable(reason:))
        let unavailableScaffold = PopoverScaffold(
            category: .gpu,
            subtitle: "Sensor unavailable",
            statusLevel: .warning,
            badgeText: "Unavailable",
            tabs: [.overview, .detail, .history],
            selectedTab: .constant(.overview),
            unavailableReason: "Access denied by sandbox",
            preferences: prefs,
            coordinator: coord
        ) {
            Text("Should not be visible")
        }
        let unavailableHosting = NSHostingView(rootView: unavailableScaffold)
        unavailableHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 350)
        unavailableHosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(unavailableHosting.fittingSize.width, 330)

        // 4. Paused state (preferences.isSamplingPaused == true)
        prefs.isSamplingPaused = true
        let pausedScaffold = PopoverScaffold(
            category: .power,
            subtitle: "Paused",
            statusLevel: .fine,
            badgeText: "Paused",
            tabs: [.overview, .detail, .history],
            selectedTab: .constant(.overview),
            preferences: prefs,
            coordinator: coord
        ) {
            Text("Should not be visible")
        }
        let pausedHosting = NSHostingView(rootView: pausedScaffold)
        pausedHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 350)
        pausedHosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(pausedHosting.fittingSize.width, 330)

        // 5. Footers across categories
        for cat in MetricCategory.allCases {
            let footer = PopoverFooter(category: cat, preferences: prefs, coordinator: coord)
            let footerHosting = NSHostingView(rootView: footer)
            footerHosting.frame = CGRect(x: 0, y: 0, width: 330, height: 30)
            footerHosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(footerHosting.fittingSize.width, 0)
        }
    }
}
