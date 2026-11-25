import Foundation

// MARK: - Families, layouts, roles, width classes

/// Renderer family a widget is drawn by (task 9.7). One renderer per family on the app side.
public enum WidgetFamily: String, Sendable, CaseIterable {
    case value   // label over value text
    case dual    // two values (two-line / single-line text, dual capsule)
    case bar     // single capsule, memory allocation capsule
    case ring    // donut gauges
    case graph   // sparklines and duplex graphs
    case glyph   // thermometer, fan, battery, activity arrows / LEDs
}

/// Concrete drawing layout. The family is derived from it.
public enum WidgetLayout: String, Sendable, CaseIterable {
    case labelValue
    case twoLine, singleLine, dualCapsule
    case singleCapsule, memoryAllocation
    case ring, cpuRing
    case sparkline, cpuSparkline, duplexGraph
    case thermometer, fanGlyph, battery, arrows, leds

    public var family: WidgetFamily {
        switch self {
        case .labelValue: return .value
        case .twoLine, .singleLine, .dualCapsule: return .dual
        case .singleCapsule, .memoryAllocation: return .bar
        case .ring, .cpuRing: return .ring
        case .sparkline, .cpuSparkline, .duplexGraph: return .graph
        case .thermometer, .fanGlyph, .battery, .arrows, .leds: return .glyph
        }
    }
}

/// Semantic color role. The renderer resolves it through `CategoryPalette`.
public enum WidgetColorRole: Hashable, Sendable {
    /// Template / primary label color.
    case label
    /// The metric category's own palette color.
    case category
    /// The shared status palette color for the level.
    case status(StatusLevel)

    var token: String {
        switch self {
        case .label: return "l"
        case .category: return "c"
        case .status(let level): return "s\(level.rawValue)"
        }
    }
}

/// Fixed width class per style: the canvas width never depends on the current value.
/// `worstCase` is the longest string the style can display; the renderer measures it once.
public enum WidgetWidthClass: String, Hashable, Sendable {
    case stackedPercent   // label over value, 32 pt minimum (worst case "100%")
    case stackedTemperature
    case stackedRPM
    case stackedBytes
    case twoLineRate      // 60 pt
    case singleLineRate   // 82 pt
    case twoLineFan       // 36 pt
    case twoLinePower     // 34 pt
    case singleCapsule    // 25 pt
    case dualCapsule      // 36 pt
    case ring             // 18 pt bare, 32 pt labeled
    case graph            // 36 pt bare, 50 pt labeled
    case thermometer      // 42 pt minimum, grows for the worst-case string only
    case fanGlyph         // 44 pt
    case battery          // 25 pt
    case arrows           // 18 pt
    case leds             // 20 pt

    public var minWidth: Double {
        switch self {
        case .stackedPercent, .stackedTemperature, .stackedRPM, .stackedBytes: return 32
        case .twoLineRate: return 60
        case .singleLineRate: return 82
        case .twoLineFan: return 36
        case .twoLinePower: return 34
        case .singleCapsule: return 25
        case .dualCapsule: return 36
        case .ring: return 18
        case .graph: return 36
        case .thermometer: return 42
        case .fanGlyph: return 44
        case .battery: return 25
        case .arrows: return 18
        case .leds: return 20
        }
    }

    /// Longest value string the style can display, used to size the canvas once.
    public var worstCase: String? {
        switch self {
        case .stackedPercent: return "100%"
        case .stackedTemperature: return "199 °C"  // formatTemperature emits "<n> °C"; °C is wider than °F
        case .stackedRPM: return "9999"
        case .stackedBytes: return "999G"
        case .thermometer: return "199 °C"
        case .twoLinePower: return "100% ⚡"
        case .fanGlyph: return "9999"
        default: return nil
        }
    }
}

// MARK: - Series

