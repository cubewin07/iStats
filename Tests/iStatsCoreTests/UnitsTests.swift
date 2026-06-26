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
}
