import XCTest
import SwiftUI
@testable import iStatsCore
@testable import iStats

final class ThermalSamplerTests: XCTestCase {

    // MARK: - Mock Providers

    private struct MockThermalInfoProvider: ThermalInfoProvider {
        var sensorsToReturn: [SensorReading] = []
        var pressureToReturn: ThermalPressure? = nil
        var shouldThrow: Bool = false

        func thermalSensors() throws -> [SensorReading] {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock hardware access failure")
            }
            return sensorsToReturn
        }

        func thermalPressure() throws -> ThermalPressure? {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock thermal pressure failure")
            }
            return pressureToReturn
        }
    }

    // MARK: - Unit Tests

    func testThermalSamplerCategory() {
        let sampler = ThermalSampler(provider: MockThermalInfoProvider())
        XCTAssertEqual(sampler.category, .thermal)
    }

    func testThermalSamplerWithMockData() throws {
        let mockSensors = [
            SensorReading(name: "CPU Package", celsius: 45.2),
            SensorReading(name: "GPU Cluster", celsius: 42.0),
            SensorReading(name: "Battery", celsius: 28.5)
        ]
        let provider = MockThermalInfoProvider(
            sensorsToReturn: mockSensors,
            pressureToReturn: .nominal
        )
        let sampler = ThermalSampler(provider: provider)

        let sample = try sampler.sample()
        XCTAssertEqual(sample.sensors.count, 3)
        XCTAssertEqual(sample.sensors[0].name, "CPU Package")
        XCTAssertEqual(sample.sensors[0].celsius, 45.2)
        XCTAssertEqual(sample.sensors[1].name, "GPU Cluster")
        XCTAssertEqual(sample.sensors[1].celsius, 42.0)
        XCTAssertEqual(sample.sensors[2].name, "Battery")
        XCTAssertEqual(sample.sensors[2].celsius, 28.5)
        XCTAssertEqual(sample.pressure, .nominal)
    }

    func testThermalSamplerElevatedPressure() throws {
        let mockSensors = [
            SensorReading(name: "CPU Package", celsius: 92.5)
        ]
        let provider = MockThermalInfoProvider(
            sensorsToReturn: mockSensors,
            pressureToReturn: .serious
        )
        let sampler = ThermalSampler(provider: provider)

        let sample = try sampler.sample()
        XCTAssertEqual(sample.pressure, .serious)
        XCTAssertEqual(sample.pressure?.displayName, "Serious")
        XCTAssertTrue(sample.pressure?.isElevated == true)
    }

    func testThermalSamplerDegradedSensorsWithPressure() throws {
        // Degraded state: hardware sensors unavailable, but OS thermal pressure is available (Requirement 3.3, 3.4)
        let provider = MockThermalInfoProvider(
            sensorsToReturn: [],
            pressureToReturn: .fair
        )
        let sampler = ThermalSampler(provider: provider)

        let sample = try sampler.sample()
        XCTAssertTrue(sample.sensors.isEmpty)
        XCTAssertEqual(sample.pressure, .fair)
    }

    func testThermalSamplerUnavailableThrowsUnsupported() {
        // Complete unavailable state: both sensors and pressure unavailable (Requirement 3.3)
        let provider = MockThermalInfoProvider(
            sensorsToReturn: [],
            pressureToReturn: nil
        )
        let sampler = ThermalSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample()) { error in
            guard case SamplerError.unsupported = error else {
                XCTFail("Expected SamplerError.unsupported, got: \(error)")
                return
            }
        }
    }

    func testThermalSamplerProviderFailureThrows() {
        let provider = MockThermalInfoProvider(shouldThrow: true)
        let sampler = ThermalSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample())
    }

    func testCalculateSampleFiltersInvalidTemperatures() {
        let rawSensors = [
            SensorReading(name: "Valid Sensor", celsius: 50.0),
            SensorReading(name: "Absolute Zero Error", celsius: -273.15),
            SensorReading(name: "Zero Reading Error", celsius: 0.0),
            SensorReading(name: "Overheat Glitch", celsius: 250.0),
            SensorReading(name: "NaN Error", celsius: .nan),
            SensorReading(name: "Infinity Error", celsius: .infinity)
        ]

        let sample = ThermalSampler.calculateSample(sensors: rawSensors, pressure: .nominal)
        XCTAssertEqual(sample.sensors.count, 1)
        XCTAssertEqual(sample.sensors[0].name, "Valid Sensor")
        XCTAssertEqual(sample.sensors[0].celsius, 50.0)
        XCTAssertEqual(sample.pressure, .nominal)
    }

    func testTemperatureUnitFormattingAcrossSensors() {
        let sensor = SensorReading(name: "CPU Package", celsius: 100.0)
        let celsiusFormatted = Units.formatTemperatureSensor(sensor, unit: .celsius)
        let fahrenheitFormatted = Units.formatTemperatureSensor(sensor, unit: .fahrenheit)

        XCTAssertEqual(celsiusFormatted, "100.0 °C")
        XCTAssertEqual(fahrenheitFormatted, "212.0 °F")
    }

    // MARK: - Live Hardware Telemetry

    func testLiveHostThermalInfoProviderAndSampler() throws {
        let provider = HostThermalInfoProvider()
        let pressure = try? provider.thermalPressure()

        // Thermal pressure is standard macOS public API and should always resolve on macOS 13+
        XCTAssertNotNil(pressure)

        let sampler = ThermalSampler(provider: provider)
        let sample = try sampler.sample()

        // Sample must be valid and not crash
        XCTAssertNotNil(sample.pressure)
        for sensor in sample.sensors {
            XCTAssertFalse(sensor.name.isEmpty)
            XCTAssertTrue(sensor.celsius > 0.0 && sensor.celsius < 150.0, "Sensor \(sensor.name) has unexpected temp \(sensor.celsius)")
        }

        print("Live Thermal Sample on Host: Sensors=\(sample.sensors.count), Pressure=\(String(describing: sample.pressure))")
        for s in sample.sensors {
            print("  - \(s.name): \(String(format: "%.1f", s.celsius)) °C (\(String(format: "%.1f", Units.celsiusToFahrenheit(s.celsius))) °F)")
        }
    }

    // MARK: - UI Rendering & View Model Tests

    @MainActor
    func testThermalSummaryViewRendersWithData() {
        let sample = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 48.0),
                SensorReading(name: "GPU Cluster", celsius: 44.0),
                SensorReading(name: "Battery", celsius: 29.0)
            ],
            pressure: .nominal
        )
        let history = [
            Sample(value: sample, availability: .available)
        ]

        let view = ThermalSummaryView(
            sample: sample,
            history: history,
            temperatureUnit: .celsius
        )

        XCTAssertNotNil(view.body)
    }

    @MainActor
    func testThermalSummaryViewRendersFahrenheit() {
        let sample = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 50.0)
            ],
            pressure: .fair
        )

        let view = ThermalSummaryView(
            sample: sample,
            history: [],
            temperatureUnit: .fahrenheit
        )

        XCTAssertNotNil(view.body)
    }

    @MainActor
    func testDetailPopoverViewIncludesThermal() {
        let thermalSample = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Package", celsius: 46.5)
            ],
            pressure: .nominal
        )

        let popover = DetailPopoverView(
            thermalSample: thermalSample
        )

        XCTAssertNotNil(popover.body)
    }
}
