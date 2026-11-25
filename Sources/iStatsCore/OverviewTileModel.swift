import Foundation

/// Unit display preferences used to format Overview tiles consistently with each category's Now page.
public struct OverviewUnitPreferences: Sendable, Equatable {
    public var temperatureUnit: Units.TemperatureUnit
    public var networkUnit: Units.NetworkUnit
    public var byteUnitStandard: Units.ByteUnitStandard

    public init(
        temperatureUnit: Units.TemperatureUnit = .celsius,
        networkUnit: Units.NetworkUnit = .bytesPerSecond,
        byteUnitStandard: Units.ByteUnitStandard = .iec
    ) {
        self.temperatureUnit = temperatureUnit
        self.networkUnit = networkUnit
        self.byteUnitStandard = byteUnitStandard
    }
}

/// Pure summary model for a single category tile on the Overview destination (ADR 0011 / Task 9.4).
public struct OverviewTileModel: Identifiable, Equatable, Sendable {
    public let category: MetricCategory
    public let displayName: String
    public let symbolName: String
    public let headline: String
    public let unit: String
    public let secondaryText: String?
    public let spark: [Double]
    public let status: StatusLevel
    public let availability: Availability?
    public let hasData: Bool

    public var id: MetricCategory { category }

    public init(
        category: MetricCategory,
        displayName: String,
        symbolName: String,
        headline: String,
        unit: String,
        secondaryText: String? = nil,
        spark: [Double],
        status: StatusLevel,
        availability: Availability? = nil,
        hasData: Bool
    ) {
        self.category = category
        self.displayName = displayName
        self.symbolName = symbolName
        self.headline = headline
        self.unit = unit
        self.secondaryText = secondaryText
        self.spark = spark
        self.status = status
        self.availability = availability
        self.hasData = hasData
    }

    // MARK: - Ordering & System Uptime

    /// Categories shown in Overview, ordered per `MetricCategory.allCases` and hiding `.power` when `!hasBattery`.
    public static func visibleCategories(
        enabled: Set<MetricCategory>,
        hasBattery: Bool = true
    ) -> [MetricCategory] {
        PanelDestination.orderedCategories(enabled: enabled).filter { category in
            hasBattery || category != .power
        }
    }

    /// Formats system uptime for the Overview header summary (pure wrapper over `Units.formatUptime`).
    public static func formattedUptime(_ uptimeSeconds: TimeInterval) -> String {
        Units.formatUptime(uptimeSeconds)
    }

    /// Computes sanitized download/upload byte rates from cumulative counters via `RateMath`.
    /// Counter resets (`current < previous`) or non-positive elapsed intervals safely return `0`.
    public static func networkRates(
        previousInBytes: UInt64,
        currentInBytes: UInt64,
        previousOutBytes: UInt64,
        currentOutBytes: UInt64,
        elapsedSeconds: TimeInterval
    ) -> (downBytesPerSec: Double, upBytesPerSec: Double) {
        (
            RateMath.bytesPerSecond(
                previous: previousInBytes,
                current: currentInBytes,
                elapsedSeconds: elapsedSeconds
            ),
            RateMath.bytesPerSecond(
                previous: previousOutBytes,
                current: currentOutBytes,
                elapsedSeconds: elapsedSeconds
            )
        )
    }

    // MARK: - Store & Snapshot Factories

    /// Builds all visible Overview tiles from `MetricsStore` in active category order.
    public static func tiles(
        enabledCategories: Set<MetricCategory>,
        store: MetricsStore,
        availabilityByCategory: [MetricCategory: Availability] = [:],
        hasBattery: Bool = true,
        units: OverviewUnitPreferences = .init(),
        sparkMaxPoints: Int = 30
    ) -> [OverviewTileModel] {
        visibleCategories(enabled: enabledCategories, hasBattery: hasBattery).map { category in
            make(
                category: category,
                store: store,
                availability: availabilityByCategory[category],
                hasBattery: hasBattery,
                units: units,
                sparkMaxPoints: sparkMaxPoints
            )
        }
    }

