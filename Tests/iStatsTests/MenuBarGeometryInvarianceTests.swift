import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

/// Anti-jitter and geometry invariance: each menu bar style has a fixed width class, so a widget keeps the
/// same pixel size across wildly fluctuating metric values. Everything here goes through `WidgetModel`
/// and the per-family renderers, the same path the menu bar uses.
@MainActor
final class MenuBarGeometryInvarianceTests: XCTestCase {

    // MARK: - Helpers

    private func image(
        _ category: MetricCategory,
        _ style: MetricDisplayStyle,
        snapshot: WidgetSnapshot = WidgetSnapshot(),
        showLabel: Bool = false,
        layout: ThroughputLayout? = nil,
        options: WidgetOptions = WidgetOptions()
    ) -> NSImage {
        let config = MenuBarItemConfig(category: category, style: style, throughputLayout: layout, showLabel: showLabel)
        return MenuBarIconRenderer.image(for: WidgetModel.make(config: config, snapshot: snapshot, options: options))
    }

    private func cpu(_ total: Double, user: Double? = nil, system: Double = 0) -> CPUSample {
        CPUSample(totalUsage: total, perCore: [total, total], user: user ?? total, system: system, idle: max(0, 100 - total))
    }

    private func series(_ values: [Double], secondary: [Double] = [], tertiary: [Double] = []) -> WidgetSeries {
        WidgetSeries(primary: values, secondary: secondary, tertiary: tertiary, stamp: values.count)
    }

    private func width(_ widthClass: WidgetWidthClass) -> CGFloat { WidgetMetrics.width(widthClass) }

    // MARK: - 1. Label/value text: one width per class, 22 pt high, for every value

    func testCategoryStackedTextWidthInvarianceAcrossNumberFluctuations() {
        for usage in [0.0, 1.0, 9.0, 10.0, 55.0, 99.0, 100.0] {
            for category in [MetricCategory.cpu, .memory, .gpu] {
                let snap = WidgetSnapshot(
                    cpu: cpu(usage),
                    memory: MemorySample(total: 100, used: UInt64(usage), free: 100 - UInt64(usage), wired: 0, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal),
                    gpu: GPUSample(utilization: usage)
                )
                let img = image(category, .text, snapshot: snap)
                XCTAssertEqual(img.size.width, width(.stackedPercent), "\(category) text at \(usage)% must keep the class width")
                XCTAssertEqual(img.size.height, 22.0)
            }
        }
        // Placeholders keep the same width
        XCTAssertEqual(image(.cpu, .text).size.width, width(.stackedPercent))
        XCTAssertGreaterThanOrEqual(width(.stackedPercent), 32.0)

        // Template when no status color applies
        XCTAssertTrue(image(.cpu, .text, snapshot: WidgetSnapshot(cpu: cpu(20))).isTemplate)
    }

