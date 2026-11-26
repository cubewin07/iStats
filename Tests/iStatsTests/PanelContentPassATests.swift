import XCTest
@testable import iStatsCore
@testable import iStats

/// Task 9.5: derived content rules for the CPU, Memory, GPU and Temperature panels.
final class PanelContentPassATests: XCTestCase {
    private func memory(
        total: UInt64 = 16 * 1_073_741_824,
        used: UInt64 = 8 * 1_073_741_824,
        swapUsed: UInt64 = 0,
        active: UInt64? = nil,
        inactive: UInt64? = nil
    ) -> MemorySample {
        MemorySample(
            total: total, used: used, free: total - used, wired: 2 * 1_073_741_824,
            compressed: 1_073_741_824, cached: 1_073_741_824, swapUsed: swapUsed,
            pressure: .warning, active: active, inactive: inactive
        )
    }

    // MARK: Memory

    func testScrubReadoutUsesHeroUnitIEC() {
        let text = MemoryPageContent.scrubReadout(percentUsed: 50, totalBytes: 16 * 1_073_741_824, standard: .iec)
        XCTAssertEqual(text, "8.0 GiB")
        XCTAssertEqual(MemoryPageContent.heroUnit(standard: .iec).label, "GiB")
    }

    func testScrubReadoutUsesHeroUnitSI() {
        let text = MemoryPageContent.scrubReadout(percentUsed: 25, totalBytes: 16_000_000_000, standard: .si)
        XCTAssertEqual(text, "4.0 GB")
        XCTAssertTrue(text.hasSuffix(MemoryPageContent.heroUnit(standard: .si).label))
    }

    func testMemoryHeadlineDoesNotRepeatPressureOrCompression() {
        let headline = MemoryPageContent.headline(sample: memory(), standard: .iec)
        XCTAssertEqual(headline, "of 16 GiB")
        XCTAssertFalse(headline.contains("Pressure"))
        XCTAssertFalse(headline.lowercased().contains("compressed"))
    }

    func testMemoryHeadlineShowsSwapOnlyWhenActive() {
        let headline = MemoryPageContent.headline(sample: memory(swapUsed: 1_073_741_824), standard: .iec)
        XCTAssertTrue(headline.hasSuffix("swap"))
    }

    func testVirtualMemoryRowsExcludeNowLegendValues() {
        let rows = MemoryPageContent.virtualMemoryRows(
            sample: memory(active: 3_000_000_000, inactive: 2_000_000_000), standard: .iec
        )
        let labels = Set(rows.map(\.label))
        XCTAssertEqual(labels, ["Active Pages", "Inactive Pages"])
        for repeated in ["App Memory", "Wired", "Compressed", "Cached", "Free"] {
            XCTAssertFalse(labels.contains(repeated))
        }
        XCTAssertTrue(MemoryPageContent.virtualMemoryRows(sample: memory(), standard: .iec).isEmpty)
    }

    // MARK: CPU

    func testCPULoadLegendCarriesValueOnce() {
        XCTAssertEqual(CPUPageContent.loadLegend(window: "1m", value: 1.234), "1m 1.23")
        XCTAssertEqual(CPUPageContent.loadLegend(window: "15m", value: nil), "15m --")
    }

    func testCPUStatusBoundaries() {
        XCTAssertEqual(StatusThresholds.cpuPanel(usagePercent: 74.9, loadOneMinute: nil, coreCount: 8), .fine)
        XCTAssertGreaterThanOrEqual(StatusThresholds.cpuPanel(usagePercent: 75, loadOneMinute: nil, coreCount: 8), .elevated)
        XCTAssertEqual(StatusThresholds.cpuPanel(usagePercent: 90, loadOneMinute: nil, coreCount: 8), .critical)
    }

    // MARK: GPU

    func testGPUHeadlineIsStateWordWithoutRepeatedValues() {
        func sample(_ util: Double) -> GPUSample {
            GPUSample(utilization: util, tempCelsius: 61)
        }
        XCTAssertEqual(GPUPageContent.headline(sample: sample(5)), "Idle")
        XCTAssertEqual(GPUPageContent.headline(sample: sample(40)), "Active")
        XCTAssertEqual(GPUPageContent.headline(sample: sample(90)), "Heavy GPU load")
        for util in [5.0, 40.0, 90.0] {
            let text = GPUPageContent.headline(sample: sample(util))
            XCTAssertNil(text.rangeOfCharacter(from: .decimalDigits))
        }
    }

    // MARK: Temperature

    func testSpectrumBarFitsSectionInterior() {
        XCTAssertEqual(TemperaturePageContent.spectrumBarWidth, Double(Instrument.Size.contentWidth - 2 * Instrument.Space.modulePadding))
        XCTAssertLessThanOrEqual(TemperaturePageContent.spectrumBarWidth, Double(Instrument.Size.contentWidth))
    }

    func testSensorGroupSummaryHasNoTemperature() {
        XCTAssertEqual(TemperaturePageContent.groupSummary(sensorCount: 1), "1 sensor")
        XCTAssertEqual(TemperaturePageContent.groupSummary(sensorCount: 6), "6 sensors")
        XCTAssertFalse(TemperaturePageContent.groupSummary(sensorCount: 6).contains("°"))
    }
}
