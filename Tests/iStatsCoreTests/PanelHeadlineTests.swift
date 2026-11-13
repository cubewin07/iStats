import XCTest
@testable import iStatsCore

final class PanelHeadlineTests: XCTestCase {

    func testCPUHeadlineFormattingAndNilHandling() {
        XCTAssertEqual(PanelHeadline.cpu(sample: nil), "Processor telemetry unavailable")

        let sample = CPUSample(
            totalUsage: 72.5,
            perCore: Array(repeating: 72.5, count: 10),
            user: 50.0,
            system: 22.5,
            idle: 27.5,
            loadAverage: LoadAverage(oneMinute: 2.1, fiveMinute: 1.8, fifteenMinute: 1.2),
            frequencyHz: 3_200_000_000
        )

        let headline = PanelHeadline.cpu(sample: sample)
        XCTAssertTrue(headline.contains("Moderate load"))
        XCTAssertTrue(headline.contains("10 cores"))
        XCTAssertTrue(headline.contains("3.20 GHz"))

        // Without clock speed
        let sampleNoClock = CPUSample(
            totalUsage: 72.5,
            perCore: [72.5],
            user: 50.0,
            system: 22.5,
            idle: 27.5,
            frequencyHz: nil
        )
        let headlineNoClock = PanelHeadline.cpu(sample: sampleNoClock, clockSpeedHz: nil)
        XCTAssertFalse(headlineNoClock.contains("GHz"))
    }

    func testMemoryHeadlineFormatting() {
        XCTAssertEqual(PanelHeadline.memory(sample: nil), "Memory telemetry unavailable")

        let sample = MemorySample(
            total: 16_000_000_000,
            used: 12_000_000_000,
            free: 4_000_000_000,
            wired: 2_000_000_000,
            compressed: 2_000_000_000,
            cached: 1_000_000_000,
            swapUsed: 1_000_000_000,
            pressure: .warning
        )

        let headline = PanelHeadline.memory(sample: sample)
        XCTAssertTrue(headline.contains("Pressure elevated"))
        XCTAssertTrue(headline.contains("compressed"))
        XCTAssertTrue(headline.contains("swap"))
    }

    func testGPUHeadlineFormatting() {
        XCTAssertEqual(PanelHeadline.gpu(sample: nil), "GPU telemetry unavailable")

        let sample = GPUSample(
            utilization: 65.0,
            memoryUsed: 2_000_000_000,
            tempCelsius: 62.0
        )

        let headline = PanelHeadline.gpu(sample: sample)
        XCTAssertTrue(headline.contains("Active"))
        XCTAssertTrue(headline.contains("65% utilization"))
        XCTAssertTrue(headline.contains("62°C"))
    }

    func testThermalHeadlineFormatting() {
        XCTAssertEqual(PanelHeadline.thermal(sample: nil), "Thermal telemetry unavailable")

        let sample = ThermalSample(
            sensors: [],
            pressure: .fair
        )

        let headline = PanelHeadline.thermal(sample: sample, cpuTemp: 68.0, gpuTemp: 55.0)
        XCTAssertTrue(headline.contains("Warm"))
        XCTAssertTrue(headline.contains("CPU 68°"))
        XCTAssertTrue(headline.contains("GPU 55°"))
    }

    func testFanHeadlineFormatting() {
        XCTAssertEqual(PanelHeadline.fan(sample: nil), "Fan telemetry unavailable")

        let fanless = FanSample(fans: [])
        XCTAssertEqual(PanelHeadline.fan(sample: fanless), "Fanless passive cooling")

        let dualFan = FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 1800, minRPM: 1200, maxRPM: 5400),
            FanReading(name: "Right Fan", rpm: 1950, minRPM: 1200, maxRPM: 5400)
        ])

        let headline = PanelHeadline.fan(sample: dualFan)
        XCTAssertTrue(headline.contains("Quiet"))
        XCTAssertTrue(headline.contains("2 fans"))
    }

    func testNetworkHeadlineFormatting() {
        XCTAssertEqual(PanelHeadline.network(sample: nil), "Network telemetry unavailable")

        let sample = NetworkSample(
            interfaces: [
                InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 2_500_000, bytesOutPerSec: 300_000, totalBytesIn: 0, totalBytesOut: 0)
            ],
            localIPv4: "192.168.1.50"
        )

        let headline = PanelHeadline.network(sample: sample)
        XCTAssertTrue(headline.contains("Active"))
        XCTAssertTrue(headline.contains("↓"))
        XCTAssertTrue(headline.contains("↑"))
        XCTAssertTrue(headline.contains("192.168.1.50"))
    }

    func testDiskHeadlineFormatting() {
        XCTAssertEqual(PanelHeadline.disk(sample: nil), "Disk telemetry unavailable")

        let sample = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000_000_000, used: 500_000_000_000, free: 500_000_000_000)
            ],
            io: DiskIO(bytesReadPerSec: 15_000_000, bytesWrittenPerSec: 5_000_000, readOpsPerSec: 100, writeOpsPerSec: 50)
        )

        let headline = PanelHeadline.disk(sample: sample)
        XCTAssertTrue(headline.contains("Active"))
        XCTAssertTrue(headline.contains("/s"))
        XCTAssertTrue(headline.contains("free"))
    }

    func testPowerHeadlineFormatting() {
        XCTAssertEqual(PanelHeadline.power(sample: nil), "Power telemetry unavailable")

        let sample = PowerSample(
            hasBattery: true,
            charge: 65.0,
            state: .discharging,
            timeRemaining: 15000, // 250 minutes = 4h 10m
            powerDrawWatts: 14.8
        )

        let headline = PanelHeadline.power(sample: sample)
        XCTAssertTrue(headline.contains("On battery"))
        XCTAssertTrue(headline.contains("4h 10m left"))
        XCTAssertTrue(headline.contains("14.8 W"))
    }
}
