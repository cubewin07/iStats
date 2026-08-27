import XCTest
import SwiftUI
import iStatsCore
@testable import iStats

// MARK: - Mock Denied / Sandboxed Providers

private struct MockDeniedThermalInfoProvider: ThermalInfoProvider {
    let error: Error

    init(error: Error = SamplerError.systemCallFailed("EPERM: Sandbox denied IOHID/SMC access")) {
        self.error = error
    }

    func thermalSensors() throws -> [SensorReading] {
        throw error
    }

    func thermalPressure() throws -> ThermalPressure? {
        throw error
    }
}

private struct MockDeniedFanInfoProvider: FanInfoProvider {
    let error: Error

    init(error: Error = SamplerError.systemCallFailed("EPERM: Sandbox denied AppleSMC user client access")) {
        self.error = error
    }

    func fanCount() throws -> Int {
        throw error
    }

    func fans() throws -> [FanReading] {
        throw error
    }
}

private struct MockDeniedGPUInfoProvider: GPUInfoProvider {
    let error: Error?

    init(error: Error? = SamplerError.systemCallFailed("EPERM: Sandbox denied IOAccelerator registry access")) {
        self.error = error
    }

    func gpuStatistics() throws -> RawGPUStatistics? {
        if let error = error {
            throw error
        }
        return nil
    }
}

private struct MockHealthyCPUInfoProvider: CPUInfoProvider {
    func processorTicks() throws -> [ProcessorTicks] {
        [ProcessorTicks(user: 100, system: 50, idle: 850, nice: 0)]
    }

    func cpuLoadInfo() throws -> [Double] {
        [15.0]
    }

    func loadAverage() throws -> LoadAverage {
        LoadAverage(oneMinute: 1.5, fiveMinute: 1.2, fifteenMinute: 1.0)
    }

    func cpuFrequencyHz() throws -> UInt64? {
        3_500_000_000
    }
}

// MARK: - Sandbox Degradation Tests

final class SandboxDegradationTests: XCTestCase {

    // MARK: - Phase 5 Samplers Denial & Degradation

