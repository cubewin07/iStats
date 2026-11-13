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

    // MARK: - 8. HistoryPage v3 Tests (Task 8.5.5 / B8, B9, B10, Kit v2)

    func testHistoryPageInitializesRangeFromPreferencesInInitB10() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        prefs.setHistoryRange(.fiveMinutes, for: .memory)
        prefs.setHistoryRange(.fifteenMinutes, for: .network)

        let memoryPage = HistoryPage(category: .memory, coordinator: coord, preferences: prefs)
        let networkPage = HistoryPage(category: .network, coordinator: coord, preferences: prefs)
        let cpuPage = HistoryPage(category: .cpu, coordinator: coord, preferences: prefs)

        // Must reflect saved range immediately after init (before onAppear / hosting)
        XCTAssertEqual(memoryPage.currentSelectedRange, .fiveMinutes)
        XCTAssertEqual(networkPage.currentSelectedRange, .fifteenMinutes)
        XCTAssertEqual(cpuPage.currentSelectedRange, .oneMinute)

        var capturedProbe = HistoryPageProbeSnapshot()
        let probed = memoryPage
            .environment(\.historyPageProbeEnabled, true)
            .onPreferenceChange(HistoryPageProbeKey.self) { capturedProbe = $0 }

        let hosting = NSHostingView(rootView: probed)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 320)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(capturedProbe.selectedRange, .fiveMinutes)
        XCTAssertEqual(capturedProbe.showAverageLine, false)
        XCTAssertEqual(capturedProbe.showPeakMarker, false)
        XCTAssertEqual(capturedProbe.timeAxisLabels, ["-5m", "-3m", "-1m", "now"])
    }

    func testHistoryPage1m5m15mScalarQueriesAndEnvelopesB8B9() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let ref = Date(timeIntervalSince1970: 1_700_010_000.0)
        // Populate 900 seconds (15m @ 1 Hz) across CPU, Memory, Network, and Power (watts nil, charge present)
        var batch: [MetricReading] = []
        batch.reserveCapacity(900 * 4)
        for i in 0..<900 {
            let ts = ref.addingTimeInterval(-Double(899 - i))
            let user = 20.0 + Double(i % 25)
            let sys = 10.0 + Double(i % 10)
            batch.append(.cpu(Sample(
                value: CPUSample(totalUsage: user + sys, perCore: [user + sys], user: user, system: sys, idle: 100.0 - user - sys),
                timestamp: ts
            )))
            batch.append(.memory(Sample(
                value: MemorySample(total: 1000, used: UInt64(400 + (i % 200)), free: 400, wired: 100, compressed: 50, cached: 50, swapUsed: 0, pressure: .normal),
                timestamp: ts
            )))
            batch.append(.network(Sample(
                value: NetworkSample(interfaces: [InterfaceThroughput(
                    interfaceName: "en0",
                    bytesInPerSec: 1_000_000.0 + Double(i % 50) * 10_000.0,
                    bytesOutPerSec: 250_000.0 + Double(i % 20) * 5_000.0,
                    totalBytesIn: 10_000_000,
                    totalBytesOut: 2_000_000
                )]),
                timestamp: ts
            )))
            // B9: powerDrawWatts nil with 85% charge must NOT populate powerWatts
            batch.append(.power(Sample(
                value: PowerSample(hasBattery: true, charge: 85.0, state: .charging, timeRemaining: 3600, powerDrawWatts: nil),
                timestamp: ts
            )))
        }
        coord.handleReadings(batch)

        // 1m Memory -> .single timestamped points (60 points)
        prefs.setHistoryRange(.oneMinute, for: .memory)
        let mem1m = HistoryPage(category: .memory, coordinator: coord, preferences: prefs)
            .buildSeriesData(referenceDate: ref)
        XCTAssertTrue(mem1m.mode.isTimestamped)
        XCTAssertFalse(mem1m.mode.isEnvelope)
        XCTAssertEqual(mem1m.activeValues.count, 60)

        // 5m Memory -> .envelope buckets (bucketWidth = 2.5s -> ~120 buckets)
        prefs.setHistoryRange(.fiveMinutes, for: .memory)
        let mem5m = HistoryPage(category: .memory, coordinator: coord, preferences: prefs)
            .buildSeriesData(referenceDate: ref)
        XCTAssertTrue(mem5m.mode.isEnvelope)
        XCTAssertEqual(mem5m.sampleInterval, 2.5, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(mem5m.activeValues.count, 118)
        XCTAssertLessThanOrEqual(mem5m.activeValues.count, 121)

        // 15m Memory -> .envelope buckets (bucketWidth = 7.5s -> ~120 buckets)
        prefs.setHistoryRange(.fifteenMinutes, for: .memory)
        let mem15m = HistoryPage(category: .memory, coordinator: coord, preferences: prefs)
            .buildSeriesData(referenceDate: ref)
        XCTAssertTrue(mem15m.mode.isEnvelope)
        XCTAssertEqual(mem15m.sampleInterval, 7.5, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(mem15m.activeValues.count, 118)
        XCTAssertLessThanOrEqual(mem15m.activeValues.count, 121)

        // 1m CPU -> .stacked; 5m CPU -> .envelope
        prefs.setHistoryRange(.oneMinute, for: .cpu)
        let cpu1m = HistoryPage(category: .cpu, coordinator: coord, preferences: prefs)
            .buildSeriesData(referenceDate: ref)
        XCTAssertEqual(cpu1m.activeValues.count, 60)
        XCTAssertFalse(cpu1m.mode.isEnvelope)

        prefs.setHistoryRange(.fiveMinutes, for: .cpu)
        let cpu5m = HistoryPage(category: .cpu, coordinator: coord, preferences: prefs)
            .buildSeriesData(referenceDate: ref)
        XCTAssertTrue(cpu5m.mode.isEnvelope)

        // 5m Network -> .mirroredEnvelope
        prefs.setHistoryRange(.fiveMinutes, for: .network)
        let net5m = HistoryPage(category: .network, coordinator: coord, preferences: prefs)
            .buildSeriesData(referenceDate: ref)
        XCTAssertTrue(net5m.mode.isEnvelope)
        XCTAssertTrue(net5m.mode.isMirrored)

        // B9 Power -> defaults to .powerWatts, stays empty when only charge % was recorded
        prefs.setHistoryRange(.oneMinute, for: .power)
        let power1m = HistoryPage(category: .power, coordinator: coord, preferences: prefs)
            .buildSeriesData(referenceDate: ref)
        XCTAssertEqual(power1m.unit, "W")
        XCTAssertEqual(power1m.rawSampleCount, 0)
        XCTAssertTrue(power1m.activeValues.isEmpty)
    }

    func testHistoryPageTimestampPinnedStatCellDoesNotDriftB10() throws {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let base = Date(timeIntervalSince1970: 1_700_020_000.0)
        // 60 samples from t = base..base+59, with peak at i = 20 (95%)
        for i in 0..<60 {
            let val = (i == 20) ? 95.0 : 30.0 + Double(i % 10)
            coord.handleReading(.memory(Sample(
                value: MemorySample(total: 1000, used: UInt64(val * 10), free: UInt64((100 - val) * 10), wired: 100, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal),
                timestamp: base.addingTimeInterval(Double(i))
            )))
        }

        prefs.setHistoryRange(.oneMinute, for: .memory)
        let page = HistoryPage(category: .memory, coordinator: coord, preferences: prefs)
        let ref1 = base.addingTimeInterval(59.0)
        let data1 = page.buildSeriesData(referenceDate: ref1)
        let stats1 = LiveChartMath.computeStats(for: data1.activeValues)!
        let targets1 = HistoryPage.statTargets(stats: stats1, seriesData: data1)

        XCTAssertEqual(targets1.max.index, 20)
        let pinnedPeakDate = try XCTUnwrap(targets1.max.timestamp)
        XCTAssertEqual(pinnedPeakDate.timeIntervalSince1970, base.timeIntervalSince1970 + 20.0, accuracy: 1e-6)

        // Append 5 newer samples (t = base+60..base+64); window [5..64] shifts indices by -5
        for i in 60..<65 {
            coord.handleReading(.memory(Sample(
                value: MemorySample(total: 1000, used: 350, free: 650, wired: 100, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal),
                timestamp: base.addingTimeInterval(Double(i))
            )))
        }

        let ref2 = base.addingTimeInterval(64.0)
        let data2 = page.buildSeriesData(referenceDate: ref2)
        let resolvedIdx = HistoryPage.resolveTimestampIndex(for: pinnedPeakDate, in: data2.timestamps)
        // Must track the pinned Date to index 15 rather than drifting on fixed index 20!
        XCTAssertEqual(resolvedIdx, 15)
        XCTAssertEqual(data2.activeValues[15], 95.0, accuracy: 1e-6)

        let pinnedScrubState = try XCTUnwrap(page.buildPinnedGlanceState(resolvedPinnedIndex: resolvedIdx, seriesData: data2))
        XCTAssertEqual(pinnedScrubState.formattedPrimary, "95")
        XCTAssertEqual(pinnedScrubState.primaryUnit, "%")
        XCTAssertEqual(pinnedScrubState.relativeTimeText, "44s ago")

        // Advance past the 60s window so pinned timestamp falls outside -> unpins cleanly (nil)
        let refExpired = base.addingTimeInterval(85.0)
        for i in 65..<86 {
            coord.handleReading(.memory(Sample(
                value: MemorySample(total: 1000, used: 350, free: 650, wired: 100, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal),
                timestamp: base.addingTimeInterval(Double(i))
            )))
        }
        let data3 = page.buildSeriesData(referenceDate: refExpired)
        XCTAssertNil(HistoryPage.resolveTimestampIndex(for: pinnedPeakDate, in: data3.timestamps))
    }

    func testHistoryPageTimeAxisAndScrubAxisLabels() {
        XCTAssertEqual(
            HistoryPage.timeAxisTicks(for: .oneMinute).map(\.label),
            ["-60s", "-40s", "-20s", "now"]
        )
        XCTAssertEqual(
            HistoryPage.timeAxisTicks(for: .fiveMinutes).map(\.label),
            ["-5m", "-3m", "-1m", "now"]
        )
        XCTAssertEqual(
            HistoryPage.timeAxisTicks(for: .fifteenMinutes).map(\.label),
            ["-15m", "-10m", "-5m", "now"]
        )

        XCTAssertEqual(HistoryPage.formatScrubAxisLabel(secondsAgo: 0), "AT -0s")
        XCTAssertEqual(HistoryPage.formatScrubAxisLabel(secondsAgo: 12), "AT -12s")
        XCTAssertEqual(HistoryPage.formatScrubAxisLabel(secondsAgo: 60), "AT -1m")
        XCTAssertEqual(HistoryPage.formatScrubAxisLabel(secondsAgo: 90), "AT -1m30s")
        XCTAssertEqual(HistoryPage.formatScrubAxisLabel(secondsAgo: 300), "AT -5m")
    }

    func testHistoryPageKitAdoptionAndPanelScaffoldScrubRouting() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let now = Date()
        for i in 0..<25 {
            let ts = now.addingTimeInterval(-Double(24 - i))
            coord.handleReading(.cpu(Sample(
                value: CPUSample(totalUsage: 40.0 + Double(i), perCore: [40.0], user: 25.0 + Double(i), system: 15.0, idle: 60.0 - Double(i)),
                timestamp: ts
            )))
        }

        // Render Kit SegmentedControl and FilterChip standalone
        let seg = SegmentedControl(options: HistoryTimeRange.allCases, selection: .constant(.fiveMinutes)) { $0.rawValue }
        let segHost = NSHostingView(rootView: seg)
        segHost.frame = CGRect(x: 0, y: 0, width: 150, height: 30)
        segHost.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(segHost.fittingSize.width, 40)

        let chip = FilterChip(title: "User", isSelected: true, dotColor: .blue, tint: .blue) {}
        let chipHost = NSHostingView(rootView: chip)
        chipHost.frame = CGRect(x: 0, y: 0, width: 100, height: 30)
        chipHost.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(chipHost.fittingSize.width, 20)

        // Render HistoryPage inside PanelScaffold and verify Environment(\.chartScrubAction) routing
        var scaffoldProbe = PanelScaffoldProbeSnapshot()
        var historyProbe = HistoryPageProbeSnapshot()

        let scaffold = PanelScaffold(
            category: .cpu,
            glance: PanelGlance(value: 64, format: "%.0f", unit: "%", headline: "Live CPU"),
            status: .fine,
            pages: [.overview, .detail, .history],
            selection: .constant(.history)
        ) { _ in
            HistoryPage(category: .cpu, coordinator: coord, preferences: prefs)
                .environment(\.historyPageProbeEnabled, true)
                .onPreferenceChange(HistoryPageProbeKey.self) { historyProbe = $0 }
        }
        .environment(\.panelScaffoldProbeEnabled, true)
        .onPreferenceChange(PanelScaffoldProbeKey.self) { scaffoldProbe = $0 }

        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: scaffold)
        hosting.frame = NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 480)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        hosting.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(historyProbe.fourthCellLabel, "NOW")
        XCTAssertEqual(historyProbe.timeAxisLabels, ["-60s", "-40s", "-20s", "now"])
        XCTAssertTrue((scaffoldProbe.glanceSummary ?? "").contains("64 %"))
    }

    // MARK: - 9. Stage 4 & Stage 5: Polished Panels (8.5.8a–h) & InstrumentGalleryPreview

    private func populateRichTelemetry(in coord: MetricsCoordinator, endingAt endDate: Date, count: Int = 65) {
        let gib: UInt64 = 1_073_741_824
        var batch: [MetricReading] = []
        batch.reserveCapacity(count * 8)

        for i in 0..<count {
            let ts = endDate.addingTimeInterval(-Double(count - 1 - i))
            let wave = Double(i % 12)
            batch.append(.cpu(Sample(
                value: CPUSample(
                    totalUsage: 28.0 + wave * 1.5,
                    perCore: [18.0 + wave, 22.0 + wave, 16.0, 20.0, 35.0 + wave, 38.0 + wave, 30.0, 32.0, 34.0, 36.0],
                    user: 18.0 + wave,
                    system: 10.0 + wave * 0.5,
                    idle: 72.0 - wave * 1.5,
                    loadAverage: LoadAverage(oneMinute: 2.4, fiveMinute: 2.1, fifteenMinute: 1.8),
                    frequencyHz: 3_120_000_000,
                    efficiencyCoreCount: 4,
                    performanceCoreCount: 6
                ),
                timestamp: ts
            )))
            batch.append(.memory(Sample(
                value: MemorySample(
                    total: 16 * gib,
                    used: 10 * gib,
                    free: 6 * gib,
                    wired: 3 * gib,
                    compressed: 1 * gib,
                    cached: 2 * gib,
                    swapUsed: 256 * 1024 * 1024,
                    pressure: .normal,
                    appMemory: 6 * gib,
                    active: 4 * gib,
                    inactive: 2 * gib,
                    swapTotal: 2 * gib,
                    swapFree: (2 * gib) - (256 * 1024 * 1024)
                ),
                timestamp: ts
            )))
            batch.append(.gpu(Sample(
                value: GPUSample(
                    utilization: 34.0 + wave * 2.0,
                    memoryUsed: 2 * gib,
                    tempCelsius: 52.0 + wave * 0.4,
                    powerWatts: 7.5 + wave * 0.3,
                    coreCount: 16,
                    deviceName: "Apple M3 Pro",
                    allocatedMemory: 2 * gib,
                    recommendedMaxMemory: 18 * gib,
                    rendererUtilization: 30.0 + wave,
                    tilerUtilization: 22.0 + wave * 0.5,
                    isUnifiedMemory: true,
                    displayCount: 1,
                    displayDescriptions: ["Built-in Liquid Retina XDR"],
                    recoveryCount: 0,
                    supportsRaytracing: true,
                    metalFeatureSet: "Metal 3"
                ),
                timestamp: ts
            )))
            batch.append(.thermal(Sample(
                value: ThermalSample(
                    sensors: [
                        SensorReading(name: "CPU Performance Core 1", celsius: 56.0 + wave * 0.5),
                        SensorReading(name: "GPU Cluster 1", celsius: 51.0 + wave * 0.4),
                        SensorReading(name: "Memory Proximity", celsius: 42.0),
                        SensorReading(name: "Storage NAND", celsius: 36.0),
                        SensorReading(name: "Battery Sensor 1", celsius: 31.0)
                    ],
                    pressure: .nominal
                ),
                timestamp: ts
            )))
            batch.append(.fan(Sample(
                value: FanSample(fans: [
                    FanReading(name: "Left Fan", rpm: 1600 + Int(wave) * 30, minRPM: 1200, maxRPM: 5800),
                    FanReading(name: "Right Fan", rpm: 1680 + Int(wave) * 30, minRPM: 1200, maxRPM: 6000)
                ]),
                timestamp: ts
            )))
            batch.append(.network(Sample(
                value: NetworkSample(
                    interfaces: [
                        InterfaceThroughput(
                            interfaceName: "en0",
                            bytesInPerSec: 2_400_000.0 + wave * 100_000.0,
                            bytesOutPerSec: 450_000.0 + wave * 20_000.0,
                            totalBytesIn: 120_000_000,
                            totalBytesOut: 28_000_000,
                            ipv4Address: "192.168.1.42",
                            type: .wifi
                        ),
                        InterfaceThroughput(
                            interfaceName: "en5",
                            bytesInPerSec: 0,
                            bytesOutPerSec: 0,
                            totalBytesIn: 0,
                            totalBytesOut: 0,
                            ipv4Address: nil,
                            type: .ethernet
                        )
                    ],
                    primaryInterface: "en0",
                    primaryType: .wifi,
                    localIPv4: "192.168.1.42",
                    gatewayIPv4: "192.168.1.1",
                    primaryDNS: "1.1.1.1",
                    wifiDetails: WiFiLinkTelemetry(
                        ssid: "LabNet-5G",
                        rssi: -54,
                        noise: -92,
                        txRate: 866.0,
                        channel: 36,
                        band: "5 GHz"
                    )
                ),
                timestamp: ts
            )))
            batch.append(.disk(Sample(
                value: DiskSample(
                    volumes: [
                        VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000_000_000, used: 480_000_000_000, free: 520_000_000_000),
                        VolumeCapacity(name: "Backup", mountPoint: "/Volumes/Backup", total: 2_000_000_000_000, used: 700_000_000_000, free: 1_300_000_000_000)
                    ],
                    io: DiskIO(
                        bytesReadPerSec: 18_000_000.0 + wave * 500_000.0,
                        bytesWrittenPerSec: 4_500_000.0 + wave * 200_000.0,
                        readOpsPerSec: 210,
                        writeOpsPerSec: 85
                    )
                ),
                timestamp: ts
            )))
            batch.append(.power(Sample(
                value: PowerSample(
                    hasBattery: true,
                    charge: 84.0,
                    state: .charging,
                    timeRemaining: 2400,
                    cycleCount: 112,
                    condition: "Normal",
                    designCapacity: 5100,
                    currentMaxCapacity: 4950,
                    powerDrawWatts: 18.5 + wave * 0.4,
                    adapterWatts: 96.0,
                    voltageVolts: 12.2,
                    amperageMilliAmps: 1800.0,
                    designCycleCount: 1000,
                    adapterName: "Apple 96W USB-C"
                ),
                timestamp: ts
            )))
        }
        coord.handleReadings(batch)
        coord.updateProcessesForTesting(ProcessSample(
            topCPU: [
                ProcessInfoItem(pid: 201, name: "Xcode", bundleID: "com.apple.dt.Xcode", cpuPercent: 32.4, memoryBytes: 2_400_000_000),
                ProcessInfoItem(pid: 202, name: "swift-frontend", bundleID: nil, cpuPercent: 18.1, memoryBytes: 900_000_000)
            ],
            topMemory: [
                ProcessInfoItem(pid: 201, name: "Xcode", bundleID: "com.apple.dt.Xcode", cpuPercent: 32.4, memoryBytes: 2_400_000_000),
                ProcessInfoItem(pid: 202, name: "swift-frontend", bundleID: nil, cpuPercent: 18.1, memoryBytes: 900_000_000)
            ],
            skippedCount: 0
        ))
    }

    func testPolishedPanels858aThroughHAllTabsRenderAndClamp() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        populateRichTelemetry(in: coord, endingAt: Date(), count: 65)

        // Verify synced Fan Details tab support (B13 / PopoverConfig)
        XCTAssertEqual(PopoverTab.supportedTabs(for: .fan), [.overview, .detail, .history])
        XCTAssertEqual(PopoverTab.detail.title(for: .fan), "Fans")

        for category in MetricCategory.allCases {
            let tabs = PopoverTab.supportedTabs(for: category, hasBattery: true)
            XCTAssertEqual(tabs, [.overview, .detail, .history], "All 8 categories with battery support Now/Details/History")

            for tab in tabs {
                let panelView = PanelFactory.makeCategoryPanelView(
                    category: category,
                    initialTab: tab,
                    rememberLastTab: false,
                    coordinator: coord,
                    preferences: prefs
                )
                let controller = NSHostingController(rootView: AnyView(panelView))
                let size = controller.sizeThatFits(in: CGSize(width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight))
                XCTAssertEqual(size.width, Instrument.Size.panelWidth, accuracy: 2.0, "\(category).\(tab) must fit 352pt width")
                XCTAssertGreaterThan(size.height, 140.0, "\(category).\(tab) must have positive height")
                XCTAssertLessThanOrEqual(size.height, Instrument.Size.maxHeight + 0.5, "\(category).\(tab) must clamp to maxHeight")
            }
        }

        // Verify FanPanel Details hardware table renders distinct content from Now (B13)
        let fanNowView = FanPanel(initialTab: .overview, rememberLastTab: false, coordinator: coord, preferences: prefs)
            .frame(width: Instrument.Size.panelWidth, height: 420)
        let fanDetailView = FanPanel(initialTab: .detail, rememberLastTab: false, coordinator: coord, preferences: prefs)
            .frame(width: Instrument.Size.panelWidth, height: 420)
        let fanNowRenderer = ImageRenderer(content: fanNowView)
        let fanDetailRenderer = ImageRenderer(content: fanDetailView)
        let fanNowCG = fanNowRenderer.cgImage
        let fanDetailCG = fanDetailRenderer.cgImage
        XCTAssertNotNil(fanNowCG)
        XCTAssertNotNil(fanDetailCG)
        if let fanNowCG, let fanDetailCG {
            let nowData = NSBitmapImageRep(cgImage: fanNowCG).tiffRepresentation
            let detailData = NSBitmapImageRep(cgImage: fanDetailCG).tiffRepresentation
            XCTAssertNotEqual(nowData, detailData, "Fan Details page must render distinct hardware table rather than duplicating Now (B13)")
        }

        // Verify Fanless Details + Power Desktop fallback
        coord.handleReading(.fan(Sample(value: FanSample(fans: []))))
        let fanlessDetailCtrl = NSHostingController(rootView: FanPanel(initialTab: .detail, rememberLastTab: false, coordinator: coord, preferences: prefs))
        let fanlessSize = fanlessDetailCtrl.sizeThatFits(in: CGSize(width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight))
        XCTAssertGreaterThan(fanlessSize.height, 140.0)

        coord.handleReading(.power(Sample(value: PowerSample(hasBattery: false, powerDrawWatts: 42.0, adapterWatts: 150.0, adapterName: "Internal PSU"))))
        let desktopPowerCtrl = NSHostingController(rootView: PowerPanel(initialTab: .overview, rememberLastTab: false, coordinator: coord, preferences: prefs))
        let desktopSize = desktopPowerCtrl.sizeThatFits(in: CGSize(width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight))
        XCTAssertGreaterThan(desktopSize.height, 140.0)
    }

    #if DEBUG
    func testInstrumentGalleryPreviewDriverAndHarnessLayout() {
        let baseDate = Date(timeIntervalSince1970: 1_700_050_000.0)
        let driver = InstrumentGalleryTelemetryDriver(referenceDate: baseDate, seedSampleCount: 75)
        defer { driver.stop() }

        // All 8 categories and process list must be populated immediately from seedHistory
        XCTAssertNotNil(driver.coordinator.latestCPU)
        XCTAssertNotNil(driver.coordinator.latestMemory)
        XCTAssertNotNil(driver.coordinator.latestGPU)
        XCTAssertNotNil(driver.coordinator.latestThermal)
        XCTAssertNotNil(driver.coordinator.latestFan)
        XCTAssertNotNil(driver.coordinator.latestNetwork)
        XCTAssertNotNil(driver.coordinator.latestDisk)
        XCTAssertNotNil(driver.coordinator.latestPower)
        XCTAssertNotNil(driver.coordinator.latestProcesses)
        XCTAssertEqual(driver.tickCount, 75)

        // Test +60 ms late sample jitter + 10x spike driving ChartModel (A1 + ChartScale hysteresis)
        driver.loadMode = .spike10x
        driver.lateJitterEnabled = true
        let model = ChartModel(sampleInterval: 1.0)
        var prevEdge: TimeInterval = 0

        for stepIdx in 0..<6 {
            driver.stepTick()
            let netPoints = driver.coordinator.timedScalarHistory(
                for: .networkInBytesPerSec,
                duration: 60.0,
                referenceDate: driver.lastSampleDate
            )
            _ = model.step(
                now: driver.lastSampleDate.timeIntervalSince1970 + 0.016,
                mode: .single(points: netPoints, color: CategoryPalette.tint(for: .network)),
                category: .network,
                sampleInterval: 1.0,
                explicitWindow: 60.0,
                isScrubbing: false,
                motionPolicy: .full
            )
            if stepIdx > 0 {
                XCTAssertGreaterThanOrEqual(model.timeline.edge, prevEdge - 1e-12, "A1: +60ms jitter must never snap edge backward")
            }
            prevEdge = model.timeline.edge
        }
        // 10x spike on network (~12 MB/s) must raise ceiling well above steady ~1.5 MB/s
        XCTAssertGreaterThan(model.topScale.displayedCeiling, 8_000_000.0)

        // Test 15s sleep gap -> clean edge snap
        driver.injectSleepGap(seconds: 15.0)
        XCTAssertEqual(driver.lastSleepGapSeconds, 15.0)
        let postGapPoints = driver.coordinator.timedScalarHistory(
            for: .networkInBytesPerSec,
            duration: 60.0,
            referenceDate: driver.lastSampleDate
        )
        _ = model.step(
            now: driver.lastSampleDate.timeIntervalSince1970 + 1.0,
            mode: .single(points: postGapPoints, color: CategoryPalette.tint(for: .network)),
            category: .network,
            sampleInterval: 1.0,
            explicitWindow: 60.0,
            isScrubbing: false,
            motionPolicy: .full
        )
        XCTAssertEqual(model.timeline.edge, driver.lastSampleDate.timeIntervalSince1970, accuracy: 1.5)

        // Render InstrumentGalleryPreview view hierarchy cleanly
        let gallery = InstrumentGalleryPreview(driver: driver)
        let hosting = NSHostingView(rootView: gallery)
        hosting.frame = CGRect(x: 0, y: 0, width: 1140, height: 820)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.width, 300)
        XCTAssertGreaterThan(hosting.fittingSize.height, 200)
        driver.stop()
    }
    #endif
}
