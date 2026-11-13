import XCTest
@testable import iStatsCore

final class InsightEngineTests: XCTestCase {

    // MARK: - 1. Sustained Rule (Priority 5)

    func testSustainedRuleFiresWhenAboveElevatedContinuously() {
        // 60 samples at 1.0s interval >= 50%
        let series = Array(repeating: 65.0, count: 65)
        let insights = InsightEngine.insights(series: series, interval: 1.0, unit: .percent)

        XCTAssertFalse(insights.isEmpty)
        let top = insights.first
        XCTAssertEqual(top?.kind, .sustained)
        XCTAssertEqual(top?.priority, 5)
        XCTAssertTrue(top?.text.contains("Busy for") ?? false)
    }

    func testSustainedRuleDoesNotFireWhenInterrupted() {
        // 50 elevated, then drops to 10 for last 5
        var series = Array(repeating: 65.0, count: 50)
        series.append(contentsOf: [10.0, 10.0, 10.0, 10.0, 10.0])

        let insights = InsightEngine.insights(series: series, interval: 1.0, unit: .percent)
        XCTAssertFalse(insights.contains(where: { $0.kind == .sustained }))
    }

    // MARK: - 2. Recent Spike Rule (Priority 4)

    func testRecentSpikeFiresWithinLast30Seconds() {
        // Flat 20%, then jump to 80% at 10s ago
        var series = Array(repeating: 20.0, count: 50)
        series[40] = 85.0 // 10s ago
        for i in 41..<50 {
            series[i] = 75.0
        }

        let insights = InsightEngine.insights(series: series, interval: 1.0, unit: .percent)
        let spike = insights.first(where: { $0.kind == .recentSpike })
        XCTAssertNotNil(spike)
        XCTAssertEqual(spike?.priority, 4)
        XCTAssertTrue(spike?.text.contains("Spike to") ?? false)
    }

    // MARK: - 3. Peak Rule (Priority 3)

    func testPeakRuleFiresWhenPeakIsOldAndSubstantiallyHigher() {
        // Peak 95% at 45 seconds ago, currently 40%
        var series = Array(repeating: 40.0, count: 60)
        series[15] = 95.0 // 45 seconds ago

        let insights = InsightEngine.insights(series: series, interval: 1.0, unit: .percent)
        let peak = insights.first(where: { $0.kind == .peak })
        XCTAssertNotNil(peak)
        XCTAssertEqual(peak?.priority, 3)
        XCTAssertTrue(peak?.text.contains("Peak 95%") ?? false)
        XCTAssertTrue(peak?.text.contains("ago") ?? false)
    }

    func testPeakRuleDoesNotFireIfTooRecent() {
        // Peak is only 5s ago
        var series = Array(repeating: 40.0, count: 60)
        series[55] = 95.0

        let insights = InsightEngine.insights(series: series, interval: 1.0, unit: .percent)
        XCTAssertFalse(insights.contains(where: { $0.kind == .peak }))
    }

    // MARK: - 4. Trend vs Average (Priority 2)

    func testTrendVsAverageFiresWhen60SamplesAndSignificantDelta() {
        // Baseline 30%, recently jumped to 55%
        var series = Array(repeating: 30.0, count: 60)
        series[59] = 55.0

        let insights = InsightEngine.insights(series: series, interval: 1.0, unit: .percent)
        let trend = insights.first(where: { $0.kind == .trendVsAverage })
        XCTAssertNotNil(trend)
        XCTAssertEqual(trend?.priority, 2)
        XCTAssertTrue(trend?.text.contains("Up") ?? false)
        XCTAssertTrue(trend?.text.contains("vs 1m avg") ?? false)
    }

    // MARK: - 5. Quiet Streak (Priority 1)

    func testQuietStreakFiresWhenIdleForOver5Minutes() {
        // 350 samples at 5% (interval 1s -> 350s = ~5m 50s)
        let series = Array(repeating: 5.0, count: 350)
        let insights = InsightEngine.insights(series: series, interval: 1.0, unit: .percent)

        let quiet = insights.first(where: { $0.kind == .quietStreak })
        XCTAssertNotNil(quiet)
        XCTAssertEqual(quiet?.priority, 1)
        XCTAssertTrue(quiet?.text.contains("Idle for") ?? false)
    }

