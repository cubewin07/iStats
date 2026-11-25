import Foundation

// MARK: - MenuBarAppearance UI Labels

public extension MenuBarAppearance {
    /// Human-readable label for Settings controls.
    var displayName: String {
        switch self {
        case .monochrome: return "Monochrome"
        case .statusTint: return "Status Tint"
        case .categoryColor: return "Category Color"
        }
    }

    /// Brief explanation of how this appearance mode tints menu bar widgets.
    var summary: String {
        switch self {
        case .monochrome:
            return "Always matches the macOS menu bar as monochrome templates."
        case .statusTint:
            return "Monochrome until a metric reaches warning or critical levels."
        case .categoryColor:
            return "Uses each category's accent palette continuously."
        }
    }
}

// MARK: - Widget Catalog

/// A single discoverable menu bar widget entry used by Settings galleries and previews (Task 9.8).
public struct WidgetCatalogEntry: Identifiable, Hashable, Sendable {
    public let category: MetricCategory
    public let style: MetricDisplayStyle
    public let title: String
    public let summary: String
    /// Representative sample values used to synthesize deterministic previews.
    public let sampleValues: [Double]
    /// Whether this entry is meaningful only on Macs with a battery.
    public let requiresBattery: Bool

    public var id: String { "\(category.rawValue).\(style.rawValue)" }
    public var vocabularyName: String { style.vocabularyName }
    public var family: WidgetFamily { style.widgetFamily }

    public init(
        category: MetricCategory,
        style: MetricDisplayStyle,
        title: String,
        summary: String,
        sampleValues: [Double],
        requiresBattery: Bool = false
    ) {
        self.category = category
        self.style = style
        self.title = title
        self.summary = summary
        self.sampleValues = sampleValues
        self.requiresBattery = requiresBattery
    }

    /// Builds a `MenuBarItemConfig` corresponding to this catalog entry.
    public func makeConfig(
        source: MetricSource? = nil,
        throughputLayout: ThroughputLayout? = nil,
        showLabel: Bool = false
    ) -> MenuBarItemConfig {
        let resolvedSource: MetricSource?
        if category == .thermal && (style == .text || style == .glyph) {
            resolvedSource = source ?? .peak
        } else {
            resolvedSource = source
        }
        return MenuBarItemConfig(
            category: category,
            style: style,
            source: resolvedSource,
            throughputLayout: throughputLayout ?? (style == .throughput ? .stacked : nil),
            showLabel: showLabel
        )
    }

