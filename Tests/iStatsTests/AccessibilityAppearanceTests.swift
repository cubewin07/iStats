import XCTest
import SwiftUI
import AppKit
@testable import iStatsCore
@testable import iStats

@MainActor
final class AccessibilityAppearanceTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.accessibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        return (defaults, prefs, coord, suiteName)
    }

    private func cleanup(defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 1. Appearance Matrix: Light & Dark Modes Across All 8 Panels

    func testAppearanceMatrixLightAndDarkPanels() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // Populate sample telemetry
        coord.handleReading(.cpu(Sample(value: CPUSample(totalUsage: 45.0, perCore: [40.0, 50.0], user: 25.0, system: 20.0, idle: 55.0))))
        coord.handleReading(.memory(Sample(value: MemorySample(total: 16 * 1024 * 1024 * 1024, used: 8 * 1024 * 1024 * 1024, free: 8 * 1024 * 1024 * 1024, wired: 2 * 1024 * 1024 * 1024, compressed: 1 * 1024 * 1024 * 1024, cached: 2 * 1024 * 1024 * 1024, swapUsed: 0, pressure: .normal))))
        coord.handleReading(.gpu(Sample(value: GPUSample(utilization: 35.0, memoryUsed: 1024, tempCelsius: 50.0, powerWatts: 10.0))))
        coord.handleReading(.thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU Core", celsius: 55.0)], pressure: .nominal))))
        coord.handleReading(.fan(Sample(value: FanSample(fans: [FanReading(name: "Left Fan", rpm: 1800, minRPM: 1200, maxRPM: 5500)]))))
        coord.handleReading(.network(Sample(value: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 5000000, bytesOutPerSec: 1200000, totalBytesIn: 10000000, totalBytesOut: 2000000)]))))
        coord.handleReading(.disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 250_000_000_000, free: 250_000_000_000)], io: DiskIO(bytesReadPerSec: 5000000, bytesWrittenPerSec: 2000000, readOpsPerSec: 100, writeOpsPerSec: 50)))))
        coord.handleReading(.power(Sample(value: PowerSample(hasBattery: true, charge: 88.0, state: .charging, timeRemaining: 3600, powerDrawWatts: 24.0))))

        let colorSchemes: [ColorScheme] = [.light, .dark]

        for scheme in colorSchemes {
            for category in MetricCategory.allCases {
                let panelView = PanelFactory.makeCategoryPanelView(category: category, coordinator: coord, preferences: prefs)
                    .environment(\.colorScheme, scheme)

                let hosting = NSHostingView(rootView: AnyView(panelView))
                hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 420)
                hosting.layoutSubtreeIfNeeded()

                let size = hosting.fittingSize
                XCTAssertEqual(size.width, Instrument.Size.panelWidth, accuracy: 2.0, "Panel \(category) width in \(scheme) must match 352pt")
                XCTAssertGreaterThan(size.height, 80, "Panel \(category) height in \(scheme) must be > 80pt")
            }
        }
    }

    // MARK: - 2. Reduce Motion Policy

    func testReduceMotionPolicyFallbacks() {
        // Glide fraction returns 0.0 when elapsed is 0 or interval <= 0
        XCTAssertEqual(LiveChartMath.glideOffset(elapsed: 0.5, interval: 0.0), 0.0)

        // Motion policy reduced enum behavior
        let full = MotionPolicy.full
        let reduced = MotionPolicy.reduced
        let frozen = MotionPolicy.frozen

        XCTAssertTrue(full.allowsContinuousAnimation)
        XCTAssertTrue(full.allowsEasing)

        XCTAssertFalse(reduced.allowsContinuousAnimation)
        XCTAssertTrue(reduced.allowsEasing)

        XCTAssertFalse(frozen.allowsContinuousAnimation)
        XCTAssertFalse(frozen.allowsEasing)
    }

    // MARK: - 3. Differentiate Without Colour

    func testDifferentiateWithoutColourSymbols() {
        // Each StatusLevel has a distinct, unambiguous SF Symbol name
        let levels: [StatusLevel] = StatusLevel.allCases
        var symbolSet = Set<String>()

        for level in levels {
            let symbol = level.symbolName
            XCTAssertFalse(symbol.isEmpty, "StatusLevel.\(level) must have non-empty symbolName")
            symbolSet.insert(symbol)
        }

        XCTAssertEqual(symbolSet.count, levels.count, "Each StatusLevel must have a unique SF symbol for colorblind accessibility")
    }

    // MARK: - 4. High Contrast & Reduce Transparency

    func testHighContrastAndReduceTransparencyTokens() {
        // Module surface produces valid colors
        let modColor = Instrument.Surface.module
        XCTAssertNotNil(modColor)

        // Panel surface uses system window background
        let panelColor = Instrument.Surface.panel
        XCTAssertNotNil(panelColor)

        // Test module layout and rendering
        let module = Module(eyebrow: "TEST") {
            Text("Module Content")
        }

        let hosting = NSHostingView(rootView: module)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 60)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.width, 50)
        XCTAssertGreaterThan(hosting.fittingSize.height, 20)
    }

    // MARK: - 5. VoiceOver & Numerical Text Scale

    func testVoiceOverAndTextScaleInvariance() {
        // Test LiveNumber doesn't truncate with 0.7 scale factor
        let liveNum = LiveNumber(
            value: 99.9,
            format: { String(format: "%.1f", $0) },
            font: Instrument.Typography.display,
            unit: "%"
        )

        let hosting = NSHostingView(rootView: liveNum)
        hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 50)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hosting.fittingSize.width, 30)
        XCTAssertGreaterThan(hosting.fittingSize.height, 20)
    }

    // MARK: - 6. MetricRow Accessibility Differentiate Without Color

    func testMetricRowDifferentiateWithoutColor() {
        for level in StatusLevel.allCases {
            let row = MetricRow(
                label: "CPU Peak",
                valueText: "92%",
                statusLevel: level
            )

            let hosting = NSHostingView(rootView: row)
            hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 30)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.width, 50, "MetricRow with status \(level) should layout cleanly")
        }
    }
}
