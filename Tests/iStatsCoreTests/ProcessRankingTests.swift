import XCTest
@testable import iStatsCore

final class ProcessRankingTests: XCTestCase {

    func testNewPIDReturnsZeroCPU() {
        let now = Date()
        let snap = RawProcessSnapshot(
            pid: 101,
            name: "NewApp",
            totalCpuTimeNs: 500_000_000,
            physicalFootprintBytes: 50_000_000,
            timestamp: now
        )

        let (sample, newRecords) = ProcessRanking.rankProcesses(
            currentSnapshots: [snap],
            previousRecords: [:]
        )

        XCTAssertEqual(sample.topCPU.count, 1)
        XCTAssertEqual(sample.topCPU.first?.cpuPercent, 0.0)
        XCTAssertEqual(sample.topMemory.first?.memoryBytes, 50_000_000)
        XCTAssertEqual(newRecords[101]?.totalCpuTimeNs, 500_000_000)
    }

    func testSteadyLoadCalculatesAccuratePercentage() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let t1 = Date(timeIntervalSince1970: 1002.0) // 2.0s delta

        let prevRecords: [Int32: ProcessCPURecord] = [
            201: ProcessCPURecord(totalCpuTimeNs: 1_000_000_000, timestamp: t0)
        ]

        // Consumed 1.0s of CPU time over 2.0s wall time -> 50% CPU
        let currentSnap = RawProcessSnapshot(
            pid: 201,
            name: "ActiveApp",
            totalCpuTimeNs: 2_000_000_000,
            physicalFootprintBytes: 120_000_000,
            timestamp: t1
        )

        let (sample, _) = ProcessRanking.rankProcesses(
            currentSnapshots: [currentSnap],
            previousRecords: prevRecords
        )

        XCTAssertEqual(sample.topCPU.first?.cpuPercent ?? 0, 50.0, accuracy: 0.01)
    }

    func testCounterResetOrPIDReuseNeverYieldsNegative() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let t1 = Date(timeIntervalSince1970: 1002.0)

        // Previous PID had high CPU time
        let prevRecords: [Int32: ProcessCPURecord] = [
            301: ProcessCPURecord(totalCpuTimeNs: 50_000_000_000, timestamp: t0)
        ]

        // PID was reused or counter reset to a lower value
        let currentSnap = RawProcessSnapshot(
            pid: 301,
            name: "ReusedPIDApp",
            totalCpuTimeNs: 1_000_000,
            physicalFootprintBytes: 20_000_000,
            timestamp: t1
        )

        let (sample, _) = ProcessRanking.rankProcesses(
            currentSnapshots: [currentSnap],
            previousRecords: prevRecords
        )

        XCTAssertEqual(sample.topCPU.first?.cpuPercent, 0.0)
    }

    func testTieBreakingDeterministicByPID() {
        let items = [
            ProcessInfoItem(pid: 500, name: "AppB", cpuPercent: 25.0, memoryBytes: 100),
            ProcessInfoItem(pid: 200, name: "AppA", cpuPercent: 25.0, memoryBytes: 100)
        ]

        let top = ProcessRanking.topN(items: items, by: .cpu, limit: 2)
        XCTAssertEqual(top.first?.pid, 200)
        XCTAssertEqual(top.last?.pid, 500)
    }

    func testLimitGreaterThanCountReturnsAllAvailable() {
        let items = [
            ProcessInfoItem(pid: 1, name: "App1", cpuPercent: 10.0, memoryBytes: 200),
            ProcessInfoItem(pid: 2, name: "App2", cpuPercent: 20.0, memoryBytes: 100)
        ]

        let top = ProcessRanking.topN(items: items, by: .memory, limit: 10)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top.first?.pid, 1)
        XCTAssertEqual(top.last?.pid, 2)
    }

    func testGroupChildrenAggregatesUnderSameBundleID() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let t1 = Date(timeIntervalSince1970: 1001.0)

        let prevRecords: [Int32: ProcessCPURecord] = [
            10: ProcessCPURecord(totalCpuTimeNs: 1_000_000_000, timestamp: t0),
            11: ProcessCPURecord(totalCpuTimeNs: 1_000_000_000, timestamp: t0)
        ]

        let snaps = [
            RawProcessSnapshot(
                pid: 10,
                name: "Safari",
                bundleID: "com.apple.Safari",
                totalCpuTimeNs: 1_200_000_000, // +20%
                physicalFootprintBytes: 200_000_000,
                timestamp: t1
            ),
            RawProcessSnapshot(
                pid: 11,
                name: "com.apple.WebKit.WebContent",
                bundleID: "com.apple.Safari",
                totalCpuTimeNs: 1_300_000_000, // +30%
                physicalFootprintBytes: 300_000_000,
                timestamp: t1
            )
        ]

        let (sample, _) = ProcessRanking.rankProcesses(
            currentSnapshots: snaps,
            previousRecords: prevRecords,
            limit: 5,
            groupChildren: true
        )

        XCTAssertEqual(sample.topCPU.count, 1)
        XCTAssertEqual(sample.topCPU.first?.name, "Safari")
        XCTAssertEqual(sample.topCPU.first?.cpuPercent ?? 0, 50.0, accuracy: 0.1)
        XCTAssertEqual(sample.topMemory.first?.memoryBytes, 500_000_000)
    }
}