    /// Synthesizes a deterministic `WidgetSnapshot` from `sampleValues` for offline previews.
    public func sampleSnapshot(hasBattery: Bool = true) -> WidgetSnapshot {
        let values = sampleValues
        let primary = values.first ?? 50.0
        switch category {
        case .cpu:
            let user = values.count > 1 ? values[1] : primary * 0.65
            let sys = values.count > 2 ? values[2] : max(0, primary - user)
            let sample = CPUSample(
                totalUsage: primary,
                perCore: [22, 26, 30, 28, 54, 62, 58, 66],
                user: user,
                system: sys,
                idle: max(0, 100 - primary),
                efficiencyCoreCount: 4,
                performanceCoreCount: 4
            )
            let userSeries = values.map { $0 * 0.68 }
            let sysSeries = values.map { $0 * 0.32 }
            let series = WidgetSeries(primary: values, secondary: userSeries, tertiary: sysSeries, stamp: 1, scaleFloor: 100)
            return WidgetSnapshot(cpu: sample, series: series)

        case .memory:
            let total: UInt64 = 16 * 1024 * 1024 * 1024
            let used = UInt64(Double(total) * min(max(primary, 0), 100) / 100.0)
            let app = UInt64(Double(total) * 0.38)
            let wired = UInt64(Double(total) * 0.14)
            let compressed = UInt64(Double(total) * 0.10)
            let sample = MemorySample(
                total: total,
                used: used,
                free: total - min(total, used),
                wired: wired,
                compressed: compressed,
                cached: 2 * 1024 * 1024 * 1024,
                swapUsed: 0,
                pressure: .normal,
                appMemory: app,
                active: app
            )
            let series = WidgetSeries(primary: values, stamp: 1, scaleFloor: 100)
            return WidgetSnapshot(memory: sample, series: series)

        case .gpu:
            let sample = GPUSample(utilization: primary, memoryUsed: 2 * 1024 * 1024 * 1024, tempCelsius: 52, powerWatts: 11)
            let series = WidgetSeries(primary: values, stamp: 1, scaleFloor: 100)
            return WidgetSnapshot(gpu: sample, series: series)

        case .thermal:
            let sample = ThermalSample(
                sensors: [
                    SensorReading(name: "CPU Package", celsius: primary),
                    SensorReading(name: "GPU Cluster 1", celsius: max(30, primary - 4)),
                    SensorReading(name: "Memory Module", celsius: max(30, primary - 11)),
                    SensorReading(name: "Storage NAND", celsius: max(28, primary - 17)),
                    SensorReading(name: "Battery Sensor", celsius: 33)
                ],
                pressure: .nominal
            )
            let series = WidgetSeries(primary: values, stamp: 1, scaleFloor: 100)
            return WidgetSnapshot(thermal: sample, series: series)

        case .fan:
            let rpm1 = Int(primary)
            let rpm2 = Int(values.count > 1 ? values[1] : primary + 150)
            let sample = FanSample(fans: [
                FanReading(name: "Left Fan", rpm: rpm1, minRPM: 1200, maxRPM: 5800),
                FanReading(name: "Right Fan", rpm: rpm2, minRPM: 1200, maxRPM: 5800)
            ])
            let series = WidgetSeries(primary: values, stamp: 1, scaleFloor: 2000, emptyMax: FanMath.fallbackMaxRPM)
            return WidgetSnapshot(fan: sample, series: series)

        case .network:
            let inRate = primary
            let outRate = values.count > 1 ? values[1] : primary * 0.25
            let sample = NetworkSample(interfaces: [
                InterfaceThroughput(
                    interfaceName: "en0",
                    bytesInPerSec: inRate,
                    bytesOutPerSec: outRate,
                    totalBytesIn: 1_500_000_000,
                    totalBytesOut: 420_000_000
                )
            ])
            let inSeries = values
            let outSeries = values.map { $0 * 0.35 }
            let series = WidgetSeries(primary: inSeries, secondary: outSeries, stamp: 1, scaleFloor: 1024)
            return WidgetSnapshot(network: sample, series: series)

        case .disk:
            let readRate = primary
            let writeRate = values.count > 1 ? values[1] : primary * 0.3
            let total: UInt64 = 1_000_000_000_000
            let used: UInt64 = 620_000_000_000
            let sample = DiskSample(
                volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: total, used: used, free: total - used)],
                io: DiskIO(bytesReadPerSec: readRate, bytesWrittenPerSec: writeRate, readOpsPerSec: 180, writeOpsPerSec: 75)
            )
            let readSeries = values
            let writeSeries = values.map { $0 * 0.4 }
            let series = WidgetSeries(primary: readSeries, secondary: writeSeries, stamp: 1, scaleFloor: 1024 * 1024)
            return WidgetSnapshot(disk: sample, series: series)

        case .power:
            let watts = values.count > 1 ? values[1] : 16.5
            let sample: PowerSample
            if hasBattery {
                sample = PowerSample(
                    hasBattery: true,
                    charge: primary,
                    state: .discharging,
                    timeRemaining: 5 * 3600 + 20 * 60,
                    powerDrawWatts: watts,
                    adapterWatts: 67
                )
            } else {
                sample = PowerSample(
                    hasBattery: false,
                    charge: nil,
                    state: .acConnected,
                    timeRemaining: nil,
                    powerDrawWatts: watts,
                    adapterWatts: 140
                )
            }
            let wattSeries = values.count >= 3 ? Array(values.dropFirst()) : [12, 16, 18, 15, 22, 19]
            let series = WidgetSeries(primary: wattSeries, stamp: 1, scaleFloor: 5)
            return WidgetSnapshot(power: sample, series: series)
        }
    }
}

