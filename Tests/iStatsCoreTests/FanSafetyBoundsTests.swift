import XCTest
@testable import iStatsCore

final class FanSafetyBoundsTests: XCTestCase {

    // MARK: - FanSafetyBounds.clamp Tests (Requirement 4.3, ADR 0004)

    func testClampWithinValidRange() {
        let clamped = FanSafetyBounds.clamp(targetRPM: 2500, minRPM: 1200, maxRPM: 5500)
        XCTAssertEqual(clamped, 2500)
    }

    func testClampBelowMinimumRPM() {
        // Clamping below minRPM prevents under-cooling and dangerous thermal throttling
        let clamped = FanSafetyBounds.clamp(targetRPM: 800, minRPM: 1200, maxRPM: 5500)
        XCTAssertEqual(clamped, 1200)
    }

    func testClampAboveMaximumRPM() {
        // Clamping above maxRPM protects physical fan bearings from over-speed wear
        let clamped = FanSafetyBounds.clamp(targetRPM: 6500, minRPM: 1200, maxRPM: 5500)
        XCTAssertEqual(clamped, 5500)
    }

    func testClampNegativeTarget() {
        let clamped = FanSafetyBounds.clamp(targetRPM: -500, minRPM: 1000, maxRPM: 5000)
        XCTAssertEqual(clamped, 1000)

        let clampedNoMin = FanSafetyBounds.clamp(targetRPM: -500, minRPM: nil, maxRPM: 5000)
        XCTAssertEqual(clampedNoMin, 0)
    }

    func testClampWithNilBounds() {
        let clampedBothNil = FanSafetyBounds.clamp(targetRPM: 3000, minRPM: nil, maxRPM: nil)
        XCTAssertEqual(clampedBothNil, 3000)

        let clampedMinOnly = FanSafetyBounds.clamp(targetRPM: 800, minRPM: 1500, maxRPM: nil)
        XCTAssertEqual(clampedMinOnly, 1500)

        let clampedMaxOnly = FanSafetyBounds.clamp(targetRPM: 6000, minRPM: nil, maxRPM: 4500)
        XCTAssertEqual(clampedMaxOnly, 4500)
    }

    func testClampWithInvertedBounds() {
        // If hardware or driver erroneously reports max < min, failsafe to min
        let clamped = FanSafetyBounds.clamp(targetRPM: 3000, minRPM: 4000, maxRPM: 2000)
        XCTAssertEqual(clamped, 4000)
    }

    // MARK: - FanSafetyBounds.validate Tests (Requirements 4.2, 4.3)

    func testValidateSuccess() {
        let result = FanSafetyBounds.validate(targetRPM: 2400, minRPM: 1200, maxRPM: 5000)
        switch result {
        case .success(let rpm):
            XCTAssertEqual(rpm, 2400)
        case .failure(let error):
            XCTFail("Expected success, but got error: \(error)")
        }
    }

    func testValidateTargetBelowMinimum() {
        let result = FanSafetyBounds.validate(targetRPM: 1000, minRPM: 1200, maxRPM: 5000)
        switch result {
        case .success:
            XCTFail("Expected failure for target below minimum")
        case .failure(let error):
            XCTAssertEqual(error, .targetBelowMinimum(target: 1000, minimum: 1200))
        }
    }

    func testValidateTargetAboveMaximum() {
        let result = FanSafetyBounds.validate(targetRPM: 6000, minRPM: 1200, maxRPM: 5000)
        switch result {
        case .success:
            XCTFail("Expected failure for target above maximum")
        case .failure(let error):
            XCTAssertEqual(error, .targetAboveMaximum(target: 6000, maximum: 5000))
        }
    }

    func testValidateBoundsUnavailable() {
        let result1 = FanSafetyBounds.validate(targetRPM: 2000, minRPM: nil, maxRPM: 5000)
        XCTAssertEqual(result1, .failure(.boundsUnavailable))

        let result2 = FanSafetyBounds.validate(targetRPM: 2000, minRPM: 1000, maxRPM: nil)
        XCTAssertEqual(result2, .failure(.boundsUnavailable))
    }

    func testValidateInvalidBounds() {
        let result = FanSafetyBounds.validate(targetRPM: 2000, minRPM: 5000, maxRPM: 1000)
        XCTAssertEqual(result, .failure(.invalidBounds(min: 5000, max: 1000)))
    }

    // MARK: - FanControlPolicy & Modes Tests (Requirements 4.4, 13.2, ADR 0004)

    func testFanControlPolicyConstants() {
        XCTAssertEqual(FanControlPolicy.defaultMode, .systemAutomatic)
        XCTAssertEqual(FanControlPolicy.statusLabel, "System Controlled")
        XCTAssertFalse(FanControlPolicy.readOnlyExplanation.isEmpty)
        XCTAssertTrue(FanControlPolicy.readOnlyExplanation.contains("macOS system firmware"))
        XCTAssertFalse(FanControlPolicy.privilegePostureDescription.isEmpty)
        XCTAssertTrue(FanControlPolicy.privilegePostureDescription.contains("zero privilege escalation"))
    }

    func testFanControlModeEnumAndCodable() throws {
        XCTAssertEqual(FanControlMode.allCases.count, 3)
        XCTAssertEqual(FanControlMode.systemAutomatic.rawValue, "automatic")
        XCTAssertEqual(FanControlMode.manual.rawValue, "manual")
        XCTAssertEqual(FanControlMode.unsupported.rawValue, "unsupported")

        let mode = FanControlMode.systemAutomatic
        let data = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(FanControlMode.self, from: data)
        XCTAssertEqual(decoded, mode)
    }

    func testFanSampleIsFanless() {
        let emptySample = FanSample(fans: [])
        XCTAssertTrue(emptySample.isFanless)

        let fanSample = FanSample(fans: [FanReading(name: "Fan 1", rpm: 2000)])
        XCTAssertFalse(fanSample.isFanless)
    }
}