    /// Builds an `OverviewTileModel` for `category` directly from a `MetricsStore`.
    public static func make(
        category: MetricCategory,
        store: MetricsStore,
        availability: Availability? = nil,
        hasBattery: Bool = true,
        units: OverviewUnitPreferences = .init(),
        sparkMaxPoints: Int = 30
    ) -> OverviewTileModel {
        let snapshot = store.latest(for: category)
        let spark = sparkSeries(
            for: category,
            in: store,
            hasBattery: hasBattery,
            maxPoints: sparkMaxPoints
        )
        return make(
            category: category,
            snapshot: snapshot,
            history: spark,
            availability: availability,
            hasBattery: hasBattery,
            units: units
        )
    }

    /// Builds an `OverviewTileModel` for `category` from an optional latest `MetricReading` and scalar history.
    public static func make(
        category: MetricCategory,
        snapshot: MetricReading?,
        history: [Double],
        availability: Availability? = nil,
        hasBattery: Bool = true,
        units: OverviewUnitPreferences = .init()
    ) -> OverviewTileModel {
        let identity = category.identity
        let displayName = identity.displayName(hasBattery: hasBattery)
        let symbolName = identity.symbol(hasBattery: hasBattery)
        let effectiveAvailability = availability ?? snapshot?.availability

        if case .unavailable(let reason) = effectiveAvailability {
            return OverviewTileModel(
                category: category,
                displayName: displayName,
                symbolName: symbolName,
                headline: "--",
                unit: "",
                secondaryText: nil,
                spark: [],
                status: .fine,
                availability: .unavailable(reason: reason),
                hasData: false
            )
        }

        guard let snapshot else {
            return OverviewTileModel(
                category: category,
                displayName: displayName,
                symbolName: symbolName,
                headline: "--",
                unit: "",
                secondaryText: nil,
                spark: history,
                status: .fine,
                availability: effectiveAvailability,
                hasData: false
            )
        }

        switch (category, snapshot) {
        case (.cpu, .cpu(let s)):
            return makeCPU(
                sample: s.value,
                displayName: displayName,
                symbolName: symbolName,
                spark: history,
                availability: effectiveAvailability
            )

        case (.memory, .memory(let s)):
            return makeMemory(
                sample: s.value,
                displayName: displayName,
                symbolName: symbolName,
                spark: history,
                availability: effectiveAvailability,
                units: units
            )

        case (.gpu, .gpu(let s)):
            return makeGPU(
                sample: s.value,
                displayName: displayName,
                symbolName: symbolName,
                spark: history,
                availability: effectiveAvailability
            )

        case (.thermal, .thermal(let s)):
            return makeThermal(
                sample: s.value,
                displayName: displayName,
                symbolName: symbolName,
                spark: history,
                availability: effectiveAvailability,
                units: units
            )

        case (.fan, .fan(let s)):
            return makeFan(
                sample: s.value,
                displayName: displayName,
                symbolName: symbolName,
                spark: history,
                availability: effectiveAvailability
            )

        case (.network, .network(let s)):
            return makeNetwork(
                sample: s.value,
                displayName: displayName,
                symbolName: symbolName,
                spark: history,
                availability: effectiveAvailability,
                units: units
            )

        case (.disk, .disk(let s)):
            return makeDisk(
                sample: s.value,
                displayName: displayName,
                symbolName: symbolName,
                spark: history,
                availability: effectiveAvailability,
                units: units
            )

        case (.power, .power(let s)):
            return makePower(
                sample: s.value,
                displayName: displayName,
                symbolName: symbolName,
                spark: history,
                availability: effectiveAvailability,
                hasBattery: hasBattery
            )

        default:
            return OverviewTileModel(
                category: category,
                displayName: displayName,
                symbolName: symbolName,
                headline: "--",
                unit: "",
                secondaryText: nil,
                spark: history,
                status: .fine,
                availability: effectiveAvailability,
                hasData: false
            )
        }
    }

