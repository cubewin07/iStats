import XCTest
import Foundation
import iStatsCore
@testable import iStats

final class Phase5ValidationTests: XCTestCase {

    func testLiveValidationThermalFanGPU() throws {
        print("\n=======================================================")
        print("PHASE 5 LIVE METRIC VALIDATION (Thermal, Fan, GPU)")
        print("=======================================================")

        // 1. THERMAL SENSORS & PRESSURE VALIDATION
        print("\n--- 1. THERMAL SENSORS & SYSTEM PRESSURE ---")
        let thermalProvider = HostThermalInfoProvider()
        let thermalSampler = ThermalSampler(provider: thermalProvider)
        let thermalSample = try thermalSampler.sample()

        print("Total Active Thermal Sensors Detected: \(thermalSample.sensors.count)")
        if let pressure = thermalSample.pressure {
            print("System Thermal Pressure State:        \(pressure.displayName) (\(pressure.rawValue))")
            print("Thermal Pressure Elevated:            \(pressure.isElevated ? "YES" : "NO")")
        } else {
            print("System Thermal Pressure State:        Unavailable / Unexposed")
        }

        print("\n\(pad("Sensor Channel", 28)) | \(pad("Temp (°C)", 12)) | \(pad("Temp (°F)", 12)) | Status")
        print(String(repeating: "-", count: 68))
        for sensor in thermalSample.sensors {
            let cStr = Units.formatTemperature(sensor.celsius, unit: .celsius)
            let fStr = Units.formatTemperature(sensor.celsius, unit: .fahrenheit)
            let status = (sensor.celsius > 0.0 && sensor.celsius < 110.0) ? "VALID" : "OUT_OF_RANGE"
            print("\(pad(sensor.name, 28)) | \(pad(cStr, 12)) | \(pad(fStr, 12)) | \(status)")
            XCTAssertGreaterThan(sensor.celsius, 0.0, "Sensor \(sensor.name) temperature should be positive")
            XCTAssertLessThan(sensor.celsius, 120.0, "Sensor \(sensor.name) temperature should be below safety limit")
        }

        if let peak = thermalSample.sensors.max(by: { $0.celsius < $1.celsius }) {
            print("\nPeak Thermal Sensor: \(peak.name) at \(Units.formatTemperature(peak.celsius, unit: .celsius)) (\(Units.formatTemperature(peak.celsius, unit: .fahrenheit)))")
        }

        // 2. FAN TELEMETRY & SAFETY BOUNDS VALIDATION
        print("\n--- 2. FAN TELEMETRY & SAFETY POLICY ---")
        let fanProvider = HostFanInfoProvider()
        let fanSampler = FanSampler(provider: fanProvider)
        let fanSample = try fanSampler.sample()

        print("System Fan Count:     \(fanSample.fans.count) \(fanSample.isFanless ? "(Fanless Hardware)" : "Active Fans")")
        print("Fan Control Policy:   \(FanControlPolicy.statusLabel) (\(FanControlPolicy.readOnlyExplanation))")

        if !fanSample.isFanless {
            print("\n\(pad("Fan Descriptor", 20)) | \(pad("Actual RPM", 12)) | \(pad("Min RPM", 10)) | \(pad("Max RPM", 10)) | Range Check")
            print(String(repeating: "-", count: 68))
            for fan in fanSample.fans {
                let rpmStr = Units.formatRPM(fan.rpm)
                let minStr = fan.minRPM.map { "\($0)" } ?? "N/A"
                let maxStr = fan.maxRPM.map { "\($0)" } ?? "N/A"
                let rangeOk = (fan.minRPM != nil && fan.maxRPM != nil) ? (fan.minRPM! <= fan.maxRPM!) : true
                print("\(pad(fan.name, 20)) | \(pad(rpmStr, 12)) | \(pad(minStr, 10)) | \(pad(maxStr, 10)) | \(rangeOk ? "BOUNDS_VALID" : "INVALID")")
                XCTAssertGreaterThanOrEqual(fan.rpm, 0, "Fan RPM should be non-negative")
                if let minRPM = fan.minRPM, let maxRPM = fan.maxRPM {
                    XCTAssertLessThanOrEqual(minRPM, maxRPM, "Min RPM must be <= Max RPM")
                }
            }
        } else {
            print("Fanless hardware detected (e.g. MacBook Air). Fans list is cleanly empty.")
        }

        // 3. GPU METRICS & PERFORMANCE STATISTICS VALIDATION
        print("\n--- 3. GPU UTILIZATION & MEMORY TELEMETRY ---")
        let gpuProvider = HostGPUInfoProvider()
        let gpuSampler = GPUSampler(provider: gpuProvider)
        let gpuSample = try gpuSampler.sample()

        if let raw = try gpuProvider.gpuStatistics() {
            print("Detected GPU Device:  \(raw.deviceName ?? "Apple Integrated GPU")")
        }

        if let util = gpuSample.utilization {
            print("GPU Core Utilization: \(String(format: "%.2f%%", util))")
            XCTAssertGreaterThanOrEqual(util, 0.0)
            XCTAssertLessThanOrEqual(util, 100.0)
        } else {
            print("GPU Core Utilization: N/A")
        }

        if let memUsed = gpuSample.memoryUsed {
            let memStr = Units.formatBytes(memUsed, standard: .iec)
            print("GPU Memory In Use:    \(memStr) (\(memUsed) bytes)")
        } else {
            print("GPU Memory In Use:    N/A")
        }

        if let temp = gpuSample.tempCelsius {
            let tempC = Units.formatTemperature(temp, unit: .celsius)
            let tempF = Units.formatTemperature(temp, unit: .fahrenheit)
            print("GPU Temperature:      \(tempC) (\(tempF))")
            XCTAssertGreaterThan(temp, 0.0)
            XCTAssertLessThan(temp, 120.0)
        } else {
            print("GPU Temperature:      N/A")
        }

        if let power = gpuSample.powerWatts {
            print("GPU Power Draw:       \(String(format: "%.2f W", power))")
            XCTAssertGreaterThanOrEqual(power, 0.0)
        } else {
            print("GPU Power Draw:       N/A (Dynamic Power Gating / Unmetered)")
        }

        print("\n=======================================================\n")
    }

    private func pad(_ text: String, _ length: Int) -> String {
        if text.count >= length {
            return String(text.prefix(length))
        }
        return text + String(repeating: " ", count: length - text.count)
    }
}
