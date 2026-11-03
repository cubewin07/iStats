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

    func testStepRotationDegreesIncremental() {
        // At 1.0 rps, a 16.67ms step (60fps) advances by 6 degrees
        let next = FanMath.stepRotationDegrees(currentDegrees: 45.0, dt: 1.0 / 60.0, speedRPS: 1.0)
        XCTAssertEqual(next, 51.0, accuracy: 0.01)

        // Wraps cleanly at 360 degrees
        let wrapped = FanMath.stepRotationDegrees(currentDegrees: 358.0, dt: 1.0 / 60.0, speedRPS: 1.0)
        XCTAssertEqual(wrapped, 4.0, accuracy: 0.01)

        // Clamps dt to prevent huge jump
        let clamped = FanMath.stepRotationDegrees(currentDegrees: 0.0, dt: 10.0, speedRPS: 1.0)
        XCTAssertEqual(clamped, 36.0, accuracy: 0.01) // 0.1 * 1.0 * 360 = 36 deg
    }
}