/// Sparkline / graph data. Equality and hashing use only the newest-sample stamp, the sample count and the
/// scale, so a graph widget changes its identity exactly when a new sample arrives.
public struct WidgetSeries: Hashable, Sendable {
    public var primary: [Double]
    public var secondary: [Double]
    public var tertiary: [Double]
    public var stamp: Int
    /// Minimum y-axis maximum.
    public var scaleFloor: Double
    /// y-axis maximum used when there is no data at all.
    public var emptyMax: Double

    public init(
        primary: [Double] = [],
        secondary: [Double] = [],
        tertiary: [Double] = [],
        stamp: Int = 0,
        scaleFloor: Double = 100,
        emptyMax: Double? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.stamp = stamp
        self.scaleFloor = scaleFloor
        self.emptyMax = emptyMax ?? scaleFloor
    }

    /// y-axis maximum for the primary series.
    public var primaryMax: Double {
        guard let peak = primary.max() else { return emptyMax }
        return max(peak, scaleFloor)
    }

    public static func == (lhs: WidgetSeries, rhs: WidgetSeries) -> Bool {
        lhs.stamp == rhs.stamp && lhs.primary.count == rhs.primary.count && lhs.scaleFloor == rhs.scaleFloor
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stamp)
        hasher.combine(primary.count)
        hasher.combine(scaleFloor)
    }

    /// Stamp for a sample list: newest timestamp in milliseconds combined with the count.
    public static func stamp<V: Sendable>(of samples: [Sample<V>]) -> Int {
        let ms = Int(((samples.last?.timestamp.timeIntervalSinceReferenceDate ?? 0) * 1000).rounded())
        return ms &* 31 &+ samples.count
    }

    /// Builds a series from samples with optional per-point extraction (points that yield nil are skipped).
    public static func build<V: Sendable>(
        _ samples: [Sample<V>],
        scaleFloor: Double = 100,
        emptyMax: Double? = nil,
        primary: (V) -> Double?,
        secondary: ((V) -> Double?)? = nil,
        tertiary: ((V) -> Double?)? = nil
    ) -> WidgetSeries {
        WidgetSeries(
            primary: samples.compactMap { primary($0.value) },
            secondary: secondary.map { f in samples.compactMap { f($0.value) } } ?? [],
            tertiary: tertiary.map { f in samples.compactMap { f($0.value) } } ?? [],
            stamp: stamp(of: samples),
            scaleFloor: scaleFloor,
            emptyMax: emptyMax
        )
    }
}

// MARK: - Inputs

/// Latest samples (and, for graph styles only, history) a widget is computed from.
public struct WidgetSnapshot: Sendable {
    public var cpu: CPUSample?
    public var memory: MemorySample?
    public var gpu: GPUSample?
    public var thermal: ThermalSample?
    public var fan: FanSample?
    public var network: NetworkSample?
    public var disk: DiskSample?
    public var power: PowerSample?
    public var series: WidgetSeries

    public init(
        cpu: CPUSample? = nil,
        memory: MemorySample? = nil,
        gpu: GPUSample? = nil,
        thermal: ThermalSample? = nil,
        fan: FanSample? = nil,
        network: NetworkSample? = nil,
        disk: DiskSample? = nil,
        power: PowerSample? = nil,
        series: WidgetSeries = WidgetSeries()
    ) {
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.thermal = thermal
        self.fan = fan
        self.network = network
        self.disk = disk
        self.power = power
        self.series = series
    }
}

public struct WidgetOptions: Sendable, Hashable {
    public var temperatureUnit: Units.TemperatureUnit
    public var networkUnit: Units.NetworkUnit
    public var byteUnitStandard: Units.ByteUnitStandard

    public init(
        temperatureUnit: Units.TemperatureUnit = .celsius,
        networkUnit: Units.NetworkUnit = .bytesPerSecond,
        byteUnitStandard: Units.ByteUnitStandard = .si
    ) {
        self.temperatureUnit = temperatureUnit
        self.networkUnit = networkUnit
        self.byteUnitStandard = byteUnitStandard
    }
}

// MARK: - Model

