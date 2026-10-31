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

    // MARK: - 1. CategoryDetailPopoverView Layout and Data Binding

    func testCategoryDetailPopoverViewAllCategoriesWithData() {
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
            let view = CategoryDetailPopoverView(category: category, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 200, "Fitting width for \(category) should be >= 200pt")
            XCTAssertGreaterThan(fit.height, 100, "Fitting height for \(category) should be >= 100pt")
        }
    }

    func testCategoryDetailPopoverViewColdStartPlaceholders() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Empty coordinator (cold start) -> all categories should calculate valid layout
        for category in MetricCategory.allCases {
            let view = CategoryDetailPopoverView(category: category, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 0)
            XCTAssertGreaterThan(fit.height, 0)
        }
    }

    // MARK: - 1b. ConfigPopoverFactory Exhaustive Permutations Test

    func testConfigPopoverFactoryExhaustiveRenderWithDataAndColdStart() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // 1. Cold start check (no samples in coordinator)
        for category in MetricCategory.allCases {
            let stylesWithBattery = PopoverStyle.supportedPopovers(for: category, hasBattery: true)
            for style in stylesWithBattery {
                let view = ConfigPopoverFactory.makePopoverView(
                    category: category,
                    popoverStyle: style,
                    coordinator: coord,
                    preferences: prefs
                )
                let hosting = NSHostingView(rootView: AnyView(view))
                hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
                hosting.layoutSubtreeIfNeeded()
                let fit = hosting.fittingSize
                XCTAssertGreaterThan(fit.width, 0, "Cold start width for \(category) - \(style) should be > 0")
                XCTAssertGreaterThan(fit.height, 0, "Cold start height for \(category) - \(style) should be > 0")
            }

            // Also check batteryless styles (especially for thermal and power)
            let stylesWithoutBattery = PopoverStyle.supportedPopovers(for: category, hasBattery: false)
            for style in stylesWithoutBattery {
                let controller = ConfigPopoverFactory.makeHostingController(
                    category: category,
                    popoverStyle: style,
                    coordinator: coord,
                    preferences: prefs
                )
                XCTAssertNotNil(controller.view)
            }
        }

        // 2. Populated check (with live samples in coordinator)
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

        for category in MetricCategory.allCases {
            let styles = PopoverStyle.supportedPopovers(for: category, hasBattery: true)
            for style in styles {
                let view = ConfigPopoverFactory.makePopoverView(
                    category: category,
                    popoverStyle: style,
                    coordinator: coord,
                    preferences: prefs
                )
                let hosting = NSHostingView(rootView: AnyView(view))
                hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
                hosting.layoutSubtreeIfNeeded()
                let fit = hosting.fittingSize
                XCTAssertGreaterThan(fit.width, 100, "Populated width for \(category) - \(style) should be >= 100pt")
                XCTAssertGreaterThan(fit.height, 50, "Populated height for \(category) - \(style) should be >= 50pt")
            }
        }
    }

    // MARK: - 2. Universal DetailPopoverView Layout

    func testUniversalDetailPopoverViewLayout() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let popover = DetailPopoverView(coordinator: coord, preferences: prefs)
        let hosting = NSHostingView(rootView: popover)
        hosting.frame = CGRect(x: 0, y: 0, width: 340, height: 600)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 250)
        XCTAssertGreaterThan(fit.height, 200)
    }

    // MARK: - 3. Hardware Illustration Views Layout & Geometry

    func testCPUDieIllustrationViewLayout() {
        let sample = CPUSample(
            totalUsage: 55.0,
            perCore: [40.0, 50.0, 60.0, 70.0, 30.0, 45.0, 65.0, 80.0],
            user: 35.0,
            system: 20.0,
            idle: 45.0,
            efficiencyCoreCount: 4,
            performanceCoreCount: 4
        )
        let view = CPUDieIllustrationView(sample: sample)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 180)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 50)
        XCTAssertGreaterThan(fit.height, 50)
    }

    func testMemoryStickIllustrationViewLayout() {
        let sample = MemorySample(
            total: 32 * 1024 * 1024 * 1024,
            used: 24 * 1024 * 1024 * 1024,
            free: 8 * 1024 * 1024 * 1024,
            wired: 6 * 1024 * 1024 * 1024,
            compressed: 4 * 1024 * 1024 * 1024,
            cached: 4 * 1024 * 1024 * 1024,
            swapUsed: 1024 * 1024 * 1024,
            pressure: .warning
        )
        let view = MemoryStickIllustrationView(sample: sample)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 140)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 30)
        XCTAssertGreaterThan(fit.height, 30)
    }

    func testGPUDieIllustrationViewLayout() {
        let sample = GPUSample(utilization: 75.0, memoryUsed: 2048, tempCelsius: 68.0, powerWatts: 12.0)
        let view = GPUDieIllustrationView(sample: sample)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 160)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 40)
        XCTAssertGreaterThan(fit.height, 40)
    }

    func testThermalHeatMapIllustrationViewLayout() {
        let sensors = [
            SensorReading(name: "CPU Package", celsius: 55.0),
            SensorReading(name: "GPU Cluster 1", celsius: 52.0),
            SensorReading(name: "Memory Module A", celsius: 45.0),
            SensorReading(name: "Storage NAND", celsius: 38.0),
            SensorReading(name: "Battery", celsius: 32.0)
        ]
        let sample = ThermalSample(sensors: sensors, pressure: .nominal)
        let view = ThermalHeatMapIllustrationView(sample: sample, temperatureUnit: .celsius)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 180)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 50)
        XCTAssertGreaterThan(fit.height, 50)
    }

    func testFanBladesIllustrationViewLayout() {
        let sample = FanSample(
            fans: [
                FanReading(name: "Left Fan", rpm: 2500, minRPM: 2000, maxRPM: 6000),
                FanReading(name: "Right Fan", rpm: 2700, minRPM: 2000, maxRPM: 6000)
            ]
        )
        let view = FanBladesIllustrationView(sample: sample)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 150)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 40)
        XCTAssertGreaterThan(fit.height, 40)
    }

    func testNetworkPipesIllustrationViewLayout() {
        let sample = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1024 * 1024 * 3.5, bytesOutPerSec: 1024 * 512, totalBytesIn: 1000, totalBytesOut: 500)
        ])
        let view = NetworkPipesIllustrationView(sample: sample)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 140)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 30)
        XCTAssertGreaterThan(fit.height, 20)
    }

    func testDiskStorageTankIllustrationViewLayout() {
        let sample = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500 * 1024 * 1024 * 1024, used: 350 * 1024 * 1024 * 1024, free: 150 * 1024 * 1024 * 1024)
            ]
        )
        let view = DiskStorageTankIllustrationView(sample: sample)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 140)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 30)
        XCTAssertGreaterThan(fit.height, 20)
    }

    func testPowerBudgetIllustrationViewLayout() {
        let sample = PowerSample(
            hasBattery: true,
            charge: 80.0,
            state: .charging,
            powerDrawWatts: 22.5,
            adapterWatts: 67.0
        )
        let view = PowerBudgetIllustrationView(sample: sample)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 140)
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        XCTAssertGreaterThan(fit.width, 50)
        XCTAssertGreaterThan(fit.height, 50)
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
}
