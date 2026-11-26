import XCTest
@testable import iStatsCore

final class AlertRuleTests: XCTestCase {
    func testDefaultsMatchV1Defaults() {
        let rules = Dictionary(uniqueKeysWithValues: AlertRule.defaults.map { ($0.kind, $0) })
        XCTAssertEqual(rules.count, AlertKind.allCases.count)
        XCTAssertEqual(rules[.cpu]?.threshold, 90)
        XCTAssertEqual(rules[.memory]?.threshold, 85)
        XCTAssertEqual(rules[.batteryLow]?.threshold, 20)
        XCTAssertEqual(rules[.batteryLow]?.comparison, .below)
        XCTAssertEqual(rules[.temperature]?.threshold, 90)
        XCTAssertEqual(rules[.disk]?.threshold, 90)
        for rule in rules.values {
            XCTAssertFalse(rule.enabled)
            XCTAssertEqual(rule.sustainSeconds, 0)
            XCTAssertEqual(rule.cooldownSeconds, 300)
            XCTAssertNil(rule.target)
            if rule.kind != .batteryLow { XCTAssertEqual(rule.comparison, .above) }
        }
    }

    func testCodableRoundTrip() throws {
        let rule = AlertRule(
            kind: .disk, enabled: true, threshold: 92, comparison: .above,
            sustainSeconds: 60, cooldownSeconds: 900, target: "/Volumes/Data"
        )
        let data = try JSONEncoder().encode([rule] + AlertRule.defaults)
        let decoded = try JSONDecoder().decode([AlertRule].self, from: data)
        XCTAssertEqual(decoded.first, rule)
        XCTAssertEqual(Array(decoded.dropFirst()), AlertRule.defaults)
    }

    func testClampedEnforcesRanges() {
        XCTAssertEqual(AlertRule(kind: .cpu, threshold: 10).clamped().threshold, 50)
        XCTAssertEqual(AlertRule(kind: .temperature, threshold: 500).clamped().threshold, 105)
        XCTAssertEqual(AlertRule(kind: .batteryLow, threshold: 1).clamped().threshold, 5)
        XCTAssertEqual(AlertRule(kind: .disk, threshold: 99).clamped().threshold, 98)
        XCTAssertEqual(AlertRule(kind: .cpu, sustainSeconds: -5, cooldownSeconds: 1).clamped().sustainSeconds, 0)
        XCTAssertEqual(AlertRule(kind: .cpu, cooldownSeconds: 1).clamped().cooldownSeconds, 30)
    }

    func testIsTriggeredFollowsComparison() {
        XCTAssertTrue(AlertRule(kind: .cpu, threshold: 90).isTriggered(by: 95))
        XCTAssertFalse(AlertRule(kind: .cpu, threshold: 90).isTriggered(by: 80))
        XCTAssertTrue(AlertRule(kind: .batteryLow, threshold: 20).isTriggered(by: 15))
        XCTAssertFalse(AlertRule(kind: .batteryLow, threshold: 20).isTriggered(by: 50))
    }

    func testV1KeyMapping() {
        let suite = "iStats.test.alertrule.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Nothing set: factory defaults, disabled, 300s cooldown.
        XCTAssertEqual(PreferencesMigration.legacyAlertRules(defaults), AlertRule.defaults)

        let keys = PreferencesMigration.LegacyAlertKeys.self
        defaults.set(true, forKey: keys.cpuEnabled)
        defaults.set(75.0, forKey: keys.cpuThreshold)
        defaults.set(true, forKey: keys.batteryLowEnabled)
        defaults.set(15, forKey: keys.batteryLowThreshold) // stored as Int in v1
        defaults.set(true, forKey: keys.batteryFullEnabled)
        defaults.set(80.0, forKey: keys.thermalThreshold)
        defaults.set(600.0, forKey: keys.cooldown)

        let rules = Dictionary(uniqueKeysWithValues: PreferencesMigration.legacyAlertRules(defaults).map { ($0.kind, $0) })
        XCTAssertEqual(rules[.cpu]?.enabled, true)
        XCTAssertEqual(rules[.cpu]?.threshold, 75)
        XCTAssertEqual(rules[.batteryLow]?.threshold, 15)
        XCTAssertEqual(rules[.batteryLow]?.enabled, true)
        XCTAssertEqual(rules[.batteryFull]?.enabled, true)
        XCTAssertEqual(rules[.temperature]?.threshold, 80)
        XCTAssertEqual(rules[.temperature]?.enabled, false)
        XCTAssertEqual(rules[.memory]?.threshold, 85)
        XCTAssertEqual(rules[.disk]?.threshold, 90)
        XCTAssertTrue(rules.values.allSatisfy { $0.cooldownSeconds == 600 })
    }
}
