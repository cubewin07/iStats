import XCTest
@testable import iStatsCore

final class ModelsTests: XCTestCase {

    func testCPUSamplePropertiesAndEquality() {
        let cpu1 = CPUSample(totalUsage: 45.0, perCore: [40.0, 50.0], user: 25.0, system: 20.0, idle: 55.0)
        let cpu2 = CPUSample(totalUsage: 45.0, perCore: [40.0, 50.0], user: 25.0, system: 20.0, idle: 55.0)
        let cpu3 = CPUSample(totalUsage: 50.0, perCore: [50.0, 50.0], user: 30.0, system: 20.0, idle: 50.0)

        XCTAssertEqual(cpu1, cpu2)
        XCTAssertNotEqual(cpu1, cpu3)
        XCTAssertEqual(cpu1.totalUsage, 45.0)
        XCTAssertEqual(cpu1.perCore, [40.0, 50.0])
        XCTAssertEqual(cpu1.user, 25.0)
        XCTAssertEqual(cpu1.system, 20.0)
        XCTAssertEqual(cpu1.idle, 55.0)
    }

    func testMemorySampleAndPressure() {
        let mem = MemorySample(
            total: 16_000_000_000,
            used: 10_000_000_000,
            free: 6_000_000_000,
            wired: 2_000_000_000,
            compressed: 1_000_000_000,
            cached: 3_000_000_000,
            swapUsed: 500_000_000,
            pressure: .normal
        )

        XCTAssertEqual(mem.total, 16_000_000_000)
        XCTAssertEqual(mem.used, 10_000_000_000)
        XCTAssertEqual(mem.pressure, .normal)
        XCTAssertEqual(MemoryPressure.warning.rawValue, "warning")
        XCTAssertEqual(MemoryPressure.critical.rawValue, "critical")
    }

    func testThermalSampleAndPressure() {
        let sensor1 = SensorReading(name: "CPU Proximity", celsius: 42.5)
        let sensor2 = SensorReading(name: "GPU Proximity", celsius: 40.0)
        let sample = ThermalSample(sensors: [sensor1, sensor2], pressure: .fair)

        XCTAssertEqual(sample.sensors.count, 2)
        XCTAssertEqual(sample.sensors[0].name, "CPU Proximity")
        XCTAssertEqual(sample.sensors[0].celsius, 42.5)
        XCTAssertEqual(sample.pressure, .fair)
        XCTAssertEqual(ThermalPressure.nominal.rawValue, "nominal")
        XCTAssertEqual(ThermalPressure.serious.rawValue, "serious")
        XCTAssertEqual(ThermalPressure.critical.rawValue, "critical")
    }

    func testFanSampleAndReadings() {
        let fan1 = FanReading(name: "Left Fan", rpm: 1800, minRPM: 1200, maxRPM: 5000)
        let fan2 = FanReading(name: "Right Fan", rpm: 1850)
        let sample = FanSample(fans: [fan1, fan2])

        XCTAssertEqual(sample.fans.count, 2)
        XCTAssertEqual(sample.fans[0].rpm, 1800)
        XCTAssertEqual(sample.fans[0].minRPM, 1200)
        XCTAssertEqual(sample.fans[0].maxRPM, 5000)
        XCTAssertNil(sample.fans[1].minRPM)
    }

    func testNetworkSampleAndAggregateCalculations() {
        let en0 = InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1000.0, bytesOutPerSec: 500.0, totalBytesIn: 10000, totalBytesOut: 5000)
        let en1 = InterfaceThroughput(interfaceName: "en1", bytesInPerSec: 2000.0, bytesOutPerSec: 1500.0, totalBytesIn: 20000, totalBytesOut: 15000)
        let sample = NetworkSample(interfaces: [en0, en1])

        XCTAssertEqual(sample.interfaces.count, 2)
        XCTAssertEqual(sample.totalBytesInPerSec, 3000.0, accuracy: 0.001)
        XCTAssertEqual(sample.totalBytesOutPerSec, 2000.0, accuracy: 0.001)
        XCTAssertEqual(sample.totalBytesIn, 30000)
        XCTAssertEqual(sample.totalBytesOut, 20000)
    }

    func testDiskSampleAndIO() {
        let vol = VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 200_000_000_000, free: 300_000_000_000)
        let io = DiskIO(bytesReadPerSec: 10_000_000, bytesWrittenPerSec: 5_000_000, readOpsPerSec: 100, writeOpsPerSec: 50)
        let sample = DiskSample(volumes: [vol], io: io)

        XCTAssertEqual(sample.volumes.count, 1)
        XCTAssertEqual(sample.volumes[0].name, "Macintosh HD")
        XCTAssertEqual(sample.io?.bytesReadPerSec, 10_000_000)
        XCTAssertEqual(sample.io?.writeOpsPerSec, 50)
    }

    func testPowerSampleBatteryStates() {
        let sample = PowerSample(
            hasBattery: true,
            charge: 88.5,
            state: .charging,
            timeRemaining: 3600,
            cycleCount: 42,
            condition: "Normal",
            designCapacity: 6000,
            currentMaxCapacity: 5800,
            powerDrawWatts: 18.5,
            adapterWatts: 67.0
        )

        XCTAssertTrue(sample.hasBattery)
        XCTAssertEqual(sample.charge, 88.5)
        XCTAssertEqual(sample.state, .charging)
        XCTAssertEqual(sample.timeRemaining, 3600)
        XCTAssertEqual(sample.cycleCount, 42)
        XCTAssertEqual(sample.powerDrawWatts, 18.5)
        XCTAssertEqual(sample.adapterWatts, 67.0)

        let noBatterySample = PowerSample(hasBattery: false)
        XCTAssertFalse(noBatterySample.hasBattery)
        XCTAssertNil(noBatterySample.charge)
    }

    func testGPUSample() {
        let gpu = GPUSample(utilization: 12.5, memoryUsed: 1_000_000_000, tempCelsius: 48.0, powerWatts: 5.2)
        XCTAssertEqual(gpu.utilization, 12.5)
        XCTAssertEqual(gpu.memoryUsed, 1_000_000_000)
        XCTAssertEqual(gpu.tempCelsius, 48.0)
        XCTAssertEqual(gpu.powerWatts, 5.2)

        let unavailableGPU = GPUSample()
        XCTAssertNil(unavailableGPU.utilization)
    }
}
