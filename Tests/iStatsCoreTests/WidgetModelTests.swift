import XCTest
@testable import iStatsCore

final class WidgetModelTests: XCTestCase {
    private func cpu(_ total: Double, user: Double? = nil, system: Double = 0) -> CPUSample {
        CPUSample(totalUsage: total, perCore: [total, total], user: user ?? total, system: system, idle: 100 - total)
    }

    private func make(_ cat: MetricCategory, _ style: MetricDisplayStyle, _ snap: WidgetSnapshot,
                      showLabel: Bool = false, options: WidgetOptions = WidgetOptions()) -> WidgetModel {
        WidgetModel.make(config: MenuBarItemConfig(category: cat, style: style, showLabel: showLabel), snapshot: snap, options: options)
    }

    func testFractionsAreClampedAndQuantized() {
        XCTAssertEqual(WidgetModel.quantize(-5), 0)
        XCTAssertEqual(WidgetModel.quantize(250), 100)
        XCTAssertEqual(WidgetModel.quantize(49.6), 50)
        XCTAssertEqual(WidgetModel.quantize(.nan), 0)
    }

    func testUnavailableTextUsesPlaceholder() {
        let m = make(.cpu, .text, WidgetSnapshot())
        XCTAssertEqual(m.texts, ["--%"])
        XCTAssertEqual(make(.gpu, .text, WidgetSnapshot(gpu: GPUSample(utilization: nil))).texts, ["--%"])
        XCTAssertEqual(make(.thermal, .glyph, WidgetSnapshot()).texts, ["--°"])
    }

    func testNilIsDistinguishedFromZero() {
        let nilModel = make(.gpu, .text, WidgetSnapshot(gpu: GPUSample(utilization: nil)))
        let zeroModel = make(.gpu, .text, WidgetSnapshot(gpu: GPUSample(utilization: 0)))
        XCTAssertNotEqual(nilModel, zeroModel)
        XCTAssertEqual(zeroModel.texts, ["0%"])
    }

    func testCPUGaugeCarriesUserAndSystemWithoutOverflow() {
        let m = make(.cpu, .gauge, WidgetSnapshot(cpu: cpu(90, user: 70, system: 60)), showLabel: true)
        XCTAssertEqual(m.layout, .cpuRing)
        XCTAssertEqual(m.fractions, [70, 30])
        XCTAssertEqual(m.label, "CPU")
        XCTAssertNil(make(.cpu, .gauge, WidgetSnapshot(cpu: cpu(10))).label)
    }

    func testCPUBarUsesDualPrimaryAndSecondary() {
        let m = make(.cpu, .bar, WidgetSnapshot(cpu: cpu(40, user: 30, system: 10)))
        XCTAssertEqual(m.layout, .dualCapsule)
        XCTAssertEqual(m.fractions, [30, 10])
        XCTAssertEqual(m.flags, [false])
        let hybrid = CPUSample(totalUsage: 50, perCore: [10, 20, 80, 90], user: 30, system: 20, idle: 50,
                               efficiencyCoreCount: 2, performanceCoreCount: 2)
        let h = make(.cpu, .bar, WidgetSnapshot(cpu: hybrid))
        XCTAssertEqual(h.fractions, [15, 85])
        XCTAssertEqual(h.flags, [true])
    }

    func testStatusColorRoleOnlyAtWarning() {
        XCTAssertEqual(make(.cpu, .text, WidgetSnapshot(cpu: cpu(20))).colorRole, .label)
        let hot = make(.cpu, .text, WidgetSnapshot(cpu: cpu(97)))
        XCTAssertEqual(hot.colorRole, .status(StatusThresholds.cpu(usagePercent: 97)))
    }

