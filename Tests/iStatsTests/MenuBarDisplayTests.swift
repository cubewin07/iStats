import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class MenuBarDisplayTests: XCTestCase {
    // MARK: - ADR 0007 Modular Rendering & Controller Lifecycle Tests

    private func widgetImage(_ category: MetricCategory, _ style: MetricDisplayStyle, _ snapshot: WidgetSnapshot = WidgetSnapshot()) -> NSImage {
        let model = WidgetModel.make(config: MenuBarItemConfig(category: category, style: style), snapshot: snapshot, options: WidgetOptions())
        return MenuBarIconRenderer.image(for: model)
    }

    func testMenuBarIconRendererDrawings() {
        let snap = WidgetSnapshot(
            cpu: CPUSample(totalUsage: 50, perCore: [50], user: 30, system: 20, idle: 50),
            gpu: GPUSample(utilization: 75),
            series: WidgetSeries(primary: [10, 30, 60, 90], secondary: [], tertiary: [], stamp: 4)
        )
        // Ring (18x18 pt)
        let gaugeImg = widgetImage(.gpu, .gauge, snap)
        XCTAssertEqual(gaugeImg.size, NSSize(width: 18, height: 18))
        // Capsule bar (25x22 pt)
        let barImg = widgetImage(.gpu, .bar, snap)
        XCTAssertEqual(barImg.size, NSSize(width: 25, height: 22))
        // Sparkline (36x16 pt)
        let sparklineImg = widgetImage(.gpu, .sparkline, snap)
        XCTAssertEqual(sparklineImg.size, NSSize(width: 36, height: 16))
    }

    func testMenuBarIconRendererConfigRendering() {
        let suiteName = "test.istats.renderer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)

        let cpuGaugeConfig = MenuBarItemConfig(category: .cpu, style: .gauge)
        let resGauge = MenuBarIconRenderer.render(config: cpuGaugeConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resGauge.image)
        XCTAssertTrue(resGauge.toolTip.contains("CPU"))

        let netThroughputConfig = MenuBarItemConfig(category: .network, style: .throughput)
        let resThroughput = MenuBarIconRenderer.render(config: netThroughputConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resThroughput.image)
        XCTAssertTrue(resThroughput.toolTip.contains("Network"))

        // Fan configs
        let fanTextConfig = MenuBarItemConfig(category: .fan, style: .text)
        let resFanText = MenuBarIconRenderer.render(config: fanTextConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resFanText.image)
        XCTAssertTrue(resFanText.toolTip.contains("Fans"))

        let fanTachoConfig = MenuBarItemConfig(category: .fan, style: .gauge)
        let resFanTacho = MenuBarIconRenderer.render(config: fanTachoConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resFanTacho.image)

        let fanBladesConfig = MenuBarItemConfig(category: .fan, style: .symbol)
        let resFanBlades = MenuBarIconRenderer.render(config: fanBladesConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resFanBlades.image)

        let fanThroughputConfig = MenuBarItemConfig(category: .fan, style: .throughput)
        let resFanThroughput = MenuBarIconRenderer.render(config: fanThroughputConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resFanThroughput.image)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testMenuBarControllerMultiItemDynamicLifecycle() {
        let suiteName = "test.istats.controller.lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)

        // Set explicit items: 1 CPU gauge, 1 RAM bar
        let item1 = MenuBarItemConfig(category: .cpu, style: .gauge)
        let item2 = MenuBarItemConfig(category: .memory, style: .bar)
        prefs.menuBarItems = [item1, item2]

        let controller = MenuBarController(preferences: prefs, coordinator: coord)

        // Verify both items created
        XCTAssertEqual(controller.statusItems.count, 2)
        XCTAssertNotNil(controller.statusItems[item1.id])
        XCTAssertNotNil(controller.statusItems[item2.id])

        // Add a 3rd item for CPU (text)
        prefs.setItemEnabled(category: .cpu, style: .text, isEnabled: true)
        let item3 = MenuBarItemConfig(category: .cpu, style: .text)
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 3)
        XCTAssertNotNil(controller.statusItems[item3.id])

        // Disable CPU category -> All CPU items (item1, item3) are removed from active status items
        prefs.setCategory(.cpu, isEnabled: false)
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 1)
        XCTAssertNil(controller.statusItems[item1.id])
        XCTAssertNotNil(controller.statusItems[item2.id])
        XCTAssertNil(controller.statusItems[item3.id])

        // Re-enable CPU category -> CPU items reappear
        prefs.setCategory(.cpu, isEnabled: true)
        controller.syncStatusItems()

        XCTAssertEqual(controller.statusItems.count, 3)
        XCTAssertNotNil(controller.statusItems[item1.id])

        // Clean up
        for (_, item) in controller.statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFallbackStatusItemWhenAllItemsDisabled() {
        let suiteName = "iStats.test.fallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let scheduler = SampleScheduler()
        let store = MetricsStore()
        let coord = MetricsCoordinator(scheduler: scheduler, store: store, preferencesStore: prefs)

        // Clear all items
        prefs.menuBarItems = []

        let controller = MenuBarController(preferences: prefs, coordinator: coord)

        // Fallback status item should be installed
        XCTAssertEqual(controller.statusItems.count, 1)
        XCTAssertNotNil(controller.statusItems[MenuBarController.fallbackStatusItemId])

        let fallbackItem = controller.statusItems[MenuBarController.fallbackStatusItemId]
        XCTAssertEqual(fallbackItem?.button?.identifier?.rawValue, MenuBarController.fallbackStatusItemId)

        // Now add an item back
        prefs.menuBarItems = [MenuBarItemConfig(category: .cpu, style: .text)]
        controller.syncStatusItems()

        // Fallback item should be removed and replaced with CPU item
        XCTAssertEqual(controller.statusItems.count, 1)
        XCTAssertNil(controller.statusItems[MenuBarController.fallbackStatusItemId])
        XCTAssertNotNil(controller.statusItems["cpu.text"])

        // Clean up
        for (_, item) in controller.statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCategoryPopoverInstantiation() {
        for category in MetricCategory.allCases {
            let view = PanelFactory.makeCategoryPanelView(
                category: category,
                coordinator: .shared,
                preferences: .shared
            )
            let hosting = NSHostingView(rootView: AnyView(view))
            XCTAssertNotNil(hosting)
        }
    }

    // MARK: - Bespoke Expressive Drawing Tests

    func testBespokeCategorySymbols() {
        let snap = WidgetSnapshot(
            cpu: CPUSample(totalUsage: 85, perCore: [85], user: 60, system: 25, idle: 15),
            memory: MemorySample(total: 100, used: 92, free: 8, wired: 20, compressed: 10, cached: 0, swapUsed: 0, pressure: .critical),
            gpu: GPUSample(utilization: 95),
            thermal: ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: 88)]),
            fan: FanSample(fans: [FanReading(name: "Fan", rpm: 3500, minRPM: 1000, maxRPM: 6000)]),
            network: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 5_000_000, bytesOutPerSec: 2_000_000, totalBytesIn: 0, totalBytesOut: 0)]),
            disk: DiskSample(io: DiskIO(bytesReadPerSec: 50_000_000, bytesWrittenPerSec: 20_000_000, readOpsPerSec: 0, writeOpsPerSec: 0)),
            power: PowerSample(hasBattery: true, charge: 90, state: .charging)
        )
        for (category, style, size) in [
            (MetricCategory.cpu, MetricDisplayStyle.gauge, NSSize(width: 18, height: 18)),
            (.memory, .symbol, NSSize(width: 18, height: 18)),
            (.gpu, .gauge, NSSize(width: 18, height: 18)),
            (.thermal, .gauge, NSSize(width: 18, height: 18)),
            (.network, .symbol, NSSize(width: 18, height: 18)),
            (.disk, .symbol, NSSize(width: 20, height: 18)),
            (.power, .symbol, NSSize(width: 25, height: 16)),
            (.fan, .glyph, NSSize(width: 44, height: 22))
        ] {
            XCTAssertEqual(widgetImage(category, style, snap).size, size, "\(category) \(style)")
            XCTAssertEqual(widgetImage(category, style).size, size, "\(category) \(style) with no data")
        }
        // No battery still draws the 25x16 instrument
        XCTAssertEqual(widgetImage(.power, .symbol, WidgetSnapshot(power: PowerSample(hasBattery: false))).size, NSSize(width: 25, height: 16))
    }

    func testPowerIconVariantRendering() {
        for variant in PowerStateVariant.allCases {
            let symbolImg = MenuBarIconRenderer.drawBatteryInstrument(charge: 65.0, state: .discharging, hasBattery: true, variant: variant)
            XCTAssertEqual(symbolImg.size, NSSize(width: 25, height: 16))
        }
    }

    func testBespokeCategoryGaugesBarsAndSparklines() {
        let series = WidgetSeries(primary: [10, 20, 50, 80], secondary: [5, 10, 20, 30], tertiary: [5, 10, 30, 50], stamp: 4)
        let snap = WidgetSnapshot(
            cpu: CPUSample(totalUsage: 50, perCore: [50], user: 30, system: 20, idle: 50),
            memory: MemorySample(total: 100, used: 45, free: 55, wired: 10, compressed: 5, cached: 0, swapUsed: 0, pressure: .normal),
            gpu: GPUSample(utilization: 30),
            thermal: ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: 60)]),
            fan: FanSample(fans: [FanReading(name: "Fan", rpm: 2500, minRPM: 1000, maxRPM: 5000)]),
            network: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 2000, bytesOutPerSec: 1000, totalBytesIn: 0, totalBytesOut: 0)]),
            disk: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 100, used: 40, free: 60)]),
            power: PowerSample(hasBattery: true, charge: 85, state: .discharging, powerDrawWatts: 12),
            series: series
        )
        for category in MetricCategory.allCases {
            for style in MetricDisplayStyle.supportedStyles(for: category) {
                let img = widgetImage(category, style, snap)
                XCTAssertGreaterThan(img.size.width, 0, "\(category) \(style)")
                XCTAssertEqual(img.size.height > 0, true, "\(category) \(style)")
            }
        }

        // Multi-fan bar and stacked throughput
        let dualFan = WidgetSnapshot(fan: FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 2300, minRPM: 2000, maxRPM: 6000),
            FanReading(name: "Right Fan", rpm: 2500, minRPM: 2000, maxRPM: 6000)
        ]))
        XCTAssertEqual(widgetImage(.fan, .bar, dualFan).size, NSSize(width: 36, height: 22))
        XCTAssertEqual(widgetImage(.fan, .throughput, dualFan).size, NSSize(width: WidgetMetrics.width(.twoLineFan), height: 22))
    }

    func testAllAvailableConfigsRenderingCompleteness() {
        let suiteName = "test.istats.allconfigs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)

        for config in MenuBarItemConfig.allAvailableItems {
            let res = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)
            XCTAssertFalse(res.toolTip.isEmpty, "Tooltip should be populated for \(config.id)")
            XCTAssertTrue(res.image != nil || !res.title.isEmpty, "Config \(config.id) must render image or title")
        }

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Authentic iStat Menus Instrument Tests

    func testDrawCategoryStackedTextWidthInvariance() {
        // Test 1-digit, 2-digit, 3-digit, and nil placeholder with 32.0pt fixed width
        let w = WidgetMetrics.width(.stackedPercent)
        let img1Digit = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: "2%", fixedWidth: w)
        let img2Digits = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: "82%", fixedWidth: w)
        let img3Digits = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: "100%", fixedWidth: w)
        let imgPlaceholder = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: "--%", fixedWidth: w)

        XCTAssertEqual(img1Digit.size.width, w, "1-digit percentage must have the class width")
        XCTAssertEqual(img2Digits.size.width, w, "2-digit percentage must have the class width")
        XCTAssertEqual(img3Digits.size.width, w, "3-digit percentage must have the class width")
        XCTAssertEqual(imgPlaceholder.size.width, w, "Placeholder must have the class width")

        XCTAssertEqual(img1Digit.size.height, 22.0)
        XCTAssertEqual(img2Digits.size.height, 22.0)
        XCTAssertEqual(img3Digits.size.height, 22.0)
        XCTAssertEqual(imgPlaceholder.size.height, 22.0)
    }

    func testDrawStackedTwoLineText() {
        let img = MenuBarIconRenderer.drawStackedTwoLineText(
            prefix1: "↑",
            value1: "13 KB/s",
            prefix2: "↓",
            value2: "1.6 MB/s",
            minWidth: WidgetMetrics.width(.twoLineRate)
        )
        XCTAssertEqual(img.size.height, 22)
        XCTAssertEqual(img.size.width, WidgetMetrics.width(.twoLineRate))
        XCTAssertTrue(img.isTemplate)

        // Disk throughput through the model path
        let disk = DiskSample(io: DiskIO(bytesReadPerSec: 1024 * 1024 * 1.2, bytesWrittenPerSec: 1024 * 450, readOpsPerSec: 0, writeOpsPerSec: 0))
        let config = MenuBarItemConfig(category: .disk, style: .throughput, throughputLayout: .stacked)
        let model = WidgetModel.make(config: config, snapshot: WidgetSnapshot(disk: disk), options: WidgetOptions(byteUnitStandard: .iec))
        let diskImg = MenuBarIconRenderer.image(for: model)
        XCTAssertEqual(diskImg.size.height, 22)
        XCTAssertEqual(diskImg.size.width, WidgetMetrics.width(.twoLineRate))
        XCTAssertTrue(diskImg.isTemplate)
    }

    func testStackedThroughputWidthInvariance() {
        func width(_ inB: Double, _ outB: Double) -> CGFloat {
            let net = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: inB, bytesOutPerSec: outB, totalBytesIn: 0, totalBytesOut: 0)])
            return widgetImage(.network, .throughput, WidgetSnapshot(network: net)).size.width
        }
        let expected = WidgetMetrics.width(.twoLineRate)
        XCTAssertEqual(width(0, 0), expected, "Zero network rate must keep the class width")
        XCTAssertEqual(width(1024 * 13, 1024 * 1024 * 1.6), expected, "Small network rate must keep the class width")
        XCTAssertEqual(width(1024 * 1024 * 50, 1024 * 1024 * 125), expected, "Medium network rate must keep the class width")
    }

    func testDrawCPUPerCoreBarCluster() {
        let cores8 = [10.0, 25.0, 50.0, 75.0, 20.0, 40.0, 60.0, 80.0]
        let img8 = widgetImage(.cpu, .bar, WidgetSnapshot(cpu: CPUSample(totalUsage: 60, perCore: cores8, user: 45, system: 15, idle: 40)))
        XCTAssertEqual(img8.size, NSSize(width: 36, height: 22))

        let cores10Hybrid = Array(repeating: 20.0, count: 6) + Array(repeating: 80.0, count: 4)
        let img10 = widgetImage(.cpu, .bar, WidgetSnapshot(cpu: CPUSample(totalUsage: 40, perCore: cores10Hybrid, user: 30, system: 10, idle: 60, efficiencyCoreCount: 6, performanceCoreCount: 4)))
        XCTAssertEqual(img10.size, NSSize(width: 36, height: 22))

        let coresNil = widgetImage(.cpu, .bar, WidgetSnapshot(cpu: CPUSample(totalUsage: 50, perCore: [], user: 40, system: 10, idle: 50)))
        XCTAssertEqual(coresNil.size, NSSize(width: 36, height: 22))
    }

    func testDrawCapsuleBars() {
        // Dual Capsule Bar (Generic / Template)
        let genericBar = MenuBarIconRenderer.drawDualCapsuleBar(label: "SSD", leftPercentage: 90.0, rightPercentage: 30.0)
        XCTAssertEqual(genericBar.size, NSSize(width: 36, height: 22))
        XCTAssertTrue(genericBar.isTemplate)

        // Single capsule bars: one fixed 25x22 size for every category
        let snap = WidgetSnapshot(
            memory: MemorySample(total: 100, used: 65, free: 35, wired: 0, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal),
            gpu: GPUSample(utilization: 45),
            thermal: ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: 65)]),
            fan: FanSample(fans: [FanReading(name: "Fan", rpm: 2000, minRPM: 0, maxRPM: 5000)]),
            disk: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 100, used: 72, free: 28)])
        )
        for category in [MetricCategory.memory, .gpu, .thermal, .fan, .disk] {
            let bar = widgetImage(category, .bar, snap)
            XCTAssertEqual(bar.size, NSSize(width: 25, height: 22), "\(category)")
            XCTAssertFalse(bar.isTemplate, "\(category)")
        }
    }

    func testDrawCPUDonutPie() {
        let snap = WidgetSnapshot(cpu: CPUSample(totalUsage: 60, perCore: [60], user: 45, system: 15, idle: 40))
        XCTAssertEqual(widgetImage(.cpu, .gauge, snap).size, NSSize(width: 18, height: 18))
    }

    func testDrawNetworkSplitDuplexGraph() {
        let inHistory = [1000.0, 5000.0, 20000.0, 100000.0, 50000.0]
        let outHistory = [500.0, 2000.0, 10000.0, 40000.0, 20000.0]
        let splitGraph = MenuBarIconRenderer.drawNetworkSplitDuplexGraph(inHistory: inHistory, outHistory: outHistory)
        XCTAssertEqual(splitGraph.size, NSSize(width: 36, height: 16))
    }

    func testDrawNetworkStackedThroughput() {
        let net = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1024 * 1024 * 5, bytesOutPerSec: 1024 * 500, totalBytesIn: 0, totalBytesOut: 0)])
        let netImg = widgetImage(.network, .throughput, WidgetSnapshot(network: net))
        XCTAssertEqual(netImg.size.height, 22)
        XCTAssertTrue(netImg.isTemplate)
    }

    func testDrawBatteryInstrument() {
        let batDischarging = MenuBarIconRenderer.drawBatteryInstrument(charge: 75.0, state: .discharging, hasBattery: true)
        XCTAssertEqual(batDischarging.size, NSSize(width: 25, height: 16))
        XCTAssertNotNil(batDischarging)

        let batCharging = MenuBarIconRenderer.drawBatteryInstrument(charge: 88.0, state: .charging, hasBattery: true)
        XCTAssertEqual(batCharging.size, NSSize(width: 25, height: 16))
        XCTAssertNotNil(batCharging)

        let desktopAC = MenuBarIconRenderer.drawBatteryInstrument(charge: nil, state: nil, hasBattery: false)
        XCTAssertEqual(desktopAC.size, NSSize(width: 25, height: 16))
        XCTAssertNotNil(desktopAC)

        let unmetered = MenuBarIconRenderer.drawBatteryInstrument(charge: nil, state: nil, hasBattery: true)
        XCTAssertEqual(unmetered.size, NSSize(width: 25, height: 16))
    }

    // MARK: - Design Rationalization & Semantic Contract Tests

    func testDecayMaxDynamicCeiling() {
        // Floor applies when values are below floor
        let scaledFloor = MenuBarIconRenderer.computeDecayMax(values: [100.0, 500.0], floor: 1024.0)
        XCTAssertEqual(scaledFloor, 1024.0)

        // Peak applies when values exceed floor
        let scaledPeak = MenuBarIconRenderer.computeDecayMax(values: [100.0, 5000.0, 2500.0], floor: 1024.0)
        XCTAssertEqual(scaledPeak, 5000.0)

        // Empty values fallback to floor
        let scaledEmpty = MenuBarIconRenderer.computeDecayMax(values: [], floor: 5.0)
        XCTAssertEqual(scaledEmpty, 5.0)
    }

    func testPeakThermalSensorSelectionAndTMPTitle() {
        let suiteName = "test.istats.thermal.peak.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)

        // Mock thermal sample with multiple sensors (SoC hottest at 88°C, CPU at 55°C, Memory at 45°C)
        let thermalSample = ThermalSample(
            sensors: [
                SensorReading(name: "Memory Module", celsius: 45.0),
                SensorReading(name: "CPU Core Average", celsius: 55.0),
                SensorReading(name: "SoC Peak Die", celsius: 88.0)
            ],
            pressure: .nominal
        )
        coord.handleReading(.thermal(Sample(value: thermalSample)))

        let configText = MenuBarItemConfig(category: .thermal, style: .text)
        let res = MenuBarIconRenderer.render(config: configText, coordinator: coord, preferences: prefs)

        // Verify title is "TMP", never "CPU"
        XCTAssertNotNil(res.image)
        XCTAssertTrue(res.toolTip.contains("88.0 °C") || res.toolTip.contains("88.0°C") || res.toolTip.contains("88.0"))
        XCTAssertTrue(res.toolTip.contains("SoC Peak Die"))
        XCTAssertEqual(res.accessibilityLabel, "Peak temperature 88 °C")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testComponentSpecificThermalRendering() {
        let suiteName = "test.istats.thermal.components.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)

        let thermalSample = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 52.0),
                SensorReading(name: "GPU Cluster 1", celsius: 65.0),
                SensorReading(name: "Memory Module A", celsius: 48.0),
                SensorReading(name: "Storage Flash (NAND)", celsius: 41.0),
                SensorReading(name: "Battery (Sensor 1)", celsius: 33.0),
                SensorReading(name: "SoC Peak Die", celsius: 72.0)
            ],
            pressure: .nominal
        )
        coord.handleReading(.thermal(Sample(value: thermalSample)))

        // 1. CPU Temp
        let cpuRes = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .thermal, style: .text, source: .cpu), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(cpuRes.image)
        XCTAssertTrue(cpuRes.toolTip.contains("52.0 °C") && cpuRes.toolTip.contains("CPU Package"))
        XCTAssertEqual(cpuRes.accessibilityLabel, "CPU temperature 52 °C")

        // 2. GPU Temp
        let gpuRes = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .thermal, style: .text, source: .gpu), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(gpuRes.image)
        XCTAssertTrue(gpuRes.toolTip.contains("65.0 °C") && gpuRes.toolTip.contains("GPU Cluster 1"))
        XCTAssertEqual(gpuRes.accessibilityLabel, "GPU temperature 65 °C")

        // 3. Memory Temp
        let memRes = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .thermal, style: .text, source: .memory), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(memRes.image)
        XCTAssertTrue(memRes.toolTip.contains("48.0 °C") && memRes.toolTip.contains("Memory Module A"))
        XCTAssertEqual(memRes.accessibilityLabel, "Memory temperature 48 °C")

        // 4. Storage Temp
        let ssdRes = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .thermal, style: .text, source: .ssd), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(ssdRes.image)
        XCTAssertTrue(ssdRes.toolTip.contains("41.0 °C") && ssdRes.toolTip.contains("Storage Flash (NAND)"))
        XCTAssertEqual(ssdRes.accessibilityLabel, "Storage temperature 41 °C")

        // 5. Battery Temp
        let batRes = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .thermal, style: .text, source: .battery), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(batRes.image)
        XCTAssertTrue(batRes.toolTip.contains("33.0 °C") && batRes.toolTip.contains("Battery (Sensor 1)"))
        XCTAssertEqual(batRes.accessibilityLabel, "Battery temperature 33 °C")

        // 6. Graceful degradation when sensor missing
        let emptySample = ThermalSample(sensors: [], pressure: .nominal)
        coord.handleReading(.thermal(Sample(value: emptySample)))
        let emptyRes = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .thermal, style: .text, source: .gpu), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(emptyRes.image)
        XCTAssertEqual(emptyRes.toolTip, "GPU Thermal: --")
        XCTAssertEqual(emptyRes.accessibilityLabel, "GPU thermal unavailable")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPowerBudgetTextRendering() {
        let suiteName = "test.istats.power.budget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)

        let powerSample = PowerSample(
            hasBattery: true,
            charge: 80.0,
            state: .charging,
            powerDrawWatts: 28.4,
            adapterWatts: 67.0
        )
        coord.handleReading(.power(Sample(value: powerSample)))

        let configThroughput = MenuBarItemConfig(category: .power, style: .throughput)
        let res = MenuBarIconRenderer.render(config: configThroughput, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(res.image)
        XCTAssertEqual(res.image?.size.width, WidgetMetrics.width(.twoLinePower))
        XCTAssertEqual(res.image?.size.height, 22.0)


        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDiskLinearCapacityBar() {
        let disk = DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 1000, used: 725, free: 275)])
        let diskBar = widgetImage(.disk, .bar, WidgetSnapshot(disk: disk))
        XCTAssertEqual(diskBar.size.width, 25.0)
        XCTAssertEqual(diskBar.size.height, 22.0)
        XCTAssertFalse(diskBar.isTemplate)
    }

    func testMemorySegmentedBarAndPressureBadge() {
        let memSample = MemorySample(
            total: 32 * 1024 * 1024 * 1024,
            used: 20 * 1024 * 1024 * 1024,
            free: 12 * 1024 * 1024 * 1024,
            wired: 6 * 1024 * 1024 * 1024,
            compressed: 4 * 1024 * 1024 * 1024,
            cached: 4 * 1024 * 1024 * 1024,
            swapUsed: 0,
            pressure: .warning,
            appMemory: 10 * 1024 * 1024 * 1024,
            active: 10 * 1024 * 1024 * 1024
        )

        // Segmented Stacked Bar
        let barImg = widgetImage(.memory, .bar, WidgetSnapshot(memory: memSample))
        XCTAssertEqual(barImg.size.width, 25.0)
        XCTAssertEqual(barImg.size.height, 22.0)
        XCTAssertFalse(barImg.isTemplate)

        // Pressure Badge (OK, WARN, CRIT)
        let badgeNormal = MenuBarIconRenderer.drawMemoryPressureBadge(pressure: .normal)
        let badgeWarn = MenuBarIconRenderer.drawMemoryPressureBadge(pressure: .warning)
        let badgeCrit = MenuBarIconRenderer.drawMemoryPressureBadge(pressure: .critical)

        XCTAssertEqual(badgeNormal.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(badgeWarn.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(badgeCrit.size, NSSize(width: 18, height: 18))
    }

    func testGPUDieSymbolAndTempTintedGauge() {
        let dieSymbol = MenuBarIconRenderer.drawGPUDieSymbol(utilization: 75.0, tempCelsius: 68.0)
        XCTAssertEqual(dieSymbol.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(dieSymbol.isTemplate)

        let gpuGauge = widgetImage(.gpu, .gauge, WidgetSnapshot(gpu: GPUSample(utilization: 80.0, tempCelsius: 72.0)))
        XCTAssertEqual(gpuGauge.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(gpuGauge.isTemplate)
    }
}
