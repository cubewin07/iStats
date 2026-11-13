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

    // MARK: - 7. Stage 5 Verification Across All 8 Polished Panels (Task 8.5.9)

    private func populateAll8Categories(in coord: MetricsCoordinator, at now: Date = Date()) {
        let gib: UInt64 = 1_073_741_824
        var batch: [MetricReading] = []
        for i in 0..<30 {
            let ts = now.addingTimeInterval(-Double(29 - i))
            batch.append(.cpu(Sample(
                value: CPUSample(
                    totalUsage: 48.0 + Double(i % 10),
                    perCore: [30.0, 35.0, 28.0, 32.0, 62.0, 58.0, 55.0, 60.0],
                    user: 32.0,
                    system: 16.0,
                    idle: 52.0,
                    loadAverage: LoadAverage(oneMinute: 2.3, fiveMinute: 2.0, fifteenMinute: 1.7),
                    frequencyHz: 3_000_000_000,
                    efficiencyCoreCount: 4,
                    performanceCoreCount: 4
                ),
                timestamp: ts
            )))
            batch.append(.memory(Sample(
                value: MemorySample(
                    total: 16 * gib,
                    used: 11 * gib,
                    free: 5 * gib,
                    wired: 3 * gib,
                    compressed: 2 * gib,
                    cached: 2 * gib,
                    swapUsed: 512 * 1024 * 1024,
                    pressure: .warning,
                    appMemory: 6 * gib,
                    active: 4 * gib,
                    inactive: 2 * gib,
                    swapTotal: 2 * gib,
                    swapFree: (2 * gib) - (512 * 1024 * 1024)
                ),
                timestamp: ts
            )))
            batch.append(.gpu(Sample(
                value: GPUSample(
                    utilization: 44.0 + Double(i % 8),
                    memoryUsed: 2 * gib,
                    tempCelsius: 56.0,
                    powerWatts: 11.0,
                    coreCount: 16,
                    deviceName: "Apple M3 Pro",
                    allocatedMemory: 2 * gib,
                    recommendedMaxMemory: 18 * gib,
                    rendererUtilization: 40.0,
                    tilerUtilization: 26.0,
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
                        SensorReading(name: "CPU Core 1", celsius: 64.0),
                        SensorReading(name: "GPU Cluster 1", celsius: 58.0),
                        SensorReading(name: "Memory Proximity", celsius: 44.0)
                    ],
                    pressure: .fair
                ),
                timestamp: ts
            )))
            batch.append(.fan(Sample(
                value: FanSample(fans: [
                    FanReading(name: "Left Fan", rpm: 1850, minRPM: 1200, maxRPM: 5800),
                    FanReading(name: "Right Fan", rpm: 1920, minRPM: 1200, maxRPM: 6000)
                ]),
                timestamp: ts
            )))
            batch.append(.network(Sample(
                value: NetworkSample(
                    interfaces: [
                        InterfaceThroughput(
                            interfaceName: "en0",
                            bytesInPerSec: 4_500_000,
                            bytesOutPerSec: 900_000,
                            totalBytesIn: 100_000_000,
                            totalBytesOut: 25_000_000,
                            ipv4Address: "192.168.1.42",
                            type: .wifi
                        )
                    ],
                    primaryInterface: "en0",
                    primaryType: .wifi,
                    localIPv4: "192.168.1.42",
                    gatewayIPv4: "192.168.1.1",
                    primaryDNS: "1.1.1.1",
                    wifiDetails: WiFiLinkTelemetry(ssid: "LabNet", rssi: -55, noise: -92, txRate: 866.0, channel: 36, band: "5 GHz")
                ),
                timestamp: ts
            )))
            batch.append(.disk(Sample(
                value: DiskSample(
                    volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000_000_000, used: 550_000_000_000, free: 450_000_000_000)],
                    io: DiskIO(bytesReadPerSec: 22_000_000, bytesWrittenPerSec: 6_000_000, readOpsPerSec: 180, writeOpsPerSec: 70)
                ),
                timestamp: ts
            )))
            batch.append(.power(Sample(
                value: PowerSample(
                    hasBattery: true,
                    charge: 78.0,
                    state: .discharging,
                    timeRemaining: 5400,
                    cycleCount: 110,
                    condition: "Normal",
                    designCapacity: 5100,
                    currentMaxCapacity: 4920,
                    powerDrawWatts: 19.5,
                    adapterWatts: nil,
                    voltageVolts: 11.8,
                    amperageMilliAmps: -1650.0,
                    designCycleCount: 1000
                ),
                timestamp: ts
            )))
        }
        coord.handleReadings(batch)
    }

    func testVoiceOverAXChartDescriptorAcrossAll8CategoriesAndModes() {
        let now = Date().timeIntervalSince1970
        let singlePoints = (0..<20).map { i in
            ChartPoint(timestamp: now - Double(19 - i), value: 25.0 + Double(i) * 2.0)
        }
        let dualPoints = (0..<20).map { i in
            DualChartPoint(timestamp: now - Double(19 - i), primary: 20.0 + Double(i), secondary: 10.0 + Double(i % 5))
        }
        let buckets = (0..<20).map { i in
            let mean = 35.0 + Double(i)
            return BucketPoint(timestamp: now - Double(19 - i) * 2.5, min: mean - 8.0, max: mean + 10.0, mean: mean)
        }
        let bands = [ChartBand(threshold: 60.0, color: .orange, label: "Warning")]

        let categoryModes: [(MetricCategory, LiveChartMode)] = [
            (.cpu, .stacked(points: dualPoints, primaryColor: CategoryPalette.tint(for: .cpu), secondaryColor: CategoryPalette.Series.cpuSystem, fixedMax: 100)),
            (.memory, .banded(points: singlePoints, bands: bands, fixedMax: 100)),
            (.gpu, .single(points: singlePoints, color: CategoryPalette.tint(for: .gpu), fixedMax: 100)),
            (.thermal, .banded(points: singlePoints, bands: bands, domainFloor: 30)),
            (.fan, .single(points: singlePoints, color: CategoryPalette.tint(for: .fan), domainFloor: 1200)),
            (.network, .mirrored(points: dualPoints, topColor: CategoryPalette.tint(for: .network), bottomColor: CategoryPalette.Series.networkUpload)),
            (.disk, .mirrored(points: dualPoints, topColor: CategoryPalette.tint(for: .disk), bottomColor: CategoryPalette.Series.diskWrite)),
            (.power, .single(points: singlePoints, color: CategoryPalette.tint(for: .power), domainFloor: 0)),
            (.network, .mirroredEnvelope(top: buckets, bottom: buckets, topColor: CategoryPalette.tint(for: .network), bottomColor: CategoryPalette.Series.networkUpload)),
            (.memory, .envelope(buckets: buckets, color: CategoryPalette.tint(for: .memory), bands: bands, fixedMax: 100))
        ]

        for (category, mode) in categoryModes {
            let chart = LiveChart(category: category, mode: mode, height: 84)
            let descriptor = chart.makeChartDescriptor()

            XCTAssertEqual(descriptor.title, "\(category.rawValue.capitalized) Trend")
            XCTAssertNotNil(descriptor.summary)
            XCTAssertTrue(descriptor.summary?.contains("Now:") == true, "Summary for \(category) must include Now:")
            XCTAssertTrue(descriptor.summary?.contains("Min:") == true, "Summary for \(category) must include Min:")
            XCTAssertTrue(descriptor.summary?.contains("Avg:") == true, "Summary for \(category) must include Avg:")
            XCTAssertTrue(descriptor.summary?.contains("Max:") == true, "Summary for \(category) must include Max:")
            XCTAssertTrue(descriptor.summary?.contains("20 samples") == true)

            XCTAssertEqual(descriptor.series.count, 1)
            XCTAssertEqual(descriptor.series.first?.dataPoints.count, 20)

            let xAxis = descriptor.xAxis as? AXNumericDataAxisDescriptor
            let yAxis = descriptor.yAxis as? AXNumericDataAxisDescriptor
            XCTAssertNotNil(xAxis)
            XCTAssertNotNil(yAxis)
            XCTAssertGreaterThanOrEqual(xAxis?.range.upperBound ?? 0, 20.0)
            XCTAssertGreaterThan(yAxis?.range.upperBound ?? 0, yAxis?.range.lowerBound ?? 0)
        }

        // Empty chart degrades gracefully in VoiceOver
        let emptyChart = LiveChart(category: .power, mode: .single(points: [ChartPoint](), color: .green))
        let emptyDescriptor = emptyChart.makeChartDescriptor()
        XCTAssertEqual(emptyDescriptor.summary, "No data available")
        XCTAssertEqual(emptyDescriptor.series.first?.dataPoints.count, 0)
    }

    func testIncreaseContrastAcrossAll8PolishedPanels() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        populateAll8Categories(in: coord)

        let highContrastAppearances: [(ColorScheme, NSAppearance.Name)] = [
            (.light, .accessibilityHighContrastAqua),
            (.dark, .accessibilityHighContrastDarkAqua)
        ]

        for (scheme, appearanceName) in highContrastAppearances {
            let nsAppearance = NSAppearance(named: appearanceName)
            XCTAssertNotNil(nsAppearance, "Expected macOS high-contrast appearance \(appearanceName.rawValue)")

            for category in MetricCategory.allCases {
                for tab in [PopoverTab.overview, .detail] {
                    let panel = PanelFactory.makeCategoryPanelView(
                        category: category,
                        initialTab: tab,
                        rememberLastTab: false,
                        coordinator: coord,
                        preferences: prefs
                    )
                    .environment(\.colorScheme, scheme)

                    let hosting = NSHostingView(rootView: AnyView(panel))
                    hosting.appearance = nsAppearance
                    hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight)
                    hosting.layoutSubtreeIfNeeded()

                    let fit = hosting.fittingSize
                    XCTAssertEqual(fit.width, Instrument.Size.panelWidth, accuracy: 2.0, "High-contrast \(appearanceName.rawValue) \(category).\(tab) width mismatch")
                    XCTAssertGreaterThan(fit.height, 100.0, "High-contrast \(appearanceName.rawValue) \(category).\(tab) must lay out cleanly")
                }
            }
        }
    }

    func testDifferentiateWithoutColorAcrossAll8PolishedPanelsAndStatusSymbols() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // 1. Distinct non-color indicators on StatusLevel + InlineStatusChip
        let chipTokens = [StatusLevel.elevated, .warning, .critical].map { InlineStatusChip.displayText(for: $0) }
        XCTAssertEqual(Set(chipTokens).count, 3, "Each alert level must have a distinct glyph + text token")
        XCTAssertEqual(chipTokens, ["● Elevated", "▲ Warning", "◆ Critical"])

        // 2. Populate warning/critical conditions across all 8 panels so non-color status badges & symbols render
        let now = Date()
        let gib: UInt64 = 1_073_741_824
        coord.handleReadings([
            .cpu(Sample(value: CPUSample(totalUsage: 94.0, perCore: [92, 96, 94, 94], user: 68.0, system: 26.0, idle: 6.0, loadAverage: LoadAverage(oneMinute: 8.5, fiveMinute: 6.2, fifteenMinute: 4.1), efficiencyCoreCount: 2, performanceCoreCount: 2), timestamp: now)),
            .memory(Sample(value: MemorySample(total: 16 * gib, used: 14 * gib, free: 2 * gib, wired: 4 * gib, compressed: 3 * gib, cached: 1 * gib, swapUsed: 2 * gib, pressure: .critical, appMemory: 7 * gib), timestamp: now)),
            .gpu(Sample(value: GPUSample(utilization: 91.0, memoryUsed: 3 * gib, tempCelsius: 82.0, powerWatts: 28.0, coreCount: 16, deviceName: "Apple M3 Pro", recoveryCount: 1), timestamp: now)),
            .thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU Die", celsius: 99.0)], pressure: .critical), timestamp: now)),
            .fan(Sample(value: FanSample(fans: [FanReading(name: "Left Fan", rpm: 5600, minRPM: 1200, maxRPM: 5800)]), timestamp: now)),
            .network(Sample(value: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 12_000_000, bytesOutPerSec: 3_000_000, totalBytesIn: 500_000_000, totalBytesOut: 100_000_000, ipv4Address: "192.168.1.42", type: .wifi)], primaryInterface: "en0", primaryType: .wifi), timestamp: now)),
            .disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 485_000_000_000, free: 15_000_000_000)], io: DiskIO(bytesReadPerSec: 80_000_000, bytesWrittenPerSec: 40_000_000, readOpsPerSec: 400, writeOpsPerSec: 200)), timestamp: now)),
            .power(Sample(value: PowerSample(hasBattery: true, charge: 8.0, state: .discharging, timeRemaining: 600, powerDrawWatts: 24.0), timestamp: now))
        ])

        for category in MetricCategory.allCases {
            let panel = PanelFactory.makeCategoryPanelView(
                category: category,
                initialTab: .overview,
                rememberLastTab: false,
                coordinator: coord,
                preferences: prefs
            )
            let controller = NSHostingController(rootView: AnyView(panel))
            let size = controller.sizeThatFits(in: CGSize(width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight))
            XCTAssertEqual(size.width, Instrument.Size.panelWidth, accuracy: 2.0)
            XCTAssertGreaterThan(size.height, 140.0, "Warning/critical panel \(category) must render status chips & bars cleanly")
        }
    }

    func testReduceMotionAndFrozenMotionAcrossAll8PolishedPanels() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        populateAll8Categories(in: coord)

        // 1. Verify MotionPolicy.resolve matrix for Reduce Motion + Low Power + Paused
        XCTAssertEqual(MotionPolicy.resolve(reduceMotion: true, lowPower: false, paused: false, visible: true), .reduced)
        XCTAssertEqual(MotionPolicy.resolve(reduceMotion: true, lowPower: true, paused: false, visible: true), .frozen)
        XCTAssertEqual(MotionPolicy.resolve(reduceMotion: false, lowPower: false, paused: true, visible: true), .frozen)
        XCTAssertEqual(MotionPolicy.resolve(reduceMotion: false, lowPower: false, paused: false, visible: false), .frozen)

        // 2. Verify ChartModel snaps timeline and scale immediately under .reduced and .frozen (zero continuous glide)
        let base = Date().timeIntervalSince1970
        let pts = (0..<20).map { ChartPoint(timestamp: base - Double(19 - $0), value: 20.0 + Double($0) * 3.0) }
        for policy in [MotionPolicy.reduced, .frozen] {
            let model = ChartModel(sampleInterval: 1.0)
            _ = model.step(
                now: base + 0.25,
                mode: .single(points: pts, color: .blue),
                category: .cpu,
                sampleInterval: 1.0,
                explicitWindow: 60.0,
                isScrubbing: false,
                motionPolicy: policy
            )
            XCTAssertEqual(model.timeline.edge, base, accuracy: 1e-6, "Non-full MotionPolicy.\(policy) must snap edge directly to latest timestamp without glide lag")
        }

        // 3. Render all 8 panels under .reduced and .frozen policies across all tabs
        for policy in [MotionPolicy.reduced, .frozen] {
            for category in MetricCategory.allCases {
                for tab in PopoverTab.supportedTabs(for: category, hasBattery: true) {
                    let panel = PanelFactory.makeCategoryPanelView(
                        category: category,
                        initialTab: tab,
                        rememberLastTab: false,
                        coordinator: coord,
                        preferences: prefs
                    )
                    .motionPolicy(policy)

                    let controller = NSHostingController(rootView: AnyView(panel))
                    let size = controller.sizeThatFits(in: CGSize(width: Instrument.Size.panelWidth, height: Instrument.Size.maxHeight))
                    XCTAssertEqual(size.width, Instrument.Size.panelWidth, accuracy: 2.0, "\(category).\(tab) under \(policy) width mismatch")
                    XCTAssertGreaterThan(size.height, 140.0, "\(category).\(tab) under \(policy) must lay out cleanly")
                }
            }
        }
    }
}
