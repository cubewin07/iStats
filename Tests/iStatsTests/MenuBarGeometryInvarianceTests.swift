import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

/// Anti-jitter and geometry invariance test suite verifying that menu bar items maintain
/// strict, fixed pixel-perfect widths and bounding boxes across wildly fluctuating metric
/// numbers (preventing menu bar items from shifting / hopping horizontally).
@MainActor
final class MenuBarGeometryInvarianceTests: XCTestCase {

    // MARK: - 1. Category Stacked Text Width Invariance (32.0pt fixed width)

    func testCategoryStackedTextWidthInvarianceAcrossNumberFluctuations() {
        let testValues = [
            "0%", "1%", "5%", "9%",      // Single digit
            "10%", "25%", "50%", "99%",  // Two digits
            "100%",                       // Three digits
            "--%", "N/A"                  // Placeholders
        ]

        for val in testValues {
            let cpuText = MenuBarIconRenderer.drawCategoryStackedText(title: "CPU", value: val, fixedWidth: 32.0)
            XCTAssertEqual(cpuText.size.width, 32.0, "CPU stacked text width for '\(val)' must be exactly 32.0pt")
            XCTAssertEqual(cpuText.size.height, 22.0, "CPU stacked text height must be 22.0pt")
            XCTAssertTrue(cpuText.isTemplate, "Stacked text must be configured as macOS template image")

            let memText = MenuBarIconRenderer.drawCategoryStackedText(title: "MEM", value: val, fixedWidth: 32.0)
            XCTAssertEqual(memText.size.width, 32.0, "MEM stacked text width for '\(val)' must be exactly 32.0pt")

            let gpuText = MenuBarIconRenderer.drawCategoryStackedText(title: "GPU", value: val, fixedWidth: 32.0)
            XCTAssertEqual(gpuText.size.width, 32.0, "GPU stacked text width for '\(val)' must be exactly 32.0pt")

            let tmpText = MenuBarIconRenderer.drawCategoryStackedText(title: "TMP", value: val, fixedWidth: 32.0)
            XCTAssertEqual(tmpText.size.width, 32.0, "TMP stacked text width for '\(val)' must be exactly 32.0pt")

            let fanText = MenuBarIconRenderer.drawCategoryStackedText(title: "FAN", value: val, fixedWidth: 32.0)
            XCTAssertEqual(fanText.size.width, 32.0, "FAN stacked text width for '\(val)' must be exactly 32.0pt")
        }
    }

    // MARK: - 2. Stacked Throughput Two-Line Text Invariance (60.0pt fixed width)

    func testStackedThroughputTwoLineTextWidthInvariance() {
        let testRates: [(Double, Double)] = [
            (0, 0),                                           // 0 B/s
            (512, 1024),                                      // bytes
            (1024 * 12, 1024 * 45),                           // KB/s
            (1024 * 1024 * 1.5, 1024 * 1024 * 8.2),           // MB/s
            (1024 * 1024 * 125, 1024 * 1024 * 450),           // hundreds MB/s
            (1024 * 1024 * 1024 * 1.2, 1024 * 1024 * 1024 * 3.5) // GB/s
        ]

        for (inBytes, outBytes) in testRates {
            // Network IEC
            let netIEC = MenuBarIconRenderer.drawNetworkStackedThroughput(
                inBytes: inBytes,
                outBytes: outBytes,
                unit: .bytesPerSecond,
                standard: .iec
            )
            XCTAssertEqual(netIEC.size.width, 60.0, "Network IEC throughput must be invariant 60.0pt width")
            XCTAssertEqual(netIEC.size.height, 22.0, "Network throughput height must be 22.0pt")
            XCTAssertTrue(netIEC.isTemplate)

            // Network SI
            let netSI = MenuBarIconRenderer.drawNetworkStackedThroughput(
                inBytes: inBytes,
                outBytes: outBytes,
                unit: .bytesPerSecond,
                standard: .si
            )
            XCTAssertEqual(netSI.size.width, 60.0, "Network SI throughput must be invariant 60.0pt width")

            // Network Bits
            let netBits = MenuBarIconRenderer.drawNetworkStackedThroughput(
                inBytes: inBytes,
                outBytes: outBytes,
                unit: .bitsPerSecond,
                standard: .iec
            )
            XCTAssertEqual(netBits.size.width, 60.0, "Network Bits throughput must be invariant 60.0pt width")

            // Disk Throughput
            let diskThroughput = MenuBarIconRenderer.drawDiskStackedThroughput(
                readBytes: inBytes,
                writeBytes: outBytes,
                standard: .iec
            )
            XCTAssertEqual(diskThroughput.size.width, 60.0, "Disk throughput must be invariant 60.0pt width")
            XCTAssertEqual(diskThroughput.size.height, 22.0)
            XCTAssertTrue(diskThroughput.isTemplate)
        }
    }