/// Authoritative menu bar widget catalog matching `MetricDisplayStyle.supportedStyles(for:hasBattery:)`.
public enum WidgetCatalog {
    /// Returns every catalog entry supported for `category` on the current hardware.
    public static func entries(for category: MetricCategory, hasBattery: Bool = true) -> [WidgetCatalogEntry] {
        switch category {
        case .cpu:
            let cpuSeries: [Double] = [42, 28, 14, 34, 48, 52, 38, 42]
            return [
                WidgetCatalogEntry(category: .cpu, style: .text, title: MetricDisplayStyle.text.displayName(for: .cpu), summary: "Total CPU utilization percentage.", sampleValues: cpuSeries),
                WidgetCatalogEntry(category: .cpu, style: .gauge, title: MetricDisplayStyle.gauge.displayName(for: .cpu), summary: "Ring gauge showing user and system load.", sampleValues: cpuSeries),
                WidgetCatalogEntry(category: .cpu, style: .bar, title: MetricDisplayStyle.bar.displayName(for: .cpu), summary: "Dual bar for efficiency and performance clusters.", sampleValues: cpuSeries),
                WidgetCatalogEntry(category: .cpu, style: .sparkline, title: MetricDisplayStyle.sparkline.displayName(for: .cpu), summary: "Live sparkline of user and system CPU load.", sampleValues: cpuSeries)
            ]

        case .memory:
            let memSeries: [Double] = [62, 58, 60, 61, 63, 62, 64, 62]
            return [
                WidgetCatalogEntry(category: .memory, style: .text, title: MetricDisplayStyle.text.displayName(for: .memory), summary: "Percentage of physical RAM currently in use.", sampleValues: memSeries),
                WidgetCatalogEntry(category: .memory, style: .gauge, title: MetricDisplayStyle.gauge.displayName(for: .memory), summary: "Ring gauge tracking memory usage and pressure.", sampleValues: memSeries),
                WidgetCatalogEntry(category: .memory, style: .bar, title: MetricDisplayStyle.bar.displayName(for: .memory), summary: "Stacked capsule of App, Wired, and Compressed RAM.", sampleValues: memSeries),
                WidgetCatalogEntry(category: .memory, style: .sparkline, title: MetricDisplayStyle.sparkline.displayName(for: .memory), summary: "Recent RAM utilization history sparkline.", sampleValues: memSeries)
            ]

        case .gpu:
            let gpuSeries: [Double] = [36, 22, 28, 44, 52, 40, 32, 36]
            return [
                WidgetCatalogEntry(category: .gpu, style: .text, title: MetricDisplayStyle.text.displayName(for: .gpu), summary: "Current GPU utilization percentage.", sampleValues: gpuSeries),
                WidgetCatalogEntry(category: .gpu, style: .gauge, title: MetricDisplayStyle.gauge.displayName(for: .gpu), summary: "Compact ring showing active GPU load.", sampleValues: gpuSeries),
                WidgetCatalogEntry(category: .gpu, style: .bar, title: MetricDisplayStyle.bar.displayName(for: .gpu), summary: "Vertical capsule bar for GPU load.", sampleValues: gpuSeries),
                WidgetCatalogEntry(category: .gpu, style: .sparkline, title: MetricDisplayStyle.sparkline.displayName(for: .gpu), summary: "Sparkline chart of recent GPU utilization.", sampleValues: gpuSeries)
            ]

        case .thermal:
            let thermalSeries: [Double] = [58, 52, 54, 56, 60, 62, 59, 58]
            return [
                WidgetCatalogEntry(category: .thermal, style: .text, title: MetricDisplayStyle.text.displayName(for: .thermal), summary: "Numeric reading for Peak, CPU, GPU, RAM, SSD, or Battery sensor.", sampleValues: thermalSeries),
                WidgetCatalogEntry(category: .thermal, style: .glyph, title: MetricDisplayStyle.glyph.displayName(for: .thermal), summary: "Thermometer glyph paired with live temperature.", sampleValues: thermalSeries),
                WidgetCatalogEntry(category: .thermal, style: .sparkline, title: MetricDisplayStyle.sparkline.displayName(for: .thermal), summary: "Peak temperature trend sparkline.", sampleValues: thermalSeries)
            ]

        case .fan:
            let fanSeries: [Double] = [2400, 2600, 2100, 2250, 2400, 2550, 2450, 2400]
            return [
                WidgetCatalogEntry(category: .fan, style: .text, title: MetricDisplayStyle.text.displayName(for: .fan), summary: "Primary fan speed in RPM.", sampleValues: fanSeries),
                WidgetCatalogEntry(category: .fan, style: .glyph, title: MetricDisplayStyle.glyph.displayName(for: .fan), summary: "Fan icon paired with live RPM.", sampleValues: fanSeries),
                WidgetCatalogEntry(category: .fan, style: .bar, title: MetricDisplayStyle.bar.displayName(for: .fan), summary: "Proportional fan speed capsule bars.", sampleValues: fanSeries),
                WidgetCatalogEntry(category: .fan, style: .sparkline, title: MetricDisplayStyle.sparkline.displayName(for: .fan), summary: "Recent fan speed history sparkline.", sampleValues: fanSeries)
            ]

        case .network:
            let netSeries: [Double] = [2_400_000, 480_000, 1_100_000, 3_200_000, 2_800_000, 1_900_000, 2_400_000]
            return [
                WidgetCatalogEntry(category: .network, style: .throughput, title: MetricDisplayStyle.throughput.displayName(for: .network), summary: "Live upload and download throughput rates.", sampleValues: netSeries),
                WidgetCatalogEntry(category: .network, style: .sparkline, title: MetricDisplayStyle.sparkline.displayName(for: .network), summary: "Mirrored duplex download and upload history graph.", sampleValues: netSeries),
                WidgetCatalogEntry(category: .network, style: .glyph, title: MetricDisplayStyle.glyph.displayName(for: .network), summary: "Compact download and upload activity arrows.", sampleValues: netSeries)
            ]

        case .disk:
            let diskSeries: [Double] = [45_000_000, 12_000_000, 22_000_000, 68_000_000, 34_000_000, 45_000_000]
            return [
                WidgetCatalogEntry(category: .disk, style: .throughput, title: MetricDisplayStyle.throughput.displayName(for: .disk), summary: "Live storage read and write throughput.", sampleValues: diskSeries),
                WidgetCatalogEntry(category: .disk, style: .sparkline, title: MetricDisplayStyle.sparkline.displayName(for: .disk), summary: "Mirrored read and write I/O history graph.", sampleValues: diskSeries),
                WidgetCatalogEntry(category: .disk, style: .glyph, title: MetricDisplayStyle.glyph.displayName(for: .disk), summary: "Read and write activity LED indicators.", sampleValues: diskSeries),
                WidgetCatalogEntry(category: .disk, style: .gauge, title: MetricDisplayStyle.gauge.displayName(for: .disk), summary: "Ring gauge showing boot volume used space.", sampleValues: diskSeries),
                WidgetCatalogEntry(category: .disk, style: .text, title: MetricDisplayStyle.text.displayName(for: .disk), summary: "Remaining free capacity on the boot volume.", sampleValues: diskSeries)
            ]

        case .power:
            let powerSeries: [Double] = [82, 16.5, 14.0, 18.2, 15.8, 19.4, 16.5]
            let all: [WidgetCatalogEntry] = [
                WidgetCatalogEntry(
                    category: .power,
                    style: .glyph,
                    title: MetricDisplayStyle.glyph.displayName(for: .power, hasBattery: hasBattery),
                    summary: "Live battery fill glyph with charging and power state badges.",
                    sampleValues: powerSeries,
                    requiresBattery: true
                ),
                WidgetCatalogEntry(
                    category: .power,
                    style: .text,
                    title: MetricDisplayStyle.text.displayName(for: .power, hasBattery: hasBattery),
                    summary: hasBattery ? "Battery percentage over time remaining or wattage." : "Live system power draw in watts.",
                    sampleValues: powerSeries,
                    requiresBattery: false
                ),
                WidgetCatalogEntry(
                    category: .power,
                    style: .sparkline,
                    title: MetricDisplayStyle.sparkline.displayName(for: .power, hasBattery: hasBattery),
                    summary: "Recent system power draw sparkline in watts.",
                    sampleValues: powerSeries,
                    requiresBattery: false
                )
            ]
            return hasBattery ? all : all.filter { !$0.requiresBattery }
        }
    }