/// Everything a menu bar widget renderer needs, computed purely from samples, style and options.
/// `Hashable`: two equal models draw identical pixels, so the model (via `visualKey`) is the dirty-check
/// and image-cache key.
public struct WidgetModel: Hashable, Sendable {
    /// The single temperature range (degrees Celsius) shown by thermal widgets.
    public static let thermalRangeCelsius: ClosedRange<Double> = 30.0...100.0
    /// Network activity threshold (bytes/s) for the arrows glyph.
    public static let networkActivityThreshold: Double = 1024
    /// Disk activity threshold (bytes/s) for the R/W LEDs.
    public static let diskActivityThreshold: Double = 10_240

    public var category: MetricCategory
    public var style: MetricDisplayStyle
    public var layout: WidgetLayout
    public var showLabel: Bool
    /// Category title / label text (already resolved; nil when no label is shown).
    public var label: String?
    public var texts: [String]
    public var prefixes: [String]
    /// Values quantized to whole percent (0...100).
    public var fractions: [Int]
    public var flags: [Bool]
    public var numbers: [Int]
    public var status: StatusLevel
    public var colorRole: WidgetColorRole
    public var widthClass: WidgetWidthClass
    public var variant: PowerStateVariant?
    public var series: WidgetSeries?

    public var family: WidgetFamily { layout.family }

    /// Deterministic string form of the model; the dirty-check and cache key.
    public var visualKey: String {
        var parts: [String] = [category.rawValue, style.rawValue, layout.rawValue, showLabel ? "L1" : "L0"]
        parts.append(label ?? "-")
        parts.append("t=" + texts.joined(separator: "|"))
        parts.append("p=" + prefixes.joined(separator: "|"))
        parts.append("f=" + fractions.map(String.init).joined(separator: ","))
        parts.append("b=" + flags.map { $0 ? "1" : "0" }.joined())
        parts.append("n=" + numbers.map(String.init).joined(separator: ","))
        parts.append("s=\(status.rawValue)")
        parts.append("c=\(colorRole.token)")
        parts.append("w=\(widthClass.rawValue)")
        if let variant { parts.append("v=\(variant.rawValue)") }
        if let series { parts.append("g=\(series.stamp):\(series.primary.count)") }
        return parts.joined(separator: ";")
    }

    // MARK: Helpers