    func testThermalSamplerDegradationOnDeniedAccess() {
        let provider = MockDeniedThermalInfoProvider()
        let sampler = ThermalSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError, got: \(error)")
                return
            }
            switch samplerError {
            case .unsupported, .systemCallFailed:
                // Graceful degradation when sensors cannot be accessed
                break
            default:
                XCTFail("Unexpected SamplerError case: \(samplerError)")
            }
        }
    }

    func testFanSamplerDegradationOnDeniedAccess() {
        let provider = MockDeniedFanInfoProvider()
        let sampler = FanSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError, got: \(error)")
                return
            }
            if case .systemCallFailed(let msg) = samplerError {
                XCTAssertTrue(msg.contains("EPERM") || msg.contains("AppleSMC"))
            } else {
                XCTFail("Unexpected SamplerError case: \(samplerError)")
            }
        }
    }

    func testGPUSamplerDegradationOnDeniedAccess() {
        let provider = MockDeniedGPUInfoProvider()
        let sampler = GPUSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError, got: \(error)")
                return
            }
            if case .systemCallFailed(let msg) = samplerError {
                XCTAssertTrue(msg.contains("EPERM") || msg.contains("IOAccelerator"))
            } else {
                XCTFail("Unexpected SamplerError case: \(samplerError)")
            }
        }
    }

    func testGPUSamplerDegradationOnNilStatistics() {
        let provider = MockDeniedGPUInfoProvider(error: nil)
        let sampler = GPUSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample()) { error in
            guard case SamplerError.unsupported = error else {
                XCTFail("Expected SamplerError.unsupported when statistics return nil, got: \(error)")
                return
            }
        }
    }

    // MARK: - SampleScheduler Error Isolation (ADR 0002, ADR 0005, Req 12.3, 13.1)

    func testSchedulerIsolatesDeniedPhase5SamplersFromHealthySamplers() async {
        let scheduler = SampleScheduler(defaultInterval: 0.1, timeBudget: 1.0)

        // Register healthy CPU sampler
        let cpuSampler = CPUSampler(provider: MockHealthyCPUInfoProvider())
        await scheduler.register(cpuSampler)

        // Register denied Phase 5 samplers (Thermal, Fan, GPU)
        let thermalSampler = ThermalSampler(provider: MockDeniedThermalInfoProvider())
        let fanSampler = FanSampler(provider: MockDeniedFanInfoProvider())
        let gpuSampler = GPUSampler(provider: MockDeniedGPUInfoProvider())

        await scheduler.register(thermalSampler)
        await scheduler.register(fanSampler)
        await scheduler.register(gpuSampler)

        // Sample all concurrently
        let readings = await scheduler.sampleAll()
        XCTAssertEqual(readings.count, 4)

        // Verify healthy CPU reading is .available
        let cpuReading = readings.first(where: { $0.category == .cpu })
        XCTAssertNotNil(cpuReading)
        if case .cpu(let sample) = cpuReading {
            XCTAssertEqual(sample.availability, .available)
            XCTAssertNotNil(sample.value)
        } else {
            XCTFail("Expected .cpu reading case, got: \(String(describing: cpuReading))")
        }

        // Verify Thermal reading gracefully degraded to .unavailable
        let thermalReading = readings.first(where: { $0.category == .thermal })
        XCTAssertNotNil(thermalReading)
        XCTAssertEqual(thermalReading?.availability.isAvailable, false)
        if case .unavailable(let cat, let reason, _) = thermalReading {
            XCTAssertEqual(cat, .thermal)
            XCTAssertTrue(reason.contains("EPERM") || reason.contains("Sandbox") || reason.contains("System call failed") || reason.contains("unavailable") || reason.contains("Unsupported"))
        } else {
            XCTFail("Expected .unavailable reading for denied thermal sampler")
        }

        // Verify Fan reading gracefully degraded to .unavailable
        let fanReading = readings.first(where: { $0.category == .fan })
        XCTAssertNotNil(fanReading)
        XCTAssertEqual(fanReading?.availability.isAvailable, false)
        if case .unavailable(let cat, let reason, _) = fanReading {
            XCTAssertEqual(cat, .fan)
            XCTAssertTrue(reason.contains("EPERM") || reason.contains("AppleSMC") || reason.contains("System call failed"))
        } else {
            XCTFail("Expected .unavailable reading for denied fan sampler")
        }

        // Verify GPU reading gracefully degraded to .unavailable
        let gpuReading = readings.first(where: { $0.category == .gpu })
        XCTAssertNotNil(gpuReading)
        XCTAssertEqual(gpuReading?.availability.isAvailable, false)
        if case .unavailable(let cat, let reason, _) = gpuReading {
            XCTAssertEqual(cat, .gpu)
            XCTAssertTrue(reason.contains("EPERM") || reason.contains("IOAccelerator") || reason.contains("System call failed"))
        } else {
            XCTFail("Expected .unavailable reading for denied gpu sampler")
        }
    }

    // MARK: - UI Graceful Unavailable State Rendering

    func testThermalSummaryViewRendersUnavailableState() {
        let viewNil = ThermalSummaryView(sample: nil)
        XCTAssertNotNil(viewNil.body)

        let viewEmpty = ThermalSummaryView(sample: ThermalSample(sensors: [], pressure: nil))
        XCTAssertNotNil(viewEmpty.body)
    }

    func testFanSummaryViewRendersUnavailableState() {
        let viewNil = FanSummaryView(sample: nil)
        XCTAssertNotNil(viewNil.body)

        let viewEmpty = FanSummaryView(sample: FanSample(fans: []))
        XCTAssertNotNil(viewEmpty.body)
    }

    func testGPUSummaryViewRendersUnavailableState() {
        let viewNil = GPUSummaryView(sample: nil, history: [])
        XCTAssertNotNil(viewNil.body)

        let viewEmpty = GPUSummaryView(sample: GPUSample(), history: [])
        XCTAssertNotNil(viewEmpty.body)
    }

    func testDetailPopoverViewRendersAllUnavailablePhase5CategoriesGracefully() {
        let viewWithNil = DetailPopoverView(
            gpuSample: nil,
            thermalSample: nil,
            fanSample: nil
        )
        XCTAssertNotNil(viewWithNil.body)

        let viewWithEmpty = DetailPopoverView(
            gpuSample: GPUSample(),
            thermalSample: ThermalSample(sensors: [], pressure: nil),
            fanSample: FanSample(fans: [])
        )
        XCTAssertNotNil(viewWithEmpty.body)
    }
}
