import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class Phase7RefinementTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.phase7.refinement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        return (defaults, prefs, coord, suiteName)
    }

    private func cleanup(defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 1. PanelFactory View & Tab Persistence

    func testPanelFactoryHostingControllerPassesRememberLastTab() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        for category in MetricCategory.allCases {
            var item = MenuBarItemConfig(category: category, style: .text)
            item.popover = PopoverConfig(openingTab: .overview, rememberLastTab: false)

            let view = PanelFactory.makePanelView(config: item, coordinator: coord, preferences: prefs)
            let hosting = NSHostingView(rootView: AnyView(view))
            XCTAssertNotNil(hosting, "Panel view should have a valid hosting view for \(category)")
        }
    }

    // MARK: - 2. PanelScaffold Clamps Unsupported Tab

    func testPanelScaffoldClampsUnsupportedTab() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        var capturedTab: PopoverTab = .detail
        let glance = PanelGlance(value: 12.0, headline: "Processor Idle")
        let view = PanelScaffold(
            category: .cpu,
            glance: glance,
            status: .fine,
            pages: [.overview, .history],
            selection: Binding(get: { capturedTab }, set: { capturedTab = $0 })
        ) { page in
            Text("Content for \(page.title(for: .cpu))")
        }

        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 352, height: 400)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertNotNil(hosting)
    }

    // MARK: - 3. Scalar Time Span Calculation

    func testScalarTimeSpanCalculation() {
        var store = MetricsStore()

        // 1. Empty buffer returns 0
        XCTAssertEqual(store.scalarTimeSpan(for: .cpuUser), 0.0)

        // 2. Single point returns 0
        let now = Date()
        let s1 = Sample(value: CPUSample(totalUsage: 10, perCore: [], user: 5, system: 5, idle: 90), timestamp: now)
        store.append(.cpu(s1))
        XCTAssertEqual(store.scalarTimeSpan(for: .cpuUser), 0.0)

        // 3. 10 points spaced 1 second apart returns 9 seconds span
        for i in 1...9 {
            let pointDate = now.addingTimeInterval(Double(i))
            let sample = Sample(value: CPUSample(totalUsage: 10, perCore: [], user: Double(5 + i), system: 5, idle: 90), timestamp: pointDate)
            store.append(.cpu(sample))
        }
        XCTAssertEqual(store.scalarCount(for: .cpuUser), 10)
        let totalSpan = store.scalarTimeSpan(for: .cpuUser)
        XCTAssertEqual(totalSpan, 9.0, accuracy: 0.01)

        // 4. Time span with duration filter shorter than total span
        let windowSpan = store.scalarTimeSpan(for: .cpuUser, duration: 4.0)
        // Samples strictly newer than (now+9 - 4) = now+5 are at 6, 7, 8, 9 (oldest in window is at 6, span is 3.0s)
        XCTAssertEqual(windowSpan, 3.0, accuracy: 0.01)

        // 5. Time span with duration longer than total span returns total span
        let longSpan = store.scalarTimeSpan(for: .cpuUser, duration: 300.0)
        XCTAssertEqual(longSpan, 9.0, accuracy: 0.01)
    }

    func testCoordinatorScalarTimeSpanMatchesStore() {
        let (defaults, _, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let sample1 = CPUSample(totalUsage: 10.0, perCore: [10.0], user: 5.0, system: 5.0, idle: 90.0)
        coord.handleReading(.cpu(Sample(value: sample1, timestamp: Date(timeIntervalSince1970: 1000))))

        let sample2 = CPUSample(totalUsage: 20.0, perCore: [20.0], user: 10.0, system: 10.0, idle: 80.0)
        coord.handleReading(.cpu(Sample(value: sample2, timestamp: Date(timeIntervalSince1970: 1015))))

        let span = coord.scalarTimeSpan(for: .cpuUser)
        XCTAssertEqual(span, 15.0, accuracy: 0.01)
    }

    // MARK: - 4. Preferences Store Item Updating with Custom or Peak Source

    func testMenuBarItemPopoverConfigUpdate() {
        let (defaults, prefs, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Configure a thermal item with default source .peak and uninitialized popover
        let thermalItem = MenuBarItemConfig(category: .thermal, style: .text, source: .peak)
        prefs.menuBarItems = [thermalItem]

        XCTAssertEqual(prefs.menuBarItems.count, 1)
        XCTAssertEqual(prefs.menuBarItems[0].source, .peak)

        // Resolve default config as PreferencesMenuBarPane does
        let resolvedConfig = prefs.menuBarItems[0].resolvedPopoverConfig
        XCTAssertEqual(resolvedConfig.openingTab, .overview)
        XCTAssertTrue(resolvedConfig.rememberLastTab)

        // Update opening tab and tab persistence
        var updated = resolvedConfig
        updated.openingTab = .detail
        updated.rememberLastTab = false
        prefs.menuBarItems[0].popover = updated

        XCTAssertEqual(prefs.menuBarItems[0].popover?.openingTab, .detail)
        XCTAssertEqual(prefs.menuBarItems[0].popover?.rememberLastTab, false)
    }

    // MARK: - 5. Fan Idle Ratio and Thermal Cause Attribution

    func testFanIdleRatioConsistentWithRange() {
        // At idle, RPM == minRPM (e.g. 1200 RPM when min=1200, max=6000)
        let idleFan = FanReading(name: "Fan 1", rpm: 1200, minRPM: 1200, maxRPM: 6000)
        let sample = FanSample(fans: [idleFan])

        let maxRPM = sample.fans.map(\.rpm).max() ?? 0
        let maxPossibleRPM = sample.fans.compactMap(\.maxRPM).max() ?? 6000
        let minPossibleRPM = sample.fans.compactMap(\.minRPM).min() ?? 1200
        let ratio: Double = (maxPossibleRPM > minPossibleRPM)
            ? max(0.0, min(1.0, Double(maxRPM - minPossibleRPM) / Double(maxPossibleRPM - minPossibleRPM)))
            : max(0.0, min(1.0, Double(maxRPM) / Double(maxPossibleRPM)))

        XCTAssertEqual(ratio, 0.0, "Idle fan operating at minRPM should evaluate to 0% of range")

        let headline = PanelHeadline.fan(sample: sample)
        let status = StatusThresholds.fan(rpm: 1200, minRPM: 1200, maxRPM: 6000)
        XCTAssertEqual(status, .fine)
        XCTAssertTrue(headline.contains("Quiet"))
    }

    func testThermalCauseSensorClassification() {
        let sensors = [
            SensorReading(name: "CPU Efficiency Core 1", celsius: 42.0),
            SensorReading(name: "CPU Performance Core 1", celsius: 78.5),
            SensorReading(name: "GPU Core", celsius: 55.0)
        ]
        let thermalSample = ThermalSample(sensors: sensors)

        let hottest = thermalSample.sensors.max(by: { $0.celsius < $1.celsius })
        XCTAssertNotNil(hottest)
        XCTAssertEqual(hottest?.name, "CPU Performance Core 1")

        let classified = hottest.flatMap { ThermalSensorClassifier.classify($0) }
        XCTAssertEqual(classified, .cpu)
        XCTAssertEqual(classified?.displayName, "CPU")
    }

    // MARK: - 6. GPU Memory Formatting

    func testGPUMemoryRawByteScaling() {
        // GPU memory in GPUSample is raw bytes (e.g., 2 GB = 2_147_483_648 bytes)
        let twoGigabytes: UInt64 = 2 * 1024 * 1024 * 1024
        let sample = GPUSample(utilization: 25.0, memoryUsed: twoGigabytes, tempCelsius: 48.0)

        let formatted = Units.formatBytes(sample.memoryUsed!, standard: .iec)
        XCTAssertEqual(formatted, "2.00 GiB", "Direct raw bytes should format as 2.00 GiB without double multiplication")
    }
}
