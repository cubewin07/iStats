import XCTest
@testable import iStatsCore

final class AvailabilityTests: XCTestCase {

    func testAvailableState() {
        let availability = Availability.available
        XCTAssertTrue(availability.isAvailable)
        XCTAssertNil(availability.unavailableReason)
    }

    func testUnavailableState() {
        let reason = "Sensor not detected on M1 Mac"
        let availability = Availability.unavailable(reason: reason)
        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.unavailableReason, reason)
    }

    func testAvailabilityEquality() {
        XCTAssertEqual(Availability.available, Availability.available)
        XCTAssertEqual(Availability.unavailable(reason: "timeout"), Availability.unavailable(reason: "timeout"))
        XCTAssertNotEqual(Availability.available, Availability.unavailable(reason: "denied"))
        XCTAssertNotEqual(Availability.unavailable(reason: "a"), Availability.unavailable(reason: "b"))
    }

    func testAvailabilityCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let available = Availability.available
        let availableData = try encoder.encode(available)
        let decodedAvailable = try decoder.decode(Availability.self, from: availableData)
        XCTAssertEqual(available, decodedAvailable)

        let unavailable = Availability.unavailable(reason: "hardware unsupported")
        let unavailableData = try encoder.encode(unavailable)
        let decodedUnavailable = try decoder.decode(Availability.self, from: unavailableData)
        XCTAssertEqual(unavailable, decodedUnavailable)
    }

    func testSampleInitializationWithDefaults() {
        let dateBefore = Date()
        let sample = Sample(value: 42)
        let dateAfter = Date()

        XCTAssertEqual(sample.value, 42)
        XCTAssertTrue(sample.availability.isAvailable)
        XCTAssertGreaterThanOrEqual(sample.timestamp, dateBefore)
        XCTAssertLessThanOrEqual(sample.timestamp, dateAfter)
    }

    func testSampleInitializationExplicit() {
        let customDate = Date(timeIntervalSince1970: 1000)
        let sample = Sample(value: "test", timestamp: customDate, availability: .unavailable(reason: "test failure"))

        XCTAssertEqual(sample.value, "test")
        XCTAssertEqual(sample.timestamp, customDate)
        XCTAssertEqual(sample.availability, .unavailable(reason: "test failure"))
    }

    func testSampleEquality() {
        let date = Date(timeIntervalSince1970: 500)
        let sample1 = Sample(value: 100, timestamp: date, availability: .available)
        let sample2 = Sample(value: 100, timestamp: date, availability: .available)
        let sample3 = Sample(value: 200, timestamp: date, availability: .available)

        XCTAssertEqual(sample1, sample2)
        XCTAssertNotEqual(sample1, sample3)
    }

    func testSampleCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let original = Sample(value: "hello", timestamp: Date(timeIntervalSince1970: 1000), availability: .available)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Sample<String>.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