    // MARK: - 6. Priority & Best Resolver

    func testBestPicksHighestPriorityInsight() {
        // Sustained busy should beat quiet and trend
        let series = Array(repeating: 75.0, count: 120)
        let best = InsightEngine.best(series: series, interval: 1.0, unit: .percent)

        XCTAssertNotNil(best)
        XCTAssertEqual(best?.kind, .sustained)
    }

    func testEmptySeriesReturnsNil() {
        XCTAssertNil(InsightEngine.best(series: [], interval: 1.0, unit: .percent))
    }

    // MARK: - 7. Category Specific Threshold Profiles

    func testThroughputThresholdsDoNotTriggerBusyOnIdleBackgroundTraffic() {
        // Idle traffic of 60 B/s (0.06 KB/s) for 100 seconds
        let series = Array(repeating: 60.0, count: 100)
        let insights = InsightEngine.insights(
            series: series,
            interval: 1.0,
            unit: .bytesPerSecond,
            thresholds: .throughputBytesPerSec()
        )
        // Should NOT trigger sustained busy (elevated is 10 MB/s)
        XCTAssertFalse(insights.contains(where: { $0.kind == .sustained }))
    }

    func testFanRPMThresholdsDoNotTriggerBusyOnQuietIdleRPM() {
        // Idle fan at 1250 RPM for 100 seconds
        let series = Array(repeating: 1250.0, count: 100)
        let insights = InsightEngine.insights(
            series: series,
            interval: 1.0,
            unit: .rpm,
            thresholds: .fanRPM(minRPM: 1200, maxRPM: 6000)
        )
        XCTAssertFalse(insights.contains(where: { $0.kind == .sustained }))
    }

    func testThermalThresholdsDoNotTriggerBusyAtNormalTemps() {
        // Normal 50°C temp for 100 seconds
        let series = Array(repeating: 50.0, count: 100)
        let insights = InsightEngine.insights(
            series: series,
            interval: 1.0,
            unit: .celsius,
            thresholds: .thermalCelsius()
        )
        XCTAssertFalse(insights.contains(where: { $0.kind == .sustained }))
    }

    func testThermalFahrenheitThresholdsAndFormatting() {
        // Normal 122°F (50°C) for 100 seconds should not trigger sustained busy
        let normalSeriesF = Array(repeating: 122.0, count: 100)
        let normalInsights = InsightEngine.insights(
            series: normalSeriesF,
            interval: 1.0,
            unit: .fahrenheit,
            thresholds: .thermal(unit: .fahrenheit)
        )
        XCTAssertFalse(normalInsights.contains(where: { $0.kind == .sustained }))

        // Spike from 122°F (50°C) to 194°F (90°C) 10s ago should format with °F
        var spikeSeriesF = Array(repeating: 122.0, count: 50)
        spikeSeriesF[40] = 194.0
        let spikeInsights = InsightEngine.insights(
            series: spikeSeriesF,
            interval: 1.0,
            unit: .fahrenheit,
            thresholds: .thermal(unit: .fahrenheit)
        )
        let spike = spikeInsights.first(where: { $0.kind == .recentSpike })
        XCTAssertNotNil(spike)
        XCTAssertTrue(spike?.text.contains("194°F") ?? false)
    }

    func testPowerWattsThresholdsDoNotTriggerBusyOnNormalBatteryChargeOrIdleDraw() {
        // 15 W normal laptop draw for 100s (below 25 W elevated threshold)
        let series = Array(repeating: 15.0, count: 100)
        let insights = InsightEngine.insights(
            series: series,
            interval: 1.0,
            unit: .watts,
            thresholds: .powerWatts
        )
        XCTAssertFalse(insights.contains(where: { $0.kind == .sustained }))
    }
}