    // MARK: - Per-Category Builders (Matched to Now Pages)

    private static func makeCPU(
        sample: CPUSample,
        displayName: String,
        symbolName: String,
        spark: [Double],
        availability: Availability?
    ) -> OverviewTileModel {
        let usage = sample.totalUsage.isFinite ? min(100.0, max(0.0, sample.totalUsage)) : 0.0
        let status = StatusThresholds.cpuPanel(
            usagePercent: usage,
            loadOneMinute: sample.loadAverage?.oneMinute,
            coreCount: sample.perCore.count
        )
        return OverviewTileModel(
            category: .cpu,
            displayName: displayName,
            symbolName: symbolName,
            headline: String(format: "%.0f", usage),
            unit: "%",
            secondaryText: nil,
            spark: spark,
            status: status,
            availability: availability,
            hasData: true
        )
    }

    private static func makeMemory(
        sample: MemorySample,
        displayName: String,
        symbolName: String,
        spark: [Double],
        availability: Availability?,
        units: OverviewUnitPreferences
    ) -> OverviewTileModel {
        let standard = units.byteUnitStandard
        let divisor = standard == .si ? 1_000_000_000.0 : 1_073_741_824.0
        let unitLabel = standard == .si ? "GB" : "GiB"
        let usedValue = Double(sample.used) / divisor
        let isWholeGiB = standard == .iec && sample.total >= 1_073_741_824 && sample.total % 1_073_741_824 == 0
        let totalString = Units.formatBytes(sample.total, standard: standard, fractionDigits: isWholeGiB ? 0 : 1)

        return OverviewTileModel(
            category: .memory,
            displayName: displayName,
            symbolName: symbolName,
            headline: String(format: "%.1f", usedValue),
            unit: unitLabel,
            secondaryText: "of \(totalString)",
            spark: spark,
            status: StatusThresholds.memory(sample: sample),
            availability: availability,
            hasData: true
        )
    }

    private static func makeGPU(
        sample: GPUSample,
        displayName: String,
        symbolName: String,
        spark: [Double],
        availability: Availability?
    ) -> OverviewTileModel {
        let hasUtil = sample.utilization?.isFinite == true
        let clampedUtil = sample.utilization.flatMap { $0.isFinite ? min(100.0, max(0.0, $0)) : nil } ?? 0.0
        let status = StatusThresholds.gpuPanel(
            utilizationPercent: clampedUtil,
            recoveryCount: sample.recoveryCount ?? 0
        )
        return OverviewTileModel(
            category: .gpu,
            displayName: displayName,
            symbolName: symbolName,
            headline: hasUtil ? String(format: "%.0f", clampedUtil) : "--",
            unit: hasUtil ? "%" : "",
            secondaryText: nil,
            spark: spark,
            status: status,
            availability: availability,
            hasData: hasUtil
        )
    }

    private static func makeThermal(
        sample: ThermalSample,
        displayName: String,
        symbolName: String,
        spark: [Double],
        availability: Availability?,
        units: OverviewUnitPreferences
    ) -> OverviewTileModel {
        guard let peakC = sample.peakTemperatureCelsius, peakC.isFinite else {
            let status = sample.pressure.map(StatusThresholds.thermalPressure) ?? .fine
            return OverviewTileModel(
                category: .thermal,
                displayName: displayName,
                symbolName: symbolName,
                headline: "--",
                unit: "",
                secondaryText: nil,
                spark: spark,
                status: status,
                availability: availability,
                hasData: false
            )
        }

        let displayed = units.temperatureUnit == .fahrenheit ? Units.celsiusToFahrenheit(peakC) : peakC
        let status = StatusThresholds.temperature(
            celsius: peakC,
            source: .peak,
            pressure: sample.pressure
        )
        return OverviewTileModel(
            category: .thermal,
            displayName: displayName,
            symbolName: symbolName,
            headline: String(format: "%.0f", displayed),
            unit: units.temperatureUnit.symbol,
            secondaryText: nil,
            spark: spark,
            status: status,
            availability: availability,
            hasData: true
        )
    }

