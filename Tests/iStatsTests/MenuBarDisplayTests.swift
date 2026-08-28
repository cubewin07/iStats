import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class MenuBarDisplayTests: XCTestCase {
    // MARK: - Format Title Tests

    func testFormatTitleIconMode() {
        let title = MenuBarController.formatTitle(mode: .icon)
        XCTAssertEqual(title, "")
    }

    func testFormatTitleCPUMode() {
        let sample = CPUSample(
            totalUsage: 42.4,
            perCore: [40.0, 44.8],
            user: 25.0,
            system: 17.4,
            idle: 57.6
        )

        let titleWithSample = MenuBarController.formatTitle(mode: .cpu, cpu: sample)
        XCTAssertEqual(titleWithSample, "CPU 42%")

        let titleNil = MenuBarController.formatTitle(mode: .cpu, cpu: nil)
        XCTAssertEqual(titleNil, "CPU --%")
    }

    func testFormatTitleMemoryMode() {
        let sample = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 8 * 1024 * 1024 * 1024,
            free: 8 * 1024 * 1024 * 1024,
            wired: 2 * 1024 * 1024 * 1024,
            compressed: 1 * 1024 * 1024 * 1024,
            cached: 5 * 1024 * 1024 * 1024,
            swapUsed: 0,
            pressure: .normal
        )

        let titleWithSample = MenuBarController.formatTitle(mode: .memory, memory: sample)
        XCTAssertEqual(titleWithSample, "RAM 50%")

        let titleNil = MenuBarController.formatTitle(mode: .memory, memory: nil)
        XCTAssertEqual(titleNil, "RAM --%")
    }

    func testFormatTitleBothMode() {
        let cpu = CPUSample(totalUsage: 35.0, perCore: [35.0], user: 20.0, system: 15.0, idle: 65.0)
        let mem = MemorySample(
            total: 1000,
            used: 250,
            free: 750,
            wired: 100,
            compressed: 50,
            cached: 100,
            swapUsed: 0,
            pressure: .normal
        )

        let title = MenuBarController.formatTitle(mode: .both, cpu: cpu, memory: mem)
        XCTAssertEqual(title, "CPU 35%  RAM 25%")

        let titlePartial = MenuBarController.formatTitle(mode: .both, cpu: nil, memory: mem)
        XCTAssertEqual(titlePartial, "CPU --%  RAM 25%")
    }

    func testFormatTitleNetworkMode() {
        let iface = InterfaceThroughput(
            interfaceName: "en0",
            bytesInPerSec: 1024 * 1024, // 1 MiB/s
            bytesOutPerSec: 512 * 1024, // 512 KiB/s
            totalBytesIn: 100_000_000,
            totalBytesOut: 50_000_000
        )
        let sample = NetworkSample(interfaces: [iface])

        // Bytes/s IEC
        let titleIEC = MenuBarController.formatTitle(
            mode: .network,
            network: sample,
            networkUnit: .bytesPerSecond,
            byteUnitStandard: .iec
        )
        XCTAssertTrue(titleIEC.contains("↓") && titleIEC.contains("↑"))
        XCTAssertTrue(titleIEC.contains("1 MiB/s") || titleIEC.contains("1 MB/s") || titleIEC.contains("1.0"))

        // Bits/s
        let titleBits = MenuBarController.formatTitle(
            mode: .network,
            network: sample,
            networkUnit: .bitsPerSecond,
            byteUnitStandard: .iec
        )
        XCTAssertTrue(titleBits.contains("bps") || titleBits.contains("b/s") || titleBits.contains("8"))

        // Nil
        let titleNil = MenuBarController.formatTitle(mode: .network, network: nil)
        XCTAssertEqual(titleNil, "Net --")
    }

    func testFormatTitleBatteryMode() {
        // Discharging
        let pwrDischarging = PowerSample(
            hasBattery: true,
            charge: 85.0,
            state: .discharging
        )
        let titleDischarging = MenuBarController.formatTitle(mode: .battery, power: pwrDischarging)
        XCTAssertEqual(titleDischarging, "85%")

        // Charging
        let pwrCharging = PowerSample(
            hasBattery: true,
            charge: 92.0,
            state: .charging
        )
        let titleCharging = MenuBarController.formatTitle(mode: .battery, power: pwrCharging)
        XCTAssertEqual(titleCharging, "92% ⚡")

        // No Battery (Desktop)
        let pwrDesktop = PowerSample(hasBattery: false)
        let titleDesktop = MenuBarController.formatTitle(mode: .battery, power: pwrDesktop)
        XCTAssertEqual(titleDesktop, "AC Power")

        // Nil
        let titleNil = MenuBarController.formatTitle(mode: .battery, power: nil)
        XCTAssertEqual(titleNil, "Bat --%")
    }

    func testFormatTitleThermalMode() {
        let thermal = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 45.4),
                SensorReading(name: "GPU Cluster", celsius: 42.0)
            ],
            pressure: .nominal
        )

        let titleC = MenuBarController.formatTitle(
            mode: .thermal,
            thermal: thermal,
            temperatureUnit: .celsius
        )
        XCTAssertEqual(titleC, "45 °C")

        let titleF = MenuBarController.formatTitle(
            mode: .thermal,
            thermal: thermal,
            temperatureUnit: .fahrenheit
        )
        XCTAssertEqual(titleF, "114 °F")

        let titleNilC = MenuBarController.formatTitle(mode: .thermal, thermal: nil, temperatureUnit: .celsius)
        XCTAssertEqual(titleNilC, "--°C")

        let titleNilF = MenuBarController.formatTitle(mode: .thermal, thermal: nil, temperatureUnit: .fahrenheit)
        XCTAssertEqual(titleNilF, "--°F")
    }

    func testFormatTitleGPUMode() {
        let gpu = GPUSample(utilization: 64.2, memoryUsed: 1024 * 1024 * 1024, tempCelsius: 50.0, powerWatts: 5.5)
        let titleWithSample = MenuBarController.formatTitle(mode: .gpu, gpu: gpu)
        XCTAssertEqual(titleWithSample, "GPU 64%")

        let titleNil = MenuBarController.formatTitle(mode: .gpu, gpu: nil)
        XCTAssertEqual(titleNil, "GPU --%")
    }

    // MARK: - ToolTip Tests

    func testFormatToolTip() {
        let cpu = CPUSample(totalUsage: 12.5, perCore: [12.5], user: 8.0, system: 4.5, idle: 87.5)
        let mem = MemorySample(total: 1000, used: 400, free: 600, wired: 100, compressed: 50, cached: 250, swapUsed: 0, pressure: .normal)
        let gpu = GPUSample(utilization: 22.0)
        let net = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1000, bytesOutPerSec: 500, totalBytesIn: 1000, totalBytesOut: 500)])
        let thermal = ThermalSample(sensors: [SensorReading(name: "CPU Package", celsius: 48.0)], pressure: .nominal)
        let power = PowerSample(hasBattery: true, charge: 95.0, state: .charging)

        let tooltip = MenuBarController.formatToolTip(
            cpu: cpu,
            memory: mem,
            network: net,
            power: power,
            thermal: thermal,
            gpu: gpu,
            temperatureUnit: .celsius,
            networkUnit: .bytesPerSecond,
            byteUnitStandard: .iec
        )

        XCTAssertTrue(tooltip.contains("iStats"))
        XCTAssertTrue(tooltip.contains("CPU: 12.5%"))
        XCTAssertTrue(tooltip.contains("RAM: 40.0% (Normal)"))
        XCTAssertTrue(tooltip.contains("GPU: 22.0%"))
        XCTAssertTrue(tooltip.contains("Net:"))
        XCTAssertTrue(tooltip.contains("Temp: 48.0 °C"))
        XCTAssertTrue(tooltip.contains("Bat: 95% (Charging)"))
    }

    // MARK: - ADR 0007 Modular Rendering & Controller Lifecycle Tests

    func testMenuBarIconRendererDrawings() {
        // Circular Gauge (18x18 pt)
        let gaugeImg = MenuBarIconRenderer.drawCircularGauge(percentage: 50.0)
        XCTAssertEqual(gaugeImg.size.width, 18)
        XCTAssertEqual(gaugeImg.size.height, 18)
        XCTAssertTrue(gaugeImg.isTemplate)

        // Bar Graph (13x22 pt)
        let barImg = MenuBarIconRenderer.drawBarGraph(percentage: 75.0)
        XCTAssertEqual(barImg.size.width, 13)
        XCTAssertEqual(barImg.size.height, 22)
        XCTAssertTrue(barImg.isTemplate)

        // Sparkline (36x16 pt)
        let sparklineImg = MenuBarIconRenderer.drawSparkline(values: [10.0, 30.0, 60.0, 90.0], maxValue: 100.0)
        XCTAssertEqual(sparklineImg.size.width, 36)
        XCTAssertEqual(sparklineImg.size.height, 16)
        XCTAssertTrue(sparklineImg.isTemplate)
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

        let fanTachoConfig = MenuBarItemConfig(category: .fan, style: .tachometer)
        let resFanTacho = MenuBarIconRenderer.render(config: fanTachoConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resFanTacho.image)

        let fanBladesConfig = MenuBarItemConfig(category: .fan, style: .blades)
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

    func testCategoryDetailPopoverViewInstantiation() {
        for category in MetricCategory.allCases {
            let view = CategoryDetailPopoverView(
                category: category,
                coordinator: .shared,
                preferences: .shared
            )
        let hosting = NSHostingView(rootView: view)
            XCTAssertNotNil(hosting)
        }
    }

    // MARK: - Bespoke Expressive Drawing Tests

    // MARK: - Bespoke Expressive Drawing Tests

    func testBespokeCategorySymbols() {
        // CPU
        let cpuIdle = MenuBarIconRenderer.drawCPUSymbol(usage: nil)
        let cpuLoad = MenuBarIconRenderer.drawCPUSymbol(usage: 85.0)
        XCTAssertEqual(cpuIdle.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(cpuLoad.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(cpuIdle)
        XCTAssertNotNil(cpuLoad)

        // Memory
        let memNormal = MenuBarIconRenderer.drawMemorySymbol(ratio: 40.0, pressure: .normal)
        let memCritical = MenuBarIconRenderer.drawMemorySymbol(ratio: 92.0, pressure: .critical)
        XCTAssertEqual(memNormal.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(memCritical.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(memNormal)
        XCTAssertNotNil(memCritical)

        // GPU
        let gpuIdle = MenuBarIconRenderer.drawGPUSymbol(utilization: 0.0)
        let gpuLoad = MenuBarIconRenderer.drawGPUSymbol(utilization: 95.0)
        XCTAssertEqual(gpuIdle.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(gpuLoad.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(gpuIdle)
        XCTAssertNotNil(gpuLoad)

        // Thermal
        let thermalCool = MenuBarIconRenderer.drawThermalSymbol(celsius: 42.0)
        let thermalHot = MenuBarIconRenderer.drawThermalSymbol(celsius: 88.0)
        XCTAssertEqual(thermalCool.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(thermalHot.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(thermalCool)
        XCTAssertNotNil(thermalHot)

        // Fan
        let fanIdle = MenuBarIconRenderer.drawFanSymbol(rpm: 0, percentage: 0.0)
        let fanActive = MenuBarIconRenderer.drawFanSymbol(rpm: 3500, percentage: 60.0)
        XCTAssertEqual(fanIdle.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(fanActive.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(fanIdle)
        XCTAssertNotNil(fanActive)

        // Network
        let netIdle = MenuBarIconRenderer.drawNetworkSymbol(inBytes: 0, outBytes: 0)
        let netActive = MenuBarIconRenderer.drawNetworkSymbol(inBytes: 5_000_000, outBytes: 2_000_000)
        XCTAssertEqual(netIdle.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(netActive.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(netIdle)
        XCTAssertNotNil(netActive)

        // Disk
        let diskIdle = MenuBarIconRenderer.drawDiskSymbol(readBytes: 0, writeBytes: 0)
        let diskActive = MenuBarIconRenderer.drawDiskSymbol(readBytes: 50_000_000, writeBytes: 20_000_000)
        XCTAssertEqual(diskIdle.size, NSSize(width: 20, height: 18))
        XCTAssertEqual(diskActive.size, NSSize(width: 20, height: 18))
        XCTAssertNotNil(diskIdle)
        XCTAssertNotNil(diskActive)

        // Power
        let powerBat = MenuBarIconRenderer.drawPowerSymbol(charge: 75.0, state: .discharging, hasBattery: true)
        let powerChg = MenuBarIconRenderer.drawPowerSymbol(charge: 90.0, state: .charging, hasBattery: true)
        let powerAC = MenuBarIconRenderer.drawPowerSymbol(charge: nil, state: nil, hasBattery: false)
        XCTAssertEqual(powerBat.size, NSSize(width: 25, height: 16))
        XCTAssertEqual(powerChg.size, NSSize(width: 25, height: 16))
        XCTAssertEqual(powerAC.size, NSSize(width: 25, height: 16))
        XCTAssertNotNil(powerBat)
        XCTAssertNotNil(powerChg)
        XCTAssertNotNil(powerAC)
    }

    func testBespokeCategoryGaugesBarsAndSparklines() {
        // CPU
        XCTAssertNotNil(MenuBarIconRenderer.drawCPUGauge(percentage: 50.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawCPUBar(percentage: 50.0, user: 30.0, system: 20.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawCPUSparkline(history: [10, 20, 50, 80]))

        // Memory
        XCTAssertNotNil(MenuBarIconRenderer.drawMemoryGauge(ratio: 45.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawMemoryBar(ratio: 45.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawMemorySparkline(history: [40, 42, 45, 48]))

        // GPU
        XCTAssertNotNil(MenuBarIconRenderer.drawGPUGauge(percentage: 30.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawGPUBar(percentage: 30.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawGPUSparkline(history: [0, 10, 25, 40]))

        // Thermal
        XCTAssertNotNil(MenuBarIconRenderer.drawThermalGauge(percentage: 60.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawThermalBar(percentage: 60.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawThermalSparkline(history: [40, 45, 50, 55]))

        // Fan
        XCTAssertNotNil(MenuBarIconRenderer.drawFanGauge(percentage: 50.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawFanBar(percentage: 50.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawFanTachometer(percentage: 50.0, rpm: 2500))
        XCTAssertNotNil(MenuBarIconRenderer.drawFanBlades(percentage: 50.0, rpm: 2500))
        XCTAssertNotNil(MenuBarIconRenderer.drawFanSparkline(history: [1200, 1500, 1800, 2000]))

        // Multi-fan bar and stacked throughput
        let dualFanSample = FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 2300, minRPM: 2000, maxRPM: 6000),
            FanReading(name: "Right Fan", rpm: 2500, minRPM: 2000, maxRPM: 6000)
        ])
        let dualBarImg = MenuBarIconRenderer.drawFanBar(fan: dualFanSample)
        XCTAssertEqual(dualBarImg.size.width, 36)
        XCTAssertEqual(dualBarImg.size.height, 22)

        let dualThroughputImg = MenuBarIconRenderer.drawFanStackedThroughput(fan: dualFanSample)
        XCTAssertEqual(dualThroughputImg.size.height, 22)
        XCTAssertEqual(dualThroughputImg.size.width, 36.0)

        // Network
        XCTAssertNotNil(MenuBarIconRenderer.drawNetworkGauge(percentage: 20.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawNetworkBar(inPct: 20.0, outPct: 10.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawNetworkSparkline(history: [1024, 2048, 5120, 10240]))

        // Disk
        XCTAssertNotNil(MenuBarIconRenderer.drawDiskGauge(percentage: 40.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawDiskBar(readPct: 30.0, writePct: 15.0))
        XCTAssertNotNil(MenuBarIconRenderer.drawDiskSparkline(history: [1000, 2000, 4000, 8000]))

        // Power
        XCTAssertNotNil(MenuBarIconRenderer.drawPowerGauge(percentage: 85.0, isCharging: false))
        XCTAssertNotNil(MenuBarIconRenderer.drawPowerBar(percentage: 85.0, isCharging: false))
        XCTAssertNotNil(MenuBarIconRenderer.drawPowerSparkline(history: [90, 88, 87, 85]))
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
        let img1Digit = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: "2%", fixedWidth: 32.0)
        let img2Digits = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: "82%", fixedWidth: 32.0)
        let img3Digits = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: "100%", fixedWidth: 32.0)
        let imgPlaceholder = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: "--%", fixedWidth: 32.0)

        XCTAssertEqual(img1Digit.size.width, 32.0, "1-digit percentage must have constant 32pt width")
        XCTAssertEqual(img2Digits.size.width, 32.0, "2-digit percentage must have constant 32pt width")
        XCTAssertEqual(img3Digits.size.width, 32.0, "3-digit percentage must have constant 32pt width")
        XCTAssertEqual(imgPlaceholder.size.width, 32.0, "Placeholder must have constant 32pt width")

        XCTAssertEqual(img1Digit.size.height, 22.0)
        XCTAssertEqual(img2Digits.size.height, 22.0)
        XCTAssertEqual(img3Digits.size.height, 22.0)
        XCTAssertEqual(imgPlaceholder.size.height, 22.0)
    }

    func testDrawStackedText() {
        let img = MenuBarIconRenderer.drawStackedText(line1: "↑ 13 KB/s", line2: "↓ 1.6 MB/s")
        XCTAssertEqual(img.size.height, 22)
        XCTAssertEqual(img.size.width, 60.0)
        XCTAssertTrue(img.isTemplate)
    }

    func testDrawStackedTwoLineText() {
        let img = MenuBarIconRenderer.drawStackedTwoLineText(
            prefix1: "↑",
            value1: "13 KB/s",
            prefix2: "↓",
            value2: "1.6 MB/s",
            minWidth: 60.0
        )
        XCTAssertEqual(img.size.height, 22)
        XCTAssertEqual(img.size.width, 60.0)
        XCTAssertTrue(img.isTemplate)

        // Disk throughput
        let diskImg = MenuBarIconRenderer.drawDiskStackedThroughput(
            readBytes: 1024 * 1024 * 1.2,
            writeBytes: 1024 * 450,
            standard: .iec
        )
        XCTAssertEqual(diskImg.size.height, 22)
        XCTAssertEqual(diskImg.size.width, 60.0)
        XCTAssertTrue(diskImg.isTemplate)
    }

    func testStackedThroughputWidthInvariance() {
        // Test varying rates: zero, small, medium, large
        let netZero = MenuBarIconRenderer.drawNetworkStackedThroughput(inBytes: 0, outBytes: 0, unit: .bytesPerSecond, standard: .iec)
        let netSmall = MenuBarIconRenderer.drawNetworkStackedThroughput(inBytes: 1024 * 13, outBytes: 1024 * 1024 * 1.6, unit: .bytesPerSecond, standard: .iec)
        let netMedium = MenuBarIconRenderer.drawNetworkStackedThroughput(inBytes: 1024 * 1024 * 50, outBytes: 1024 * 1024 * 125, unit: .bytesPerSecond, standard: .iec)

        XCTAssertEqual(netZero.size.width, 60.0, "Zero network rate must maintain 60pt invariant width")
        XCTAssertEqual(netSmall.size.width, 60.0, "Small network rate must maintain 60pt invariant width")
        XCTAssertEqual(netMedium.size.width, 60.0, "Medium network rate must maintain 60pt invariant width")
    }

    func testDrawCPUPerCoreBarCluster() {
        let cores8 = [10.0, 25.0, 50.0, 75.0, 20.0, 40.0, 60.0, 80.0]
        let img8 = MenuBarIconRenderer.drawCPUBar(perCore: cores8, user: 45.0, system: 15.0)
        XCTAssertEqual(img8.size.height, 22)
        XCTAssertEqual(img8.size.width, 41)
        XCTAssertNotNil(img8)

        let cores12 = Array(repeating: 30.0, count: 12)
        let img12 = MenuBarIconRenderer.drawCPUBar(perCore: cores12, user: 30.0, system: 0.0)
        XCTAssertEqual(img12.size.width, 41)
        XCTAssertEqual(img12.size.height, 22)

        let coresNil = MenuBarIconRenderer.drawCPUBar(perCore: nil, user: 40.0, system: 10.0)
        XCTAssertEqual(coresNil.size.width, 36)
        XCTAssertEqual(coresNil.size.height, 22)
    }

    func testDrawCapsuleBars() {
        // Dual Capsule Bar (Generic / Template)
        let genericBar = MenuBarIconRenderer.drawDualCapsuleBar(label: "SSD", leftPercentage: 90.0, rightPercentage: 30.0)
        XCTAssertEqual(genericBar.size.width, 36)
        XCTAssertEqual(genericBar.size.height, 22)
        XCTAssertTrue(genericBar.isTemplate)

        // Dual Capsule Bar (NET - Teal/Blue Colored)
        let netBar = MenuBarIconRenderer.drawNetworkBar(inPct: 50.0, outPct: 20.0)
        XCTAssertEqual(netBar.size.width, 36)
        XCTAssertEqual(netBar.size.height, 22)
        XCTAssertFalse(netBar.isTemplate)

        // Dual Capsule Bar (SSD - Indigo/Purple Colored)
        let ssdBar = MenuBarIconRenderer.drawDiskBar(readPct: 75.0, writePct: 25.0)
        XCTAssertEqual(ssdBar.size.width, 36)
        XCTAssertEqual(ssdBar.size.height, 22)
        XCTAssertFalse(ssdBar.isTemplate)

        // Single Capsule Bar (RAM - Green Colored)
        let ramBar = MenuBarIconRenderer.drawMemoryBar(ratio: 65.0)
        XCTAssertEqual(ramBar.size.width, 25)
        XCTAssertEqual(ramBar.size.height, 22)
        XCTAssertFalse(ramBar.isTemplate)

        // Single Capsule Bar (GPU - Purple Colored)
        let gpuBar = MenuBarIconRenderer.drawGPUBar(percentage: 45.0)
        XCTAssertEqual(gpuBar.size.width, 25)
        XCTAssertEqual(gpuBar.size.height, 22)
        XCTAssertFalse(gpuBar.isTemplate)

        // Single Capsule Bar (TMP - Thermal Colored)
        let tmpBar = MenuBarIconRenderer.drawThermalBar(percentage: 55.0)
        XCTAssertEqual(tmpBar.size.width, 25)
        XCTAssertEqual(tmpBar.size.height, 22)
        XCTAssertFalse(tmpBar.isTemplate)

        // Single Capsule Bar (FAN - Cyan Colored)
        let fanBar = MenuBarIconRenderer.drawFanBar(percentage: 40.0)
        XCTAssertEqual(fanBar.size.width, 25)
        XCTAssertEqual(fanBar.size.height, 22)
        XCTAssertFalse(fanBar.isTemplate)

        // Single Capsule Bar (BAT - Battery Colored)
        let batBar = MenuBarIconRenderer.drawPowerBar(percentage: 85.0)
        XCTAssertEqual(batBar.size.width, 25)
        XCTAssertEqual(batBar.size.height, 22)
        XCTAssertFalse(batBar.isTemplate)
    }

    func testDrawSingleLineText() {
        let img = MenuBarIconRenderer.drawSingleLineText(text: "CPU 45%", fixedWidth: 60.0)
        XCTAssertEqual(img.size.height, 22)
        XCTAssertGreaterThanOrEqual(img.size.width, 60.0)
        XCTAssertTrue(img.isTemplate)
    }

    func testDrawCPUDonutPie() {
        let donut = MenuBarIconRenderer.drawCPUDonutPie(user: 45.0, system: 15.0)
        XCTAssertEqual(donut.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(donut)
    }

    func testDrawNetworkSplitDuplexGraph() {
        let inHistory = [1000.0, 5000.0, 20000.0, 100000.0, 50000.0]
        let outHistory = [500.0, 2000.0, 10000.0, 40000.0, 20000.0]
        let splitGraph = MenuBarIconRenderer.drawNetworkSplitDuplexGraph(inHistory: inHistory, outHistory: outHistory)
        XCTAssertEqual(splitGraph.size, NSSize(width: 36, height: 16))
        XCTAssertNotNil(splitGraph)
    }

    func testDrawNetworkStackedThroughput() {
        let netImg = MenuBarIconRenderer.drawNetworkStackedThroughput(
            inBytes: 1024 * 1024 * 5,
            outBytes: 1024 * 500,
            unit: .bytesPerSecond,
            standard: .iec
        )
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
}