    func testWidthClassIsIndependentOfValue() {
        let a = make(.thermal, .glyph, WidgetSnapshot(thermal: ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: 35)])))
        let b = make(.thermal, .glyph, WidgetSnapshot(thermal: ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: 105)])))
        XCTAssertEqual(a.widthClass, b.widthClass)
        XCTAssertEqual(a.widthClass, .thermometer)
        XCTAssertEqual(WidgetWidthClass.thermometer.worstCase, "199 °C")
        XCTAssertEqual(WidgetWidthClass.twoLineRate.minWidth, 60)
    }

    func testThermalRangeIsSingleConstant() {
        XCTAssertEqual(WidgetModel.thermalRangeCelsius, 30.0...100.0)
        XCTAssertEqual(WidgetModel.thermalPercent(celsius: 30), 0)
        XCTAssertEqual(WidgetModel.thermalPercent(celsius: 65), 50)
        XCTAssertEqual(WidgetModel.thermalPercent(celsius: 200), 100)
    }

    func testGraphModelChangesOnlyWithNewStamp() {
        func model(stamp: Int, values: [Double]) -> WidgetModel {
            make(.gpu, .sparkline, WidgetSnapshot(series: WidgetSeries(primary: values, stamp: stamp)))
        }
        let a = model(stamp: 10, values: [1, 2, 3])
        XCTAssertEqual(a, model(stamp: 10, values: [1, 2, 3]))
        XCTAssertEqual(a.visualKey, model(stamp: 10, values: [1, 2, 3]).visualKey)
        XCTAssertNotEqual(a.visualKey, model(stamp: 11, values: [1, 2, 3, 4]).visualKey)
    }

    func testSeriesBuildStampTracksNewestSample() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        let s1 = [Sample(value: 1.0, timestamp: t0)]
        let s2 = s1 + [Sample(value: 2.0, timestamp: t0.addingTimeInterval(1))]
        let a = WidgetSeries.build(s1) { $0 }
        let b = WidgetSeries.build(s2) { $0 }
        XCTAssertNotEqual(a.stamp, b.stamp)
        XCTAssertEqual(b.primary, [1.0, 2.0])
    }

    func testMemoryBarSegmentsAndFallback() {
        let mem = MemorySample(total: 1000, used: 500, free: 500, wired: 100, compressed: 50, cached: 0, swapUsed: 0, pressure: .normal, appMemory: 300)
        let m = make(.memory, .bar, WidgetSnapshot(memory: mem))
        XCTAssertEqual(m.layout, .memoryAllocation)
        XCTAssertEqual(m.fractions, [50, 30, 10, 5])
        XCTAssertEqual(m.flags, [true])
        XCTAssertEqual(make(.memory, .bar, WidgetSnapshot()).flags, [false])
    }

    func testMemorySymbolKeyTracksRatio() {
        func key(_ used: UInt64) -> String {
            let mem = MemorySample(total: 1000, used: used, free: 1000 - used, wired: 0, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal)
            return make(.memory, .symbol, WidgetSnapshot(memory: mem)).visualKey
        }
        XCTAssertNotEqual(key(300), key(700))
    }

    func testNetworkLayouts() {
        let stacked = MenuBarItemConfig(category: .network, style: .throughput, throughputLayout: .stacked)
        let single = MenuBarItemConfig(category: .network, style: .throughput, throughputLayout: .singleLine)
        let a = WidgetModel.make(config: stacked, snapshot: WidgetSnapshot())
        let b = WidgetModel.make(config: single, snapshot: WidgetSnapshot())
        XCTAssertEqual(a.layout, .twoLine)
        XCTAssertEqual(b.layout, .singleLine)
        XCTAssertEqual(a.widthClass.minWidth, 60)
        XCTAssertEqual(b.widthClass.minWidth, 82)
        XCTAssertNotEqual(a.visualKey, b.visualKey)
    }

    func testFanTwoFanBarAndGlyphKeys() {
        let two = FanSample(fans: [FanReading(name: "L", rpm: 2000, minRPM: 1000, maxRPM: 5000), FanReading(name: "R", rpm: 3000, minRPM: 1000, maxRPM: 5000)])
        XCTAssertEqual(make(.fan, .bar, WidgetSnapshot(fan: two)).layout, .dualCapsule)
        XCTAssertEqual(make(.fan, .throughput, WidgetSnapshot(fan: two)).texts, ["2000", "3000"])
        XCTAssertEqual(make(.fan, .glyph, WidgetSnapshot(fan: FanSample(fans: []))).texts, ["—"])
    }

    func testPowerTextLinesAndBatteryModel() {
        let lines = WidgetModel.powerStackedTextLines(charge: 92, state: .charging, timeRemaining: nil, watts: nil)
        XCTAssertEqual(lines.line1, "92% ⚡")
        XCTAssertEqual(lines.line2, "Charging")
        let m = make(.power, .symbol, WidgetSnapshot())
        XCTAssertEqual(m.layout, .battery)
        XCTAssertEqual(m.flags, [false, true])
    }

    func testDescriptionStrings() {
        let cfg = MenuBarItemConfig(category: .cpu, style: .text)
        let d = WidgetDescription.make(config: cfg, snapshot: WidgetSnapshot(cpu: cpu(45.5, user: 28.5, system: 17)))
        XCTAssertEqual(d.toolTip, "CPU: 45.5% (User: 28.5%, Sys: 17.0%)")
        XCTAssertEqual(d.accessibilityLabel, "CPU load 46 percent")
        XCTAssertEqual(WidgetDescription.make(config: cfg, snapshot: WidgetSnapshot()).toolTip, "CPU: --%")
    }

    func testSupportedStylesProduceDistinctKeys() {
        for category in MetricCategory.allCases {
            var keys = Set<String>()
            let styles = MetricDisplayStyle.supportedStyles(for: category)
            for style in styles {
                let m = make(category, style, WidgetSnapshot())
                XCTAssertFalse(m.visualKey.isEmpty)
                keys.insert(m.visualKey)
            }
            XCTAssertEqual(keys.count, styles.count, "\(category)")
        }
    }
}