    // MARK: - 3. Single Capsule Bar Geometry (25.0pt width × 22.0pt height)

    func testSingleCapsuleBarGeometryInvariance() {
        let percentages: [Double] = [0.0, 15.0, 50.0, 85.0, 100.0, 150.0]

        for pct in percentages {
            // RAM Bar
            let ramBar = MenuBarIconRenderer.drawMemoryBar(ratio: pct)
            XCTAssertEqual(ramBar.size.width, 25.0, "RAM single capsule bar must be 25.0pt wide")
            XCTAssertEqual(ramBar.size.height, 22.0, "RAM single capsule bar must be 22.0pt high")

            // GPU Bar
            let gpuBar = MenuBarIconRenderer.drawGPUBar(percentage: pct)
            XCTAssertEqual(gpuBar.size.width, 25.0, "GPU single capsule bar must be 25.0pt wide")
            XCTAssertEqual(gpuBar.size.height, 22.0)

            // Thermal Bar
            let tmpBar = MenuBarIconRenderer.drawThermalBar(percentage: pct)
            XCTAssertEqual(tmpBar.size.width, 25.0, "TMP single capsule bar must be 25.0pt wide")
            XCTAssertEqual(tmpBar.size.height, 22.0)

            // Fan Bar
            let fanBar = MenuBarIconRenderer.drawFanBar(percentage: pct)
            XCTAssertEqual(fanBar.size.width, 25.0, "FAN single capsule bar must be 25.0pt wide")
            XCTAssertEqual(fanBar.size.height, 22.0)

            // Power Bar
            let powerBar = MenuBarIconRenderer.drawPowerBar(percentage: pct)
            XCTAssertEqual(powerBar.size.width, 25.0, "BAT single capsule bar must be 25.0pt wide")
            XCTAssertEqual(powerBar.size.height, 22.0)

            // Disk Bar
            let diskBar = MenuBarIconRenderer.drawDiskBar(percentage: pct)
            XCTAssertEqual(diskBar.size.width, 25.0, "SSD single capsule bar must be 25.0pt wide")
            XCTAssertEqual(diskBar.size.height, 22.0)
        }
    }

    // MARK: - 4. Dual Capsule Bar Geometry (36.0pt width × 22.0pt height)

    func testDualCapsuleBarGeometryInvariance() {
        let pairs: [(Double, Double)] = [
            (0.0, 0.0),
            (25.0, 75.0),
            (100.0, 100.0)
        ]

        for (left, right) in pairs {
            // Generic Dual Bar
            let genericDual = MenuBarIconRenderer.drawDualCapsuleBar(label: "NET", leftPercentage: left, rightPercentage: right)
            XCTAssertEqual(genericDual.size.width, 36.0, "Dual capsule bar width must be 36.0pt")
            XCTAssertEqual(genericDual.size.height, 22.0, "Dual capsule bar height must be 22.0pt")

            // Network Dual Bar
            let netDual = MenuBarIconRenderer.drawNetworkBar(inPct: left, outPct: right)
            XCTAssertEqual(netDual.size.width, 36.0, "Network dual bar width must be 36.0pt")
            XCTAssertEqual(netDual.size.height, 22.0)

            // Disk Dual Bar
            let diskDual = MenuBarIconRenderer.drawDiskBar(readPct: left, writePct: right)
            XCTAssertEqual(diskDual.size.width, 36.0, "Disk dual bar width must be 36.0pt")
            XCTAssertEqual(diskDual.size.height, 22.0)
        }

        // Dual Fan Bar
        let dualFan = FanSample(fans: [
            FanReading(name: "Fan 1", rpm: 2000, minRPM: 1500, maxRPM: 6000),
            FanReading(name: "Fan 2", rpm: 3500, minRPM: 1500, maxRPM: 6000)
        ])
        let fanDual = MenuBarIconRenderer.drawFanBar(fan: dualFan)
        XCTAssertEqual(fanDual.size.width, 36.0, "Dual fan bar width must be 36.0pt")
        XCTAssertEqual(fanDual.size.height, 22.0)

        let fanThroughput = MenuBarIconRenderer.drawFanStackedThroughput(fan: dualFan)
        XCTAssertEqual(fanThroughput.size.width, 36.0, "Dual fan throughput width must be 36.0pt")
        XCTAssertEqual(fanThroughput.size.height, 22.0)
    }

