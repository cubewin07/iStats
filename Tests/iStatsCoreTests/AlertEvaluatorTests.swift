import XCTest
@testable import iStatsCore

final class AlertEvaluatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testDoesNotFireBeforeSustainWindowAndFiresOnceAtSustain() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule(kind: .cpu, enabled: true, threshold: 90, sustainSeconds: 10, cooldownSeconds: 300)

        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0), .none)
        XCTAssertEqual(evaluator.state(for: .cpu).pendingSince, t0)

        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 94, now: t0.addingTimeInterval(5)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 92, now: t0.addingTimeInterval(9.9)), .none)

        // Reaching sustainSeconds fires once and disarms.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 91, now: t0.addingTimeInterval(10)), .fire)
        XCTAssertFalse(evaluator.state(for: .cpu).armed)
        XCTAssertNil(evaluator.state(for: .cpu).pendingSince)
        XCTAssertEqual(evaluator.state(for: .cpu).lastFired, t0.addingTimeInterval(10))

        // Continuing above threshold does not re-fire.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 96, now: t0.addingTimeInterval(15)), .none)
    }

    func testBriefDipBelowThresholdResetsPendingSustain() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule(kind: .cpu, enabled: true, threshold: 90, sustainSeconds: 10, cooldownSeconds: 300)

        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 89, now: t0.addingTimeInterval(6)), .none)
        XCTAssertNil(evaluator.state(for: .cpu).pendingSince)

        // New breach restarts the 10-second sustain clock.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(7)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(12)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(17)), .fire)
    }

    func testHysteresisPreventsFlappingAndClearsOnRecovery() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule(kind: .cpu, enabled: true, threshold: 90, sustainSeconds: 0, cooldownSeconds: 30)
        // Margin for CPU@90 is 5% of 90 = 4.5 -> must reach <= 85.5 to re-arm.

        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 92, now: t0), .fire)
        XCTAssertFalse(evaluator.state(for: .cpu).armed)

        // Dip to 88 is below 90, but inside hysteresis band (> 85.5): stays disarmed.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 88, now: t0.addingTimeInterval(35)), .none)
        XCTAssertFalse(evaluator.state(for: .cpu).armed)

        // Flapping back to 91 does not re-fire while disarmed.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 91, now: t0.addingTimeInterval(40)), .none)

        // Crossing back below 85.5 re-arms and emits .clear.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 85.0, now: t0.addingTimeInterval(45)), .clear)
        XCTAssertTrue(evaluator.state(for: .cpu).armed)

        // Next normal reading emits .none.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 80.0, now: t0.addingTimeInterval(50)), .none)

        // Now armed and past cooldown -> fires again.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 93, now: t0.addingTimeInterval(55)), .fire)
    }

    func testCooldownBlocksRefireAfterRearm() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule(kind: .cpu, enabled: true, threshold: 90, sustainSeconds: 0, cooldownSeconds: 300)

        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0), .fire)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 70, now: t0.addingTimeInterval(10)), .clear)

        // Re-armed, but within 300s cooldown: blocked.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(100)), .none)
        XCTAssertTrue(evaluator.state(for: .cpu).armed)

        // Once 300s have elapsed since lastFired, fires again.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(300)), .fire)
    }

    func testTemperatureUsesTwoDegreeHysteresis() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule(kind: .temperature, enabled: true, threshold: 90, sustainSeconds: 0, cooldownSeconds: 30)

        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 91, now: t0), .fire)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 88.5, now: t0.addingTimeInterval(40)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 88.0, now: t0.addingTimeInterval(45)), .clear)
    }

    func testBelowComparisonForBatteryLow() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule(kind: .batteryLow, enabled: true, threshold: 20, comparison: .below, sustainSeconds: 5, cooldownSeconds: 60)

        // 25% is safe
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 25, now: t0), .none)
        // Drop to 18% -> pending
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 18, now: t0.addingTimeInterval(1)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 18, now: t0.addingTimeInterval(6)), .fire)

        // Hysteresis for 20% (5% = 1%): 20.5% stays disarmed, >= 21% re-arms and clears.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 20.5, now: t0.addingTimeInterval(70)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 21.0, now: t0.addingTimeInterval(75)), .clear)
    }

    func testUnavailableReadingResetsPendingState() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule(kind: .cpu, enabled: true, threshold: 90, sustainSeconds: 10, cooldownSeconds: 60)

        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0), .none)
        XCTAssertNotNil(evaluator.state(for: .cpu).pendingSince)

        // Nil reading resets pendingSince.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: nil, now: t0.addingTimeInterval(6)), .none)
        XCTAssertNil(evaluator.state(for: .cpu).pendingSince)

        // Subsequent reading must sustain full 10s from t0+8.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(8)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(14)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(18)), .fire)
    }

    func testBackwardsClockJumpIsSafe() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule(kind: .cpu, enabled: true, threshold: 90, sustainSeconds: 10, cooldownSeconds: 60)

        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(100)), .none)
        // Clock jumps backwards by 50s -> pendingSince clamps to t0+50 instead of firing early or stalling.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(50)), .none)
        XCTAssertEqual(evaluator.state(for: .cpu).pendingSince, t0.addingTimeInterval(50))

        // Full 10s from t0+50 fires cleanly.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(59)), .none)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(60)), .fire)

        // Re-arm and test backwards clock jump during cooldown.
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 70, now: t0.addingTimeInterval(65)), .clear)
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(10)), .none)
        XCTAssertEqual(evaluator.state(for: .cpu).lastFired, t0.addingTimeInterval(10))
        // After 60s from clamped lastFired (t0+70), rule can fire again (does not wait until t0+120).
        XCTAssertEqual(evaluator.evaluate(rule: rule, value: 95, now: t0.addingTimeInterval(70)), .fire)
    }

    func testDisabledRuleNeverFiresAndResetsPending() {
        var evaluator = AlertEvaluator()
        let enabledRule = AlertRule(kind: .disk, enabled: true, threshold: 90, sustainSeconds: 10, cooldownSeconds: 60)
        let disabledRule = AlertRule(kind: .disk, enabled: false, threshold: 90, sustainSeconds: 10, cooldownSeconds: 60)

        XCTAssertEqual(evaluator.evaluate(rule: enabledRule, value: 95, now: t0), .none)
        XCTAssertEqual(evaluator.evaluate(rule: disabledRule, value: 95, now: t0.addingTimeInterval(20)), .none)
        XCTAssertNil(evaluator.state(for: .disk).pendingSince)
        XCTAssertTrue(evaluator.state(for: .disk).armed)
    }
}
