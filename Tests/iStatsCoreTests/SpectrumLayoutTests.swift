import XCTest
@testable import iStatsCore

final class SpectrumLayoutTests: XCTestCase {

    func testEmptyMarkersReturnsEmpty() {
        let placed = SpectrumLayout.place(markers: [], width: 300)
        XCTAssertTrue(placed.isEmpty)
    }

    func testSingleMarkerPlacedCorrectly() {
        // 70°C is midway between 30°C and 110°C (range 80, delta 40 -> 0.5)
        let marker = SpectrumMarker(id: "cpu", value: 70.0, label: "CPU")
        let placed = SpectrumLayout.place(markers: [marker], width: 200, minSpacing: 10)

        XCTAssertEqual(placed.count, 1)
        XCTAssertEqual(placed[0].id, "cpu")
        XCTAssertEqual(placed[0].x, 100.0, accuracy: 0.001)
        XCTAssertEqual(placed[0].tier, 0)
    }

    func testPreservesOrderAscending() {
        let markers = [
            SpectrumMarker(id: "gpu", value: 80.0, label: "GPU"),
            SpectrumMarker(id: "cpu", value: 50.0, label: "CPU"),
            SpectrumMarker(id: "ssd", value: 35.0, label: "SSD")
        ]
        let placed = SpectrumLayout.place(markers: markers, width: 200)

        XCTAssertEqual(placed.count, 3)
        XCTAssertEqual(placed[0].id, "ssd")
        XCTAssertEqual(placed[1].id, "cpu")
        XCTAssertEqual(placed[2].id, "gpu")
    }

    func testCollisionAssignsDifferentTiers() {
        // Two markers very close: 50°C and 51°C. At width 200, (1/80)*200 = 2.5 pt apart (< minSpacing 14).
        let markers = [
            SpectrumMarker(id: "m1", value: 50.0, label: "CPU"),
            SpectrumMarker(id: "m2", value: 51.0, label: "GPU")
        ]
        let placed = SpectrumLayout.place(markers: markers, width: 200, minSpacing: 14)

        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(placed[0].tier, 0)
        XCTAssertEqual(placed[1].tier, 1, "Colliding marker must be stacked to higher tier")
    }

    func testIdenticalTemperaturesStackCleanly() {
        // Three sensors with identical 60°C reading
        let markers = [
            SpectrumMarker(id: "c1", value: 60.0, label: "Core 1"),
            SpectrumMarker(id: "c2", value: 60.0, label: "Core 2"),
            SpectrumMarker(id: "c3", value: 60.0, label: "Core 3")
        ]
        let placed = SpectrumLayout.place(markers: markers, width: 200, minSpacing: 10)

        XCTAssertEqual(placed.count, 3)
        XCTAssertEqual(placed[0].tier, 0)
        XCTAssertEqual(placed[1].tier, 1)
        XCTAssertEqual(placed[2].tier, 2)
        XCTAssertEqual(placed[0].x, placed[1].x, accuracy: 0.001)
        XCTAssertEqual(placed[1].x, placed[2].x, accuracy: 0.001)
    }

    func testFarApartMarkersStayOnTierZero() {
        let markers = [
            SpectrumMarker(id: "cold", value: 35.0, label: "Cold"),
            SpectrumMarker(id: "medium", value: 70.0, label: "Med"),
            SpectrumMarker(id: "hot", value: 105.0, label: "Hot")
        ]
        let placed = SpectrumLayout.place(markers: markers, width: 200, minSpacing: 14)

        XCTAssertEqual(placed.count, 3)
        XCTAssertEqual(placed[0].tier, 0)
        XCTAssertEqual(placed[1].tier, 0)
        XCTAssertEqual(placed[2].tier, 0)
    }

    func testPlaceHorizontalEnforcesMinSpacing() {
        let markers = [
            SpectrumMarker(id: "a", value: 50.0, label: "A"),
            SpectrumMarker(id: "b", value: 50.5, label: "B"),
            SpectrumMarker(id: "c", value: 51.0, label: "C")
        ]
        let placed = SpectrumLayout.placeHorizontal(markers: markers, width: 200, minSpacing: 15)

        XCTAssertEqual(placed.count, 3)
        XCTAssertGreaterThanOrEqual(placed[1].x - placed[0].x, 15.0 - 0.001)
        XCTAssertGreaterThanOrEqual(placed[2].x - placed[1].x, 15.0 - 0.001)
        XCTAssertLessThanOrEqual(placed[2].x, 200.0)
    }
}
