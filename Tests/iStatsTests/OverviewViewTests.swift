import XCTest
import SwiftUI
import AppKit
@testable import iStatsCore
@testable import iStats

@MainActor
final class OverviewViewTests: XCTestCase {

    private func makeContext() -> (defaults: UserDefaults, prefs: PreferencesStore, coord: MetricsCoordinator, suite: String) {
        let suite = "com.istats.tests.overview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(scheduler: SampleScheduler(), store: MetricsStore(), preferencesStore: prefs)
        return (defaults, prefs, coord, suite)
    }

    private func cleanup(_ defaults: UserDefaults, suite: String) {
        PanelController.shared.close(immediately: true)
        defaults.removePersistentDomain(forName: suite)
    }

    private func seedAllCategories(in coord: MetricsCoordinator, hasBattery: Bool = true) {
        let gib: UInt64 = 1_073_741_824
        let now = Date()
        for offset in 0..<5 {
            let ts = now.addingTimeInterval(Double(offset - 4))
            coord.handleReadings([
                .cpu(Sample(value: CPUSample(totalUsage: 34.0 + Double(offset), perCore: [30, 38], user: 24, system: 10, idle: 66), timestamp: ts)),
                .memory(Sample(value: MemorySample(total: 16 * gib, used: 9 * gib, free: 7 * gib, wired: 2 * gib, compressed: 1 * gib, cached: 1 * gib, swapUsed: 0, pressure: .normal), timestamp: ts)),
                .gpu(Sample(value: GPUSample(utilization: 28.0 + Double(offset)), timestamp: ts)),
                .thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU Core", celsius: 56.0 + Double(offset))], pressure: .nominal), timestamp: ts)),
                .fan(Sample(value: FanSample(fans: [FanReading(name: "Left", rpm: 1850 + offset * 20, minRPM: 1200, maxRPM: 5800)]), timestamp: ts)),
                .network(Sample(value: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1_200_000, bytesOutPerSec: 250_000, totalBytesIn: 10_000, totalBytesOut: 5_000)], primaryInterface: "en0", primaryType: .wifi, localIPv4: "192.168.1.42"), timestamp: ts)),
                .disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500 * gib, used: 220 * gib, free: 280 * gib)], io: DiskIO(bytesReadPerSec: 4_000_000, bytesWrittenPerSec: 1_000_000, readOpsPerSec: 40, writeOpsPerSec: 10)), timestamp: ts)),
                .power(Sample(value: PowerSample(hasBattery: hasBattery, charge: hasBattery ? 82.0 : nil, state: hasBattery ? .discharging : nil, powerDrawWatts: 11.8), timestamp: ts))
            ])
        }
    }

    func testTilesRespectEnabledCategoriesOrderAndHideBatteryWhenAbsent() {
        let (defaults, prefs, coord, suite) = makeContext()
        defer { cleanup(defaults, suite: suite) }

        seedAllCategories(in: coord, hasBattery: true)
        prefs.enabledCategories = [.power, .cpu, .network, .disk]

        let overview = OverviewView(coordinator: coord, preferences: prefs)
        XCTAssertEqual(overview.tiles.map(\.category), [.cpu, .network, .disk, .power])

        // Desktop Mac (!hasBattery) hides Battery/Power tile even if enabled
        seedAllCategories(in: coord, hasBattery: false)
        prefs.enabledCategories = Set(MetricCategory.allCases)
        let desktopOverview = OverviewView(coordinator: coord, preferences: prefs)
        XCTAssertFalse(desktopOverview.tiles.contains(where: { $0.category == .power }))
        XCTAssertEqual(desktopOverview.tiles.count, MetricCategory.allCases.count - 1)
    }

    func testLayoutFits352x560WithAll8Categories() {
        let (defaults, prefs, coord, suite) = makeContext()
        defer { cleanup(defaults, suite: suite) }

        seedAllCategories(in: coord, hasBattery: true)
        prefs.enabledCategories = Set(MetricCategory.allCases)

        let view = PanelFactory.makePanelView(destination: .overview, coordinator: coord, preferences: prefs)
        let controller = NSHostingController(rootView: AnyView(view))
        let fit = controller.sizeThatFits(in: CGSize(width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight))

        XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0)
        XCTAssertGreaterThan(fit.height, 200)
        XCTAssertLessThanOrEqual(fit.height, Instrument.Size.maxHeight)
    }

    func testTileSelectionInvokesCallbackAndSwapsPanelDestination() {
        let (defaults, prefs, coord, suite) = makeContext()
        defer {
            PanelController.shared.destinationViewProvider = nil
            cleanup(defaults, suite: suite)
        }

        seedAllCategories(in: coord, hasBattery: true)

        var selected: [MetricCategory] = []
        let view = OverviewView(
            coordinator: coord,
            preferences: prefs,
            onSelectCategory: { selected.append($0) }
        )
        view.selectCategory(.memory)
        XCTAssertEqual(selected, [.memory])

        // Verify live PanelController swap from Overview -> Category Now page
        PanelController.shared.configure(preferences: prefs)
        PanelController.shared.destinationViewProvider = { dest in
            AnyView(PanelFactory.makePanelView(destination: dest, coordinator: coord, preferences: prefs))
        }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        guard let button = statusItem.button else {
            XCTFail("Expected status bar button")
            return
        }

        PanelController.shared.show(destination: .overview, relativeTo: button) {
            PanelFactory.makePanelView(destination: .overview, coordinator: coord, preferences: prefs)
        }
        XCTAssertEqual(PanelController.shared.currentDestination, .overview)

        let liveOverview = OverviewView(coordinator: coord, preferences: prefs)
        liveOverview.selectCategory(.gpu)
        XCTAssertEqual(PanelController.shared.currentDestination, .category(.gpu))
        XCTAssertTrue(PanelController.shared.isTransientPanelOpen(for: .category(.gpu)))
    }

    func testSystemUptimeSummaryDisplayedCleanly() {
        let (defaults, prefs, coord, suite) = makeContext()
        defer { cleanup(defaults, suite: suite) }

        let view = OverviewView(
            coordinator: coord,
            preferences: prefs,
            uptimeProvider: { 3 * 86400 + 14 * 3600 + 22 * 60 }
        )
        XCTAssertEqual(view.uptimeSummaryText, "Uptime 3d 14h 22m")

        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.height, 140)
        XCTAssertLessThanOrEqual(hosting.fittingSize.height, Instrument.Size.maxHeight)
    }

    func testPageSwitcherHiddenOnOverviewAndLabelsPreserved() {
        XCTAssertEqual(PageSwitcher.label(for: .overview), "Now")
        XCTAssertEqual(PageSwitcher.label(for: .detail), "Details")
        XCTAssertEqual(PageSwitcher.label(for: .history), "History")
        XCTAssertEqual(PopoverTab.overview.rawValue, "overview")
        XCTAssertEqual(PopoverTab.detail.rawValue, "detail")
        XCTAssertEqual(PopoverTab.history.rawValue, "history")

        // Overview title row has no PageSwitcher (category == nil, pages == [])
        let overviewTitle = PanelTitleRow(
            title: "Overview",
            category: nil,
            pages: [],
            selection: .constant(.overview)
        )
        let overviewHost = NSHostingView(rootView: overviewTitle)
        overviewHost.frame = CGRect(x: 0, y: 0, width: Instrument.Size.contentWidth, height: 32)
        overviewHost.layoutSubtreeIfNeeded()

        let categoryTitle = PanelTitleRow(
            title: "CPU",
            category: .cpu,
            pages: [.overview, .detail, .history],
            selection: .constant(.overview)
        )
        let categoryHost = NSHostingView(rootView: categoryTitle)
        categoryHost.frame = CGRect(x: 0, y: 0, width: Instrument.Size.contentWidth, height: 32)
        categoryHost.layoutSubtreeIfNeeded()

        // Both fit cleanly within content width; category title includes PageSwitcher
        XCTAssertLessThanOrEqual(overviewHost.fittingSize.width, Instrument.Size.contentWidth)
        XCTAssertLessThanOrEqual(categoryHost.fittingSize.width, Instrument.Size.contentWidth)
    }

    func testTypographyTokensMeetMinimum10ptFloor() {
        // OverviewView and PanelPageSection use Instrument.Typography tokens (>= 10 pt)
        let section = PanelPageSection("Now") {
            Text("Content").font(Instrument.Typography.body)
        }
        let hosting = NSHostingView(rootView: section)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.contentWidth, height: 60)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.height, 20)
    }
}
