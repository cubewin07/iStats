import XCTest
import iStatsCore

final class MotionMathTests: XCTestCase {

    func testValueDurationFormula() {
        // Zero or negative interval should be 0 duration
        XCTAssertEqual(MotionMath.valueDuration(interval: 0.0), 0.0)
        XCTAssertEqual(MotionMath.valueDuration(interval: -1.0), 0.0)

        // 0.5s interval -> 0.3s
        XCTAssertEqual(MotionMath.valueDuration(interval: 0.5), 0.3, accuracy: 0.001)

        // 1.0s interval -> 0.6s
        XCTAssertEqual(MotionMath.valueDuration(interval: 1.0), 0.6, accuracy: 0.001)

        // 2.0s interval capped at 0.6s
        XCTAssertEqual(MotionMath.valueDuration(interval: 2.0), 0.6, accuracy: 0.001)

        // 5.0s interval capped at 0.6s
        XCTAssertEqual(MotionMath.valueDuration(interval: 5.0), 0.6, accuracy: 0.001)
    }

    func testMotionPolicyResolution() {
        // Not visible always resolves to frozen regardless of other flags
        XCTAssertEqual(
            MotionPolicy.resolve(reduceMotion: false, lowPower: false, paused: false, visible: false),
            .frozen
        )
        XCTAssertEqual(
            MotionPolicy.resolve(reduceMotion: true, lowPower: true, paused: true, visible: false),
            .frozen
        )

        // Visible but paused -> frozen
        XCTAssertEqual(
            MotionPolicy.resolve(reduceMotion: false, lowPower: false, paused: true, visible: true),
            .frozen
        )

        // Visible but low power -> frozen
        XCTAssertEqual(
            MotionPolicy.resolve(reduceMotion: false, lowPower: true, paused: false, visible: true),
            .frozen
        )

        // Visible, active, but reduce motion enabled -> reduced
        XCTAssertEqual(
            MotionPolicy.resolve(reduceMotion: true, lowPower: false, paused: false, visible: true),
            .reduced
        )

        // Normal healthy visible state -> full
        XCTAssertEqual(
            MotionPolicy.resolve(reduceMotion: false, lowPower: false, paused: false, visible: true),
            .full
        )
    }

    func testMotionPolicyCapabilities() {
        XCTAssertTrue(MotionPolicy.full.allowsContinuousAnimation)
        XCTAssertTrue(MotionPolicy.full.allowsEasing)

        XCTAssertFalse(MotionPolicy.reduced.allowsContinuousAnimation)
        XCTAssertTrue(MotionPolicy.reduced.allowsEasing)

        XCTAssertFalse(MotionPolicy.frozen.allowsContinuousAnimation)
        XCTAssertFalse(MotionPolicy.frozen.allowsEasing)
    }
}
