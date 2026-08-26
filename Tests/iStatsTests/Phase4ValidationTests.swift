import XCTest
import Foundation
import iStatsCore
@testable import iStats

final class Phase4ValidationTests: XCTestCase {

    func testLiveValidationBatteryAndPower() throws {
        print("\n=======================================================")
        print("PHASE 4 LIVE METRIC VALIDATION")
        print("=======================================================")

        let provider = HostPowerInfoProvider()
        let sampler = PowerSampler(provider: provider)
        let sample = try sampler.sample()

        print("\n--- 1. BATTERY & POWER SOURCE SNAPSHOT ---")
        print("Machine Battery Installed: \(sample.hasBattery ? "YES" : "NO (Desktop Mac / AC Powered)")")

        if sample.hasBattery {
            if let charge = sample.charge {
                print("State of Charge (%):       \(String(format: "%.1f%%", charge))")
            }
            if let state = sample.state {
                print("Power State:               \(state.rawValue)")
            }
            if let time = sample.timeRemaining {
                let mins = Int(time) / 60
                print("Time Remaining:            \(mins / 60)h \(mins % 60)m (\(time)s)")
            } else {
                print("Time Remaining:            N/A (Connected to AC / Fully Charged / Calculating)")
            }

            print("\n--- 2. BATTERY HEALTH & CAPACITY (AppleSmartBattery) ---")
            if let cycles = sample.cycleCount {
                print("Cycle Count:               \(cycles)")
            }
            if let condition = sample.condition {
                print("Condition:                 \(condition)")
            }
            if let design = sample.designCapacity {
                print("Design Capacity:           \(design) mAh")
            }
            if let currentMax = sample.currentMaxCapacity {
                print("Current Maximum Capacity:  \(currentMax) mAh")
                if let design = sample.designCapacity, design > 0 {
                    let healthPct = (Double(currentMax) / Double(design)) * 100.0
                    print("Capacity Health (%):       \(String(format: "%.1f%%", healthPct))")
                }
            }

            print("\n--- 3. POWER DRAW & ADAPTER WATTAGE ---")
            if let adapter = sample.adapterWatts {
                print("Adapter Power:             \(String(format: "%.1f W", adapter))")
            } else {
                print("Adapter Power:             N/A (Running on Battery)")
            }
            if let draw = sample.powerDrawWatts {
                print("Instantaneous Power Draw:  \(String(format: "%.2f W", draw))")
            } else {
                print("Instantaneous Power Draw:  Unexposed / Zero on AC")
            }

            // Assertions for live host consistency
            if let charge = sample.charge {
                XCTAssertGreaterThanOrEqual(charge, 0.0)
                XCTAssertLessThanOrEqual(charge, 100.0)
            }
            if let cycles = sample.cycleCount {
                XCTAssertGreaterThanOrEqual(cycles, 0)
            }
            if let cond = sample.condition {
                XCTAssertFalse(cond.isEmpty)
            }
        } else {
            print("Desktop Mac detected. Battery metrics cleanly marked not applicable.")
            XCTAssertNil(sample.charge)
            XCTAssertNil(sample.cycleCount)
        }

        print("\n=======================================================\n")
    }
}