    // MARK: - 5. Sparkline & Graph Geometry (36.0pt width × 16.0pt height)

    func testSparklineGeometryInvariance() {
        let historySets: [[Double]] = [
            [],
            [50.0],
            [10.0, 20.0, 30.0, 40.0, 50.0],
            Array(repeating: 100.0, count: 60)
        ]

        for history in historySets {
            let cpuSparkline = MenuBarIconRenderer.drawCPUSparkline(history: history)
            XCTAssertEqual(cpuSparkline.size.width, 36.0, "CPU sparkline width must be 36.0pt")
            XCTAssertEqual(cpuSparkline.size.height, 16.0, "CPU sparkline height must be 16.0pt")

            let memSparkline = MenuBarIconRenderer.drawMemorySparkline(history: history)
            XCTAssertEqual(memSparkline.size.width, 36.0)
            XCTAssertEqual(memSparkline.size.height, 16.0)

            let gpuSparkline = MenuBarIconRenderer.drawGPUSparkline(history: history)
            XCTAssertEqual(gpuSparkline.size.width, 36.0)
            XCTAssertEqual(gpuSparkline.size.height, 16.0)

            let tmpSparkline = MenuBarIconRenderer.drawThermalSparkline(history: history)
            XCTAssertEqual(tmpSparkline.size.width, 36.0)
            XCTAssertEqual(tmpSparkline.size.height, 16.0)

            let fanSparkline = MenuBarIconRenderer.drawFanSparkline(history: history)
            XCTAssertEqual(fanSparkline.size.width, 36.0)
            XCTAssertEqual(fanSparkline.size.height, 16.0)

            let pwrSparkline = MenuBarIconRenderer.drawPowerSparkline(history: history)
            XCTAssertEqual(pwrSparkline.size.width, 36.0)
            XCTAssertEqual(pwrSparkline.size.height, 16.0)

            let diskSparkline = MenuBarIconRenderer.drawDiskSparkline(history: history)
            XCTAssertEqual(diskSparkline.size.width, 36.0)
            XCTAssertEqual(diskSparkline.size.height, 16.0)

            let netSplit = MenuBarIconRenderer.drawNetworkSplitDuplexGraph(inHistory: history, outHistory: history)
            XCTAssertEqual(netSplit.size.width, 36.0)
            XCTAssertEqual(netSplit.size.height, 16.0)
        }
    }

    // MARK: - 6. Gauges & Donut Pies (18.0pt × 18.0pt)

    func testGaugesAndDonutPiesGeometryInvariance() {
        let percentages: [Double] = [0.0, 33.3, 50.0, 88.8, 100.0]

        for pct in percentages {
            let cpuDonut = MenuBarIconRenderer.drawCPUDonutPie(user: pct * 0.7, system: pct * 0.3)
            XCTAssertEqual(cpuDonut.size, NSSize(width: 18, height: 18), "CPU donut must be 18x18pt")

            let memGauge = MenuBarIconRenderer.drawMemoryGauge(ratio: pct)
            XCTAssertEqual(memGauge.size, NSSize(width: 18, height: 18), "Memory gauge must be 18x18pt")

            let gpuGauge = MenuBarIconRenderer.drawGPUGauge(percentage: pct)
            XCTAssertEqual(gpuGauge.size, NSSize(width: 18, height: 18), "GPU gauge must be 18x18pt")

            let tmpGauge = MenuBarIconRenderer.drawThermalGauge(percentage: pct)
            XCTAssertEqual(tmpGauge.size, NSSize(width: 18, height: 18), "Thermal gauge must be 18x18pt")

            let fanGauge = MenuBarIconRenderer.drawFanGauge(percentage: pct)
            XCTAssertEqual(fanGauge.size, NSSize(width: 18, height: 18), "Fan gauge must be 18x18pt")

            let diskGauge = MenuBarIconRenderer.drawDiskGauge(percentage: pct)
            XCTAssertEqual(diskGauge.size, NSSize(width: 18, height: 18), "Disk gauge must be 18x18pt")

            let pwrGauge = MenuBarIconRenderer.drawPowerGauge(percentage: pct)
            XCTAssertEqual(pwrGauge.size, NSSize(width: 18, height: 18), "Power gauge must be 18x18pt")
        }
    }

