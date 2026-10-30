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
        let imgIdle1 = MenuBarIconRenderer.drawNetworkActivityArrows(inBytes: 0, outBytes: 0)
        let imgIdle2 = MenuBarIconRenderer.drawNetworkActivityArrows(inBytes: 256, outBytes: 512)
        // Active download
        let imgActiveDown = MenuBarIconRenderer.drawNetworkActivityArrows(inBytes: 100_000, outBytes: 0)

        XCTAssertTrue(imgIdle1 === imgIdle2, "Inactive network arrows must reuse identical cached NSImage pointer")
        XCTAssertFalse(imgIdle1 === imgActiveDown, "State change must return different image instance")
    }

    func testDiskActivityLedsReusesSameImagePointer() {
        // Both below 10240 bytes -> inactive state
        let imgIdle1 = MenuBarIconRenderer.drawDiskActivityLeds(readBytes: 0, writeBytes: 0)
        let imgIdle2 = MenuBarIconRenderer.drawDiskActivityLeds(readBytes: 1024, writeBytes: 2048)
        // Active write
        let imgActiveWrite = MenuBarIconRenderer.drawDiskActivityLeds(readBytes: 0, writeBytes: 50_000)

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

    func testComputeVisualKeyCalculatesExpectedTokensAcrossCategories() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        // 1. CPU
        let cpuSample = CPUSample(totalUsage: 25.0, perCore: [25.0], user: 15.0, system: 10.0, idle: 75.0)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: cpuSample))

        let cpuText = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .cpu, style: .text), coordinator: coord, preferences: prefs)
        XCTAssertEqual(cpuText, "cpu:text:25%")

        let cpuGauge = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .cpu, style: .gauge), coordinator: coord, preferences: prefs)
        XCTAssertEqual(cpuGauge, "cpu:gauge:15:10")

        let cpuSparkline = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .cpu, style: .sparkline), coordinator: coord, preferences: prefs)
        XCTAssertNil(cpuSparkline, "Sparkline continuous graphs must return nil visualKey")

        // 2. Memory
        let memSample = MemorySample(total: 1000, used: 550, free: 450, wired: 100, compressed: 50, cached: 250, swapUsed: 0, pressure: .normal)
        coord.handleReading(MetricReading.wrap(category: .memory, value: memSample))

        let memGauge = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .memory, style: .gauge), coordinator: coord, preferences: prefs)
        XCTAssertEqual(memGauge, "mem:gauge:55:10:45:5")

        let memBadge = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .memory, style: .symbol), coordinator: coord, preferences: prefs)
        XCTAssertEqual(memBadge, "mem:badge:normal")

        // 3. GPU
        let gpuSample = GPUSample(utilization: 35.0, tempCelsius: 48.0)
        coord.handleReading(MetricReading.wrap(category: .gpu, value: gpuSample))

        let gpuGauge = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .gpu, style: .gauge), coordinator: coord, preferences: prefs)
        XCTAssertEqual(gpuGauge, "gpu:gauge:35:48")

        let gpuSymbol = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .gpu, style: .symbol), coordinator: coord, preferences: prefs)
        XCTAssertEqual(gpuSymbol, "gpu:symbol:35:48")

        // 4. Power
        let pwrSample = PowerSample(hasBattery: true, charge: 92.0, state: .charging)
        coord.handleReading(MetricReading.wrap(category: .power, value: pwrSample))

        let pwrGauge = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .power, style: .gauge), coordinator: coord, preferences: prefs)
        XCTAssertEqual(pwrGauge, "pwr:gauge:92:true:charging")

        let pwrSymbol = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .power, style: .symbol), coordinator: coord, preferences: prefs)
        XCTAssertEqual(pwrSymbol, "pwr:symbol:92:charging:true")

        // 5. Fan
        let fanSample = FanSample(fans: [FanReading(name: "Fan 1", rpm: 2100, minRPM: 1200, maxRPM: 5000)])
        coord.handleReading(MetricReading.wrap(category: .fan, value: fanSample))

        let fanGauge = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .fan, style: .gauge), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(fanGauge)
        XCTAssertTrue(fanGauge!.starts(with: "fan:gauge:"))

        // 6. Network
        let netSample = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 50_000, bytesOutPerSec: 200, totalBytesIn: 1000, totalBytesOut: 500)])
        coord.handleReading(MetricReading.wrap(category: .network, value: netSample))

        let netArrows = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .network, style: .symbol), coordinator: coord, preferences: prefs)
        XCTAssertEqual(netArrows, "net:arrows:true:false")

        // 7. Disk
        let diskSample = DiskSample(
            volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000, used: 600_000, free: 400_000)],
            io: DiskIO(bytesReadPerSec: 50_000, bytesWrittenPerSec: 0, readOpsPerSec: 10, writeOpsPerSec: 0)
        )
        coord.handleReading(MetricReading.wrap(category: .disk, value: diskSample))

        let diskLeds = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .disk, style: .symbol), coordinator: coord, preferences: prefs)
        XCTAssertEqual(diskLeds, "disk:leds:true:false")

        let diskGauge = MenuBarIconRenderer.computeVisualKey(config: MenuBarItemConfig(category: .disk, style: .gauge), coordinator: coord, preferences: prefs)
        XCTAssertEqual(diskGauge, "disk:gauge:60")
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

    func testCPUBarUpdatesWhenPerCoreLoadShiftsAtSameTotalUsage() {
        let (defaults, prefs, coord, controller, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, controller: controller, suiteName: suiteName) }

        let cpuBarItem = MenuBarItemConfig(category: .cpu, style: .bar)
        prefs.menuBarItems = [cpuBarItem]
        controller.syncStatusItems()
        controller.resetPerformanceCounters()

        let sample1 = CPUSample(totalUsage: 25.0, perCore: [50.0, 0.0, 50.0, 0.0], user: 15.0, system: 10.0, idle: 75.0)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample1))
        controller.updateItems(for: .cpu)

        // Total is still 25.0%, but core distribution changed
        let sample2 = CPUSample(totalUsage: 25.0, perCore: [25.0, 25.0, 25.0, 25.0], user: 15.0, system: 10.0, idle: 75.0)
        coord.handleReading(MetricReading.wrap(category: .cpu, value: sample2))
        controller.updateItems(for: .cpu)

        XCTAssertEqual(controller.buttonMutationCount, 2, "CPU .bar must redraw when per-core bars change even if total usage is identical")
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

    func testVisualKeyDistinguishesNilFromZeroForPowerAndGPU() {
        let pwrTpNil = MenuBarIconRenderer.visualKeyForPower(
            style: .throughput,
            power: PowerSample(hasBattery: true, powerDrawWatts: nil, adapterWatts: nil)
        )
        let pwrTpZero = MenuBarIconRenderer.visualKeyForPower(
            style: .throughput,
            power: PowerSample(hasBattery: true, powerDrawWatts: 0.0, adapterWatts: 0.0)
        )
        XCTAssertNotEqual(pwrTpNil, pwrTpZero, "Power .throughput visualKey must distinguish nil ('--W'/'AC') from 0.0 ('0W'/'0W')")

        let pwrSymNil = MenuBarIconRenderer.visualKeyForPower(
            style: .symbol,
            power: PowerSample(hasBattery: true, charge: nil, state: .unknown)
        )
        let pwrSymZero = MenuBarIconRenderer.visualKeyForPower(
            style: .symbol,
            power: PowerSample(hasBattery: true, charge: 0.0, state: .unknown)
        )
        XCTAssertNotEqual(pwrSymNil, pwrSymZero, "Power .symbol visualKey must distinguish nil charge from 0% charge")

        let gpuGaugeNil = MenuBarIconRenderer.visualKeyForGPU(
            style: .gauge,
            gpu: GPUSample(utilization: 30.0, tempCelsius: nil)
        )
        let gpuGaugeZero = MenuBarIconRenderer.visualKeyForGPU(
            style: .gauge,
            gpu: GPUSample(utilization: 30.0, tempCelsius: 0.0)
        )
        XCTAssertNotEqual(gpuGaugeNil, gpuGaugeZero, "GPU .gauge visualKey must distinguish nil temp (purple) from 0°C (green)")
    }

    func testFanGaugeAndBarIgnoreSingleRPMJitterAtSamePercentage() {
        let fan1 = FanSample(fans: [FanReading(name: "Fan 1", rpm: 2100, minRPM: 1200, maxRPM: 5000)])
        let fan2 = FanSample(fans: [FanReading(name: "Fan 1", rpm: 2101, minRPM: 1200, maxRPM: 5000)])

        XCTAssertEqual(
            MenuBarIconRenderer.visualKeyForFan(style: .gauge, fan: fan1),
            MenuBarIconRenderer.visualKeyForFan(style: .gauge, fan: fan2),
            "Fan .gauge visualKey must not churn on 1 RPM jitter when rounded percentage is unchanged"
        )
        XCTAssertEqual(
            MenuBarIconRenderer.visualKeyForFan(style: .bar, fan: fan1),
            MenuBarIconRenderer.visualKeyForFan(style: .bar, fan: fan2),
            "Fan .bar visualKey must not churn on 1 RPM jitter when rounded percentage is unchanged"
        )
        XCTAssertNotEqual(
            MenuBarIconRenderer.visualKeyForFan(style: .throughput, fan: fan1),
            MenuBarIconRenderer.visualKeyForFan(style: .throughput, fan: fan2),
            "Fan .throughput visualKey must still update on exact RPM change"
        )
    }
    func testFanTextKeyTracksRPMWithoutNeedingBounds() {
        let first = FanSample(fans: [FanReading(name: "Fan", rpm: 2000)])
        let second = FanSample(fans: [FanReading(name: "Fan", rpm: 2100)])
        XCTAssertEqual(MenuBarIconRenderer.visualKeyForFan(style: .text, fan: first), "fan:text:2000")
        XCTAssertNotEqual(MenuBarIconRenderer.visualKeyForFan(style: .text, fan: first),
                          MenuBarIconRenderer.visualKeyForFan(style: .text, fan: second))
        XCTAssertEqual(MenuBarIconRenderer.visualKeyForFan(style: .text, fan: nil), "fan:text:--")
    }

}
