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

    func testCPUPopoverRendering() {
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
        let coord = MetricsCoordinator(scheduler: SampleScheduler(), store: MetricsStore(), preferencesStore: PreferencesStore.shared)
        coord.handleReading(.cpu(Sample(value: sample)))

        let view = CPUPopover(coordinator: coord)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hosting)
    }

    func testCPUPopoverHighCoreCountAndIntelRendering() {
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
        let coord24 = MetricsCoordinator(scheduler: SampleScheduler(), store: MetricsStore(), preferencesStore: PreferencesStore.shared)
        coord24.handleReading(.cpu(Sample(value: highCoreSample)))
        let view24 = CPUPopover(initialTab: .detail, coordinator: coord24)
        let hosting24 = NSHostingView(rootView: view24)
        hosting24.frame = CGRect(x: 0, y: 0, width: 330, height: 450)
        XCTAssertNotNil(hosting24)

        // Intel / No topology
        let intelSample = CPUSample(
            totalUsage: 25.0,
            perCore: [20.0, 30.0, 25.0, 25.0],
            user: 15.0,
            system: 10.0,
            idle: 75.0
        )
        let coordIntel = MetricsCoordinator(scheduler: SampleScheduler(), store: MetricsStore(), preferencesStore: PreferencesStore.shared)
        coordIntel.handleReading(.cpu(Sample(value: intelSample)))
        let viewIntel = CPUPopover(coordinator: coordIntel)
        let hostingIntel = NSHostingView(rootView: viewIntel)
        hostingIntel.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hostingIntel)
    }

    func testNoWidgetsActiveViewRendering() {
        let view = NoWidgetsActiveView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 180)
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

    func testNetworkPopoverRendering() {
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
        let defaults = UserDefaults(suiteName: "iStats.test.netpopover.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )
        coordinator.handleReading(.network(Sample(value: netSample)))

        // Bytes/sec IEC
        prefs.networkUnit = .bytesPerSecond
        prefs.byteUnitStandard = .iec
        let viewBytesIEC = NetworkPopover(coordinator: coordinator, preferences: prefs)
        let hostingBytesIEC = NSHostingView(rootView: viewBytesIEC)
        hostingBytesIEC.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hostingBytesIEC)

        // Bits/sec SI
        prefs.networkUnit = .bitsPerSecond
        prefs.byteUnitStandard = .si
        let viewBitsSI = NetworkPopover(coordinator: coordinator, preferences: prefs)
        let hostingBitsSI = NSHostingView(rootView: viewBitsSI)
        hostingBitsSI.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hostingBitsSI)

        // Empty / nil sample
        let emptyCoord = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )
        let viewNil = NetworkPopover(coordinator: emptyCoord, preferences: prefs)
        let hostingNil = NSHostingView(rootView: viewNil)
        XCTAssertNotNil(hostingNil)

        // Enriched sample with full connectivity & Wi-Fi link telemetry
        let wifiDetails = WiFiLinkTelemetry(
            ssid: "Office-5G",
            rssi: -58,
            noise: -92,
            txRate: 650.0,
            channel: 36,
            band: "5 GHz"
        )
        let enrichedSample = NetworkSample(
            interfaces: [
                InterfaceThroughput(
                    interfaceName: "en0",
                    bytesInPerSec: 1024 * 1024 * 12.5,
                    bytesOutPerSec: 1024 * 1024 * 3.2,
                    totalBytesIn: 1024 * 1024 * 1024 * 45,
                    totalBytesOut: 1024 * 1024 * 1024 * 8,
                    ipv4Address: "192.168.1.105",
                    type: .wifi
                ),
                InterfaceThroughput(
                    interfaceName: "utun3",
                    bytesInPerSec: 1024 * 512,
                    bytesOutPerSec: 1024 * 256,
                    totalBytesIn: 1024 * 1024 * 500,
                    totalBytesOut: 1024 * 1024 * 250,
                    ipv4Address: "10.8.0.2",
                    type: .vpn
                )
            ],
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.105",
            gatewayIPv4: "192.168.1.1",
            primaryDNS: "1.1.1.1",
            wifiDetails: wifiDetails
        )
        coordinator.handleReading(.network(Sample(value: enrichedSample)))
        let viewEnriched = NetworkPopover(initialTab: .detail, coordinator: coordinator, preferences: prefs)
        let hostingEnriched = NSHostingView(rootView: viewEnriched)
        hostingEnriched.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hostingEnriched)

        // Enriched Ethernet sample
        let ethernetSample = NetworkSample(
            interfaces: [
                InterfaceThroughput(
                    interfaceName: "en1",
                    bytesInPerSec: 1024 * 1024 * 50,
                    bytesOutPerSec: 1024 * 1024 * 20,
                    totalBytesIn: 1024 * 1024 * 1024 * 100,
                    totalBytesOut: 1024 * 1024 * 1024 * 50,
                    ipv4Address: "10.0.1.25",
                    type: .ethernet
                )
            ],
            primaryInterface: "en1",
            primaryType: .ethernet,
            localIPv4: "10.0.1.25",
            gatewayIPv4: "10.0.1.1",
            primaryDNS: "8.8.8.8"
        )
        coordinator.handleReading(.network(Sample(value: ethernetSample)))
        let viewEthernet = NetworkPopover(coordinator: coordinator, preferences: prefs)
        let hostingEthernet = NSHostingView(rootView: viewEthernet)
        hostingEthernet.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hostingEthernet)
    }

    func testDiskPopoverRenderingWithAndWithoutIO() {
        let volumes = [
            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500 * 1024 * 1024 * 1024, used: 250 * 1024 * 1024 * 1024, free: 250 * 1024 * 1024 * 1024),
            VolumeCapacity(name: "External Drive", mountPoint: "/Volumes/Backup", total: 1000 * 1024 * 1024 * 1024, used: 900 * 1024 * 1024 * 1024, free: 100 * 1024 * 1024 * 1024)
        ]
        let io = DiskIO(bytesReadPerSec: 1024 * 1024 * 15, bytesWrittenPerSec: 1024 * 1024 * 8, readOpsPerSec: 200, writeOpsPerSec: 80)
        let sampleWithIO = DiskSample(volumes: volumes, io: io)
        let defaults = UserDefaults(suiteName: "iStats.test.diskpopover.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )

        // With I/O
        coordinator.handleReading(.disk(Sample(value: sampleWithIO)))
        let viewWithIO = DiskPopover(coordinator: coordinator, preferences: prefs)
        let hostingWithIO = NSHostingView(rootView: viewWithIO)
        hostingWithIO.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hostingWithIO)

        // Without I/O (graceful degradation)
        let sampleWithoutIO = DiskSample(volumes: volumes, io: nil)
        let coordNoIO = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )
        coordNoIO.handleReading(.disk(Sample(value: sampleWithoutIO)))
        let viewWithoutIO = DiskPopover(coordinator: coordNoIO, preferences: prefs)
        let hostingWithoutIO = NSHostingView(rootView: viewWithoutIO)
        hostingWithoutIO.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hostingWithoutIO)

        // Nil sample
        let coordNil = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )
        let viewNil = DiskPopover(coordinator: coordNil, preferences: prefs)
        let hostingNil = NSHostingView(rootView: viewNil)
        XCTAssertNotNil(hostingNil)
    }

    func testCategoryPopoverViewWithAllCategories() {
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

        coordinator.handleReading(.cpu(Sample(value: cpu)))
        coordinator.handleReading(.memory(Sample(value: mem)))
        coordinator.handleReading(.network(Sample(value: net)))
        coordinator.handleReading(.disk(Sample(value: disk)))

        for category in MetricCategory.allCases {
            let view = PopoverFactory.makeCategoryPopoverView(category: category, coordinator: coordinator, preferences: prefs)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
            XCTAssertNotNil(hosting)
        }
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

    func testPowerPopoverRenderingWithBattery() {
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
        let defaults = UserDefaults(suiteName: "iStats.test.powerpop.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )
        coordinator.handleReading(.power(Sample(value: sample)))

        let view = PowerPopover(coordinator: coordinator, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hosting)
    }

    func testPowerPopoverRenderingChargingState() {
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
        let defaults = UserDefaults(suiteName: "iStats.test.powerpopcharge.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )
        coordinator.handleReading(.power(Sample(value: sample)))

        let view = PowerPopover(coordinator: coordinator, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hosting)
    }

    func testPowerPopoverRenderingNoBatteryMachine() {
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
        let defaults = UserDefaults(suiteName: "iStats.test.powerpopnobat.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )
        coordinator.handleReading(.power(Sample(value: sample)))

        let view = PowerPopover(coordinator: coordinator, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hosting)
    }

    func testPowerPopoverRenderingNoBatteryUnexposedWattage() {
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
        let defaults = UserDefaults(suiteName: "iStats.test.powerpopunexp.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )
        coordinator.handleReading(.power(Sample(value: sample)))

        let view = PowerPopover(coordinator: coordinator, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hosting)
    }

    func testPowerPopoverRenderingNilSample() {
        let defaults = UserDefaults(suiteName: "iStats.test.powerpopnil.\(UUID().uuidString)")!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(
            scheduler: SampleScheduler(),
            store: MetricsStore(),
            preferencesStore: prefs
        )

        let view = PowerPopover(coordinator: coordinator, preferences: prefs)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 330, height: 400)
        XCTAssertNotNil(hosting)
    }

    // MARK: - TrendChartMath and TrendChart Tests

    func testTrendChartMathStatsComputation() {
        XCTAssertNil(TrendChartMath.computeStats(for: []))

        let stats = TrendChartMath.computeStats(for: [10.0, 50.0, 30.0, 20.0])
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.min, 10.0)
        XCTAssertEqual(stats?.max, 50.0)
        XCTAssertEqual(stats?.avg, 27.5)
        XCTAssertEqual(stats?.now, 20.0)
    }

    func testTrendChartMathHoverIndex() {
        XCTAssertNil(TrendChartMath.hoverIndex(for: 50, totalWidth: 0, count: 10))
        XCTAssertNil(TrendChartMath.hoverIndex(for: 50, totalWidth: 100, count: 0))

        XCTAssertEqual(TrendChartMath.hoverIndex(for: 0, totalWidth: 100, count: 11), 0)
        XCTAssertEqual(TrendChartMath.hoverIndex(for: 50, totalWidth: 100, count: 11), 5)
        XCTAssertEqual(TrendChartMath.hoverIndex(for: 100, totalWidth: 100, count: 11), 10)
    }

    func testTrendChartMathRelativeTimeFormatting() {
        XCTAssertEqual(TrendChartMath.formatRelativeTime(secondsAgo: 0), "0s ago")
        XCTAssertEqual(TrendChartMath.formatRelativeTime(secondsAgo: 14), "14s ago")
        XCTAssertEqual(TrendChartMath.formatRelativeTime(secondsAgo: 120), "2m ago")
        XCTAssertEqual(TrendChartMath.formatRelativeTime(secondsAgo: 150), "2m 30s ago")
        XCTAssertEqual(TrendChartMath.formatRelativeTime(secondsAgo: 7200), "2h ago")
    }

    func testTrendChartMathMaxBoundCeiling() {
        XCTAssertEqual(TrendChartMath.computeMaxBound(values: [20, 40], fixedMax: 100), 100.0)
        XCTAssertEqual(TrendChartMath.computeMaxBound(values: [0, 0], fixedMax: nil, floor: 5.0), 5.0)
        XCTAssertEqual(TrendChartMath.computeMaxBound(values: [100.0], fixedMax: nil, floor: 1.0), 115.0, accuracy: 0.001)
    }

    func testTrendChartRenderModes() {
        let singleChart = TrendChart(
            mode: .single(values: [10, 20, 30], color: .blue),
            height: 60,
            showStatsStrip: true
        )
        let singleHost = NSHostingView(rootView: singleChart)
        singleHost.frame = CGRect(x: 0, y: 0, width: 330, height: 80)
        singleHost.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(singleHost.fittingSize.height, 40)

        let stackedChart = TrendChart(
            mode: .stacked(primary: [10, 20], secondary: [5, 10], primaryColor: .blue, secondaryColor: .red),
            height: 60
        )
        let stackedHost = NSHostingView(rootView: stackedChart)
        stackedHost.frame = CGRect(x: 0, y: 0, width: 330, height: 60)
        stackedHost.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(stackedHost.fittingSize.height, 40)

        let mirroredChart = TrendChart(
            mode: .mirrored(top: [100, 200], bottom: [50, 80], topColor: .indigo, bottomColor: .pink),
            height: 140,
            showStatsStrip: true
        )
        let mirroredHost = NSHostingView(rootView: mirroredChart)
        mirroredHost.frame = CGRect(x: 0, y: 0, width: 330, height: 160)
        mirroredHost.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(mirroredHost.fittingSize.height, 80)
    }
}
