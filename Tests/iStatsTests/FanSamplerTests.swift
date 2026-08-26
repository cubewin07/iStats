import XCTest
import SwiftUI
@testable import iStatsCore
@testable import iStats

final class FanSamplerTests: XCTestCase {

    // MARK: - Mock Providers

    private struct MockFanInfoProvider: FanInfoProvider {
        var fansToReturn: [FanReading] = []
        var shouldThrow: Bool = false

        func fanCount() throws -> Int {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock hardware access failure")
            }
            return fansToReturn.count
        }

        func fans() throws -> [FanReading] {
            if shouldThrow {
                throw SamplerError.systemCallFailed("Mock hardware access failure")
            }
            return fansToReturn
        }
    }

    // MARK: - Unit Tests

    func testFanSamplerCategory() {
        let sampler = FanSampler(provider: MockFanInfoProvider())
        XCTAssertEqual(sampler.category, .fan)
    }

    func testFanSamplerWithDualFans() throws {
        let mockFans = [
            FanReading(name: "Left Fan", rpm: 1850, minRPM: 1200, maxRPM: 5500),
            FanReading(name: "Right Fan", rpm: 1920, minRPM: 1200, maxRPM: 5500)
        ]
        let provider = MockFanInfoProvider(fansToReturn: mockFans)
        let sampler = FanSampler(provider: provider)

        let sample = try sampler.sample()
        XCTAssertEqual(sample.fans.count, 2)
        XCTAssertEqual(sample.fans[0].name, "Left Fan")
        XCTAssertEqual(sample.fans[0].rpm, 1850)
        XCTAssertEqual(sample.fans[0].minRPM, 1200)
        XCTAssertEqual(sample.fans[0].maxRPM, 5500)
        XCTAssertEqual(sample.fans[1].name, "Right Fan")
        XCTAssertEqual(sample.fans[1].rpm, 1920)
        XCTAssertEqual(sample.fans[1].minRPM, 1200)
        XCTAssertEqual(sample.fans[1].maxRPM, 5500)
    }

    func testFanSamplerWithSingleFan() throws {
        let mockFans = [
            FanReading(name: "System Fan", rpm: 2100, minRPM: 1000, maxRPM: 6000)
        ]
        let provider = MockFanInfoProvider(fansToReturn: mockFans)
        let sampler = FanSampler(provider: provider)

        let sample = try sampler.sample()
        XCTAssertEqual(sample.fans.count, 1)
        XCTAssertEqual(sample.fans[0].name, "System Fan")
        XCTAssertEqual(sample.fans[0].rpm, 2100)
        XCTAssertEqual(sample.fans[0].minRPM, 1000)
        XCTAssertEqual(sample.fans[0].maxRPM, 6000)
    }

    func testFanSamplerFanlessSystem() throws {
        // Requirement 4.4 / ADR 0003: Fanless machines report 0 fans cleanly without error
        let provider = MockFanInfoProvider(fansToReturn: [])
        let sampler = FanSampler(provider: provider)

        let sample = try sampler.sample()
        XCTAssertTrue(sample.fans.isEmpty)
    }

    func testFanSamplerNegativeOrCorruptValuesClamped() {
        let rawFans = [
            FanReading(name: "Glitch Fan", rpm: -300, minRPM: -100, maxRPM: -500),
            FanReading(name: "Valid Fan", rpm: 1500, minRPM: 1000, maxRPM: 5000)
        ]

        let sample = FanSampler.calculateSample(fans: rawFans)
        XCTAssertEqual(sample.fans.count, 2)
        XCTAssertEqual(sample.fans[0].name, "Glitch Fan")
        XCTAssertEqual(sample.fans[0].rpm, 0)
        XCTAssertNil(sample.fans[0].minRPM)
        XCTAssertNil(sample.fans[0].maxRPM)

        XCTAssertEqual(sample.fans[1].name, "Valid Fan")
        XCTAssertEqual(sample.fans[1].rpm, 1500)
        XCTAssertEqual(sample.fans[1].minRPM, 1000)
        XCTAssertEqual(sample.fans[1].maxRPM, 5000)
    }

    func testFanSamplerProviderFailureThrows() {
        let provider = MockFanInfoProvider(shouldThrow: true)
        let sampler = FanSampler(provider: provider)

        XCTAssertThrowsError(try sampler.sample())
    }

    // MARK: - Live Hardware Telemetry

    func testLiveHostFanInfoProviderAndSampler() throws {
        let provider = HostFanInfoProvider()
        let count = try provider.fanCount()
        let fans = try provider.fans()

        XCTAssertEqual(count, fans.count)

        let sampler = FanSampler(provider: provider)
        let sample = try sampler.sample()

        if sample.fans.isEmpty {
            print("Live Host Fan Telemetry: Fanless system detected (0 physical fans).")
        } else {
            print("Live Host Fan Telemetry: Found \(sample.fans.count) fan(s):")
            for (idx, fan) in sample.fans.enumerated() {
                let boundsStr = Units.formatFanBounds(min: fan.minRPM, max: fan.maxRPM) ?? "unbounded"
                print("  [\(idx)] \(fan.name): \(Units.formatRPM(fan.rpm)) (Bounds: \(boundsStr))")
                XCTAssertFalse(fan.name.isEmpty)
                XCTAssertGreaterThanOrEqual(fan.rpm, 0)
                if let min = fan.minRPM {
                    XCTAssertGreaterThanOrEqual(min, 0)
                }
                if let max = fan.maxRPM {
                    XCTAssertGreaterThanOrEqual(max, 0)
                }
            }
        }
    }

    @MainActor
    func testFanSummaryViewRendersWithData() {
        let sample = FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 1850, minRPM: 1200, maxRPM: 5500),
            FanReading(name: "Right Fan", rpm: 1920, minRPM: 1200, maxRPM: 5500)
        ])
        let history = [
            Sample(value: sample, availability: .available)
        ]

        let view = FanSummaryView(
            sample: sample,
            history: history
        )

        XCTAssertNotNil(view.body)
    }

    @MainActor
    func testFanSummaryViewRendersFanless() {
        let sample = FanSample(fans: [])
        let view = FanSummaryView(
            sample: sample,
            history: []
        )

        XCTAssertNotNil(view.body)
    }

    @MainActor
    func testDetailPopoverViewIncludesFan() {
        let fanSample = FanSample(fans: [
            FanReading(name: "System Fan", rpm: 1500, minRPM: 1000, maxRPM: 5000)
        ])

        let popover = DetailPopoverView(
            fanSample: fanSample
        )

        XCTAssertNotNil(popover.body)
    }

    // MARK: - Fan Policy & Safety Bounds Integration (Requirements 4.3, 4.4, 13.2, ADR 0004)

    func testFanPolicyDefaultAndDescriptions() {
        XCTAssertEqual(FanControlPolicy.defaultMode, .systemAutomatic)
        XCTAssertEqual(FanControlPolicy.statusLabel, "System Controlled")
        XCTAssertFalse(FanControlPolicy.readOnlyExplanation.isEmpty)
    }

    func testFanSafetyClampingWithSampleBounds() {
        let fan = FanReading(name: "Exhaust Fan", rpm: 2000, minRPM: 1200, maxRPM: 5400)
        
        // Clamping below min bounds
        let clampedLow = FanSafetyBounds.clamp(targetRPM: 500, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
        XCTAssertEqual(clampedLow, 1200)

        // Clamping above max bounds
        let clampedHigh = FanSafetyBounds.clamp(targetRPM: 7000, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
        XCTAssertEqual(clampedHigh, 5400)

        // Target within bounds
        let clampedNormal = FanSafetyBounds.clamp(targetRPM: 3000, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
        XCTAssertEqual(clampedNormal, 3000)
    }
}