    /// Returns the recommended default catalog entry for `category`.
    public static func defaultEntry(for category: MetricCategory, hasBattery: Bool = true) -> WidgetCatalogEntry {
        let preferredStyle: MetricDisplayStyle
        switch category {
        case .cpu: preferredStyle = .bar
        case .memory: preferredStyle = .bar
        case .gpu: preferredStyle = .bar
        case .thermal: preferredStyle = .glyph
        case .fan: preferredStyle = .glyph
        case .network: preferredStyle = .throughput
        case .disk: preferredStyle = .throughput
        case .power: preferredStyle = hasBattery ? .glyph : .text
        }
        let list = entries(for: category, hasBattery: hasBattery)
        return list.first { $0.style == preferredStyle } ?? list[0]
    }

    /// Returns all catalog entries across every category for the given hardware profile.
    public static func allEntries(hasBattery: Bool = true) -> [WidgetCatalogEntry] {
        MetricCategory.allCases.flatMap { entries(for: $0, hasBattery: hasBattery) }
    }

    /// Looks up a specific catalog entry by category and style, if supported on the hardware.
    public static func entry(for category: MetricCategory, style: MetricDisplayStyle, hasBattery: Bool = true) -> WidgetCatalogEntry? {
        entries(for: category, hasBattery: hasBattery).first { $0.style == style }
    }
}
