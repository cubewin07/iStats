import XCTest
@testable import iStatsCore

final class ThermalSensorClassifierTests: XCTestCase {

    func testClassifySensors() {
        let cpuReading = SensorReading(name: "CPU Efficiency Core 1", celsius: 52.0)
        let gpuReading = SensorReading(name: "GPU Core Zone", celsius: 61.0)
        let memReading = SensorReading(name: "LPDDR5 Memory Rank 0", celsius: 48.0)
        let ssdReading = SensorReading(name: "NAND Storage Array", celsius: 43.0)
        let batReading = SensorReading(name: "Battery Gas Gauge", celsius: 31.0)
        let miscReading = SensorReading(name: "Ambient Enclosure", celsius: 28.0)

        XCTAssertEqual(ThermalSensorClassifier.classify(cpuReading), .cpu)
        XCTAssertEqual(ThermalSensorClassifier.classify(gpuReading), .gpu)
        XCTAssertEqual(ThermalSensorClassifier.classify(memReading), .memory)
        XCTAssertEqual(ThermalSensorClassifier.classify(ssdReading), .ssd)
        XCTAssertEqual(ThermalSensorClassifier.classify(batReading), .battery)
        XCTAssertNil(ThermalSensorClassifier.classify(miscReading))
    }

    func testSensorsInSampleAndPeakExtraction() {
        let sensors = [
            SensorReading(name: "CPU Performance Core 1", celsius: 72.0),
            SensorReading(name: "CPU Efficiency Core 1", celsius: 65.0),
            SensorReading(name: "GPU Zone 1", celsius: 78.0),
            SensorReading(name: "GPU Zone 2", celsius: 74.0),
            SensorReading(name: "RAM Bank A", celsius: 54.0),
            SensorReading(name: "SSD Flash", celsius: 45.0)
        ]

        let sample = ThermalSample(
            sensors: sensors,
            pressure: .fair
        )

        let cpuSensors = ThermalSensorClassifier.sensors(in: sample, for: .cpu)
        XCTAssertEqual(cpuSensors.count, 2)
        XCTAssertEqual(ThermalSensorClassifier.peakCelsius(in: sample, for: .cpu), 72.0)

        let gpuSensors = ThermalSensorClassifier.sensors(in: sample, for: .gpu)
        XCTAssertEqual(gpuSensors.count, 2)
        XCTAssertEqual(ThermalSensorClassifier.peakCelsius(in: sample, for: .gpu), 78.0)

        let memSensors = ThermalSensorClassifier.sensors(in: sample, for: .memory)
        XCTAssertEqual(memSensors.count, 1)
        XCTAssertEqual(ThermalSensorClassifier.peakCelsius(in: sample, for: .memory), 54.0)

        let batSensors = ThermalSensorClassifier.sensors(in: sample, for: .battery)
        XCTAssertEqual(batSensors.count, 0)
        XCTAssertNil(ThermalSensorClassifier.peakCelsius(in: sample, for: .battery))

        // Peak source returns all sensors and peak temp
        let allSensors = ThermalSensorClassifier.sensors(in: sample, for: .peak)
        XCTAssertEqual(allSensors.count, 6)
        XCTAssertEqual(ThermalSensorClassifier.peakCelsius(in: sample, for: .peak), 78.0)
        XCTAssertEqual(sample.peakTemperatureCelsius, 78.0)
    }

    func testMetricSourceProperties() {
        for source in MetricSource.allCases {
            XCTAssertFalse(source.displayName.isEmpty)
            XCTAssertFalse(source.shortLabel.isEmpty)
            XCTAssertFalse(source.symbolName.isEmpty)
            XCTAssertEqual(source.id, source.rawValue)
        }
    }
}
