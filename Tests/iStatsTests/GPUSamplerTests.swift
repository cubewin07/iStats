import XCTest
import SwiftUI
@testable import iStatsCore
@testable import iStats

final class GPUSamplerTests: XCTestCase {

    // MARK: - Mock Provider

    private struct MockGPUInfoProvider: GPUInfoProvider {
        var statsToReturn: RawGPUStatistics? = nil
        var shouldThrow: Bool = false

        func gpuStatistics() throws -> RawGPUStatistics? {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock GPU hardware error")
            }
            return statsToReturn
        }
    }

    // MARK: - Unit Tests

    func testGPUSamplerCategory() {
        let sampler = GPUSampler(provider: MockGPUInfoProvider())
        XCTAssertEqual(sampler.category, .gpu)
    }

    func testGPUSamplerWithFullMetrics() throws {
        let raw = RawGPUStatistics(
            utilization: 42.5,
            memoryUsed: 2_147_483_648,
            allocatedMemory: 4_294_967_296,
            tempCelsius: 48.5,
            powerWatts: 6.2,
            rendererUtilization: 38.0,
            tilerUtilization: 12.0,
            deviceName: "Apple M4 Pro",
            coreCount: 16,
            recommendedMaxMemory: 16_000_000_000,
            isUnifiedMemory: true,
            displayCount: 2,
            displayDescriptions: ["Built-in Retina (120Hz)", "DELL SE2725HM (100Hz)"],
            recoveryCount: 0
        )
        let provider = MockGPUInfoProvider(statsToReturn: raw)
        let sampler = GPUSampler(provider: provider)

        let sample = try sampler.sample()
        XCTAssertEqual(sample.utilization, 42.5)
        XCTAssertEqual(sample.memoryUsed, 2_147_483_648)
        XCTAssertEqual(sample.tempCelsius, 48.5)
        XCTAssertEqual(sample.powerWatts, 6.2)
        XCTAssertEqual(sample.coreCount, 16)
        XCTAssertEqual(sample.deviceName, "Apple M4 Pro")
        XCTAssertEqual(sample.allocatedMemory, 4_294_967_296)
        XCTAssertEqual(sample.recommendedMaxMemory, 16_000_000_000)
        XCTAssertEqual(sample.rendererUtilization, 38.0)
        XCTAssertEqual(sample.tilerUtilization, 12.0)
        XCTAssertEqual(sample.isUnifiedMemory, true)
        XCTAssertEqual(sample.displayCount, 2)
        XCTAssertEqual(sample.displayDescriptions?.count, 2)
        XCTAssertEqual(sample.recoveryCount, 0)
    }

    func testGPUSamplerWithPartialMetrics() throws {
        let raw = RawGPUStatistics(
            utilization: 25.0,
            memoryUsed: nil,
            tempCelsius: nil,
            powerWatts: nil
        )
        let provider = MockGPUInfoProvider(statsToReturn: raw)
        let sampler = GPUSampler(provider: provider)

        let sample = try sampler.sample()
        XCTAssertEqual(sample.utilization, 25.0)
        XCTAssertNil(sample.memoryUsed)
        XCTAssertNil(sample.tempCelsius)
        XCTAssertNil(sample.powerWatts)
    }

    func testGPUSamplerCalculateSampleClamping() {
        let extremeRaw = RawGPUStatistics(
            utilization: 150.0,
            memoryUsed: 1_000_000,
            tempCelsius: 200.0, // out of bounds
            powerWatts: -10.0   // invalid negative power
        )

        let sample1 = GPUSampler.calculateSample(raw: extremeRaw)
        XCTAssertEqual(sample1.utilization, 100.0) // clamped to 100
        XCTAssertEqual(sample1.memoryUsed, 1_000_000)
        XCTAssertNil(sample1.tempCelsius) // filtered out
        XCTAssertNil(sample1.powerWatts)  // filtered out

        let negativeRaw = RawGPUStatistics(
            utilization: -35.0,
            memoryUsed: 0,
            tempCelsius: 52.0,
            powerWatts: 8.4
        )

        let sample2 = GPUSampler.calculateSample(raw: negativeRaw)
        XCTAssertEqual(sample2.utilization, 0.0) // clamped to 0
        XCTAssertEqual(sample2.memoryUsed, 0)
        XCTAssertEqual(sample2.tempCelsius, 52.0)
        XCTAssertEqual(sample2.powerWatts, 8.4)
    }

    func testGPUSamplerNilStatisticsThrowsUnsupported() {
        let provider = MockGPUInfoProvider(statsToReturn: nil)
        let sampler = GPUSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError but got \(error)")
                return
            }
            if case .unsupported = samplerError {
                // Success
            } else {
                XCTFail("Expected .unsupported but got \(samplerError)")
            }
        }
    }

    func testGPUSamplerEmptyStatisticsThrowsUnsupported() {
        let provider = MockGPUInfoProvider(statsToReturn: RawGPUStatistics())
        let sampler = GPUSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample()) { error in
            guard let samplerError = error as? SamplerError else {
                XCTFail("Expected SamplerError but got \(error)")
                return
            }
            if case .unsupported = samplerError {
                // Success
            } else {
                XCTFail("Expected .unsupported but got \(samplerError)")
            }
        }
    }

    func testGPUSamplerProviderFailureThrows() {
        let provider = MockGPUInfoProvider(shouldThrow: true)
        let sampler = GPUSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample())
    }

    // MARK: - Live Host Provider Test

    func testLiveHostGPUInfoProviderAndSampler() throws {
        let provider = HostGPUInfoProvider()
        if let stats = try? provider.gpuStatistics() {
            print("Live GPU Statistics on Host:")
            if let name = stats.deviceName {
                print("  Device: \(name)")
            }
            if let cores = stats.coreCount {
                print("  Cores: \(cores)")
                XCTAssertGreaterThan(cores, 0)
            }
            if let util = stats.utilization {
                print("  Utilization: \(String(format: "%.1f%%", util))")
                XCTAssertGreaterThanOrEqual(util, 0.0)
                XCTAssertLessThanOrEqual(util, 100.0)
            }
            if let r = stats.rendererUtilization {
                print("  Renderer Utilization: \(String(format: "%.1f%%", r))")
            }
            if let t = stats.tilerUtilization {
                print("  Tiler Utilization: \(String(format: "%.1f%%", t))")
            }
            if let mem = stats.memoryUsed {
                print("  Memory In Use: \(mem) bytes (\(Units.formatBytes(mem, standard: .iec)))")
                XCTAssertGreaterThanOrEqual(mem, 0)
            }
            if let alloc = stats.allocatedMemory {
                print("  Allocated Memory: \(alloc) bytes")
            }
            if let maxMem = stats.recommendedMaxMemory {
                print("  Max Working Set: \(Units.formatBytes(maxMem, standard: .iec))")
            }
            if let unified = stats.isUnifiedMemory {
                print("  Unified Memory: \(unified)")
            }
            if let descs = stats.displayDescriptions {
                print("  Displays: \(descs.joined(separator: ", "))")
            }
            if let temp = stats.tempCelsius {
                print("  Temperature: \(temp) °C")
                XCTAssertGreaterThan(temp, 0.0)
                XCTAssertLessThan(temp, 120.0)
            }
            if let pwr = stats.powerWatts {
                print("  Power: \(pwr) W")
                XCTAssertGreaterThanOrEqual(pwr, 0.0)
            }

            let sampler = GPUSampler(provider: provider)
            let sample = try sampler.sample()
            XCTAssertNotNil(sample)
        } else {
            print("Host GPU Statistics returned nil on this environment.")
        }
    }

    // MARK: - UI Tests

    @MainActor
    func testGPUSummaryViewRendersWithData() {
        let sample = GPUSample(
            utilization: 38.5,
            memoryUsed: 1_500_000_000,
            tempCelsius: 47.0,
            powerWatts: 5.5
        )
        let history = [
            Sample(value: GPUSample(utilization: 20.0)),
            Sample(value: GPUSample(utilization: 30.0)),
            Sample(value: sample)
        ]

        let view = GPUSummaryView(
            sample: sample,
            history: history,
            temperatureUnit: .celsius,
            byteStandard: .iec
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 200)
        XCTAssertNotNil(hosting)
    }

    @MainActor
    func testGPUSummaryViewRendersEnrichedData() {
        let sample = GPUSample(
            utilization: 52.0,
            memoryUsed: 2_500_000_000,
            tempCelsius: 62.0,
            powerWatts: 14.5,
            coreCount: 16,
            deviceName: "Apple M4 Pro",
            allocatedMemory: 4_000_000_000,
            recommendedMaxMemory: 18_000_000_000,
            rendererUtilization: 48.0,
            tilerUtilization: 12.0,
            isUnifiedMemory: true,
            displayCount: 2,
            displayDescriptions: ["Built-in Retina Display (1512×982 @ 120Hz)", "DELL SE2725HM (1920×1080 @ 100Hz)"],
            recoveryCount: 0
        )
        let history = [
            Sample(value: GPUSample(utilization: 30.0)),
            Sample(value: sample)
        ]

        let view = GPUSummaryView(
            sample: sample,
            history: history,
            temperatureUnit: .celsius,
            byteStandard: .iec
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 350)
        XCTAssertNotNil(hosting)
    }

    @MainActor
    func testGPUSummaryViewRendersFahrenheitAndSI() {
        let sample = GPUSample(
            utilization: 75.0,
            memoryUsed: 2_000_000_000,
            tempCelsius: 60.0,
            powerWatts: 12.0,
            coreCount: 10,
            deviceName: "Apple M2",
            allocatedMemory: 3_000_000_000,
            recommendedMaxMemory: 16_000_000_000,
            rendererUtilization: 65.0,
            tilerUtilization: 10.0,
            isUnifiedMemory: true,
            displayCount: 1,
            displayDescriptions: ["Built-in Liquid Retina"],
            recoveryCount: 0
        )

        let view = GPUSummaryView(
            sample: sample,
            history: [],
            temperatureUnit: .fahrenheit,
            byteStandard: .si
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 280)
        XCTAssertNotNil(hosting)
    }

    @MainActor
    func testGPUSummaryViewRendersUnavailable() {
        let view = GPUSummaryView(sample: GPUSample(), history: [])
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 100)
        XCTAssertNotNil(hosting)
    }

    @MainActor
    func testDetailPopoverViewIncludesGPU() {
        let gpuSample = GPUSample(utilization: 40.0, memoryUsed: 1_000_000_000, tempCelsius: 45.0, coreCount: 16)
        let gpuHist = [Sample(value: gpuSample)]

        let popoverView = DetailPopoverView(
            gpuSample: gpuSample,
            gpuHistory: gpuHist
        )

        let hosting = NSHostingView(rootView: popoverView)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 500)
        XCTAssertNotNil(hosting)
    }

    func testGPUSamplerCalculateSampleRichClamping() {
        let raw = RawGPUStatistics(
            utilization: 45.0,
            memoryUsed: 1_000_000,
            allocatedMemory: 2_000_000,
            tempCelsius: 50.0,
            powerWatts: 8.0,
            rendererUtilization: 140.0, // should clamp to 100
            tilerUtilization: -20.0,    // should clamp to 0
            deviceName: "Apple M4 Pro",
            coreCount: -4,              // invalid negative cores, should be filtered to nil
            recommendedMaxMemory: 16_000_000,
            isUnifiedMemory: true,
            displayCount: 2,
            displayDescriptions: ["Screen 1", "Screen 2"],
            recoveryCount: 0
        )

        let sample = GPUSampler.calculateSample(raw: raw)
        XCTAssertEqual(sample.rendererUtilization, 100.0)
        XCTAssertEqual(sample.tilerUtilization, 0.0)
        XCTAssertNil(sample.coreCount)
        XCTAssertEqual(sample.deviceName, "Apple M4 Pro")
        XCTAssertEqual(sample.displayCount, 2)
    }

    // MARK: - MetricsCoordinator Integration

    @MainActor
    func testMetricsCoordinatorGPUIntegration() {
        let coordinator = MetricsCoordinator()
        let reading = MetricReading.gpu(
            Sample(value: GPUSample(utilization: 55.0, memoryUsed: 2_000_000_000, coreCount: 16))
        )

        coordinator.handleReading(reading)
        XCTAssertEqual(coordinator.latestGPU?.value.utilization, 55.0)
        XCTAssertEqual(coordinator.latestGPU?.value.memoryUsed, 2_000_000_000)
        XCTAssertEqual(coordinator.latestGPU?.value.coreCount, 16)
        XCTAssertEqual(coordinator.gpuHistory.count, 1)
        XCTAssertEqual(coordinator.gpuHistory.first?.value.utilization, 55.0)
    }
}