    private static func makeFan(
        sample: FanSample,
        displayName: String,
        symbolName: String,
        spark: [Double],
        availability: Availability?
    ) -> OverviewTileModel {
        if sample.fans.isEmpty {
            return OverviewTileModel(
                category: .fan,
                displayName: displayName,
                symbolName: symbolName,
                headline: "Passive",
                unit: "",
                secondaryText: nil,
                spark: spark,
                status: .fine,
                availability: availability,
                hasData: true
            )
        }

        let maxRPM = max(0, sample.fans.map(\.rpm).max() ?? 0)
        let status = sample.fans.reduce(StatusLevel.fine) { current, fan in
            guard let minRPM = fan.minRPM, let fanMaxRPM = fan.maxRPM else { return current }
            return max(current, StatusThresholds.fan(rpm: Double(fan.rpm), minRPM: Double(minRPM), maxRPM: Double(fanMaxRPM)))
        }
        return OverviewTileModel(
            category: .fan,
            displayName: displayName,
            symbolName: symbolName,
            headline: "\(maxRPM)",
            unit: "rpm",
            secondaryText: nil,
            spark: spark,
            status: status,
            availability: availability,
            hasData: true
        )
    }

    private static func makeNetwork(
        sample: NetworkSample,
        displayName: String,
        symbolName: String,
        spark: [Double],
        availability: Availability?,
        units: OverviewUnitPreferences
    ) -> OverviewTileModel {
        let downBytes = sample.totalBytesInPerSec.isFinite ? max(0.0, sample.totalBytesInPerSec) : 0.0
        let upBytes = sample.totalBytesOutPerSec.isFinite ? max(0.0, sample.totalBytesOutPerSec) : 0.0
        let downParts = Units.rateComponents(downBytes, unit: units.networkUnit, standard: units.byteUnitStandard)
        let upCompact = Units.formatCompactRate(upBytes, unit: units.networkUnit, standard: units.byteUnitStandard)

        return OverviewTileModel(
            category: .network,
            displayName: displayName,
            symbolName: symbolName,
            headline: "↓ \(String(format: downParts.format, downParts.value))",
            unit: downParts.unit,
            secondaryText: "↑ \(upCompact)",
            spark: spark,
            status: networkStatus(for: sample),
            availability: availability,
            hasData: true
        )
    }

    private static func networkStatus(for sample: NetworkSample) -> StatusLevel {
        if let health = sample.connectionHealth {
            if health.isProbing { return .fine }
            switch health.status {
            case .disconnected: return .critical
            case .degraded: return .elevated
            case .connected: return .fine
            }
        }
        if let wifi = sample.wifiDetails {
            if wifi.qualityRating == "Weak" || (wifi.signalPercent ?? 100) < 30 {
                return .elevated
            }
        }
        if sample.interfaces.isEmpty ||
            (sample.interfaces.allSatisfy { $0.bytesInPerSec == 0 && $0.bytesOutPerSec == 0 } && sample.localIPv4 == nil) {
            return .critical
        }
        return .fine
    }

    private static func makeDisk(
        sample: DiskSample,
        displayName: String,
        symbolName: String,
        spark: [Double],
        availability: Availability?,
        units: OverviewUnitPreferences
    ) -> OverviewTileModel {
        let boot = sample.volumes.first(where: { $0.mountPoint == "/" })
            ?? sample.volumes.max(by: { $0.total < $1.total })

        guard let boot, boot.total > 0 else {
            return OverviewTileModel(
                category: .disk,
                displayName: displayName,
                symbolName: symbolName,
                headline: "--",
                unit: "",
                secondaryText: nil,
                spark: spark,
                status: .fine,
                availability: availability,
                hasData: false
            )
        }

        let freeParts = Units.byteComponents(boot.free, standard: units.byteUnitStandard)
        let usedPct = Double(boot.used) / Double(boot.total) * 100.0

        return OverviewTileModel(
            category: .disk,
            displayName: displayName,
            symbolName: symbolName,
            headline: String(format: freeParts.format, freeParts.value),
            unit: "\(freeParts.unit) free",
            secondaryText: "\(Int(round(usedPct)))% used",
            spark: spark,
            status: StatusThresholds.disk(usedPercent: usedPct),
            availability: availability,
            hasData: true
        )
    }

