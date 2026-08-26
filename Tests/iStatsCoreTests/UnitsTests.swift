import XCTest
@testable import iStatsCore

final class UnitsTests: XCTestCase {

    func testCelsiusFahrenheitKnownValues() {
        XCTAssertEqual(Units.celsiusToFahrenheit(0), 32, accuracy: 0.0001)
        XCTAssertEqual(Units.celsiusToFahrenheit(100), 212, accuracy: 0.0001)
        XCTAssertEqual(Units.fahrenheitToCelsius(32), 0, accuracy: 0.0001)
    }

    func testTemperatureRoundTrip() {
        for c in stride(from: -40.0, through: 120.0, by: 7.5) {
            let round = Units.fahrenheitToCelsius(Units.celsiusToFahrenheit(c))
            XCTAssertEqual(round, c, accuracy: 0.0001)
        }
    }

    func testFormatBytesIEC() {
        XCTAssertEqual(Units.formatBytes(0, standard: .iec), "0 B")
        XCTAssertEqual(Units.formatBytes(512, standard: .iec), "512 B")
        XCTAssertEqual(Units.formatBytes(1024, standard: .iec), "1.00 KiB")
        XCTAssertEqual(Units.formatBytes(1024 * 1024, standard: .iec), "1.00 MiB")
    }

    func testFormatBytesSI() {
        XCTAssertEqual(Units.formatBytes(1000, standard: .si), "1.00 KB")
        XCTAssertEqual(Units.formatBytes(1_500_000, standard: .si, fractionDigits: 1), "1.5 MB")
    }

    func testBytesToBits() {
        XCTAssertEqual(Units.bytesPerSecToBitsPerSec(125), 1000, accuracy: 0.0001)
    }

    func testFormatFrequencyHz() {
        XCTAssertEqual(Units.formatFrequencyHz(0), "0 Hz")
        XCTAssertEqual(Units.formatFrequencyHz(500), "500 Hz")
        XCTAssertEqual(Units.formatFrequencyHz(800_000), "800.00 kHz")
        XCTAssertEqual(Units.formatFrequencyHz(800_000_000), "800.00 MHz")
        XCTAssertEqual(Units.formatFrequencyHz(2_400_000_000), "2.40 GHz")
        XCTAssertEqual(Units.formatFrequencyHz(3_200_000_000, fractionDigits: 1), "3.2 GHz")
    }

    func testFormatNetworkRateIEC() {
        XCTAssertEqual(Units.formatNetworkRate(0, unit: .bytesPerSecond, standard: .iec), "0 B/s")
        XCTAssertEqual(Units.formatNetworkRate(512, unit: .bytesPerSecond, standard: .iec), "512 B/s")
        XCTAssertEqual(Units.formatNetworkRate(1024, unit: .bytesPerSecond, standard: .iec), "1.00 KiB/s")
        XCTAssertEqual(Units.formatNetworkRate(1024 * 1024 * 5.5, unit: .bytesPerSecond, standard: .iec, fractionDigits: 1), "5.5 MiB/s")
        XCTAssertEqual(Units.formatNetworkRate(1024 * 1024 * 1024 * 2.0, unit: .bytesPerSecond, standard: .iec), "2.00 GiB/s")
    }

    func testFormatNetworkRateSI() {
        XCTAssertEqual(Units.formatNetworkRate(1000, unit: .bytesPerSecond, standard: .si), "1.00 KB/s")
        XCTAssertEqual(Units.formatNetworkRate(1_500_000, unit: .bytesPerSecond, standard: .si, fractionDigits: 1), "1.5 MB/s")
    }

    func testFormatNetworkRateBits() {
        XCTAssertEqual(Units.formatNetworkRate(0, unit: .bitsPerSecond), "0 bps")
        XCTAssertEqual(Units.formatNetworkRate(125, unit: .bitsPerSecond), "1.00 Kbps") // 125 * 8 = 1000 bps
        XCTAssertEqual(Units.formatNetworkRate(125_000, unit: .bitsPerSecond), "1.00 Mbps") // 125000 * 8 = 1,000,000 bps
        XCTAssertEqual(Units.formatNetworkRate(12_500_000, unit: .bitsPerSecond, fractionDigits: 1), "100.0 Mbps")
        XCTAssertEqual(Units.formatNetworkRate(125_000_000, unit: .bitsPerSecond), "1.00 Gbps")
    }

    func testFormatNetworkRateEdgeCases() {
        XCTAssertEqual(Units.formatNetworkRate(-100, unit: .bytesPerSecond), "0 B/s")
        XCTAssertEqual(Units.formatNetworkRate(.nan, unit: .bytesPerSecond), "0 B/s")
        XCTAssertEqual(Units.formatNetworkRate(.infinity, unit: .bitsPerSecond), "0 bps")
    }

    func testFormatDiskRate() {
        XCTAssertEqual(Units.formatDiskRate(0, standard: .iec), "0 B/s")
        XCTAssertEqual(Units.formatDiskRate(1024 * 1024 * 25.0, standard: .iec), "25.00 MiB/s")
        XCTAssertEqual(Units.formatDiskRate(100_000_000, standard: .si), "100.00 MB/s")
    }
}
