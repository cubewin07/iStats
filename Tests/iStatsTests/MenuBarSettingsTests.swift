import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class MenuBarSettingsTests: XCTestCase {
    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.menubarsettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        return (defaults, prefs, coord, suiteName)
    }

    private func cleanup(defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testReorderingUpdatesActiveMenuBarItemsAndSyncsWithObservedOrder() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let cpu = MenuBarItemConfig(category: .cpu, style: .bar)
        let mem = MenuBarItemConfig(category: .memory, style: .gauge)
        let net = MenuBarItemConfig(category: .network, style: .throughput)
        prefs.menuBarItems = [cpu, mem, net]

        let view = MenuBarSettingsView(store: prefs, coordinator: coord)
        view.moveItems(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(prefs.activeMenuBarItems.map(\.id), [net.id, cpu.id, mem.id])

        // Move via single-item helper
        view.moveItem(id: cpu.id, offset: 1)
        XCTAssertEqual(prefs.activeMenuBarItems.map(\.id), [net.id, mem.id, cpu.id])

        // Simulated Cmd-drag via MenuBarOrdering.observedOrder updates PreferencesStore
        let frames: [(id: String, frame: CGRect)] = [
            (cpu.id, CGRect(x: 100, y: 0, width: 32, height: 22)),
            (net.id, CGRect(x: 140, y: 0, width: 60, height: 22)),
            (mem.id, CGRect(x: 210, y: 0, width: 24, height: 22))
        ]
        let observed = MenuBarOrdering.observedOrder(frames: frames)
        XCTAssertEqual(observed, [cpu.id, net.id, mem.id])
        if let observed {
            prefs.setActiveMenuBarOrder(observed)
        }
        XCTAssertEqual(prefs.activeMenuBarItems.map(\.id), [cpu.id, net.id, mem.id])
    }

    func testAddAndRemoveWidgetUpdatesStore() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let view = MenuBarSettingsView(store: prefs, coordinator: coord)
        let gpu = MenuBarItemConfig(category: .gpu, style: .gauge)
        view.addItem(gpu)
        XCTAssertTrue(prefs.isExactItemEnabled(category: .gpu, style: .gauge))

        view.removeItem(gpu)
        XCTAssertFalse(prefs.isExactItemEnabled(category: .gpu, style: .gauge))
    }

    func testEditingAlertRulePersistsAcrossStoreInstances() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        prefs.updateAlertRule(.temperature) { rule in
            rule.enabled = true
            rule.threshold = TemperatureThresholdScale.celsius(fromDisplay: 180.0, unit: .fahrenheit)
            rule.sustainSeconds = 30
            rule.cooldownSeconds = 900
            rule.target = MetricSource.gpu.rawValue
        }
        prefs.updateAlertRule(.disk) { rule in
            rule.enabled = true
            rule.threshold = 88
            rule.sustainSeconds = 15
            rule.target = "/Volumes/External"
        }

        let reloaded = PreferencesStore(userDefaults: defaults)
        let tempRule = reloaded.alertRule(for: .temperature)
        XCTAssertTrue(tempRule.enabled)
        XCTAssertEqual(tempRule.sustainSeconds, 30)
        XCTAssertEqual(tempRule.cooldownSeconds, 900)
        XCTAssertEqual(tempRule.target, MetricSource.gpu.rawValue)
        XCTAssertEqual(
            TemperatureThresholdScale.displayValue(celsius: tempRule.threshold, unit: .fahrenheit),
            180.0,
            accuracy: 1.0
        )

        let diskRule = reloaded.alertRule(for: .disk)
        XCTAssertTrue(diskRule.enabled)
        XCTAssertEqual(diskRule.threshold, 88)
        XCTAssertEqual(diskRule.sustainSeconds, 15)
        XCTAssertEqual(diskRule.target, "/Volumes/External")
    }

    func testCategorySettingsViewRendersAllCategoriesAndOverviewOnlyState() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Enable CPU with zero menu bar widgets -> "Shown in Overview only" state
        prefs.setCategory(.cpu, isEnabled: true)
        prefs.menuBarItems.removeAll { $0.category == .cpu }

        coord.handleReading(.network(Sample(value: NetworkSample(
            interfaces: [
                InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1200, bytesOutPerSec: 300, totalBytesIn: 1000, totalBytesOut: 500, type: .wifi),
                InterfaceThroughput(interfaceName: "en5", bytesInPerSec: 50000, bytesOutPerSec: 10000, totalBytesIn: 9000, totalBytesOut: 2000, type: .ethernet)
            ],
            primaryInterface: "en0",
            primaryType: .wifi
        ))))
        coord.handleReading(.disk(Sample(value: DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1000, used: 400, free: 600),
            VolumeCapacity(name: "Backup", mountPoint: "/Volumes/Backup", total: 2000, used: 1500, free: 500)
        ]))))

        for category in MetricCategory.allCases {
            for hasBattery in [true, false] {
                let view = CategorySettingsView(
                    category: category,
                    store: prefs,
                    coordinator: coord,
                    hasBattery: hasBattery
                )
                let hosting = NSHostingView(rootView: view)
                hosting.frame = CGRect(x: 0, y: 0, width: 640, height: 600)
                hosting.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(hosting.fittingSize.width, 200, "Category \(category) width")
                XCTAssertGreaterThan(hosting.fittingSize.height, 200, "Category \(category) height")
            }
        }
    }

    func testNetworkInterfaceSelectionAppliesInNetworkPanel() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let en0 = InterfaceThroughput(
            interfaceName: "en0",
            bytesInPerSec: 1_000_000,
            bytesOutPerSec: 100_000,
            totalBytesIn: 10_000_000,
            totalBytesOut: 1_000_000,
            ipv4Address: "192.168.1.10",
            type: .wifi
        )
        let en5 = InterfaceThroughput(
            interfaceName: "en5",
            bytesInPerSec: 25_000_000,
            bytesOutPerSec: 5_000_000,
            totalBytesIn: 500_000_000,
            totalBytesOut: 50_000_000,
            ipv4Address: "10.0.0.5",
            type: .ethernet
        )
        let sample = NetworkSample(
            interfaces: [en0, en5],
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.10"
        )
        coord.handleReading(.network(Sample(value: sample)))

        let panel = NetworkPanel(coordinator: coord, preferences: prefs)

        // Automatic: sums all interfaces (en0 + en5)
        let autoGlance = panel.deriveGlance(latest: coord.latestNetwork)
        let expectedAuto = Units.rateComponents(sample.totalBytesInPerSec, unit: prefs.networkUnit, standard: prefs.byteUnitStandard).value
        XCTAssertEqual(autoGlance.value ?? -1, expectedAuto, accuracy: 0.01)

        // Pin to en5: shows en5's rate only
        prefs.networkInterfaceSelection = "en5"
        let en5Glance = panel.deriveGlance(latest: coord.latestNetwork)
        let expectedEn5 = Units.rateComponents(en5.bytesInPerSec, unit: prefs.networkUnit, standard: prefs.byteUnitStandard).value
        XCTAssertEqual(en5Glance.value ?? -1, expectedEn5, accuracy: 0.01)

        // Pin to en0: shows en0's rate only
        prefs.networkInterfaceSelection = "en0"
        let en0Glance = panel.deriveGlance(latest: coord.latestNetwork)
        let expectedEn0 = Units.rateComponents(en0.bytesInPerSec, unit: prefs.networkUnit, standard: prefs.byteUnitStandard).value
        XCTAssertEqual(en0Glance.value ?? -1, expectedEn0, accuracy: 0.01)

        // Unplugged / missing interface: falls back gracefully to automatic totals
        prefs.networkInterfaceSelection = "en99"
        let fallbackGlance = panel.deriveGlance(latest: coord.latestNetwork)
        XCTAssertEqual(fallbackGlance.value ?? -1, expectedAuto, accuracy: 0.01)
    }
}
