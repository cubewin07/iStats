import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class MenuBarItemMatrixTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.matrix.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        return (defaults, prefs, coord, suiteName)
    }

    private func cleanup(defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 1. CPU Item Matrix Tests

    func testCPURenderingAllSupportedStyles() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let cpuSample = CPUSample(
            totalUsage: 45.5,
            perCore: [30.0, 40.0, 50.0, 62.0],
            user: 28.5,
            system: 17.0,
            idle: 54.5,
            loadAverage: LoadAverage(oneMinute: 2.1, fiveMinute: 1.5, fifteenMinute: 1.1),
            frequencyHz: 3_400_000_000,
            efficiencyCoreCount: 2,
            performanceCoreCount: 2
        )
        coord.handleReading(.cpu(Sample(value: cpuSample)))

        let styles = MetricDisplayStyle.supportedStyles(for: .cpu)
        for style in styles {
            let config = MenuBarItemConfig(category: .cpu, style: style)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)

            XCTAssertNotNil(result.image, "CPU style \(style) must render an NSImage")
            XCTAssertGreaterThan(result.image?.size.width ?? 0, 0)
            XCTAssertGreaterThan(result.image?.size.height ?? 0, 0)
            XCTAssertTrue(result.toolTip.contains("CPU: 45.5%"), "CPU tooltip should include usage")
            XCTAssertTrue(result.toolTip.contains("User: 28.5%"), "CPU tooltip should include user usage")
            XCTAssertEqual(result.accessibilityLabel, "CPU load 46 percent")
        }
    }

    func testCPURenderingColdStartAndNilMetrics() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        for style in MetricDisplayStyle.supportedStyles(for: .cpu) {
            let config = MenuBarItemConfig(category: .cpu, style: style)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)

            XCTAssertNotNil(result.image)
            XCTAssertEqual(result.toolTip, "CPU: --%")
            XCTAssertEqual(result.accessibilityLabel, "CPU load unavailable")
        }
    }

    // MARK: - 2. Memory Item Matrix Tests

    func testMemoryRenderingAllSupportedStyles() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let memSample = MemorySample(
            total: 32 * 1024 * 1024 * 1024,
            used: 20 * 1024 * 1024 * 1024,
            free: 12 * 1024 * 1024 * 1024,
            wired: 6 * 1024 * 1024 * 1024,
            compressed: 2 * 1024 * 1024 * 1024,
            cached: 4 * 1024 * 1024 * 1024,
            swapUsed: 512 * 1024 * 1024,
            pressure: .normal
        )
        coord.handleReading(.memory(Sample(value: memSample)))

        let styles = MetricDisplayStyle.supportedStyles(for: .memory)
        for style in styles {
            let config = MenuBarItemConfig(category: .memory, style: style)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)

            XCTAssertNotNil(result.image)
            XCTAssertTrue(result.toolTip.contains("62.5%"), "Memory tooltip must reflect used percentage")
            XCTAssertEqual(result.accessibilityLabel, "Memory pressure Normal, 20.00 GiB used of 32.00 GiB")
        }
    }

    func testMemoryRenderingPressureLevels() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let pressures: [(MemoryPressure, String)] = [
            (.normal, "Memory pressure Normal"),
            (.warning, "Memory pressure Warning"),
            (.critical, "Memory pressure Critical")
        ]

        for (pressure, expectedA11yText) in pressures {
            let sample = MemorySample(
                total: 16 * 1024 * 1024 * 1024,
                used: 12 * 1024 * 1024 * 1024,
                free: 4 * 1024 * 1024 * 1024,
                wired: 4 * 1024 * 1024 * 1024,
                compressed: 2 * 1024 * 1024 * 1024,
                cached: 2 * 1024 * 1024 * 1024,
                swapUsed: 0,
                pressure: pressure
            )
            coord.handleReading(.memory(Sample(value: sample)))

            let config = MenuBarItemConfig(category: .memory, style: .symbol)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)

            XCTAssertNotNil(result.image)
            XCTAssertTrue(result.accessibilityLabel.contains(expectedA11yText))
        }
    }

    func testMemoryRenderingColdStartAndNil() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        for style in MetricDisplayStyle.supportedStyles(for: .memory) {
            let config = MenuBarItemConfig(category: .memory, style: style)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)

            XCTAssertNotNil(result.image)
            XCTAssertEqual(result.toolTip, "MEM: --%")
            XCTAssertEqual(result.accessibilityLabel, "Memory telemetry unavailable")
        }
    }

    // MARK: - 3. GPU Item Matrix Tests

    func testGPURenderingAllSupportedStyles() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let gpuSample = GPUSample(
            utilization: 38.4,
            memoryUsed: 2 * 1024 * 1024 * 1024,
            tempCelsius: 52.0,
            powerWatts: 14.5
        )
        coord.handleReading(.gpu(Sample(value: gpuSample)))

        let styles = MetricDisplayStyle.supportedStyles(for: .gpu)
        for style in styles {
            let config = MenuBarItemConfig(category: .gpu, style: style)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)

            XCTAssertNotNil(result.image, "GPU style \(style) must render an NSImage")
            XCTAssertTrue(result.toolTip.contains("GPU: 38.4%"), "GPU tooltip should contain usage")
            XCTAssertEqual(result.accessibilityLabel, "GPU utilization 38 percent")
        }
    }

    func testGPURenderingColdStartAndNil() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        for style in MetricDisplayStyle.supportedStyles(for: .gpu) {
            let config = MenuBarItemConfig(category: .gpu, style: style)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)

            XCTAssertNotNil(result.image)
            XCTAssertEqual(result.toolTip, "GPU: --%")
            XCTAssertEqual(result.accessibilityLabel, "GPU utilization unavailable")
        }
    }

    // MARK: - 4. Thermal Item Matrix Tests

    func testThermalRenderingAllSupportedStyles() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let thermalSample = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 52.5),
                SensorReading(name: "GPU Cluster 1", celsius: 48.0),
                SensorReading(name: "Memory Module A", celsius: 42.0),
                SensorReading(name: "Storage Flash (NAND)", celsius: 38.0),
                SensorReading(name: "Battery (Sensor 1)", celsius: 31.0),
                SensorReading(name: "SoC Peak Die", celsius: 65.0)
            ],
            pressure: .nominal
        )
        coord.handleReading(.thermal(Sample(value: thermalSample)))

        let styles = MetricDisplayStyle.supportedStyles(for: .thermal)
        for style in styles {
            let config = MenuBarItemConfig(category: .thermal, style: style)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)
            XCTAssertNotNil(result.image)
            XCTAssertFalse(result.toolTip.isEmpty)
            XCTAssertFalse(result.accessibilityLabel.isEmpty)
        }
    }

    func testThermalRenderingFahrenheitPreference() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        prefs.temperatureUnit = .fahrenheit

        let thermalSample = ThermalSample(
            sensors: [SensorReading(name: "CPU Package", celsius: 100.0)],
            pressure: .nominal
        )
        coord.handleReading(.thermal(Sample(value: thermalSample)))

        let res = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .thermal, style: .text), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(res.image)
        XCTAssertEqual(res.toolTip, "Peak Thermal: 212.0 °F (CPU Package)")
        XCTAssertEqual(res.accessibilityLabel, "Peak temperature 212 °F")
    }

    // MARK: - 5. Fan Item Matrix Tests

    func testFanRenderingAllSupportedStyles() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let dualFanSample = FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 2400, minRPM: 2000, maxRPM: 6000),
            FanReading(name: "Right Fan", rpm: 2550, minRPM: 2000, maxRPM: 6000)
        ])
        coord.handleReading(.fan(Sample(value: dualFanSample)))

        let styles = MetricDisplayStyle.supportedStyles(for: .fan)
        for style in styles {
            let config = MenuBarItemConfig(category: .fan, style: style)
            let result = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)
            XCTAssertNotNil(result.image)
            XCTAssertTrue(result.toolTip.contains("Left Fan: 2400 RPM"))
            XCTAssertEqual(result.accessibilityLabel, "Fans running at 2550 RPM")
        }

        // Fanless
        let fanlessSample = FanSample(fans: [])
        coord.handleReading(.fan(Sample(value: fanlessSample)))
        let resFanless = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .fan, style: .symbol), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resFanless.image)
        XCTAssertEqual(resFanless.toolTip, "Fans: Fanless System")
        XCTAssertEqual(resFanless.accessibilityLabel, "Fanless system")
    }

    // MARK: - 6. Network Item Matrix Tests

    func testNetworkRenderingAllSupportedStyles() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let netSample = NetworkSample(interfaces: [
            InterfaceThroughput(
                interfaceName: "en0",
                bytesInPerSec: 1024 * 1024 * 2.5,
                bytesOutPerSec: 1024 * 512,
                totalBytesIn: 1024 * 1024 * 500,
                totalBytesOut: 1024 * 1024 * 120
            )
        ])
        coord.handleReading(.network(Sample(value: netSample)))

        for style in MetricDisplayStyle.supportedStyles(for: .network) {
            let config = MenuBarItemConfig(category: .network, style: style)
            let res = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)
            XCTAssertNotNil(res.image)
            XCTAssertTrue(res.toolTip.contains("2.50 MiB/s") || res.toolTip.contains("2.5 MiB/s"))
            XCTAssertTrue(res.accessibilityLabel.contains("Network download"))
        }
    }

    // MARK: - 7. Disk Item Matrix Tests

    func testDiskRenderingAllSupportedStyles() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let diskSample = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500 * 1024 * 1024 * 1024, used: 350 * 1024 * 1024 * 1024, free: 150 * 1024 * 1024 * 1024)
            ],
            io: DiskIO(bytesReadPerSec: 1024 * 1024 * 12, bytesWrittenPerSec: 1024 * 1024 * 4, readOpsPerSec: 120, writeOpsPerSec: 40)
        )
        coord.handleReading(.disk(Sample(value: diskSample)))

        for style in MetricDisplayStyle.supportedStyles(for: .disk) {
            let config = MenuBarItemConfig(category: .disk, style: style)
            let res = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)
            XCTAssertNotNil(res.image)
            XCTAssertFalse(res.toolTip.isEmpty)
            XCTAssertFalse(res.accessibilityLabel.isEmpty)
        }
    }

    // MARK: - 8. Power Item Matrix Tests

    func testPowerRenderingBatteryChargingDischargingAndDesktopAC() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        // 1. Battery Discharging
        let batDischarging = PowerSample(
            hasBattery: true,
            charge: 75.0,
            state: .discharging,
            timeRemaining: 14400.0,
            powerDrawWatts: 15.2,
            adapterWatts: nil
        )
        coord.handleReading(.power(Sample(value: batDischarging)))
        let resDischarging = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .power, style: .symbol), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resDischarging.image)
        XCTAssertTrue(resDischarging.toolTip.contains("75%"))
        XCTAssertTrue(resDischarging.toolTip.contains("On Battery"))
        XCTAssertEqual(resDischarging.accessibilityLabel, "Battery 75 percent, on battery")

        // 2. Battery Charging
        let batCharging = PowerSample(
            hasBattery: true,
            charge: 92.0,
            state: .charging,
            timeRemaining: 1800.0,
            powerDrawWatts: 24.0,
            adapterWatts: 67.0
        )
        coord.handleReading(.power(Sample(value: batCharging)))
        let resCharging = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .power, style: .gauge), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resCharging.image)
        XCTAssertTrue(resCharging.toolTip.contains("92%"))
        XCTAssertTrue(resCharging.toolTip.contains("Charging"))
        XCTAssertEqual(resCharging.accessibilityLabel, "Battery 92 percent, charging")

        // 3. Desktop AC Power (No Battery, e.g. Mac Studio, Mac mini)
        let desktopAC = PowerSample(
            hasBattery: false,
            powerDrawWatts: 35.0
        )
        coord.handleReading(.power(Sample(value: desktopAC)))
        let resAC = MenuBarIconRenderer.render(config: MenuBarItemConfig(category: .power, style: .text), coordinator: coord, preferences: prefs)
        XCTAssertNotNil(resAC.image)
        XCTAssertEqual(resAC.toolTip, "Power: Connected to AC (35.0 W)")
        XCTAssertEqual(resAC.accessibilityLabel, "Connected to AC power")
    }

    // MARK: - Completeness Check Across all Available Items

    func testRenderCompletenessAcrossAllDefaultItems() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        for config in MenuBarItemConfig.allAvailableItems {
            let res = MenuBarIconRenderer.render(config: config, coordinator: coord, preferences: prefs)
            XCTAssertNotNil(res.image, "Every item config in allAvailableItems must render a non-nil image")
            XCTAssertFalse(res.toolTip.isEmpty, "Tooltip must not be empty for \(config.id)")
            XCTAssertFalse(res.accessibilityLabel.isEmpty, "Accessibility label must not be empty for \(config.id)")
        }
    }
}