    /// Quantizes a percentage to a whole number in 0...100.
    public static func quantize(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, 0.0), 100.0).rounded())
    }

    /// Percentage (0...100) of the thermal range for a temperature.
    public static func thermalPercent(celsius: Double) -> Double {
        let lo = thermalRangeCelsius.lowerBound
        let hi = thermalRangeCelsius.upperBound
        return min(max((celsius - lo) / (hi - lo) * 100.0, 0.0), 100.0)
    }

    /// Fan speed as 0...100 of its range.
    public static func fanPercentage(for fan: FanReading) -> Double {
        if let maxRPM = fan.maxRPM, let minRPM = fan.minRPM, maxRPM > minRPM {
            return min(max(Double(fan.rpm - minRPM) / Double(maxRPM - minRPM) * 100.0, 0.0), 100.0)
        } else if let maxRPM = fan.maxRPM, maxRPM > 0 {
            return min(max(Double(fan.rpm) / Double(maxRPM) * 100.0, 0.0), 100.0)
        } else {
            return min(max(Double(fan.rpm) / FanMath.fallbackMaxRPM * 100.0, 0.0), 100.0)
        }
    }

    /// Compact free/used byte string such as "412G" or "1.2T".
    public static func formatCompactBytes(_ bytes: UInt64, standard: Units.ByteUnitStandard = .si) -> String {
        let base: Double = (standard == .si) ? 1000.0 : 1024.0
        let gigabytes = Double(bytes) / (base * base * base)
        if gigabytes >= base {
            return String(format: "%.1fT", gigabytes / base)
        } else if gigabytes >= 10.0 {
            return String(format: "%.0fG", gigabytes)
        } else if gigabytes >= 1.0 {
            return String(format: "%.1fG", gigabytes)
        } else {
            return String(format: "%.0fM", Double(bytes) / (base * base))
        }
    }

    /// Resolves the thermal source, display title and the hottest matching sensor.
    public static func resolveThermalSensor(
        style: MetricDisplayStyle,
        source: MetricSource? = nil,
        thermal: ThermalSample?
    ) -> (sensor: SensorReading?, title: String, componentLabel: String) {
        let src = source ?? {
            switch style {
            case .cpuTemp: return .cpu
            case .gpuTemp: return .gpu
            case .memoryTemp: return .memory
            case .storageTemp: return .ssd
            case .batteryTemp: return .battery
            default: return .peak
            }
        }()
        let title = src.shortLabel
        let componentLabel = (src == .peak) ? "Peak" : src.displayName
        let sensor = thermal.flatMap { ThermalSensorClassifier.sensors(in: $0, for: src).max(by: { $0.celsius < $1.celsius }) }
        return (sensor, title, componentLabel)
    }

    /// Two-line battery text: charge (with bolt while charging) over time remaining, wattage or state.
    public static func powerStackedTextLines(
        charge: Double?,
        state: BatteryState?,
        timeRemaining: TimeInterval?,
        watts: Double?
    ) -> (line1: String, line2: String) {
        let bolt = (state == .charging) ? " ⚡" : ""
        let l1 = String(format: "%.0f%%%@", charge ?? 0.0, bolt)
        let l2: String
        if state == .charging {
            l2 = "Charging"
        } else if let time = timeRemaining, time > 0 {
            l2 = String(format: "%d:%02d", Int(time) / 3600, (Int(time) % 3600) / 60)
        } else if let w = watts, w > 0 {
            l2 = String(format: "%.1fW", w)
        } else if state == .charged {
            l2 = "Full"
        } else if state == .acConnected {
            l2 = "AC"
        } else {
            l2 = "Bat"
        }
        return (l1, l2)
    }

    private static func statusRole(_ level: StatusLevel) -> WidgetColorRole {
        level >= .warning ? .status(level) : .label
    }

    // MARK: Factory

    public static func make(
        config: MenuBarItemConfig,
        snapshot s: WidgetSnapshot,
        options o: WidgetOptions = WidgetOptions()
    ) -> WidgetModel {
        var m = WidgetModel(
            category: config.category, style: config.style, layout: .labelValue,
            showLabel: config.showLabel, label: nil, texts: [], prefixes: [], fractions: [],
            flags: [], numbers: [], status: .fine, colorRole: .label, widthClass: .stackedPercent,
            variant: nil, series: nil
        )
        let lbl: (String) -> String? = { config.showLabel ? $0 : nil }

        switch config.category {
        case .cpu:
            let cpu = s.cpu
            let usage = cpu?.totalUsage ?? 0.0
            m.status = StatusThresholds.cpu(usagePercent: usage)
            switch config.style {
            case .gauge:
                m.layout = .cpuRing; m.widthClass = .ring; m.label = lbl("CPU"); m.colorRole = .category
                let u = quantize(cpu?.user ?? usage)
                m.fractions = [u, min(quantize(cpu?.system ?? 0.0), 100 - u)]
            case .bar:
                m.layout = .dualCapsule; m.widthClass = .dualCapsule; m.label = "CPU"; m.colorRole = .category
                var hybrid = false
                var a = 0.0, b = 0.0
                if let cores = cpu?.perCore, let e = cpu?.efficiencyCoreCount, let p = cpu?.performanceCoreCount,
                   e > 0, p > 0, e + p == cores.count {
                    hybrid = true
                    a = cores.prefix(e).reduce(0.0, +) / Double(e)
                    b = cores.suffix(from: e).reduce(0.0, +) / Double(p)
                } else {
                    a = cpu?.user ?? (cpu?.perCore.isEmpty == false ? cpu!.perCore.reduce(0.0, +) / Double(cpu!.perCore.count) : 0.0)
                    b = cpu?.system ?? 0.0
                }
                m.fractions = [quantize(a), quantize(b)]
                m.flags = [hybrid]
            case .sparkline:
                let ser = s.series
                m.series = ser; m.widthClass = .graph; m.label = lbl("CPU"); m.colorRole = .category
                m.layout = (ser.secondary.count == ser.primary.count && ser.tertiary.count == ser.primary.count && ser.primary.count >= 2)
                    ? .cpuSparkline : .sparkline
            default:
                m.layout = .labelValue; m.label = "CPU"
                m.texts = [cpu != nil ? String(format: "%.0f%%", usage) : "--%"]
                if config.style == .text { m.colorRole = statusRole(m.status) }
            }

        case .memory:
            let mem = s.memory
            let ratio = (mem != nil && mem!.total > 0) ? Double(mem!.used) / Double(mem!.total) * 100.0 : 0.0
            m.status = StatusThresholds.memory(pressure: mem?.pressure ?? .normal, swapUsedBytes: mem?.swapUsed ?? 0)
            switch config.style {
            case .gauge, .symbol:
                m.layout = .ring; m.widthClass = .ring; m.label = lbl("MEM"); m.colorRole = .status(m.status)
                m.fractions = [quantize(ratio)]
            case .bar:
                m.layout = .memoryAllocation; m.widthClass = .singleCapsule; m.label = "RAM"
                if let mem, mem.total > 0 {
                    let total = Double(mem.total)
                    let app = Double(mem.appMemory ?? mem.active ?? (mem.used - min(mem.used, mem.wired + mem.compressed)))
                    m.fractions = [quantize(ratio), quantize(app / total * 100), quantize(Double(mem.wired) / total * 100), quantize(Double(mem.compressed) / total * 100)]
                    m.flags = [true]
                } else {
                    m.fractions = [quantize(ratio), 0, 0, 0]
                    m.flags = [false]
                }
                m.colorRole = .status(.fine)
            case .sparkline:
                m.layout = .sparkline; m.widthClass = .graph; m.label = lbl("MEM"); m.series = s.series
                m.colorRole = .status(m.status)
            default:
                m.label = "MEM"; m.texts = [mem != nil ? String(format: "%.0f%%", ratio) : "--%"]
                if config.style == .text { m.colorRole = statusRole(m.status) }
            }

        case .gpu:
            let gpu = s.gpu
            let util = gpu?.utilization ?? 0.0
            m.status = StatusThresholds.gpu(utilizationPercent: util)
            switch config.style {
            case .gauge, .symbol:
                m.layout = .ring; m.widthClass = .ring; m.label = lbl("GPU"); m.fractions = [quantize(util)]
                m.colorRole = m.status >= .warning ? .status(m.status) : .category
            case .bar:
                m.layout = .singleCapsule; m.widthClass = .singleCapsule; m.label = "GPU"; m.colorRole = .category
                m.fractions = [quantize(util)]
            case .sparkline:
                m.layout = .sparkline; m.widthClass = .graph; m.label = lbl("GPU"); m.colorRole = .category; m.series = s.series
            default:
                m.label = "GPU"; m.texts = [gpu?.utilization != nil ? String(format: "%.0f%%", util) : "--%"]
                if config.style == .text { m.colorRole = statusRole(m.status) }
            }

        case .thermal:
            let (sensor, title, _) = resolveThermalSensor(style: config.style, source: config.source, thermal: s.thermal)
            let source = config.source ?? .peak
            let tempC = sensor?.celsius ?? 0.0
            m.status = StatusThresholds.temperature(celsius: tempC, source: source, pressure: s.thermal?.pressure)
            let valStr = sensor != nil ? Units.formatTemperature(tempC, unit: o.temperatureUnit, fractionDigits: 0) : "--°"
            let pct = quantize(thermalPercent(celsius: tempC))
            switch config.style {
            case .text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .batteryTemp:
                m.widthClass = .stackedTemperature
                m.label = title; m.texts = [valStr]; m.colorRole = statusRole(m.status)
                m.flags = [s.thermal?.pressure == .serious || s.thermal?.pressure == .critical]
            case .sparkline:
                m.layout = .sparkline; m.widthClass = .graph; m.label = lbl(title); m.series = s.series
                let latest = s.series.primary.last ?? 50.0
                m.colorRole = .status(StatusThresholds.temperature(celsius: latest, source: .peak))
            case .gauge:
                m.layout = .ring; m.widthClass = .ring; m.label = lbl(title); m.fractions = [pct]
                m.colorRole = .status(m.status)
            case .bar:
                m.layout = .singleCapsule; m.widthClass = .singleCapsule; m.label = "TMP"; m.fractions = [pct]
                m.colorRole = .status(m.status)
            default:
                m.layout = .thermometer; m.widthClass = .thermometer; m.texts = [valStr]
                m.fractions = [pct]; m.flags = [sensor != nil]
                m.colorRole = m.status >= .warning ? .status(m.status) : .category
            }

        case .fan:
            let fan = s.fan
            let fans = fan?.fans ?? []
            let primary = fans.max(by: { fanPercentage(for: $0) < fanPercentage(for: $1) }) ?? fans.first
            let isFanless = fan?.isFanless == true || (fan != nil && fans.isEmpty)
            m.status = isFanless ? .fine : StatusThresholds.fan(
                rpm: Double(primary?.rpm ?? 0),
                minRPM: Double(primary?.minRPM ?? 0),
                maxRPM: Double(primary?.maxRPM ?? Int(FanMath.fallbackMaxRPM))
            )
            let pct = quantize(primary.map { fanPercentage(for: $0) } ?? 0.0)
            switch config.style {
            case .text:
                m.widthClass = .stackedRPM
                m.label = "FAN"; m.texts = [isFanless ? "—" : (primary != nil ? "\(primary!.rpm)" : "--")]
                m.colorRole = statusRole(m.status)
            case .throughput:
                if !isFanless && fans.count >= 2 {
                    m.layout = .twoLine; m.widthClass = .twoLineFan; m.colorRole = .category
                    m.prefixes = ["L", "R"]; m.texts = ["\(fans[0].rpm)", "\(fans[1].rpm)"]
                } else {
                    m.widthClass = .stackedRPM
                    m.label = "FAN"; m.texts = [isFanless ? "—" : (primary != nil ? "\(primary!.rpm)" : "--")]
                }
            case .bar:
                m.colorRole = .category
                if fans.count >= 2 {
                    m.layout = .dualCapsule; m.widthClass = .dualCapsule; m.label = "FAN"
                    m.fractions = [quantize(fanPercentage(for: fans[0])), quantize(fanPercentage(for: fans[1]))]
                } else {
                    m.layout = .singleCapsule; m.widthClass = .singleCapsule; m.label = "FAN"; m.fractions = [pct]
                }
            case .sparkline:
                m.layout = .sparkline; m.widthClass = .graph; m.label = lbl("FAN"); m.colorRole = .category; m.series = s.series
            case .gauge, .symbol:
                m.layout = .ring; m.widthClass = .ring; m.label = lbl("FAN"); m.fractions = [pct]; m.colorRole = .category
            default:
                m.layout = .fanGlyph; m.widthClass = .fanGlyph
                m.texts = [isFanless ? "—" : (primary != nil ? "\(primary!.rpm)" : "--")]
                m.flags = [isFanless]
                m.colorRole = .status(m.status)
            }

        case .network:
            let inB = s.network?.totalBytesInPerSec ?? 0.0
            let outB = s.network?.totalBytesOutPerSec ?? 0.0
            switch config.style {
            case .throughput:
                let i = Units.formatCompactRate(inB, unit: o.networkUnit, standard: o.byteUnitStandard)
                let u = Units.formatCompactRate(outB, unit: o.networkUnit, standard: o.byteUnitStandard)
                if config.throughputLayout == .singleLine {
                    m.layout = .singleLine; m.widthClass = .singleLineRate; m.colorRole = .category
                    m.prefixes = ["↓", "↑"]; m.texts = [i, u]
                } else {
                    m.layout = .twoLine; m.widthClass = .twoLineRate
                    m.prefixes = ["↑", "↓"]; m.texts = [u, i]
                }
            case .sparkline:
                m.layout = .duplexGraph; m.widthClass = .graph; m.label = lbl("NET"); m.series = s.series; m.colorRole = .category
            default:
                m.layout = .arrows; m.widthClass = .arrows; m.colorRole = .category
                m.flags = [inB > networkActivityThreshold, outB > networkActivityThreshold]
            }

        case .disk:
            let r = s.disk?.io?.bytesReadPerSec ?? 0.0
            let w = s.disk?.io?.bytesWrittenPerSec ?? 0.0
            let vol = s.disk?.volumes.first(where: { $0.mountPoint == "/" }) ?? s.disk?.volumes.first
            let volRatio = (vol != nil && vol!.total > 0) ? Double(vol!.used) / Double(vol!.total) * 100.0 : 0.0
            m.status = StatusThresholds.disk(usedPercent: volRatio)
            switch config.style {
            case .throughput:
                let rs = Units.formatCompactRate(r, unit: .bytesPerSecond, standard: o.byteUnitStandard)
                let ws = Units.formatCompactRate(w, unit: .bytesPerSecond, standard: o.byteUnitStandard)
                m.prefixes = ["R", "W"]; m.texts = [rs, ws]
                if config.throughputLayout == .singleLine {
                    m.layout = .singleLine; m.widthClass = .singleLineRate; m.colorRole = .category
                } else {
                    m.layout = .twoLine; m.widthClass = .twoLineRate
                }
            case .symbol:
                m.layout = .leds; m.widthClass = .leds; m.colorRole = .category
                m.flags = [r > diskActivityThreshold, w > diskActivityThreshold]
            case .gauge:
                m.layout = .ring; m.widthClass = .ring; m.label = lbl("SSD"); m.fractions = [quantize(volRatio)]
                m.colorRole = m.status >= .warning ? .status(m.status) : .category
            case .sparkline:
                m.layout = .duplexGraph; m.widthClass = .graph; m.label = lbl("SSD"); m.series = s.series; m.colorRole = .category
            case .bar:
                m.layout = .singleCapsule; m.widthClass = .singleCapsule; m.label = "SSD"; m.colorRole = .category
                m.fractions = [quantize(volRatio)]
            default:
                m.widthClass = .stackedBytes
                m.label = "SSD"
                m.texts = [vol != nil ? formatCompactBytes(vol!.free, standard: o.byteUnitStandard) : "--G"]
                if config.style == .text { m.colorRole = statusRole(m.status) }
            }

        case .power:
            let p = s.power
            let variant = p?.variant ?? .unavailable
            m.variant = variant
            switch config.style {
            case .text:
                let lines = powerStackedTextLines(charge: p?.charge, state: p?.state, timeRemaining: p?.timeRemaining, watts: p?.powerDrawWatts)
                m.layout = .twoLine; m.widthClass = .twoLinePower
                m.prefixes = ["", ""]; m.texts = [lines.line1, lines.line2]
            case .throughput:
                m.layout = .twoLine; m.widthClass = .twoLinePower; m.colorRole = .category
                m.prefixes = ["", ""]
                m.texts = [
                    p?.powerDrawWatts.map { String(format: "%.0fW", $0) } ?? "--W",
                    p?.adapterWatts.map { String(format: "%.0fW", $0) } ?? "AC"
                ]
            case .sparkline:
                m.layout = .sparkline; m.widthClass = .graph; m.label = lbl("PWR"); m.colorRole = .category; m.series = s.series
            default:
                m.layout = .battery; m.widthClass = .battery
                m.fractions = [quantize(p?.charge ?? 0.0)]
                m.flags = [p?.charge != nil, p?.hasBattery ?? true]
            }
        }
        return m
    }
}
