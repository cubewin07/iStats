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
        // Circular Gauge
        let gaugeImg = MenuBarIconRenderer.drawCircularGauge(percentage: 50.0)
        XCTAssertEqual(gaugeImg.size.width, 18)
        XCTAssertEqual(gaugeImg.size.height, 18)
        XCTAssertTrue(gaugeImg.isTemplate)

        // Bar Graph
        let barImg = MenuBarIconRenderer.drawBarGraph(percentage: 75.0)
        XCTAssertEqual(barImg.size.width, 10)
        XCTAssertEqual(barImg.size.height, 18)
        XCTAssertTrue(barImg.isTemplate)

        // Sparkline
        let sparklineImg = MenuBarIconRenderer.drawSparkline(values: [10.0, 30.0, 60.0, 90.0], maxValue: 100.0)
        XCTAssertEqual(sparklineImg.size.width, 28)
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
        XCTAssertFalse(resThroughput.title.isEmpty)
        XCTAssertTrue(resThroughput.toolTip.contains("Network"))

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
        let item3 = MenuBarItemConfig(category: .cpu, style: .text)
        prefs.addMenuBarItem(item3)
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
}