    private static func makePower(
        sample: PowerSample,
        displayName: String,
        symbolName: String,
        spark: [Double],
        availability: Availability?,
        hasBattery: Bool
    ) -> OverviewTileModel {
        let usesBattery = hasBattery && sample.hasBattery
        if usesBattery {
            let hasCharge = sample.charge?.isFinite == true
            let clampedCharge = sample.charge.flatMap { $0.isFinite ? min(100.0, max(0.0, $0)) : nil } ?? 0.0
            let wattsText: String? = sample.powerDrawWatts.flatMap {
                ($0.isFinite && $0 > 0) ? String(format: "%.1f W", $0) : nil
            }
            let status: StatusLevel
            if sample.isPowerDeficit {
                status = .warning
            } else if sample.isOnHold {
                status = .fine
            } else if let charge = sample.charge, charge.isFinite {
                let isChargingOrAC = sample.state == .charging || sample.state == .charged || sample.state == .acConnected
                status = StatusThresholds.battery(chargePercent: charge, isCharging: isChargingOrAC)
            } else {
                status = .fine
            }

            return OverviewTileModel(
                category: .power,
                displayName: displayName,
                symbolName: symbolName,
                headline: hasCharge ? String(format: "%.0f", clampedCharge) : "--",
                unit: hasCharge ? "%" : "",
                secondaryText: wattsText,
                spark: spark,
                status: status,
                availability: availability,
                hasData: hasCharge
            )
        }

        let hasWatts = sample.powerDrawWatts?.isFinite == true
        let watts = sample.powerDrawWatts.flatMap { $0.isFinite ? max(0.0, $0) : nil } ?? 0.0
        return OverviewTileModel(
            category: .power,
            displayName: displayName,
            symbolName: symbolName,
            headline: hasWatts ? String(format: "%.1f", watts) : "--",
            unit: hasWatts ? "W" : "",
            secondaryText: nil,
            spark: spark,
            status: .fine,
            availability: availability,
            hasData: hasWatts
        )
    }

    // MARK: - Scalar Sparkline Extraction

    private static func sparkSeries(
        for category: MetricCategory,
        in store: MetricsStore,
        hasBattery: Bool,
        maxPoints: Int
    ) -> [Double] {
        switch category {
        case .cpu:
            let user = store.scalarHistory(for: .cpuUser, maxPoints: maxPoints)
            let system = store.scalarHistory(for: .cpuSystem, maxPoints: maxPoints)
            if user.count == system.count {
                return zip(user, system).map(+)
            }
            return user
        case .memory:
            return store.scalarHistory(for: .memoryUsedPercent, maxPoints: maxPoints)
        case .gpu:
            return store.scalarHistory(for: .gpuUtilization, maxPoints: maxPoints)
        case .thermal:
            return store.scalarHistory(for: .thermalPeakCelsius, maxPoints: maxPoints)
        case .fan:
            return store.scalarHistory(for: .fanMaxRPM, maxPoints: maxPoints)
        case .network:
            return store.scalarHistory(for: .networkInBytesPerSec, maxPoints: maxPoints)
        case .disk:
            let read = store.scalarHistory(for: .diskReadBytesPerSec, maxPoints: maxPoints)
            let write = store.scalarHistory(for: .diskWriteBytesPerSec, maxPoints: maxPoints)
            if read.count == write.count {
                return zip(read, write).map(+)
            }
            return read
        case .power:
            return store.scalarHistory(for: hasBattery ? .powerChargePercent : .powerWatts, maxPoints: maxPoints)
        }
    }
}