    // MARK: - 7. Battery Instrument & Power Budget (25x16pt and 34x22pt)

    func testBatteryAndPowerBudgetGeometryInvariance() {
        // Battery instrument (25.0pt × 16.0pt)
        let charges: [Double?] = [nil, 0.0, 15.0, 50.0, 85.0, 100.0]
        for chg in charges {
            let batDischarging = MenuBarIconRenderer.drawBatteryInstrument(charge: chg, state: .discharging, hasBattery: true)
            XCTAssertEqual(batDischarging.size, NSSize(width: 25, height: 16), "Battery instrument must be 25x16pt")

            let batCharging = MenuBarIconRenderer.drawBatteryInstrument(charge: chg, state: .charging, hasBattery: true)
            XCTAssertEqual(batCharging.size, NSSize(width: 25, height: 16))

            let batDesktop = MenuBarIconRenderer.drawBatteryInstrument(charge: nil, state: nil, hasBattery: false)
            XCTAssertEqual(batDesktop.size, NSSize(width: 25, height: 16))
        }

        // Power budget text (34.0pt × 22.0pt)
        let budgets: [(Double, Double)] = [
            (0, 0),
            (15.2, 67.0),
            (95.0, 140.0)
        ]
        for (drawW, adapterW) in budgets {
            let budgetImg = MenuBarIconRenderer.drawPowerBudgetText(drawWatts: drawW, adapterWatts: adapterW)
            XCTAssertEqual(budgetImg.size, NSSize(width: 34, height: 22), "Power budget text must be 34x22pt")
        }
    }

    // MARK: - 8. CPU Per-Core Cluster Width Invariance

    func testCPUPerCoreBarClusterGeometry() {
        // Multi-core cluster (>= 2 cores): fixed 41.0pt width
        let cores2 = [30.0, 50.0]
        let img2 = MenuBarIconRenderer.drawCPUBar(perCore: cores2, user: 40.0, system: 10.0)
        XCTAssertEqual(img2.size.width, 41.0, "CPU per-core cluster for 2 cores must be 41.0pt wide")
        XCTAssertEqual(img2.size.height, 22.0)

        let cores4 = [20.0, 40.0, 60.0, 80.0]
        let img4 = MenuBarIconRenderer.drawCPUBar(perCore: cores4, user: 50.0, system: 10.0)
        XCTAssertEqual(img4.size.width, 41.0, "CPU per-core cluster for 4 cores must be 41.0pt wide")
        XCTAssertEqual(img4.size.height, 22.0)

        let cores8 = Array(repeating: 50.0, count: 8)
        let img8 = MenuBarIconRenderer.drawCPUBar(perCore: cores8, user: 40.0, system: 10.0)
        XCTAssertEqual(img8.size.width, 41.0, "CPU per-core cluster for 8 cores must be 41.0pt wide")
        XCTAssertEqual(img8.size.height, 22.0)

        let cores16 = Array(repeating: 65.0, count: 16)
        let img16 = MenuBarIconRenderer.drawCPUBar(perCore: cores16, user: 50.0, system: 15.0)
        XCTAssertEqual(img16.size.width, 41.0, "CPU per-core cluster for 16 cores must be 41.0pt wide")
        XCTAssertEqual(img16.size.height, 22.0)

        // Single core / nil perCore fallback (dual or single capsule bar)
        let imgNil = MenuBarIconRenderer.drawCPUBar(perCore: nil, user: 40.0, system: 10.0)
        XCTAssertEqual(imgNil.size.width, 36.0, "Single-core dual bar fallback must be 36.0pt wide")
        XCTAssertEqual(imgNil.size.height, 22.0)
    }
}
