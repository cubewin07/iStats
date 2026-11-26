import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class MenuBarDirtyCheckingTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, MenuBarController, String) {
        let suiteName = "test.istats.controller.dirtycheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        let controller = MenuBarController(preferences: prefs, coordinator: coord)
        return (defaults, prefs, coord, controller, suiteName)
    }

    private func cleanup(defaults: UserDefaults, controller: MenuBarController, suiteName: String) {
        for (_, item) in controller.statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        controller.hidePopover()
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 1. Dirty Checking & Bypass Tests

    func testIdenticalTelemetrySkipsButtonMutations() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let cpuItem = MenuBarItemConfig(category: .cpu, style: .text)
        prefs.menuBarItems = [cpuItem]
        controller.syncStatusItems()

        controller.resetPerformanceCounters()

        // 1st sample: should perform mutation
        let sample1 = CPUSample(totalUsage: 25.0, perCore: [25.0], user: 15.0, system: 10.0, idle: 75.0)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample1))
        controller.updateItems(for: .cpu)

        XCTAssertEqual(controller.buttonMutationCount, 1, "First sample should mutate button")
        XCTAssertEqual(controller.dirtyCheckBypassCount, 0, "No bypass on initial render")

        // 2nd sample: identical values -> should bypass mutation completely
        let sample2 = CPUSample(totalUsage: 25.0, perCore: [25.0], user: 15.0, system: 10.0, idle: 75.0)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample2))
        controller.updateItems(for: .cpu)

        XCTAssertEqual(controller.buttonMutationCount, 1, "Identical sample must NOT mutate button")
        XCTAssertEqual(controller.dirtyCheckBypassCount, 1, "Identical sample must increment bypass count")

        // 3rd sample: identical values again
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample2))
        controller.updateItems(for: .cpu)

        XCTAssertEqual(controller.buttonMutationCount, 1, "Consecutive identical sample must NOT mutate button")
        XCTAssertEqual(controller.dirtyCheckBypassCount, 2, "Second bypass recorded")
    }

    func testDifferentTelemetryTriggersMutation() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let cpuItem = MenuBarItemConfig(category: .cpu, style: .text)
        prefs.menuBarItems = [cpuItem]
        controller.syncStatusItems()

        controller.resetPerformanceCounters()

        // 1st sample: 25%
        let sample1 = CPUSample(totalUsage: 25.0, perCore: [25.0], user: 15.0, system: 10.0, idle: 75.0)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample1))
        controller.updateItems(for: .cpu)

        XCTAssertEqual(controller.buttonMutationCount, 1)

        // 2nd sample: 55% (different value)
        let sample2 = CPUSample(totalUsage: 55.0, perCore: [55.0], user: 35.0, system: 20.0, idle: 45.0)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample2))
        controller.updateItems(for: .cpu)

        XCTAssertEqual(controller.buttonMutationCount, 2, "Telemetry change must trigger mutation")
        XCTAssertEqual(controller.dirtyCheckBypassCount, 0)
    }

    func testBatteryGaugeBypassesMutationWhenUnchanged() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let batteryItem = MenuBarItemConfig(category: .power, style: .gauge)
        prefs.menuBarItems = [batteryItem]
        controller.syncStatusItems()

        controller.resetPerformanceCounters()

        let sample1 = PowerSample(hasBattery: true, charge: 85.0, state: .discharging)
        coord.handleReading(MetricReading.wrap(category: .power, value: sample1))
        controller.updateItems(for: .power)

        XCTAssertEqual(controller.buttonMutationCount, 1)
        XCTAssertEqual(controller.dirtyCheckBypassCount, 0)

        let sample2 = PowerSample(hasBattery: true, charge: 85.0, state: .discharging)
        coord.handleReading(MetricReading.wrap(category: .power, value: sample2))
        controller.updateItems(for: .power)

        XCTAssertEqual(controller.buttonMutationCount, 1, "Unchanged battery gauge must NOT mutate button")
        XCTAssertEqual(controller.dirtyCheckBypassCount, 1, "Unchanged battery gauge must increment bypass count")
    }

    func testGPUGaugeBypassesMutationWhenUnchanged() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let gpuItem = MenuBarItemConfig(category: .gpu, style: .gauge)
        prefs.menuBarItems = [gpuItem]
        controller.syncStatusItems()

        controller.resetPerformanceCounters()

        let sample1 = GPUSample(utilization: 24.0, tempCelsius: 52.0)
        coord.handleReading(MetricReading.wrap(category: .gpu, value: sample1))
        controller.updateItems(for: .gpu)

        XCTAssertEqual(controller.buttonMutationCount, 1)

        let sample2 = GPUSample(utilization: 24.0, tempCelsius: 52.0)
        coord.handleReading(MetricReading.wrap(category: .gpu, value: sample2))
        controller.updateItems(for: .gpu)

        XCTAssertEqual(controller.buttonMutationCount, 1, "Unchanged GPU gauge must NOT mutate button")
        XCTAssertEqual(controller.dirtyCheckBypassCount, 1, "Unchanged GPU gauge must increment bypass count")
    }

    func testThermalGaugeBypassesMutationWhenUnchanged() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let thermalItem = MenuBarItemConfig(category: .thermal, style: .gauge)
        prefs.menuBarItems = [thermalItem]
        controller.syncStatusItems()

        controller.resetPerformanceCounters()

        let sample1 = ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 46.0)])
        coord.handleReading(MetricReading.wrap(category: .thermal, value: sample1))
        controller.updateItems(for: .thermal)

        XCTAssertEqual(controller.buttonMutationCount, 1)

        let sample2 = ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 46.0)])
        coord.handleReading(MetricReading.wrap(category: .thermal, value: sample2))
        controller.updateItems(for: .thermal)

        XCTAssertEqual(controller.buttonMutationCount, 1, "Unchanged thermal gauge must NOT mutate button")
        XCTAssertEqual(controller.dirtyCheckBypassCount, 1, "Unchanged thermal gauge must increment bypass count")
    }

    // MARK: - 2. Image Cache Pointer Identity Tests

    func testDiscretePressureBadgeReusesSameImagePointer() {
        let imgNormal1 = MenuBarIconRenderer.drawMemoryPressureBadge(pressure: .normal)
        let imgNormal2 = MenuBarIconRenderer.drawMemoryPressureBadge(pressure: .normal)
        let imgWarn = MenuBarIconRenderer.drawMemoryPressureBadge(pressure: .warning)

        XCTAssertTrue(imgNormal1 === imgNormal2, "Consecutive normal pressure badge calls must return the identical cached NSImage pointer")
        XCTAssertFalse(imgNormal1 === imgWarn, "Different pressure states must return different image instances")
    }

    func testStackedTextReusesSameImagePointer() {
        let img1 = MenuBarIconRenderer.drawCategoryStackedText(title: "CPU", value: "42%")
        let img2 = MenuBarIconRenderer.drawCategoryStackedText(title: "CPU", value: "42%")
        let img3 = MenuBarIconRenderer.drawCategoryStackedText(title: "CPU", value: "43%")

        XCTAssertTrue(img1 === img2, "Identical stacked text calls must return identical cached NSImage pointer")
        XCTAssertFalse(img1 === img3, "Different values must produce different image instances")
    }

    func testNetworkActivityArrowsReusesSameImagePointer() {
        // Both below 1024 bytes -> inactive state
        func arrows(_ inB: Double, _ outB: Double) -> NSImage {
            let net = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: inB, bytesOutPerSec: outB, totalBytesIn: 0, totalBytesOut: 0)])
            let model = WidgetModel.make(config: MenuBarItemConfig(category: .network, style: .symbol), snapshot: WidgetSnapshot(network: net), options: WidgetOptions())
            return MenuBarIconRenderer.image(for: model)
        }
        let imgIdle1 = arrows(0, 0)
        let imgIdle2 = arrows(256, 512)
        // Active download
        let imgActiveDown = arrows(100_000, 0)

        XCTAssertTrue(imgIdle1 === imgIdle2, "Inactive network arrows must reuse identical cached NSImage pointer")
        XCTAssertFalse(imgIdle1 === imgActiveDown, "State change must return different image instance")
    }

    func testDiskActivityLedsReusesSameImagePointer() {
        // Both below 10240 bytes -> inactive state
        func leds(_ r: Double, _ w: Double) -> NSImage {
            let disk = DiskSample(io: DiskIO(bytesReadPerSec: r, bytesWrittenPerSec: w, readOpsPerSec: 0, writeOpsPerSec: 0))
            let model = WidgetModel.make(config: MenuBarItemConfig(category: .disk, style: .symbol), snapshot: WidgetSnapshot(disk: disk), options: WidgetOptions())
            return MenuBarIconRenderer.image(for: model)
        }
        let imgIdle1 = leds(0, 0)
        let imgIdle2 = leds(1024, 2048)
        // Active write
        let imgActiveWrite = leds(0, 50_000)

        XCTAssertTrue(imgIdle1 === imgIdle2, "Inactive disk LEDs must reuse identical cached NSImage pointer")
        XCTAssertFalse(imgIdle1 === imgActiveWrite, "State change must return different image instance")
    }

    // MARK: - 3. Lifecycle & Cleanup Tests

    func testStatusItemRemovalCleansUpCachedState() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let cpuItem = MenuBarItemConfig(category: .cpu, style: .text)
        let ramItem = MenuBarItemConfig(category: .memory, style: .text)
        prefs.menuBarItems = [cpuItem, ramItem]
        controller.syncStatusItems()

        let cpuSample = CPUSample(totalUsage: 30.0, perCore: [30.0], user: 20.0, system: 10.0, idle: 70.0)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: cpuSample))
        controller.updateItems(for: .cpu)

        XCTAssertNotNil(controller.previousRenderStates[cpuItem.id])

        // Remove CPU item
        prefs.menuBarItems = [ramItem]
        controller.syncStatusItems()

        XCTAssertNil(controller.previousRenderStates[cpuItem.id], "Removing status item must purge its cached render state")
    }

    // MARK: - 4. Two-Phase Pre-Render Visual Key Tests

    func testComputeVisualKeyIsStableDistinctAndTracksVisibleChangesAcrossCategories() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        func key(_ category: MetricCategory, _ style: MetricDisplayStyle) -> String {
            MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: category, style: style), coordinator: coord, preferences: prefs)
        }

        // CPU: percent changes the text key; a repeat of the same sample does not.
        coord.handleReading(MetricReading.wrap(category: .cpu, value: CPUSample(totalUsage: 25.0, perCore: [25.0], user: 15.0, system: 10.0, idle: 75.0)))
        let cpuText1 = key(.cpu, .text)
        let cpuGauge1 = key(.cpu, .gauge)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: CPUSample(totalUsage: 25.0, perCore: [25.0], user: 15.0, system: 10.0, idle: 75.0)))
        XCTAssertEqual(cpuText1, key(.cpu, .text))
        XCTAssertEqual(cpuGauge1, key(.cpu, .gauge))
        coord.handleReading(MetricReading.wrap(category: .cpu, value: CPUSample(totalUsage: 80.0, perCore: [80.0], user: 50.0, system: 30.0, idle: 20.0)))
        XCTAssertNotEqual(cpuText1, key(.cpu, .text))
        XCTAssertNotEqual(cpuGauge1, key(.cpu, .gauge))

        // Sparkline keys are no longer nil: they are stamp based and stable between samples.
        let spark = key(.cpu, .sparkline)
        XCTAssertFalse(spark.isEmpty)
        XCTAssertEqual(spark, key(.cpu, .sparkline), "Sparkline key must be stable between samples")

        // Memory: the ratio is part of the symbol key (stale-image bug fix).
        coord.handleReading(MetricReading.wrap(category: .memory, value: MemorySample(total: 1000, used: 550, free: 450, wired: 100, compressed: 50, cached: 250, swapUsed: 0, pressure: .normal)))
        let memSym1 = key(.memory, .symbol)
        let memGauge1 = key(.memory, .gauge)
        coord.handleReading(MetricReading.wrap(category: .memory, value: MemorySample(total: 1000, used: 300, free: 700, wired: 100, compressed: 50, cached: 250, swapUsed: 0, pressure: .normal)))
        XCTAssertNotEqual(memSym1, key(.memory, .symbol))
        XCTAssertNotEqual(memGauge1, key(.memory, .gauge))

        // GPU, power, fan
        coord.handleReading(MetricReading.wrap(category: .gpu, value: GPUSample(utilization: 35.0, tempCelsius: 48.0)))
        let gpu1 = key(.gpu, .gauge)
        coord.handleReading(MetricReading.wrap(category: .gpu, value: GPUSample(utilization: 70.0, tempCelsius: 48.0)))
        XCTAssertNotEqual(gpu1, key(.gpu, .gauge))

        coord.handleReading(MetricReading.wrap(category: .power, value: PowerSample(hasBattery: true, charge: 92.0, state: .charging)))
        let pwr1 = key(.power, .symbol)
        coord.handleReading(MetricReading.wrap(category: .power, value: PowerSample(hasBattery: true, charge: 40.0, state: .discharging)))
        XCTAssertNotEqual(pwr1, key(.power, .symbol))

        coord.handleReading(MetricReading.wrap(category: .fan, value: FanSample(fans: [FanReading(name: "Fan 1", rpm: 2100, minRPM: 1200, maxRPM: 5000)])))
        XCTAssertFalse(key(.fan, .gauge).isEmpty)

        // Network arrows and disk LEDs track only the active flags.
        func net(_ inB: Double, _ outB: Double) {
            coord.handleReading(MetricReading.wrap(category: .network, value: NetworkSample(interfaces: [
                InterfaceThroughput(interfaceName: "en0", bytesInPerSec: inB, bytesOutPerSec: outB, totalBytesIn: 1000, totalBytesOut: 500)
            ])))
        }
        net(50_000, 200)
        let arrows1 = key(.network, .symbol)
        net(90_000, 300)
        XCTAssertEqual(arrows1, key(.network, .symbol), "Arrow key must ignore rate changes within the same activity state")
        net(50_000, 90_000)
        XCTAssertNotEqual(arrows1, key(.network, .symbol))

        func disk(_ r: Double, _ w: Double) {
            coord.handleReading(MetricReading.wrap(category: .disk, value: DiskSample(
                volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000, used: 600_000, free: 400_000)],
                io: DiskIO(bytesReadPerSec: r, bytesWrittenPerSec: w, readOpsPerSec: 1, writeOpsPerSec: 1)
            )))
        }
        disk(50_000, 0)
        let leds1 = key(.disk, .symbol)
        let diskGauge1 = key(.disk, .gauge)
        disk(80_000, 0)
        XCTAssertEqual(leds1, key(.disk, .symbol))
        XCTAssertEqual(diskGauge1, key(.disk, .gauge), "Disk gauge key must ignore I/O when capacity is unchanged")
        disk(50_000, 50_000)
        XCTAssertNotEqual(leds1, key(.disk, .symbol))
    }

    func testVisualKeyChangesOnSourceThroughputLayoutAndShowLabel() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        // showLabel change
        let gaugeWithoutLabel = MenuBarItemConfig(category: .cpu, style: .gauge, showLabel: false)
        let gaugeWithLabel = MenuBarItemConfig(category: .cpu, style: .gauge, showLabel: true)
        let key1 = MenuBarIconRenderer.computeVisualKey(config: gaugeWithoutLabel, coordinator: coord, preferences: prefs)
        let key2 = MenuBarIconRenderer.computeVisualKey(config: gaugeWithLabel, coordinator: coord, preferences: prefs)
        XCTAssertNotEqual(key1, key2)

        // throughputLayout change
        let netStacked = MenuBarItemConfig(category: .network, style: .throughput, throughputLayout: .stacked)
        let netSingle = MenuBarItemConfig(category: .network, style: .throughput, throughputLayout: .singleLine)
        let netKey1 = MenuBarIconRenderer.computeVisualKey(config: netStacked, coordinator: coord, preferences: prefs)
        let netKey2 = MenuBarIconRenderer.computeVisualKey(config: netSingle, coordinator: coord, preferences: prefs)
        XCTAssertNotEqual(netKey1, netKey2)

        // thermal source change
        let thermalSample = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Core", celsius: 45.0),
                SensorReading(name: "GPU MESA", celsius: 65.0)
            ],
            pressure: .nominal
        )
        coord.handleReading(MetricReading.wrap(category: .thermal, value: thermalSample))
        let thermCPU = MenuBarItemConfig(category: .thermal, style: .text, source: .cpu)
        let thermGPU = MenuBarItemConfig(category: .thermal, style: .text, source: .gpu)
        let thermKeyCPU = MenuBarIconRenderer.computeVisualKey(config: thermCPU, coordinator: coord, preferences: prefs)
        let thermKeyGPU = MenuBarIconRenderer.computeVisualKey(config: thermGPU, coordinator: coord, preferences: prefs)
        XCTAssertNotEqual(thermKeyCPU, thermKeyGPU)
    }

    // MARK: - 5. Regression Tests for Sub-Component & Tooltip Updates

    func testPowerTextUpdatesWhenTimeRemainingOrWattsChangeAtSameCharge() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let pwrItem = MenuBarItemConfig(category: .power, style: .text)
        prefs.menuBarItems = [pwrItem]
        controller.syncStatusItems()
        controller.resetPerformanceCounters()

        let sample1 = PowerSample(hasBattery: true, charge: 80.0, state: .discharging, timeRemaining: 2 * 3600 + 15 * 60, powerDrawWatts: 12.0)
        coord.handleReading(MetricReading.wrap(category: .power, value: sample1))
        controller.updateItems(for: .power)
        let img1 = controller.statusItems[pwrItem.id]?.button?.image

        // Time remaining ticks down from 2:15 to 2:10 while charge stays 80%
        let sample2 = PowerSample(hasBattery: true, charge: 80.0, state: .discharging, timeRemaining: 2 * 3600 + 10 * 60, powerDrawWatts: 12.0)
        coord.handleReading(MetricReading.wrap(category: .power, value: sample2))
        controller.updateItems(for: .power)
        let img2 = controller.statusItems[pwrItem.id]?.button?.image

        XCTAssertEqual(controller.buttonMutationCount, 2, "Power .text must redraw when time remaining changes even if charge % is unchanged")
        XCTAssertFalse(img1 === img2, "Power .text image must update when second line time changes")
    }

    func testCPUBarUpdatesWhenClusterLoadShiftsAtSameTotalUsage() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let cpuBarItem = MenuBarItemConfig(category: .cpu, style: .bar)
        prefs.menuBarItems = [cpuBarItem]
        controller.syncStatusItems()
        controller.resetPerformanceCounters()

        // Hybrid 2E + 2P: load concentrated on E-cluster (50% E, 0% P, 25% total)
        let sample1 = CPUSample(
            totalUsage: 25.0,
            perCore: [50.0, 50.0, 0.0, 0.0],
            user: 15.0,
            system: 10.0,
            idle: 75.0,
            efficiencyCoreCount: 2,
            performanceCoreCount: 2
        )
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample1))
        controller.updateItems(for: .cpu)

        // Total is still 25.0%, but load shifted from E-cluster to P-cluster (0% E, 50% P)
        let sample2 = CPUSample(
            totalUsage: 25.0,
            perCore: [0.0, 0.0, 50.0, 50.0],
            user: 15.0,
            system: 10.0,
            idle: 75.0,
            efficiencyCoreCount: 2,
            performanceCoreCount: 2
        )
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample2))
        controller.updateItems(for: .cpu)

        XCTAssertEqual(controller.buttonMutationCount, 2, "CPU .bar must redraw when E/P cluster utilization shifts even if total usage is identical")
    }

    func testMultiFanBarAndThroughputUpdateWhenSecondaryFanChanges() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let fanBarItem = MenuBarItemConfig(category: .fan, style: .bar)
        let fanTpItem = MenuBarItemConfig(category: .fan, style: .throughput)
        prefs.menuBarItems = [fanBarItem, fanTpItem]
        controller.syncStatusItems()
        controller.resetPerformanceCounters()

        let sample1 = FanSample(fans: [
            FanReading(name: "Left", rpm: 3500, minRPM: 1200, maxRPM: 5000),
            FanReading(name: "Right", rpm: 2000, minRPM: 1200, maxRPM: 5000)
        ])
        coord.handleReading(MetricReading.wrap(category: .fan, value: sample1))
        controller.updateItems(for: .fan)
        XCTAssertEqual(controller.buttonMutationCount, 2)

        // Primary fan (Left) stays at 3500 RPM, Secondary fan (Right) rises to 2800 RPM
        let sample2 = FanSample(fans: [
            FanReading(name: "Left", rpm: 3500, minRPM: 1200, maxRPM: 5000),
            FanReading(name: "Right", rpm: 2800, minRPM: 1200, maxRPM: 5000)
        ])
        coord.handleReading(MetricReading.wrap(category: .fan, value: sample2))
        controller.updateItems(for: .fan)

        XCTAssertEqual(controller.buttonMutationCount, 4, "Both Fan .bar and .throughput must update when secondary fan RPM changes")
    }

    func testDiskGaugeAndNetworkSymbolUpdateTooltipsWhileReusingCachedImagePointer() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let diskItem = MenuBarItemConfig(category: .disk, style: .gauge)
        let netItem = MenuBarItemConfig(category: .network, style: .symbol)
        prefs.menuBarItems = [diskItem, netItem]
        controller.syncStatusItems()

        let disk1 = DiskSample(
            volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000, used: 600_000, free: 400_000)],
            io: DiskIO(bytesReadPerSec: 1_024, bytesWrittenPerSec: 0, readOpsPerSec: 1, writeOpsPerSec: 0)
        )
        coord.handleReading(MetricReading.wrap(category: .disk, value: disk1))
        controller.updateItems(for: .disk)

        let diskBtn = controller.statusItems[diskItem.id]?.button
        let diskImg1 = diskBtn?.image
        let diskTip1 = diskBtn?.toolTip

        // Volume remains 60% full, but Disk I/O jumps to 50 MB/s
        let disk2 = DiskSample(
            volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000, used: 600_000, free: 400_000)],
            io: DiskIO(bytesReadPerSec: 50_000_000, bytesWrittenPerSec: 10_000_000, readOpsPerSec: 500, writeOpsPerSec: 100)
        )
        coord.handleReading(MetricReading.wrap(category: .disk, value: disk2))
        controller.updateItems(for: .disk)

        XCTAssertTrue(diskBtn?.image === diskImg1, "Disk gauge NSImage pointer must be reused from cache when capacity % is unchanged")
        XCTAssertNotEqual(diskBtn?.toolTip, diskTip1, "Disk gauge tooltip must update when live I/O rates change")

        let net1 = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 10_000, bytesOutPerSec: 0, totalBytesIn: 10_000, totalBytesOut: 0)])
        coord.handleReading(MetricReading.wrap(category: .network, value: net1))
        controller.updateItems(for: .network)

        let netBtn = controller.statusItems[netItem.id]?.button
        let netImg1 = netBtn?.image
        let netTip1 = netBtn?.toolTip

        // Both still > 1024 B/s (active), but rate jumped to 5 MB/s
        let net2 = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 5_000_000, bytesOutPerSec: 0, totalBytesIn: 5_010_000, totalBytesOut: 0)])
        coord.handleReading(MetricReading.wrap(category: .network, value: net2))
        controller.updateItems(for: .network)

        XCTAssertTrue(netBtn?.image === netImg1, "Network arrows NSImage pointer must be reused from cache when activity state is unchanged")
        XCTAssertNotEqual(netBtn?.toolTip, netTip1, "Network arrows tooltip must update when live throughput rate changes")
    }

    private func modelKey(_ category: MetricCategory, _ style: MetricDisplayStyle, _ snapshot: WidgetSnapshot, options: WidgetOptions = WidgetOptions()) -> String {
        WidgetModel.make(config: MenuBarItemConfig(category: category, style: style), snapshot: snapshot, options: options).visualKey
    }

    func testVisualKeyDistinguishesNilFromZeroForPowerAndGPU() {
        let pwrTpNil = modelKey(.power, .throughput, WidgetSnapshot(power: PowerSample(hasBattery: true, powerDrawWatts: nil, adapterWatts: nil)))
        let pwrTpZero = modelKey(.power, .throughput, WidgetSnapshot(power: PowerSample(hasBattery: true, powerDrawWatts: 0.0, adapterWatts: 0.0)))
        XCTAssertNotEqual(pwrTpNil, pwrTpZero, "Power .throughput key must distinguish nil from 0.0")

        let pwrSymNil = modelKey(.power, .symbol, WidgetSnapshot(power: PowerSample(hasBattery: true, charge: nil, state: .unknown)))
        let pwrSymZero = modelKey(.power, .symbol, WidgetSnapshot(power: PowerSample(hasBattery: true, charge: 0.0, state: .unknown)))
        XCTAssertNotEqual(pwrSymNil, pwrSymZero, "Power .symbol key must distinguish nil charge from 0% charge")

        let gpuNil = modelKey(.gpu, .text, WidgetSnapshot())
        let gpuZero = modelKey(.gpu, .text, WidgetSnapshot(gpu: GPUSample(utilization: 0.0)))
        XCTAssertNotEqual(gpuNil, gpuZero, "GPU .text key must distinguish a missing sample from 0%")
    }

    func testFanGaugeAndBarIgnoreSingleRPMJitterAtSamePercentage() {
        let fan1 = WidgetSnapshot(fan: FanSample(fans: [FanReading(name: "Fan 1", rpm: 2100, minRPM: 1200, maxRPM: 5000)]))
        let fan2 = WidgetSnapshot(fan: FanSample(fans: [FanReading(name: "Fan 1", rpm: 2101, minRPM: 1200, maxRPM: 5000)]))

        XCTAssertEqual(modelKey(.fan, .gauge, fan1), modelKey(.fan, .gauge, fan2),
                       "Fan .gauge key must not churn on 1 RPM jitter when rounded percentage is unchanged")
        XCTAssertEqual(modelKey(.fan, .bar, fan1), modelKey(.fan, .bar, fan2),
                       "Fan .bar key must not churn on 1 RPM jitter when rounded percentage is unchanged")
        XCTAssertNotEqual(modelKey(.fan, .throughput, fan1), modelKey(.fan, .throughput, fan2),
                          "Fan .throughput key must still update on exact RPM change")
    }

    func testDiskTextRespectsSIAndIECStandard() {
        let bytes: UInt64 = 500_000_000_000
        XCTAssertEqual(WidgetModel.formatCompactBytes(bytes, standard: .si), "500G")
        XCTAssertEqual(WidgetModel.formatCompactBytes(bytes, standard: .iec), "466G")

        let disk = DiskSample(volumes: [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000_000_000, used: 500_000_000_000, free: bytes)
        ])
        let siKey = modelKey(.disk, .text, WidgetSnapshot(disk: disk), options: WidgetOptions(byteUnitStandard: .si))
        let iecKey = modelKey(.disk, .text, WidgetSnapshot(disk: disk), options: WidgetOptions(byteUnitStandard: .iec))
        XCTAssertNotEqual(siKey, iecKey)
        XCTAssertTrue(siKey.contains("500G"))
        XCTAssertTrue(iecKey.contains("466G"))
    }

    func testSparklineKeyChangesOnlyWithNewSample() {
        let a = WidgetSeries(primary: [1, 2, 3], secondary: [], tertiary: [], stamp: 100)
        let same = WidgetSeries(primary: [1, 2, 3], secondary: [], tertiary: [], stamp: 100)
        let next = WidgetSeries(primary: [1, 2, 3, 4], secondary: [], tertiary: [], stamp: 101)
        let k1 = modelKey(.gpu, .sparkline, WidgetSnapshot(gpu: GPUSample(utilization: 3), series: a))
        XCTAssertEqual(k1, modelKey(.gpu, .sparkline, WidgetSnapshot(gpu: GPUSample(utilization: 3), series: same)))
        XCTAssertNotEqual(k1, modelKey(.gpu, .sparkline, WidgetSnapshot(gpu: GPUSample(utilization: 4), series: next)))
    }

    func testRenderDoesNotDoubleCacheStackedOrSingleLineThroughput() {
        let (defaults, prefs, coord, _, suiteName) = makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        MenuBarIconRenderer.clearImageCache()

        let cpu = CPUSample(totalUsage: 42, perCore: [42], user: 22, system: 20, idle: 58)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: cpu))
        let cpuConfig = MenuBarItemConfig(category: .cpu, style: .text)
        let cpuResult = MenuBarIconRenderer.render(config: cpuConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(cpuResult.visualKey)
        XCTAssertTrue(MenuBarIconRenderer.hasCachedImage(forKey: cpuResult.visualKey ?? ""))
        XCTAssertFalse(MenuBarIconRenderer.hasCachedImage(forKey: "stacked:CPU:42%:32.0:0:0:0"))

        let net = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1024 * 50, bytesOutPerSec: 1024 * 10, totalBytesIn: 1000, totalBytesOut: 500)
        ])
        coord.handleReading(MetricReading.wrap(category: .network, value: net))
        var netConfig = MenuBarItemConfig(category: .network, style: .throughput)
        netConfig.throughputLayout = .singleLine
        let netResult = MenuBarIconRenderer.render(config: netConfig, coordinator: coord, preferences: prefs)
        XCTAssertNotNil(netResult.visualKey)
        XCTAssertTrue(MenuBarIconRenderer.hasCachedImage(forKey: netResult.visualKey ?? ""))
        let inStr = Units.formatCompactRate(1024 * 50, unit: prefs.networkUnit, standard: prefs.byteUnitStandard)
        let outStr = Units.formatCompactRate(1024 * 10, unit: prefs.networkUnit, standard: prefs.byteUnitStandard)
        XCTAssertFalse(MenuBarIconRenderer.hasCachedImage(forKey: "singleLineTp:↓:\(inStr):↑:\(outStr):82.0"))
    }

    func testDrawSingleLineThroughputCacheKeyIncludesColors() {
        MenuBarIconRenderer.clearImageCache()
        let img1 = MenuBarIconRenderer.drawSingleLineThroughput(
            prefix1: "↓",
            value1: "10 KB/s",
            prefix2: "↑",
            value2: "5 KB/s",
            color1: .systemBlue,
            color2: .systemGreen
        )
        let img2 = MenuBarIconRenderer.drawSingleLineThroughput(
            prefix1: "↓",
            value1: "10 KB/s",
            prefix2: "↑",
            value2: "5 KB/s",
            color1: .systemRed,
            color2: .systemOrange
        )
        XCTAssertFalse(img1 === img2, "drawSingleLineThroughput must not return stale cached image when colors differ")
    }
}
