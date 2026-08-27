import XCTest
import AppKit
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
}
