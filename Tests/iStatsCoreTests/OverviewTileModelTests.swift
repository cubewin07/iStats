import XCTest
@testable import iStatsCore

final class OverviewTileModelTests: XCTestCase {

    // MARK: - Fixture Headlines & Units (Matched to Now Pages)

    func testHeadlinesAndUnitsForAllCategoriesFromFixtures() {
        var store = MetricsStore()
        let gib: UInt64 = 1_073_741_824

        let cpu = CPUSample(
            totalUsage: 42.4,
            perCore: [40, 45, 42, 43],
            user: 30,
            system: 12.4,
            idle: 57.6,
            loadAverage: LoadAverage(oneMinute: 1.5, fiveMinute: 1.3, fifteenMinute: 1.1)
        )
        let memory = MemorySample(
            total: 16 * gib,
            used: 10 * gib,
            free: 6 * gib,
            wired: 2 * gib,
            compressed: 1 * gib,
            cached: 1 * gib,
            swapUsed: 0,
            pressure: .normal
        )
        let gpu = GPUSample(utilization: 64.2, recoveryCount: 0)
        let thermal = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Performance Core 1", celsius: 62.0),
                SensorReading(name: "GPU Cluster 1", celsius: 55.0)
            ],
            pressure: .nominal
        )
        let fan = FanSample(fans: [
            FanReading(name: "Left Fan", rpm: 2150, minRPM: 1200, maxRPM: 5800),
            FanReading(name: "Right Fan", rpm: 2320, minRPM: 1200, maxRPM: 6000)
        ])
        let network = NetworkSample(
            interfaces: [
                InterfaceThroughput(
                    interfaceName: "en0",
                    bytesInPerSec: 1_572_864, // 1.5 MiB/s
                    bytesOutPerSec: 262_144,  // 256 KiB/s
                    totalBytesIn: 10_000_000,
                    totalBytesOut: 2_000_000,
                    ipv4Address: "192.168.1.42",
                    type: .wifi
                )
            ],
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            connectionHealth: NetworkConnectionHealth(status: .connected, reason: "OK", isPathSatisfied: true, isInternetReachable: true)
        )
        let disk = DiskSample(
            volumes: [
                VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 200_000_000_000, free: 300_000_000_000)
            ],
            io: DiskIO(bytesReadPerSec: 12_000_000, bytesWrittenPerSec: 4_000_000, readOpsPerSec: 120, writeOpsPerSec: 40)
        )
        let power = PowerSample(
            hasBattery: true,
            charge: 84.0,
            state: .discharging,
            powerDrawWatts: 12.4
        )

        let now = Date()
        store.append([
            .cpu(Sample(value: cpu, timestamp: now)),
            .memory(Sample(value: memory, timestamp: now)),
            .gpu(Sample(value: gpu, timestamp: now)),
            .thermal(Sample(value: thermal, timestamp: now)),
            .fan(Sample(value: fan, timestamp: now)),
            .network(Sample(value: network, timestamp: now)),
            .disk(Sample(value: disk, timestamp: now)),
            .power(Sample(value: power, timestamp: now))
        ])

        let tiles = OverviewTileModel.tiles(
            enabledCategories: Set(MetricCategory.allCases),
            store: store,
            hasBattery: true,
            units: OverviewUnitPreferences(temperatureUnit: .celsius, networkUnit: .bytesPerSecond, byteUnitStandard: .iec)
        )
        XCTAssertEqual(tiles.map(\.category), MetricCategory.allCases)

        let byCategory = Dictionary(uniqueKeysWithValues: tiles.map { ($0.category, $0) })

        XCTAssertEqual(byCategory[.cpu]?.headline, "42")
        XCTAssertEqual(byCategory[.cpu]?.unit, "%")
        XCTAssertEqual(byCategory[.cpu]?.symbolName, "cpu")
        XCTAssertEqual(byCategory[.cpu]?.displayName, "CPU")
        XCTAssertEqual(byCategory[.cpu]?.spark.count, 1)

        XCTAssertEqual(byCategory[.memory]?.headline, "10.0")
        XCTAssertEqual(byCategory[.memory]?.unit, "GiB")
        XCTAssertEqual(byCategory[.memory]?.secondaryText, "of 16 GiB")

        XCTAssertEqual(byCategory[.gpu]?.headline, "64")
        XCTAssertEqual(byCategory[.gpu]?.unit, "%")
        XCTAssertEqual(byCategory[.gpu]?.symbolName, "cube.transparent")

        XCTAssertEqual(byCategory[.thermal]?.headline, "62")
        XCTAssertEqual(byCategory[.thermal]?.unit, "°C")
        XCTAssertEqual(byCategory[.thermal]?.symbolName, "thermometer.medium")

        XCTAssertEqual(byCategory[.fan]?.headline, "2320")
        XCTAssertEqual(byCategory[.fan]?.unit, "rpm")
        XCTAssertEqual(byCategory[.fan]?.symbolName, "fan")

        XCTAssertEqual(byCategory[.network]?.headline, "↓ 1.5")
        XCTAssertEqual(byCategory[.network]?.unit, "MiB/s")
        XCTAssertEqual(byCategory[.network]?.secondaryText, "↑ 256 KiB/s")
        XCTAssertEqual(byCategory[.network]?.symbolName, "network")

        XCTAssertEqual(byCategory[.disk]?.headline, "279")
        XCTAssertEqual(byCategory[.disk]?.unit, "GiB free")
        XCTAssertEqual(byCategory[.disk]?.secondaryText, "40% used")
        XCTAssertEqual(byCategory[.disk]?.symbolName, "internaldrive")

        XCTAssertEqual(byCategory[.power]?.headline, "84")
        XCTAssertEqual(byCategory[.power]?.unit, "%")
        XCTAssertEqual(byCategory[.power]?.secondaryText, "12.4 W")
        XCTAssertEqual(byCategory[.power]?.displayName, "Battery")
        XCTAssertEqual(byCategory[.power]?.symbolName, "battery.100percent")
        XCTAssertTrue(tiles.allSatisfy(\.hasData))
    }

    func testUnitConversionsForTemperatureNetworkAndBytes() {
        var store = MetricsStore()
        let now = Date()
        let gib: UInt64 = 1_000_000_000
        store.append([
            .thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 50.0)], pressure: .nominal), timestamp: now)),
            .memory(Sample(value: MemorySample(total: 16 * gib, used: 8 * gib, free: 8 * gib, wired: 2 * gib, compressed: 1 * gib, cached: 1 * gib, swapUsed: 0, pressure: .normal), timestamp: now)),
            .network(Sample(value: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1_250_000, bytesOutPerSec: 250_000, totalBytesIn: 0, totalBytesOut: 0)]), timestamp: now)),
            .disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 500 * gib, used: 200 * gib, free: 300 * gib)]), timestamp: now))
        ])

        let units = OverviewUnitPreferences(temperatureUnit: .fahrenheit, networkUnit: .bitsPerSecond, byteUnitStandard: .si)

        let thermal = OverviewTileModel.make(category: .thermal, store: store, units: units)
        XCTAssertEqual(thermal.headline, "122")
        XCTAssertEqual(thermal.unit, "°F")

        let memory = OverviewTileModel.make(category: .memory, store: store, units: units)
        XCTAssertEqual(memory.headline, "8.0")
        XCTAssertEqual(memory.unit, "GB")

        let network = OverviewTileModel.make(category: .network, store: store, units: units)
        XCTAssertEqual(network.headline, "↓ 10")
        XCTAssertEqual(network.unit, "Mbps")
        XCTAssertEqual(network.secondaryText, "↑ 2.0 Mbps")

        let disk = OverviewTileModel.make(category: .disk, store: store, units: units)
        XCTAssertEqual(disk.headline, "300")
        XCTAssertEqual(disk.unit, "GB free")
    }

    // MARK: - Fresh Install & Unavailable States

    func testFreshInstallShowsPlaceholdersNotZeros() {
        let store = MetricsStore()
        let tiles = OverviewTileModel.tiles(enabledCategories: Set(MetricCategory.allCases), store: store)
        XCTAssertEqual(tiles.count, MetricCategory.allCases.count)

        for tile in tiles {
            XCTAssertEqual(tile.headline, "--", "\(tile.category) should show -- on fresh install")
            XCTAssertEqual(tile.unit, "")
            XCTAssertFalse(tile.hasData)
            XCTAssertEqual(tile.status, .fine)
            XCTAssertTrue(tile.spark.isEmpty)
        }
    }

    func testUnavailableMapsToReason() {
        var store = MetricsStore()
        store.recordUnavailable(category: .gpu, reason: "GPU telemetry denied")

        let tileFromStore = OverviewTileModel.make(category: .gpu, store: store)
        XCTAssertEqual(tileFromStore.headline, "--")
        XCTAssertEqual(tileFromStore.unit, "")
        XCTAssertFalse(tileFromStore.hasData)
        XCTAssertEqual(tileFromStore.availability, .unavailable(reason: "GPU telemetry denied"))

        let tileFromParam = OverviewTileModel.make(
            category: .thermal,
            snapshot: .thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 55)], pressure: .nominal))),
            history: [55],
            availability: .unavailable(reason: "SMC unavailable")
        )
        XCTAssertEqual(tileFromParam.headline, "--")
        XCTAssertFalse(tileFromParam.hasData)
        XCTAssertEqual(tileFromParam.availability, .unavailable(reason: "SMC unavailable"))
        XCTAssertTrue(tileFromParam.spark.isEmpty)
    }

    func testFanlessMacShowsPassive() {
        let reading = MetricReading.fan(Sample(value: FanSample(fans: [])))
        let tile = OverviewTileModel.make(category: .fan, snapshot: reading, history: [])
        XCTAssertEqual(tile.headline, "Passive")
        XCTAssertEqual(tile.unit, "")
        XCTAssertEqual(tile.status, .fine)
        XCTAssertTrue(tile.hasData)
    }

    // MARK: - Battery Absent & Category Filtering

    func testBatteryAbsentHidesPowerTile() {
        let store = MetricsStore()
        let tiles = OverviewTileModel.tiles(
            enabledCategories: Set(MetricCategory.allCases),
            store: store,
            hasBattery: false
        )
        XCTAssertFalse(tiles.contains(where: { $0.category == .power }))
        XCTAssertEqual(tiles.count, MetricCategory.allCases.count - 1)
    }

    func testEnabledCategoriesFilterAndOrder() {
        let store = MetricsStore()
        let tiles = OverviewTileModel.tiles(
            enabledCategories: [.disk, .cpu, .network],
            store: store,
            hasBattery: true
        )
        XCTAssertEqual(tiles.map(\.category), [.cpu, .network, .disk])
    }

    // MARK: - Threshold Boundaries

    func testStatusAtThresholdBoundaries() {
        // CPU: fine < 75, elevated >= 75, critical >= 90, or warning when 1m load > 1.5 * cores
        XCTAssertEqual(
            OverviewTileModel.make(
                category: .cpu,
                snapshot: .cpu(Sample(value: CPUSample(totalUsage: 74.9, perCore: [75, 74], user: 50, system: 24.9, idle: 25.1))),
                history: []
            ).status,
            .fine
        )
        XCTAssertEqual(
            OverviewTileModel.make(
                category: .cpu,
                snapshot: .cpu(Sample(value: CPUSample(totalUsage: 75.0, perCore: [75, 75], user: 50, system: 25, idle: 25))),
                history: []
            ).status,
            .elevated
        )
        XCTAssertEqual(
            OverviewTileModel.make(
                category: .cpu,
                snapshot: .cpu(Sample(value: CPUSample(totalUsage: 90.0, perCore: [90, 90], user: 60, system: 30, idle: 10))),
                history: []
            ).status,
            .critical
        )
        XCTAssertEqual(
            OverviewTileModel.make(
                category: .cpu,
                snapshot: .cpu(Sample(value: CPUSample(
                    totalUsage: 30.0,
                    perCore: [30, 30, 30, 30],
                    user: 20,
                    system: 10,
                    idle: 70,
                    loadAverage: LoadAverage(oneMinute: 6.1, fiveMinute: 3.0, fifteenMinute: 2.0)
                ))),
                history: []
            ).status,
            .warning
        )

        // GPU: elevated >= 80, critical >= 95, recoveryCount > 0 -> warning
        XCTAssertEqual(
            OverviewTileModel.make(category: .gpu, snapshot: .gpu(Sample(value: GPUSample(utilization: 79.9))), history: []).status,
            .fine
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .gpu, snapshot: .gpu(Sample(value: GPUSample(utilization: 80.0))), history: []).status,
            .elevated
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .gpu, snapshot: .gpu(Sample(value: GPUSample(utilization: 95.0))), history: []).status,
            .critical
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .gpu, snapshot: .gpu(Sample(value: GPUSample(utilization: 10.0, recoveryCount: 1))), history: []).status,
            .warning
        )

        // Thermal: peak >= 60 elevated, >= 75 warning, >= 90 critical
        XCTAssertEqual(
            OverviewTileModel.make(category: .thermal, snapshot: .thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 59.9)], pressure: .nominal))), history: []).status,
            .fine
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .thermal, snapshot: .thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 75.0)], pressure: .nominal))), history: []).status,
            .warning
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .thermal, snapshot: .thermal(Sample(value: ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 90.0)], pressure: .nominal))), history: []).status,
            .critical
        )

        // Disk: elevated >= 85%, warning >= 90%, critical >= 95%
        XCTAssertEqual(
            OverviewTileModel.make(category: .disk, snapshot: .disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 1000, used: 849, free: 151)]))), history: []).status,
            .fine
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .disk, snapshot: .disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 1000, used: 850, free: 150)]))), history: []).status,
            .elevated
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .disk, snapshot: .disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 1000, used: 900, free: 100)]))), history: []).status,
            .warning
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .disk, snapshot: .disk(Sample(value: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 1000, used: 950, free: 50)]))), history: []).status,
            .critical
        )

        // Battery: discharging <= 40 elevated, <= 20 warning, <= 10 critical
        XCTAssertEqual(
            OverviewTileModel.make(category: .power, snapshot: .power(Sample(value: PowerSample(hasBattery: true, charge: 41.0, state: .discharging))), history: []).status,
            .fine
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .power, snapshot: .power(Sample(value: PowerSample(hasBattery: true, charge: 20.0, state: .discharging))), history: []).status,
            .warning
        )
        XCTAssertEqual(
            OverviewTileModel.make(category: .power, snapshot: .power(Sample(value: PowerSample(hasBattery: true, charge: 10.0, state: .discharging))), history: []).status,
            .critical
        )
    }

    // MARK: - Network Rate Reset & Uptime Formatting

    func testNetworkRateResetGivesZero() {
        // Normal delta
        let normal = OverviewTileModel.networkRates(
            previousInBytes: 1_000,
            currentInBytes: 3_000,
            previousOutBytes: 500,
            currentOutBytes: 1_500,
            elapsedSeconds: 2.0
        )
        XCTAssertEqual(normal.downBytesPerSec, 1_000.0, accuracy: 0.001)
        XCTAssertEqual(normal.upBytesPerSec, 500.0, accuracy: 0.001)

        // Counter wrap / interface reset -> 0 (never negative or huge underflow)
        let reset = OverviewTileModel.networkRates(
            previousInBytes: 50_000_000,
            currentInBytes: 1_200,
            previousOutBytes: 10_000_000,
            currentOutBytes: 400,
            elapsedSeconds: 2.0
        )
        XCTAssertEqual(reset.downBytesPerSec, 0.0)
        XCTAssertEqual(reset.upBytesPerSec, 0.0)

        // Zero elapsed -> 0
        let zeroElapsed = OverviewTileModel.networkRates(
            previousInBytes: 100,
            currentInBytes: 200,
            previousOutBytes: 100,
            currentOutBytes: 200,
            elapsedSeconds: 0.0
        )
        XCTAssertEqual(zeroElapsed.downBytesPerSec, 0.0)
        XCTAssertEqual(zeroElapsed.upBytesPerSec, 0.0)
    }

    func testFormattedUptimeHelper() {
        XCTAssertEqual(OverviewTileModel.formattedUptime(0), "0m")
        XCTAssertEqual(OverviewTileModel.formattedUptime(45), "1m")
        XCTAssertEqual(OverviewTileModel.formattedUptime(5 * 3600 + 12 * 60), "5h 12m")
        XCTAssertEqual(OverviewTileModel.formattedUptime(3 * 86400 + 14 * 3600 + 22 * 60), "3d 14h 22m")
    }
}