    func testTemperatureFanAndStorageTextWidthsAreFixed() {
        for celsius in [20.0, 52.0, 99.0, 105.0] {
            let thermal = ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: celsius)])
            let img = image(.thermal, .text, snapshot: WidgetSnapshot(thermal: thermal))
            XCTAssertEqual(img.size.width, image(.thermal, .text, snapshot: WidgetSnapshot(thermal: ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: 40)]))).size.width)
        }
        for rpm in [0, 900, 2400, 6500, 9999] {
            let fan = FanSample(fans: [FanReading(name: "Fan", rpm: rpm, minRPM: 1000, maxRPM: 6500)])
            XCTAssertEqual(image(.fan, .text, snapshot: WidgetSnapshot(fan: fan)).size.width, width(.stackedRPM), "fan text at \(rpm) rpm")
        }
        for free: UInt64 in [500_000_000, 9_000_000_000, 412_000_000_000, 1_200_000_000_000] {
            let disk = DiskSample(volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 2_000_000_000_000, used: 2_000_000_000_000 - free, free: free)])
            XCTAssertEqual(image(.disk, .text, snapshot: WidgetSnapshot(disk: disk)).size.width, width(.stackedBytes), "disk free \(free)")
        }
    }

    // MARK: - 2. Throughput: 60 pt two-line, 82 pt single-line

    func testStackedThroughputWidthInvariance() {
        let rates: [(Double, Double)] = [
            (0, 0), (512, 1024), (1024 * 12, 1024 * 45),
            (1024 * 1024 * 1.5, 1024 * 1024 * 8.2),
            (1024 * 1024 * 125, 1024 * 1024 * 450),
            (1024 * 1024 * 1024 * 1.2, 1024 * 1024 * 1024 * 3.5)
        ]
        for (inB, outB) in rates {
            let net = NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: inB, bytesOutPerSec: outB, totalBytesIn: 0, totalBytesOut: 0)])
            for standard in [Units.ByteUnitStandard.iec, .si] {
                for unit in [Units.NetworkUnit.bytesPerSecond, .bitsPerSecond] {
                    let stacked = image(.network, .throughput, snapshot: WidgetSnapshot(network: net), layout: .stacked,
                                        options: WidgetOptions(networkUnit: unit, byteUnitStandard: standard))
                    XCTAssertEqual(stacked.size.width, width(.twoLineRate), "network stacked \(unit) \(standard)")
                    XCTAssertEqual(stacked.size.height, 22.0)
                    XCTAssertTrue(stacked.isTemplate)

                    let single = image(.network, .throughput, snapshot: WidgetSnapshot(network: net), layout: .singleLine,
                                       options: WidgetOptions(networkUnit: unit, byteUnitStandard: standard))
                    XCTAssertEqual(single.size.width, width(.singleLineRate), "network single-line \(unit) \(standard)")
                }
            }
            let disk = DiskSample(io: DiskIO(bytesReadPerSec: inB, bytesWrittenPerSec: outB, readOpsPerSec: 0, writeOpsPerSec: 0))
            let diskImg = image(.disk, .throughput, snapshot: WidgetSnapshot(disk: disk), layout: .stacked)
            XCTAssertEqual(diskImg.size.width, width(.twoLineRate), "disk stacked throughput")
            XCTAssertEqual(diskImg.size.height, 22.0)
            XCTAssertEqual(image(.disk, .throughput, snapshot: WidgetSnapshot(disk: disk), layout: .singleLine).size.width, width(.singleLineRate))
        }
    }

    // MARK: - 3. Single capsule bar: 25 x 22

    func testSingleCapsuleBarGeometryInvariance() {
        for pct in [0.0, 15.0, 50.0, 85.0, 100.0, 150.0] {
            let mem = MemorySample(total: 100, used: UInt64(min(pct, 100)), free: 0, wired: 0, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal)
            let snap = WidgetSnapshot(
                memory: mem,
                gpu: GPUSample(utilization: pct),
                thermal: ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: 30 + pct)]),
                fan: FanSample(fans: [FanReading(name: "Fan", rpm: Int(pct * 60), minRPM: 0, maxRPM: 6000)]),
                disk: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 100, used: UInt64(min(pct, 100)), free: 0)])
            )
            for (category, style) in [(MetricCategory.memory, MetricDisplayStyle.bar), (.gpu, .bar), (.thermal, .bar), (.fan, .bar), (.disk, .bar)] {
                let img = image(category, style, snapshot: snap)
                XCTAssertEqual(img.size, NSSize(width: 25, height: 22), "\(category) bar at \(pct)")
            }
        }
    }

    // MARK: - 4. Dual capsule bar: 36 x 22

    func testDualCapsuleBarGeometryInvariance() {
        for (user, sys) in [(0.0, 0.0), (25.0, 75.0), (100.0, 100.0)] {
            let img = image(.cpu, .bar, snapshot: WidgetSnapshot(cpu: cpu(user, user: user, system: sys)))
            XCTAssertEqual(img.size, NSSize(width: 36, height: 22))
        }
        // Hybrid E/P cores and larger core counts keep the same width
        let hybrid = CPUSample(totalUsage: 50, perCore: Array(repeating: 25.0, count: 6) + Array(repeating: 80.0, count: 4),
                               user: 45, system: 10, idle: 50, efficiencyCoreCount: 6, performanceCoreCount: 4)
        XCTAssertEqual(image(.cpu, .bar, snapshot: WidgetSnapshot(cpu: hybrid)).size, NSSize(width: 36, height: 22))
        let sixteen = CPUSample(totalUsage: 65, perCore: Array(repeating: 65.0, count: 16), user: 50, system: 15, idle: 35)
        XCTAssertEqual(image(.cpu, .bar, snapshot: WidgetSnapshot(cpu: sixteen)).size, NSSize(width: 36, height: 22))
        XCTAssertEqual(image(.cpu, .bar).size, NSSize(width: 36, height: 22))

        let dualFan = FanSample(fans: [
            FanReading(name: "Fan 1", rpm: 2000, minRPM: 1500, maxRPM: 6000),
            FanReading(name: "Fan 2", rpm: 3500, minRPM: 1500, maxRPM: 6000)
        ])
        XCTAssertEqual(image(.fan, .bar, snapshot: WidgetSnapshot(fan: dualFan)).size, NSSize(width: 36, height: 22))
        XCTAssertEqual(image(.fan, .throughput, snapshot: WidgetSnapshot(fan: dualFan)).size, NSSize(width: width(.twoLineFan), height: 22))
    }

    // MARK: - 5. Sparklines and graphs: 36 x 16 (50 x 22 labeled)

    func testSparklineGeometryInvariance() {
        let sets: [[Double]] = [[], [50.0], [10, 20, 30, 40, 50], Array(repeating: 100.0, count: 60)]
        for values in sets {
            let snap = WidgetSnapshot(series: series(values, secondary: values, tertiary: values))
            let cases: [(MetricCategory, MetricDisplayStyle)] = [
                (.cpu, .sparkline), (.memory, .sparkline), (.gpu, .sparkline), (.thermal, .sparkline),
                (.fan, .sparkline), (.power, .sparkline), (.network, .sparkline), (.disk, .sparkline)
            ]
            for (category, style) in cases {
                let bare = image(category, style, snapshot: snap)
                XCTAssertEqual(bare.size, NSSize(width: 36, height: 16), "\(category) sparkline with \(values.count) points")
                let labeled = image(category, style, snapshot: snap, showLabel: true)
                XCTAssertEqual(labeled.size, NSSize(width: 50, height: 22), "\(category) labeled sparkline")
            }
        }
    }

    // MARK: - 6. Rings: 18 x 18 (32 x 22 labeled)

    func testGaugesAndDonutPiesGeometryInvariance() {
        for pct in [0.0, 33.3, 50.0, 88.8, 100.0] {
            let snap = WidgetSnapshot(
                cpu: cpu(pct, user: pct * 0.7, system: pct * 0.3),
                memory: MemorySample(total: 100, used: UInt64(pct), free: 0, wired: 0, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal),
                gpu: GPUSample(utilization: pct),
                thermal: ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: 30 + pct * 0.7)]),
                disk: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 100, used: UInt64(pct), free: 0)])
            )
            for (category, style) in [(MetricCategory.cpu, MetricDisplayStyle.gauge), (.memory, .gauge), (.memory, .symbol),
                                      (.gpu, .gauge), (.thermal, .gauge), (.disk, .gauge)] {
                XCTAssertEqual(image(category, style, snapshot: snap).size, NSSize(width: 18, height: 18), "\(category) \(style) at \(pct)")
                XCTAssertEqual(image(category, style, snapshot: snap, showLabel: true).size, NSSize(width: 32, height: 22), "\(category) \(style) labeled")
            }
        }
    }

    // MARK: - 7. Battery instrument and power budget

    func testBatteryAndPowerBudgetGeometryInvariance() {
        for chg in [nil, 0.0, 15.0, 50.0, 85.0, 100.0] as [Double?] {
            for state in [BatteryState.discharging, .charging] {
                let power = PowerSample(hasBattery: true, charge: chg, state: state)
                XCTAssertEqual(image(.power, .symbol, snapshot: WidgetSnapshot(power: power)).size, NSSize(width: 25, height: 16))
            }
            XCTAssertEqual(image(.power, .symbol, snapshot: WidgetSnapshot(power: PowerSample(hasBattery: false))).size, NSSize(width: 25, height: 16))
            for variant in PowerStateVariant.allCases {
                XCTAssertEqual(MenuBarIconRenderer.drawBatteryInstrument(charge: chg, state: nil, hasBattery: true, variant: variant).size,
                               NSSize(width: 25, height: 16), "variant \(variant)")
            }
        }
        for (draw, adapter) in [(0.0, 0.0), (15.2, 67.0), (95.0, 140.0)] {
            let power = PowerSample(hasBattery: true, charge: 50, state: .discharging, powerDrawWatts: draw, adapterWatts: adapter)
            XCTAssertEqual(image(.power, .throughput, snapshot: WidgetSnapshot(power: power)).size, NSSize(width: width(.twoLinePower), height: 22))
        }
        // Battery text keeps its width class across values
        for chg in [5.0, 50.0, 100.0] {
            let power = PowerSample(hasBattery: true, charge: chg, state: .charging)
            XCTAssertEqual(image(.power, .text, snapshot: WidgetSnapshot(power: power)).size.width, width(.twoLinePower))
        }
    }

    // MARK: - 8. Thermometer glyph: one width regardless of digits

    func testThermometerGlyphWidthIsConstantAndNotClipped() {
        func width(_ celsius: Double, unit: Units.TemperatureUnit = .celsius) -> CGFloat {
            let thermal = ThermalSample(sensors: [SensorReading(name: "CPU die", celsius: celsius)])
            return image(.thermal, .glyph, snapshot: WidgetSnapshot(thermal: thermal), options: WidgetOptions(temperatureUnit: unit)).size.width
        }
        let two = width(52)
        XCTAssertGreaterThanOrEqual(two, 42.0)
        XCTAssertEqual(width(5), two, "1-digit temperature keeps the width")
        XCTAssertEqual(width(102), two, "3-digit temperature must not widen the glyph")
        XCTAssertEqual(width(100, unit: .fahrenheit), two, "°F values (212) must fit the same width")
        XCTAssertEqual(image(.thermal, .glyph).size.height, 22.0)
    }

    // MARK: - 9. Glyph widths

    func testFanGlyphArrowsAndLedsAreFixedWidth() {
        for rpm in [0, 800, 3200, 9999] {
            let fan = FanSample(fans: [FanReading(name: "Fan", rpm: rpm, minRPM: 0, maxRPM: 6000)])
            XCTAssertEqual(image(.fan, .glyph, snapshot: WidgetSnapshot(fan: fan)).size, NSSize(width: 44, height: 22))
        }
        XCTAssertEqual(image(.network, .symbol).size, NSSize(width: 18, height: 18))
        XCTAssertEqual(image(.disk, .symbol).size, NSSize(width: 20, height: 18))
    }

    // MARK: - 10. Minimum text size

    func testMinimumWidgetFontSizeIsNineAndLabelsKeepTheirBounds() {
        XCTAssertGreaterThanOrEqual(MenuBarIconRenderer.minimumWidgetFontSize, 9.0)
        let labeled = image(.memory, .bar)
        XCTAssertEqual(labeled.size.height, 22.0)
    }
}
