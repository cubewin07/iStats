import XCTest
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class DetailViewGraphsTests: XCTestCase {
    // MARK: - MetricsCoordinator Tests

    func testMetricsCoordinatorInitialization() {
        let scheduler = SampleScheduler()
        let store = MetricsStore()
        let defaults = UserDefaults(suiteName: "iStats.test.coordinator.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)

        let coordinator = MetricsCoordinator(scheduler: scheduler, store: store, preferencesStore: prefs)

        XCTAssertNil(coordinator.latestCPU)
        XCTAssertNil(coordinator.latestMemory)
        XCTAssertTrue(coordinator.cpuHistory.isEmpty)
        XCTAssertTrue(coordinator.memoryHistory.isEmpty)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testMetricsCoordinatorHandlesReadings() {
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: PreferencesStore(userDefaults: UserDefaults(suiteName: "iStats.test.\(UUID().uuidString)")!)
        )

        let cpuSample = CPUSample(
            totalUsage: 25.5,
            perCore: [20.0, 31.0],
            user: 15.0,
            system: 10.5,
            idle: 74.5,
            loadAverage: LoadAverage(oneMinute: 1.5, fiveMinute: 1.2, fifteenMinute: 0.9),
            frequencyHz: 3_200_000_000
        )
        let cpuReading = MetricReading.cpu(Sample(value: cpuSample, timestamp: Date(), availability: .available))
        coordinator.handleReading(cpuReading)

        XCTAssertNotNil(coordinator.latestCPU)
        XCTAssertEqual(coordinator.latestCPU?.value.totalUsage, 25.5)
        XCTAssertEqual(coordinator.cpuHistory.count, 1)

        let memSample = MemorySample(
            total: 16 * 1024 * 1024 * 1024,
            used: 10 * 1024 * 1024 * 1024,
            free: 6 * 1024 * 1024 * 1024,
            wired: 3 * 1024 * 1024 * 1024,
            compressed: 2 * 1024 * 1024 * 1024,
            cached: 4 * 1024 * 1024 * 1024,
            swapUsed: 512 * 1024 * 1024,
            pressure: .normal
        )
        let memReading = MetricReading.memory(Sample(value: memSample, timestamp: Date(), availability: .available))
        coordinator.handleReading(memReading)

        XCTAssertNotNil(coordinator.latestMemory)
        XCTAssertEqual(coordinator.latestMemory?.value.total, 16 * 1024 * 1024 * 1024)
        XCTAssertEqual(coordinator.memoryHistory.count, 1)
    }

    // MARK: - RollingGraphView Tests

    func testRollingGraphPointCalculation() {
        let graph = RollingGraphView(
            values: [0.0, 50.0, 100.0],
            minValue: 0.0,
            maxValue: 100.0,
            tintColor: .blue,
            capacity: 3,
            height: 100,
            showGrid: true
        )

        let points = graph.calculatePoints(width: 200, height: 100)
        XCTAssertEqual(points.count, 3)

        // First point (0%) should be near the bottom (height - 2)
        XCTAssertEqual(points[0].x, 0.0, accuracy: 0.1)
        XCTAssertEqual(points[0].y, 98.0, accuracy: 0.1)

        // Middle point (50%) should be in the vertical center
        XCTAssertEqual(points[1].x, 100.0, accuracy: 0.1)
        XCTAssertEqual(points[1].y, 50.0, accuracy: 0.1)

        // Last point (100%) should be near the top (2.0)
        XCTAssertEqual(points[2].x, 200.0, accuracy: 0.1)
        XCTAssertEqual(points[2].y, 2.0, accuracy: 0.1)
    }

    func testRollingGraphEmptyValues() {
        let graph = RollingGraphView(values: [], minValue: 0, maxValue: 100)
        let points = graph.calculatePoints(width: 100, height: 50)
        XCTAssertTrue(points.isEmpty)
    }

    // MARK: - MenuBarController Title & Tooltip Formatting

    func testMenuBarFormatting() {
        let cpu = CPUSample(
            totalUsage: 14.2,
            perCore: [10, 18],
            user: 8,
            system: 6,
            idle: 86
        )
        let mem = MemorySample(
            total: 1000,
            used: 650,
            free: 350,
            wired: 200,
            compressed: 100,
            cached: 150,
            swapUsed: 0,
            pressure: .normal
        )

        // Icon mode
        XCTAssertEqual(MenuBarController.formatTitle(mode: .icon, cpu: cpu, memory: mem), "")

        // CPU mode
        XCTAssertEqual(MenuBarController.formatTitle(mode: .cpu, cpu: cpu, memory: mem), "CPU 14%")
        XCTAssertEqual(MenuBarController.formatTitle(mode: .cpu, cpu: nil, memory: mem), "CPU --%")

        // Memory mode
        XCTAssertEqual(MenuBarController.formatTitle(mode: .memory, cpu: cpu, memory: mem), "RAM 65%")
        XCTAssertEqual(MenuBarController.formatTitle(mode: .memory, cpu: cpu, memory: nil), "RAM --%")

        // Both mode
        XCTAssertEqual(MenuBarController.formatTitle(mode: .both, cpu: cpu, memory: mem), "CPU 14%  RAM 65%")
        XCTAssertEqual(MenuBarController.formatTitle(mode: .both, cpu: nil, memory: mem), "CPU --%  RAM 65%")

        // Tooltip
        let tooltip = MenuBarController.formatToolTip(cpu: cpu, memory: mem)
        XCTAssertTrue(tooltip.contains("CPU: 14.2%"))
        XCTAssertTrue(tooltip.contains("RAM: 65.0% (Normal)"))
    }

    // MARK: - SwiftUI View Instantiation & Hierarchy Tests

    func testCPUSummaryViewRendering() {
        let sample = CPUSample(
            totalUsage: 45.0,
            perCore: [30.0, 40.0, 50.0, 60.0, 20.0, 35.0, 70.0, 55.0],
            user: 30.0,
            system: 15.0,
            idle: 55.0,
            loadAverage: LoadAverage(oneMinute: 2.1, fiveMinute: 1.8, fifteenMinute: 1.5),
            frequencyHz: 3_500_000_000,
            efficiencyCoreCount: 4,
            performanceCoreCount: 4
        )
        let history = [Sample(value: sample, timestamp: Date(), availability: .available)]

        let view = CPUSummaryView(sample: sample, history: history)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        XCTAssertNotNil(hosting)
    }

    func testCPUSummaryViewHighCoreCountAndIntelRendering() {
        // High core count (e.g. 24 cores)
        let highCoreSample = CPUSample(
            totalUsage: 65.0,
            perCore: Array(repeating: 65.0, count: 24),
            user: 50.0,
            system: 15.0,
            idle: 35.0,
            efficiencyCoreCount: 8,
            performanceCoreCount: 16
        )
        let view24 = CPUSummaryView(sample: highCoreSample, history: [])
        let hosting24 = NSHostingView(rootView: view24)
        hosting24.frame = CGRect(x: 0, y: 0, width: 320, height: 350)
        XCTAssertNotNil(hosting24)

        // Intel / No topology
        let intelSample = CPUSample(
            totalUsage: 25.0,
            perCore: [20.0, 30.0, 25.0, 25.0],
            user: 15.0,
            system: 10.0,
            idle: 75.0
        )
        let viewIntel = CPUSummaryView(sample: intelSample, history: [])
        let hostingIntel = NSHostingView(rootView: viewIntel)
        hostingIntel.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        XCTAssertNotNil(hostingIntel)
    }

    func testDetailPopoverViewRendering() {
        let defaults = UserDefaults(suiteName: "iStats.test.popover.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )

        let cpu = CPUSample(totalUsage: 12.0, perCore: [12.0], user: 8.0, system: 4.0, idle: 88.0)
        let mem = MemorySample(total: 8000, used: 4000, free: 4000, wired: 1000, compressed: 500, cached: 1000, swapUsed: 0, pressure: .normal)

        let popover = DetailPopoverView(
            coordinator: coordinator,
            preferences: prefs,
            cpuSample: cpu,
            memorySample: mem,
            cpuHistory: [Sample(value: cpu)],
            memoryHistory: [Sample(value: mem)]
        )

        let hosting = NSHostingView(rootView: popover)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
        XCTAssertNotNil(hosting)
    }

    // MARK: - Network & Disk Coordinator & View Tests

    func testMetricsCoordinatorHandlesNetworkAndDiskReadings() {
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: PreferencesStore(userDefaults: UserDefaults(suiteName: "iStats.test.netdisk.\(UUID().uuidString)")!)
        )

        let netSample = NetworkSample(interfaces: [
            InterfaceThroughput(
                interfaceName: "en0",
                bytesInPerSec: 1024 * 500,
                bytesOutPerSec: 1024 * 100,
                totalBytesIn: 1024 * 1024 * 50,
                totalBytesOut: 1024 * 1024 * 10
            )
        ])
        let netReading = MetricReading.network(Sample(value: netSample, timestamp: Date(), availability: .available))
        coordinator.handleReading(netReading)

        XCTAssertNotNil(coordinator.latestNetwork)
        XCTAssertEqual(coordinator.latestNetwork?.value.totalBytesInPerSec, 1024 * 500)
        XCTAssertEqual(coordinator.latestNetwork?.value.totalBytesOutPerSec, 1024 * 100)
        XCTAssertEqual(coordinator.networkHistory.count, 1)

        let diskSample = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 1_000_000_000_000, used: 400_000_000_000, free: 600_000_000_000)
            ],
            io: DiskIO(bytesReadPerSec: 5_000_000, bytesWrittenPerSec: 2_000_000, readOpsPerSec: 150, writeOpsPerSec: 60)
        )
        let diskReading = MetricReading.disk(Sample(value: diskSample, timestamp: Date(), availability: .available))
        coordinator.handleReading(diskReading)

        XCTAssertNotNil(coordinator.latestDisk)
        XCTAssertEqual(coordinator.latestDisk?.value.volumes.count, 1)
        XCTAssertEqual(coordinator.latestDisk?.value.io?.bytesReadPerSec, 5_000_000)
        XCTAssertEqual(coordinator.diskHistory.count, 1)
    }

    func testNetworkSummaryViewRendering() {
        let netSample = NetworkSample(interfaces: [
            InterfaceThroughput(
                interfaceName: "en0",
                bytesInPerSec: 1024 * 1024 * 2.5,
                bytesOutPerSec: 1024 * 512,
                totalBytesIn: 1024 * 1024 * 1024 * 10,
                totalBytesOut: 1024 * 1024 * 1024 * 2
            ),
            InterfaceThroughput(
                interfaceName: "pdp_ip0",
                bytesInPerSec: 0,
                bytesOutPerSec: 0,
                totalBytesIn: 1024 * 100,
                totalBytesOut: 1024 * 50
            )
        ])
        let history = [Sample(value: netSample, timestamp: Date(), availability: .available)]

        // Bytes/sec IEC
        let viewBytesIEC = NetworkSummaryView(
            sample: netSample,
            history: history,
            networkUnit: .bytesPerSecond,
            byteStandard: .iec
        )
        let hostingBytesIEC = NSHostingView(rootView: viewBytesIEC)
        hostingBytesIEC.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        XCTAssertNotNil(hostingBytesIEC)

        // Bits/sec SI
        let viewBitsSI = NetworkSummaryView(
            sample: netSample,
            history: history,
            networkUnit: .bitsPerSecond,
            byteStandard: .si
        )
        let hostingBitsSI = NSHostingView(rootView: viewBitsSI)
        hostingBitsSI.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        XCTAssertNotNil(hostingBitsSI)

        // Empty / nil sample
        let viewNil = NetworkSummaryView(sample: nil, history: [])
        let hostingNil = NSHostingView(rootView: viewNil)
        XCTAssertNotNil(hostingNil)
    }

    func testDiskSummaryViewRenderingWithAndWithoutIO() {
        let volumes = [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500 * 1024 * 1024 * 1024, used: 250 * 1024 * 1024 * 1024, free: 250 * 1024 * 1024 * 1024),
            VolumeCapacity(name: "External Drive", mountPoint: "/Volumes/Backup", total: 1000 * 1024 * 1024 * 1024, used: 900 * 1024 * 1024 * 1024, free: 100 * 1024 * 1024 * 1024)
        ]
        let io = DiskIO(bytesReadPerSec: 1024 * 1024 * 15, bytesWrittenPerSec: 1024 * 1024 * 8, readOpsPerSec: 200, writeOpsPerSec: 80)
        let sampleWithIO = DiskSample(volumes: volumes, io: io)
        let history = [Sample(value: sampleWithIO, timestamp: Date(), availability: .available)]

        // With I/O
        let viewWithIO = DiskSummaryView(sample: sampleWithIO, history: history, byteStandard: .iec)
        let hostingWithIO = NSHostingView(rootView: viewWithIO)
        hostingWithIO.frame = CGRect(x: 0, y: 0, width: 320, height: 350)
        XCTAssertNotNil(hostingWithIO)

        // Without I/O (graceful degradation)
        let sampleWithoutIO = DiskSample(volumes: volumes, io: nil)
        let viewWithoutIO = DiskSummaryView(sample: sampleWithoutIO, history: [], byteStandard: .si)
        let hostingWithoutIO = NSHostingView(rootView: viewWithoutIO)
        hostingWithoutIO.frame = CGRect(x: 0, y: 0, width: 320, height: 250)
        XCTAssertNotNil(hostingWithoutIO)

        // Nil sample
        let viewNil = DiskSummaryView(sample: nil, history: [])
        let hostingNil = NSHostingView(rootView: viewNil)
        XCTAssertNotNil(hostingNil)
    }

    func testDetailPopoverViewWithAllCategories() {
        let defaults = UserDefaults(suiteName: "iStats.test.allpopover.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )

        let cpu = CPUSample(totalUsage: 22.0, perCore: [22.0], user: 12.0, system: 10.0, idle: 78.0)
        let mem = MemorySample(total: 16000, used: 8000, free: 8000, wired: 2000, compressed: 1000, cached: 2000, swapUsed: 0, pressure: .normal)
        let net = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 10000, bytesOutPerSec: 5000, totalBytesIn: 100000, totalBytesOut: 50000)
        ])
        let disk = DiskSample(
            volumes: [VolumeCapacity(name: "Mac HD", mountPoint: "/", total: 100000, used: 50000, free: 50000)],
            io: DiskIO(bytesReadPerSec: 2000, bytesWrittenPerSec: 1000, readOpsPerSec: 20, writeOpsPerSec: 10)
        )

        let popover = DetailPopoverView(
            coordinator: coordinator,
            preferences: prefs,
            cpuSample: cpu,
            memorySample: mem,
            networkSample: net,
            diskSample: disk,
            cpuHistory: [Sample(value: cpu)],
            memoryHistory: [Sample(value: mem)],
            networkHistory: [Sample(value: net)],
            diskHistory: [Sample(value: disk)]
        )

        let hosting = NSHostingView(rootView: popover)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 700)
        XCTAssertNotNil(hosting)
    }

    // MARK: - Power & Battery Coordinator & View Tests (Requirements 8.1-8.4, 10.1)

    func testMetricsCoordinatorHandlesPowerReadings() {
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: PreferencesStore(userDefaults: UserDefaults(suiteName: "iStats.test.powercoord.\(UUID().uuidString)")!)
        )

        let powerSample = PowerSample(
            hasBattery: true,
            charge: 85.0,
            state: .discharging,
            timeRemaining: 7200.0,
            cycleCount: 120,
            condition: "Normal",
            designCapacity: 6000,
            currentMaxCapacity: 5700,
            powerDrawWatts: 12.5,
            adapterWatts: nil
        )
        let powerReading = MetricReading.power(Sample(value: powerSample, timestamp: Date(), availability: .available))
        coordinator.handleReading(powerReading)

        XCTAssertNotNil(coordinator.latestPower)
        XCTAssertEqual(coordinator.latestPower?.value.charge, 85.0)
        XCTAssertEqual(coordinator.latestPower?.value.state, .discharging)
        XCTAssertEqual(coordinator.latestPower?.value.powerDrawWatts, 12.5)
        XCTAssertEqual(coordinator.powerHistory.count, 1)
    }

    func testPowerSummaryViewRenderingWithBattery() {
        let sample = PowerSample(
            hasBattery: true,
            charge: 75.0,
            state: .discharging,
            timeRemaining: 10800.0,
            cycleCount: 79,
            condition: "Normal",
            designCapacity: 6249,
            currentMaxCapacity: 5894,
            powerDrawWatts: 15.2,
            adapterWatts: 68.0
        )
        let history = [Sample(value: sample, timestamp: Date(), availability: .available)]

        let view = PowerSummaryView(sample: sample, history: history)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 350)
        XCTAssertNotNil(hosting)
    }

    func testPowerSummaryViewRenderingChargingState() {
        let sample = PowerSample(
            hasBattery: true,
            charge: 45.0,
            state: .charging,
            timeRemaining: 3000.0, // 50m to full
            cycleCount: 150,
            condition: "Normal",
            designCapacity: 6000,
            currentMaxCapacity: 5500,
            powerDrawWatts: 28.5,
            adapterWatts: 96.0
        )
        let history = [Sample(value: sample, timestamp: Date(), availability: .available)]

        let view = PowerSummaryView(sample: sample, history: history)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 350)
        XCTAssertNotNil(hosting)
    }

    func testPowerSummaryViewRenderingNoBatteryMachine() {
        // Desktop Mac (e.g. Mac Studio, Mac mini, Mac Pro, iMac)
        let sample = PowerSample(
            hasBattery: false,
            charge: nil,
            state: nil,
            timeRemaining: nil,
            cycleCount: nil,
            condition: nil,
            designCapacity: nil,
            currentMaxCapacity: nil,
            powerDrawWatts: 35.0, // System power draw if exposed
            adapterWatts: 140.0
        )
        let history = [Sample(value: sample, timestamp: Date(), availability: .available)]

        let view = PowerSummaryView(sample: sample, history: history)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 250)
        XCTAssertNotNil(hosting)
    }

    func testPowerSummaryViewRenderingNoBatteryUnexposedWattage() {
        // Desktop Mac where power draw is unexposed
        let sample = PowerSample(
            hasBattery: false,
            charge: nil,
            state: nil,
            timeRemaining: nil,
            cycleCount: nil,
            condition: nil,
            designCapacity: nil,
            currentMaxCapacity: nil,
            powerDrawWatts: nil,
            adapterWatts: nil
        )

        let view = PowerSummaryView(sample: sample, history: [])
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        XCTAssertNotNil(hosting)
    }

    func testPowerSummaryViewRenderingNilSample() {
        let view = PowerSummaryView(sample: nil, history: [])
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        XCTAssertNotNil(hosting)
    }

    func testDetailPopoverViewWithAllCategoriesIncludingPower() {
        let defaults = UserDefaults(suiteName: "iStats.test.allpopoverpower.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )

        let cpu = CPUSample(totalUsage: 22.0, perCore: [22.0], user: 12.0, system: 10.0, idle: 78.0)
        let mem = MemorySample(total: 16000, used: 8000, free: 8000, wired: 2000, compressed: 1000, cached: 2000, swapUsed: 0, pressure: .normal)
        let net = NetworkSample(interfaces: [
            InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 10000, bytesOutPerSec: 5000, totalBytesIn: 100000, totalBytesOut: 50000)
        ])
        let disk = DiskSample(
            volumes: [VolumeCapacity(name: "Mac HD", mountPoint: "/", total: 100000, used: 50000, free: 50000)],
            io: DiskIO(bytesReadPerSec: 2000, bytesWrittenPerSec: 1000, readOpsPerSec: 20, writeOpsPerSec: 10)
        )
        let power = PowerSample(
            hasBattery: true,
            charge: 88.0,
            state: .charging,
            timeRemaining: 1800.0,
            cycleCount: 65,
            condition: "Normal",
            designCapacity: 6200,
            currentMaxCapacity: 5900,
            powerDrawWatts: 22.4,
            adapterWatts: 67.0
        )

        let popover = DetailPopoverView(
            coordinator: coordinator,
            preferences: prefs,
            cpuSample: cpu,
            memorySample: mem,
            networkSample: net,
            diskSample: disk,
            powerSample: power,
            cpuHistory: [Sample(value: cpu)],
            memoryHistory: [Sample(value: mem)],
            networkHistory: [Sample(value: net)],
            diskHistory: [Sample(value: disk)],
            powerHistory: [Sample(value: power)]
        )

        let hosting = NSHostingView(rootView: popover)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 850)
        XCTAssertNotNil(hosting)
    }

    func testDetailPopoverViewWithNoBatteryMachine() {
        let defaults = UserDefaults(suiteName: "iStats.test.nobatterypopover.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )

        let noBatteryPower = PowerSample(
            hasBattery: false,
            charge: nil,
            state: nil,
            timeRemaining: nil,
            cycleCount: nil,
            condition: nil,
            designCapacity: nil,
            currentMaxCapacity: nil,
            powerDrawWatts: nil,
            adapterWatts: nil
        )

        let popover = DetailPopoverView(
            coordinator: coordinator,
            preferences: prefs,
            powerSample: noBatteryPower,
            powerHistory: [Sample(value: noBatteryPower)]
        )

        let hosting = NSHostingView(rootView: popover)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 500)
        XCTAssertNotNil(hosting)
    }
}
