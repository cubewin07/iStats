import XCTest
@testable import iStatsCore

final class FanMathTests: XCTestCase {

    func testZeroOrNegativeRPMReturnsZeroSpeed() {
        XCTAssertEqual(FanMath.visualSpeed(rpm: 0), 0.0)
        XCTAssertEqual(FanMath.visualSpeed(rpm: -100), 0.0)
        XCTAssertEqual(FanMath.visualSpeed(rpm: 0.0), 0.0)
    }

    func testMinRPMSpeedsToMinVisualSpeed() {
        let speed = FanMath.visualSpeed(rpm: 1200, min: 1200, max: 6000)
        XCTAssertEqual(speed, FanMath.minVisualRPS, accuracy: 0.001)
    }

    func testMaxRPMSpeedsToMaxVisualSpeed() {
        let speed = FanMath.visualSpeed(rpm: 6000, min: 1200, max: 6000)
        XCTAssertEqual(speed, FanMath.maxVisualRPS, accuracy: 0.001)
    }

    func testSpeedIsStrictlyCappedAtMaxVisualRPS() {
        let extremeSpeed = FanMath.visualSpeed(rpm: 12000, min: 1000, max: 5000)
        XCTAssertEqual(extremeSpeed, FanMath.maxVisualRPS)
    }

    func testFallbackBoundsWhenBoundsAreNil() {
        let halfSpeed = FanMath.visualSpeed(rpm: 3000, min: nil, max: nil)
        let expected = FanMath.minVisualRPS + (0.5 * (FanMath.maxVisualRPS - FanMath.minVisualRPS))
        XCTAssertEqual(halfSpeed, expected, accuracy: 0.001)
    }

    func testFractionCalculation() {
        XCTAssertEqual(FanMath.fraction(rpm: 0, min: 1000, max: 5000), 0.0)
        XCTAssertEqual(FanMath.fraction(rpm: 3000, min: 1000, max: 5000), 0.5, accuracy: 0.001)
        XCTAssertEqual(FanMath.fraction(rpm: 5000, min: 1000, max: 5000), 1.0, accuracy: 0.001)
        XCTAssertEqual(FanMath.fraction(rpm: 6000, min: 1000, max: 5000), 1.0)
    }

    func testRotationDegreesDeterministic() {
        // 1.0 rps at 0.5s = 180 degrees
        let deg = FanMath.rotationDegrees(time: 0.5, speedRPS: 1.0)
        XCTAssertEqual(deg, 180.0, accuracy: 0.001)

        // 1.0 rps at 1.0s = 0 degrees (360 mod 360)
        let fullRev = FanMath.rotationDegrees(time: 1.0, speedRPS: 1.0)
        XCTAssertEqual(fullRev, 0.0, accuracy: 0.001)
    }
}
