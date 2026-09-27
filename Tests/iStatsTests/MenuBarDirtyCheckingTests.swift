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
        XCTAssertEqual(memGauge, "mem:gauge:5500")

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
}
