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

    // MARK: - 7. LiveChart v3 Time-Domain Engine Tests (Task 8.5.3 / B7, A1–A9)

    func testLiveChartV3TimeDomainAndEnvelopeRenderModes() {
        let base: TimeInterval = 1_700_000_000.0
        let singlePoints = (0..<30).map { i in
            ChartPoint(timestamp: base + Double(i), value: 20.0 + Double(i % 15))
        }
        let dualPoints = (0..<30).map { i in
            DualChartPoint(
                timestamp: base + Double(i),
                primary: 15.0 + Double(i % 10),
                secondary: 5.0 + Double(i % 8)
            )
        }
        let mirroredDualPoints = (0..<30).map { i in
            DualChartPoint(
                timestamp: base + Double(i),
                primary: 12_000_000.0 + Double(i) * 100_000.0,
                secondary: 800_000.0 + Double(i) * 10_000.0
            )
        }
        let buckets = (0..<40).map { i in
            let mean = 40.0 + Double(i % 12)
            return BucketPoint(
                timestamp: base + Double(i) * 2.5,
                min: mean - 10.0,
                max: mean + 15.0,
                mean: mean
            )
        }
        let bands = [
            ChartBand(threshold: 60.0, color: .orange, label: "Warning"),
            ChartBand(threshold: 80.0, color: .red, label: "Critical")
        ]

        let charts: [LiveChart] = [
            LiveChart(
                category: .cpu,
                mode: .single(points: singlePoints, color: .blue),
                height: 84,
                showAverageLine: true,
                showPeakMarker: true,
                showAxisTicks: true
            ),
            LiveChart(
                category: .cpu,
                mode: .stacked(points: dualPoints, primaryColor: .blue, secondaryColor: .red, fixedMax: 100.0),
                height: 84,
                showAxisTicks: true
            ),
            LiveChart(
                category: .network,
                mode: .mirrored(points: mirroredDualPoints, topColor: .teal, bottomColor: .purple),
                height: 84,
                showAxisTicks: true
            ),
            LiveChart(
                category: .memory,
                mode: .banded(points: singlePoints, bands: bands, fixedMax: 100.0),
                height: 84,
                showAxisTicks: true
            ),
            LiveChart(
                category: .memory,
                mode: .envelope(buckets: buckets, color: .purple, bands: bands, fixedMax: 100.0),
                height: 140,
                windowDuration: 300.0,
                showAxisTicks: true
            ),
            LiveChart(
                category: .disk,
                mode: .mirroredEnvelope(top: buckets, bottom: buckets, topColor: .blue, bottomColor: .orange),
                height: 140,
                windowDuration: 300.0,
                showAxisTicks: true
            )
        ]

        for chart in charts {
            let hosting = NSHostingView(rootView: chart)
            hosting.frame = CGRect(x: 0, y: 0, width: 352, height: chart.height)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.height, 40)
        }
    }

    func testLiveChartFlatSeriesTimelineDoesNotTwitchB7() {
        let model = ChartModel(sampleInterval: 1.0)
        let base: TimeInterval = 1_700_000_000.0

        // 1. Timestamped flat series (all 0.0 values): edge advances strictly monotonically
        // as new timestamps arrive, never snapping back.
        var points = (0..<60).map { i in
            ChartPoint(timestamp: base + Double(i), value: 0.0)
        }
        var now = base + 60.0
        _ = model.step(
            now: now,
            mode: .single(points: points, color: .teal),
            category: .network,
            sampleInterval: 1.0,
            explicitWindow: 60.0,
            isScrubbing: false,
            motionPolicy: .full
        )
        var prevEdge = model.timeline.edge
        XCTAssertEqual(prevEdge, base + 59.0, accuracy: 1e-6)

        // Advance at 60 fps while flat sample #60 arrives at t = base + 60
        points.append(ChartPoint(timestamp: base + 60.0, value: 0.0))
        let dt = 1.0 / 60.0
        for _ in 0..<60 {
            now += dt
            _ = model.step(
                now: now,
                mode: .single(points: points, color: .teal),
                category: .network,
                sampleInterval: 1.0,
                explicitWindow: 60.0,
                isScrubbing: false,
                motionPolicy: .full
            )
            XCTAssertGreaterThanOrEqual(model.timeline.edge, prevEdge - 1e-12, "Flat timestamped series must never snap backward")
            prevEdge = model.timeline.edge
        }
        XCTAssertEqual(model.timeline.edge, base + 60.0, accuracy: 1e-4)

        // 2. Legacy [Double] flat series: advancing wall-clock `now` without value changes
        // must remain completely still (zero modulo snap-back).
        let legacyModel = ChartModel(sampleInterval: 1.0)
        let flatValues = Array(repeating: 0.0, count: 60)
        var wallNow = base + 100.0
        _ = legacyModel.step(
            now: wallNow,
            mode: .single(values: flatValues, color: .teal),
            category: .network,
            sampleInterval: 1.0,
            explicitWindow: 60.0,
            isScrubbing: false,
            motionPolicy: .full
        )
        var prevLegacyEdge = legacyModel.timeline.edge
        XCTAssertEqual(prevLegacyEdge, base + 99.0, accuracy: 1e-6)
        for frame in 1...180 {
            wallNow += 1.0 / 60.0
            _ = legacyModel.step(
                now: wallNow,
                mode: .single(values: flatValues, color: .teal),
                category: .network,
                sampleInterval: 1.0,
                explicitWindow: 60.0,
                isScrubbing: false,
                motionPolicy: .full
            )
            XCTAssertGreaterThanOrEqual(legacyModel.timeline.edge, prevLegacyEdge - 1e-12, "Flat legacy [Double] series must not snap backward")
            if frame >= 60 {
                XCTAssertEqual(legacyModel.timeline.edge, base + 100.0, accuracy: 1e-4, "Flat legacy [Double] series must hold steady after trailing interval")
            }
            prevLegacyEdge = legacyModel.timeline.edge
        }
    }

    func testLiveChartIndependentMirroredScalesAndPartialBufferProjection() {
        let model = ChartModel(sampleInterval: 1.0)
        let base: TimeInterval = 1_700_000_000.0
        // 15 samples at 1 Hz in a 60 s window with asymmetric download (12 MB/s) vs upload (800 KB/s)
        let asymmetricPoints = (0..<15).map { i in
            DualChartPoint(
                timestamp: base + Double(i),
                primary: 12_000_000.0,
                secondary: 800_000.0
            )
        }

        let resolved = model.step(
            now: base + 15.0,
            mode: .mirrored(points: asymmetricPoints, topColor: .blue, bottomColor: .purple),
            category: .network,
            sampleInterval: 1.0,
            explicitWindow: 60.0,
            isScrubbing: false,
            motionPolicy: .full
        )

        XCTAssertGreaterThan(model.topScale.displayedCeiling, 12_000_000.0)
        XCTAssertLessThan(model.bottomScale.displayedCeiling, 2_000_000.0)

        let topRange = ChartRenderer.VerticalRange(
            floor: model.topScale.displayedFloor,
            ceiling: model.topScale.displayedCeiling,
            topY: 0.0,
            baselineY: 42.0,
            inverted: false
        )
        let geom = ChartRenderer.buildSeriesGeometry(
            points: resolved.primaryPoints,
            timeline: model.timeline,
            windowDuration: 60.0,
            plotWidth: 300.0,
            verticalRange: topRange
        )
        XCTAssertNotNil(geom)
        // Edge is at base + 14.0; sample 0 is at base + 0.0 -> 14 s span in 60 s window
        let firstX = geom?.screenPoints.first?.x ?? 0.0
        let lastX = geom?.screenPoints.last?.x ?? 0.0
        XCTAssertEqual(lastX, 300.0, accuracy: 1e-6)
        XCTAssertEqual((lastX - firstX) / 300.0, 14.0 / 60.0, accuracy: 1e-6)
        XCTAssertEqual(Double(geom?.headPoint?.x ?? 0.0), 300.0, accuracy: 1e-6)
    }

    func testLiveChartEnvelopePolygonAndFrameIntervalThrottling() {
        let base: TimeInterval = 1_700_000_000.0
        let timeline = ChartTimeline(edge: base + 25.0, sampleInterval: 1.0)
        let range = ChartRenderer.VerticalRange(floor: 0.0, ceiling: 100.0, topY: 0.0, baselineY: 140.0, inverted: false)

        let spreadBuckets = (0..<10).map { i in
            BucketPoint(timestamp: base + Double(i) * 2.5, min: 20.0, max: 70.0, mean: 45.0)
        }
        let spreadPath = ChartRenderer.buildEnvelopePolygon(
            buckets: spreadBuckets,
            timeline: timeline,
            windowDuration: 60.0,
            plotWidth: 300.0,
            verticalRange: range
        )
        XCTAssertNotNil(spreadPath)
        XCTAssertFalse(spreadPath?.isEmpty ?? true)

        let flatBuckets = (0..<10).map { i in
            BucketPoint(timestamp: base + Double(i) * 2.5, min: 45.0, max: 45.0, mean: 45.0)
        }
        let flatPath = ChartRenderer.buildEnvelopePolygon(
            buckets: flatBuckets,
            timeline: timeline,
            windowDuration: 60.0,
            plotWidth: 300.0,
            verticalRange: range
        )
        XCTAssertNil(flatPath)

        XCTAssertEqual(LiveChart.frameInterval(isPinnedNonKey: false), 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(LiveChart.frameInterval(isPinnedNonKey: true), 1.0 / 30.0, accuracy: 1e-9)
    }

    func testLiveChartScrubControllerTimeDomainResolution() {
        let scrub = ScrubController()
        let base: TimeInterval = 1_700_000_000.0
        let points = (0..<60).map { i in
            ChartPoint(timestamp: base + Double(i), value: Double(i))
        }
        let timeline = ChartTimeline(edge: base + 59.0, sampleInterval: 1.0)

        // Hover at midpoint (x = 150 of 300 in 60 s window -> edge - 30 s = base + 29)
        let target = scrub.resolveTarget(
            atX: 150.0,
            plotWidth: 300.0,
            points: points,
            secondaryPoints: [],
            timeline: timeline,
            windowDuration: 60.0,
            isTimestamped: true
        )
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.index, 29)
        XCTAssertEqual(target?.primaryValue ?? -1, 29.0, accuracy: 1e-6)
        XCTAssertEqual(target?.secondsAgo ?? -1, 30.0, accuracy: 1e-6)
    }
}
