import AppKit
import CoreText
import SwiftUI
import iStatsCore

/// Pure rendering engine that generates authentic iStat Menus high-DPI `NSImage` graphics and formatted title text
/// for any `MenuBarItemConfig` across all `MetricCategory` and `MetricDisplayStyle` options (ADR 0007 / ADR 0008).
@MainActor
public struct MenuBarIconRenderer {
    // MARK: - Image Cache (Stage 3 Energy Optimization)

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    /// Clears the rendered image cache (useful on low memory or theme change).
    public static func clearImageCache() {
        imageCache.removeAllObjects()
    }

    /// Returns a cached `NSImage` for the given `visualKey` if present, otherwise executes `draw` and caches the result.
    private static func cachedOrDraw(visualKey: String?, draw: () -> NSImage) -> NSImage {
        if let key = visualKey, let cached = imageCache.object(forKey: key as NSString) {
            return cached
        }
        let img = draw()
        if let key = visualKey {
            imageCache.setObject(img, forKey: key as NSString)
        }
        return img
    }

    public struct RenderResult {
        public let image: NSImage?
        public let title: String
        public let toolTip: String
        public let accessibilityLabel: String
        public let visualKey: String?

        public init(
            image: NSImage? = nil,
            title: String = "",
            toolTip: String = "",
            accessibilityLabel: String = "",
            visualKey: String? = nil
        ) {
            self.image = image
            self.title = title
            self.toolTip = toolTip
            self.accessibilityLabel = accessibilityLabel.isEmpty ? toolTip : accessibilityLabel
            self.visualKey = visualKey
        }
    }

    // MARK: - Fast-Path Visual Key Computation (Pre-Render Bypass)

    /// Fast-path visual key calculator that inspects the current metric state without performing any
    /// CoreGraphics drawing or NSImage allocation.
    /// Returns `nil` for unbounded continuous displays (like sparklines) that must redraw on every tick.
    public static func computeVisualKey(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator,
        preferences: PreferencesStore
    ) -> String? {
        guard config.style != .sparkline else { return nil }

        let baseKey: String?
        switch config.category {
        case .cpu:
            baseKey = visualKeyForCPU(style: config.style, cpu: coordinator.latestCPU?.value)
        case .memory:
            let memory = coordinator.latestMemory?.value
            let ratio: Double = (memory != nil && memory!.total > 0)
                ? (Double(memory!.used) / Double(memory!.total)) * 100.0
                : 0.0
            baseKey = visualKeyForMemory(style: config.style, memory: memory, ratio: ratio, standard: preferences.byteUnitStandard)
        case .gpu:
            baseKey = visualKeyForGPU(style: config.style, gpu: coordinator.latestGPU?.value)
        case .thermal:
            baseKey = visualKeyForThermal(style: config.style, source: config.source, thermal: coordinator.latestThermal?.value, unit: preferences.temperatureUnit)
        case .fan:
            baseKey = visualKeyForFan(style: config.style, fan: coordinator.latestFan?.value)
        case .network:
            baseKey = visualKeyForNetwork(style: config.style, throughputLayout: config.throughputLayout, network: coordinator.latestNetwork?.value, unit: preferences.networkUnit, standard: preferences.byteUnitStandard)
        case .disk:
            baseKey = visualKeyForDisk(style: config.style, throughputLayout: config.throughputLayout, disk: coordinator.latestDisk?.value, standard: preferences.byteUnitStandard)
        case .power:
            baseKey = visualKeyForPower(style: config.style, power: coordinator.latestPower?.value)
        }

        guard let key = baseKey else { return nil }
        return "\(key):lbl=\(config.showLabel)"
    }

    public static func visualKeyForCPU(style: MetricDisplayStyle, cpu: CPUSample?) -> String? {
        guard style != .sparkline else { return nil }
        let usage = cpu?.totalUsage ?? 0.0
        let valStr = cpu != nil ? String(format: "%.0f%%", usage) : "--%"

        switch style {
        case .gauge:
            let qUser = Int(round(min(max(cpu?.user ?? usage, 0.0), 100.0)))
            let qSys = Int(round(min(max(cpu?.system ?? 0.0, 0.0), 100.0 - Double(qUser))))
            return "cpu:gauge:\(qUser):\(qSys)"
        case .bar:
            let qUsage = Int(round(usage))
            if let cores = cpu?.perCore, cores.count >= 2 {
                let coreKey = cores.prefix(16).map { String(Int(round(min(max($0, 0.0), 100.0)))) }.joined(separator: ",")
                return "cpu:bar:\(qUsage):\(coreKey)"
            } else {
                let qUser = Int(round(min(max(cpu?.user ?? usage, 0.0), 100.0)))
                let qSys = Int(round(min(max(cpu?.system ?? 0.0, 0.0), 100.0)))
                return "cpu:bar:\(qUsage):\(qUser):\(qSys)"
            }
        case .text:
            return "cpu:text:\(valStr)"
        default:
            return "cpu:text:\(valStr)"
        }
    }

    public static func visualKeyForMemory(
        style: MetricDisplayStyle,
        memory: MemorySample?,
        ratio: Double,
        standard: Units.ByteUnitStandard
    ) -> String? {
        guard style != .sparkline else { return nil }
        let valStr = memory != nil ? String(format: "%.0f%%", ratio) : "--%"
        let qRatio = Int(round(ratio))
        let pressureStr = memory?.pressure.rawValue ?? "normal"

        switch style {
        case .gauge:
            return "mem:gauge:\(qRatio):\(pressureStr)"
        case .bar:
            if let mem = memory, mem.total > 0 {
                let total = Double(mem.total)
                let activeBytes = Double(mem.appMemory ?? mem.active ?? (mem.used - min(mem.used, mem.wired + mem.compressed)))
                let qActive = Int(round((activeBytes / total) * 100.0))
                let qWired = Int(round((Double(mem.wired) / total) * 100.0))
                let qComp = Int(round((Double(mem.compressed) / total) * 100.0))
                return "mem:bar:\(qRatio):\(qActive):\(qWired):\(qComp)"
            }
            return "mem:bar:\(qRatio)"
        case .symbol:
            return "mem:badge:\(pressureStr)"
        case .text:
            return "mem:text:\(valStr):\(pressureStr)"
        default:
            return "mem:text:\(valStr)"
        }
    }

    public static func visualKeyForGPU(style: MetricDisplayStyle, gpu: GPUSample?) -> String? {
        guard style != .sparkline else { return nil }
        let util = gpu?.utilization ?? 0.0
        let valStr = gpu?.utilization != nil ? String(format: "%.0f%%", util) : "--%"
        let qUtil = Int(round(util))
        let tempToken = gpu?.tempCelsius != nil ? "\(Int(round(gpu!.tempCelsius!)))" : "nil"

        switch style {
        case .gauge:
            return "gpu:gauge:\(qUtil):\(tempToken)"
        case .bar:
            return "gpu:bar:\(qUtil)"
        case .symbol:
            return "gpu:symbol:\(qUtil):\(tempToken)"
        case .text:
            return "gpu:text:\(valStr)"
        default:
            return "gpu:text:\(valStr)"
        }
    }

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
        let sensor: SensorReading?
        if let th = thermal {
            let matching = ThermalSensorClassifier.sensors(in: th, for: src)
            sensor = matching.max(by: { $0.celsius < $1.celsius })
        } else {
            sensor = nil
        }
        return (sensor, title, componentLabel)
    }

    public static func visualKeyForThermal(
        style: MetricDisplayStyle,
        source: MetricSource? = nil,
        thermal: ThermalSample?,
        unit: Units.TemperatureUnit
    ) -> String? {
        guard style != .sparkline else { return nil }
        let (sensor, title, _) = resolveThermalSensor(style: style, source: source, thermal: thermal)
        let tempC = sensor?.celsius ?? 0.0
        let formattedTemp = Units.formatTemperature(tempC, unit: unit, fractionDigits: 0)
        let valStr = sensor != nil ? formattedTemp : "--°"
        let qTemp = Int(round(tempC))
        let pressureStr = thermal?.pressure?.rawValue ?? "nominal"

        switch style {
        case .gauge:
            return "thermal:gauge:\(title):\(qTemp)"
        case .glyph:
            return "thermal:glyph:\(title):\(valStr):\(pressureStr)"
        case .bar:
            return "thermal:bar:\(title):\(qTemp)"
        case .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .batteryTemp, .text:
            return "thermal:text:\(title):\(valStr):\(pressureStr)"
        default:
            return "thermal:text:\(title):\(valStr):\(pressureStr)"
        }
    }

    public static func visualKeyForFan(style: MetricDisplayStyle, fan: FanSample?) -> String? {
        guard style != .sparkline else { return nil }
        let fans = fan?.fans ?? []
        let primaryFan = fans.max(by: { fanPercentage(for: $0) < fanPercentage(for: $1) }) ?? fans.first
        let rpm = primaryFan?.rpm ?? 0
        let pct: Double = primaryFan != nil ? fanPercentage(for: primaryFan!) : 0.0
        let qPct = Int(round(pct))
        let isFanless = fan?.isFanless == true || (fan != nil && fans.isEmpty)

        switch style {
        case .gauge:
            return "fan:gauge:\(qPct):\(rpm > 0 || pct > 0.0)"
        case .bar:
            if fans.count >= 2 {
                let qPct0 = Int(round(fanPercentage(for: fans[0])))
                let qPct1 = Int(round(fanPercentage(for: fans[1])))
                return "fan:bar:\(qPct0):\(qPct1)"
            }
            return "fan:bar:\(qPct)"
        case .text:
            let rpmStr = isFanless ? "fanless" : "\(rpm)"
            return "fan:text:\(rpmStr)"
        case .throughput:
            if fans.count >= 2 {
                return "fan:tp:\(fans[0].rpm):\(fans[1].rpm)"
            }
            return "fan:tp:\(qPct):\(rpm)"
        case .glyph:
            let rpmStr = isFanless ? "fanless" : "\(rpm)"
            return "fan:glyph:\(qPct):\(rpmStr)"
        case .symbol:
            return "fan:blades:\(qPct):\(rpm > 0 || pct > 0.0)"
        default:
            return "fan:glyph:\(qPct):\(rpm)"
        }
    }

    public static func visualKeyForNetwork(
        style: MetricDisplayStyle,
        throughputLayout: ThroughputLayout? = nil,
        network: NetworkSample?,
        unit: Units.NetworkUnit,
        standard: Units.ByteUnitStandard
    ) -> String? {
        guard style != .sparkline && style != .bar else { return nil }
        let inBytes = network?.totalBytesInPerSec ?? 0.0
        let outBytes = network?.totalBytesOutPerSec ?? 0.0

        switch style {
        case .symbol:
            return "net:arrows:\(inBytes > 1024.0):\(outBytes > 1024.0)"
        case .throughput:
            let layoutStr = throughputLayout?.rawValue ?? "stacked"
            let inFormatted = Units.formatCompactRate(inBytes, unit: unit, standard: standard)
            let outFormatted = Units.formatCompactRate(outBytes, unit: unit, standard: standard)
            return "net:tp:\(layoutStr):\(inFormatted):\(outFormatted)"
        default:
            return nil
        }
    }

    public static func visualKeyForDisk(
        style: MetricDisplayStyle,
        throughputLayout: ThroughputLayout? = nil,
        disk: DiskSample?,
        standard: Units.ByteUnitStandard
    ) -> String? {
        guard style != .sparkline else { return nil }
        let readBytes = disk?.io?.bytesReadPerSec ?? 0.0
        let writeBytes = disk?.io?.bytesWrittenPerSec ?? 0.0
        let primaryVol = disk?.volumes.first(where: { $0.mountPoint == "/" }) ?? disk?.volumes.first
        let volRatio: Double = (primaryVol != nil && primaryVol!.total > 0)
            ? (Double(primaryVol!.used) / Double(primaryVol!.total)) * 100.0
            : 0.0
        let qVol = Int(round(volRatio))

        switch style {
        case .symbol:
            return "disk:leds:\(readBytes > 10240.0):\(writeBytes > 10240.0)"
        case .gauge:
            return "disk:gauge:\(qVol)"
        case .text:
            let freeStr = primaryVol != nil ? formatCompactBytes(primaryVol!.free) : "--G"
            return "disk:text:\(freeStr)"
        case .throughput:
            let layoutStr = throughputLayout?.rawValue ?? "stacked"
            let readStr = Units.formatCompactRate(readBytes, unit: .bytesPerSecond, standard: standard)
            let writeStr = Units.formatCompactRate(writeBytes, unit: .bytesPerSecond, standard: standard)
            return "disk:tp:\(layoutStr):\(readStr):\(writeStr)"
        case .bar:
            return "disk:bar:\(qVol)"
        default:
            return nil
        }
    }

    public static func powerStackedTextLines(
        charge: Double?,
        state: BatteryState?,
        timeRemaining: TimeInterval?,
        watts: Double?
    ) -> (line1: String, line2: String) {
        let chg = charge ?? 0.0
        let bolt = (state == .charging) ? " ⚡" : ""
        let l1 = String(format: "%.0f%%%@", chg, bolt)

        let l2: String
        if state == .charging {
            l2 = "Charging"
        } else if let time = timeRemaining, time > 0 {
            let hours = Int(time) / 3600
            let mins = (Int(time) % 3600) / 60
            l2 = String(format: "%d:%02d", hours, mins)
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

    public static func visualKeyForPower(style: MetricDisplayStyle, power: PowerSample?) -> String? {
        guard style != .sparkline else { return nil }
        let charge = power?.charge ?? 0.0
        let variant = power?.variant ?? .unavailable
        let isCharging = variant == .charging
        let hasBattery = power?.hasBattery ?? true
        let qCharge = Int(round(charge))
        let chargeToken = power?.charge != nil ? "\(qCharge)" : "nil"
        let varStr = variant.rawValue

        switch style {
        case .symbol:
            return "pwr:symbol:\(chargeToken):\(varStr):\(hasBattery)"
        case .text:
            let lines = powerStackedTextLines(
                charge: power?.charge,
                state: power?.state,
                timeRemaining: power?.timeRemaining,
                watts: power?.powerDrawWatts
            )
            return "pwr:text:\(chargeToken):\(varStr):\(lines.line1):\(lines.line2)"
        case .throughput:
            let drawStr = power?.powerDrawWatts != nil ? String(format: "%.0fW", power!.powerDrawWatts!) : "--W"
            let adaptStr = power?.adapterWatts != nil ? String(format: "%.0fW", power!.adapterWatts!) : "AC"
            return "pwr:tp:\(drawStr):\(adaptStr)"
        case .gauge:
            return "pwr:gauge:\(chargeToken):\(isCharging):\(varStr)"
        case .bar:
            return "pwr:bar:\(chargeToken):\(isCharging):\(varStr)"
        default:
            return "pwr:symbol:\(chargeToken):\(varStr):\(hasBattery)"
        }
    }

    /// Primary entry point: renders image, title, tooltip, and accessibility label for a given menu bar item configuration.
    public static func render(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator,
        preferences: PreferencesStore,
        visualKey: String? = nil
    ) -> RenderResult {
        let key = visualKey ?? computeVisualKey(config: config, coordinator: coordinator, preferences: preferences)

        switch config.category {
        case .cpu:
            let cpu = coordinator.latestCPU?.value
            let history = (config.style == .sparkline) ? coordinator.cpuHistory.map { $0.value.totalUsage } : []
            let userHistory = (config.style == .sparkline) ? coordinator.cpuHistory.map { $0.value.user } : []
            let sysHistory = (config.style == .sparkline) ? coordinator.cpuHistory.map { $0.value.system } : []
            return renderCPU(config: config, cpu: cpu, history: history, userHistory: userHistory, systemHistory: sysHistory, visualKey: key)

        case .memory:
            let memory = coordinator.latestMemory?.value
            let ratio: Double = (memory != nil && memory!.total > 0)
                ? (Double(memory!.used) / Double(memory!.total)) * 100.0
                : 0.0
            let history = (config.style == .sparkline) ? coordinator.memoryHistory.map {
                $0.value.total > 0 ? (Double($0.value.used) / Double($0.value.total)) * 100.0 : 0.0
            } : []
            return renderMemory(config: config, memory: memory, ratio: ratio, history: history, standard: preferences.byteUnitStandard, visualKey: key)

        case .gpu:
            let gpu = coordinator.latestGPU?.value
            let history = (config.style == .sparkline) ? coordinator.gpuHistory.compactMap { $0.value.utilization } : []
            return renderGPU(config: config, gpu: gpu, history: history, visualKey: key)

        case .thermal:
            let thermal = coordinator.latestThermal?.value
            let source = config.source ?? .peak
            let history = (config.style == .sparkline) ? coordinator.thermalHistory.compactMap { sample in
                ThermalSensorClassifier.peakCelsius(in: sample.value, for: source)
            } : []
            return renderThermal(config: config, thermal: thermal, history: history, unit: preferences.temperatureUnit, visualKey: key)

        case .fan:
            let fan = coordinator.latestFan?.value
            let history = (config.style == .sparkline) ? coordinator.fanHistory.compactMap { sample in
                Double(sample.value.fans.map(\.rpm).max() ?? 0)
            } : []
            return renderFan(config: config, fan: fan, history: history, visualKey: key)

        case .network:
            let network = coordinator.latestNetwork?.value
            let isSparklineOrBar = (config.style == .sparkline || config.style == .bar)
            let inHistory = isSparklineOrBar ? coordinator.networkHistory.map { Double($0.value.totalBytesInPerSec) } : []
            let outHistory = isSparklineOrBar ? coordinator.networkHistory.map { Double($0.value.totalBytesOutPerSec) } : []
            return renderNetwork(
                config: config,
                network: network,
                inHistory: inHistory,
                outHistory: outHistory,
                unit: preferences.networkUnit,
                standard: preferences.byteUnitStandard,
                visualKey: key
            )

        case .disk:
            let disk = coordinator.latestDisk?.value
            let isSparkline = (config.style == .sparkline)
            let readHistory = isSparkline ? coordinator.diskHistory.compactMap { Double($0.value.io?.bytesReadPerSec ?? 0) } : []
            let writeHistory = isSparkline ? coordinator.diskHistory.compactMap { Double($0.value.io?.bytesWrittenPerSec ?? 0) } : []
            let history = isSparkline ? coordinator.diskHistory.compactMap {
                Double(($0.value.io?.bytesReadPerSec ?? 0) + ($0.value.io?.bytesWrittenPerSec ?? 0))
            } : []
            return renderDisk(
                config: config,
                disk: disk,
                history: history,
                readHistory: readHistory,
                writeHistory: writeHistory,
                standard: preferences.byteUnitStandard,
                visualKey: key
            )

        case .power:
            let power = coordinator.latestPower?.value
            let history = (config.style == .sparkline) ? coordinator.powerHistory.compactMap { $0.value.powerDrawWatts } : []
            return renderPower(config: config, power: power, history: history, visualKey: key)
        }
    }

    // MARK: - 1. CPU Rendering

    private static func renderCPU(
        config: MenuBarItemConfig,
        cpu: CPUSample?,
        history: [Double],
        userHistory: [Double] = [],
        systemHistory: [Double] = [],
        visualKey: String?
    ) -> RenderResult {
        let usage = cpu?.totalUsage ?? 0.0
        let tip = cpu != nil ? String(format: "CPU: %.1f%% (User: %.1f%%, Sys: %.1f%%)", cpu!.totalUsage, cpu!.user, cpu!.system) : "CPU: --%"
        let valStr = cpu != nil ? String(format: "%.0f%%", usage) : "--%"
        let a11y = cpu != nil ? String(format: "CPU load %.0f percent", usage) : "CPU load unavailable"
        let status = StatusThresholds.cpu(usagePercent: usage)

        switch config.style {
        case .gauge:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCPUDonutPie(user: cpu?.user ?? usage, system: cpu?.system ?? 0.0, label: config.showLabel ? "CPU" : nil)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .bar:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCPUBar(
                    perCore: cpu?.perCore,
                    user: cpu?.user,
                    system: cpu?.system,
                    eCoreCount: cpu?.efficiencyCoreCount ?? 0,
                    pCoreCount: cpu?.performanceCoreCount ?? 0
                )
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .sparkline:
            let img = drawCPUSparkline(
                history: history,
                userHistory: userHistory,
                systemHistory: systemHistory,
                label: config.showLabel ? "CPU" : nil
            )
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        case .text:
            let valColor: NSColor? = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : nil
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "CPU", value: valStr, fixedWidth: 32.0, valueColor: valColor)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        default:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "CPU", value: valStr, fixedWidth: 32.0)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)
        }
    }

    // MARK: - 2. Memory Rendering

    private static func renderMemory(
        config: MenuBarItemConfig,
        memory: MemorySample?,
        ratio: Double,
        history: [Double],
        standard: Units.ByteUnitStandard,
        visualKey: String?
    ) -> RenderResult {
        let tip: String
        let a11y: String
        if let mem = memory {
            let usedStr = Units.formatBytes(mem.used, standard: standard)
            let totalStr = Units.formatBytes(mem.total, standard: standard)
            tip = "MEM: \(usedStr) / \(totalStr) (\(String(format: "%.1f%%", ratio))) - Pressure: \(mem.pressure.displayName)"
            a11y = String(format: "Memory pressure %@, %@ used of %@", mem.pressure.displayName, usedStr, totalStr)
        } else {
            tip = "MEM: --%"
            a11y = "Memory telemetry unavailable"
        }

        let valStr = memory != nil ? String(format: "%.0f%%", ratio) : "--%"
        let status = StatusThresholds.memory(pressure: memory?.pressure ?? .normal, swapUsedBytes: memory?.swapUsed ?? 0)

        switch config.style {
        case .gauge, .symbol:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawMemoryDonutPie(sample: memory, ratio: ratio, label: config.showLabel ? "MEM" : nil)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .bar:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawMemoryStackedBar(sample: memory, ratio: ratio)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .sparkline:
            let img = drawMemorySparkline(history: history, pressure: memory?.pressure, label: config.showLabel ? "MEM" : nil)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        case .text:
            let valColor: NSColor? = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : nil
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "MEM", value: valStr, fixedWidth: 32.0, valueColor: valColor)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        default:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "MEM", value: valStr, fixedWidth: 32.0)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)
        }
    }

    // MARK: - 3. GPU Rendering

    private static func renderGPU(
        config: MenuBarItemConfig,
        gpu: GPUSample?,
        history: [Double],
        visualKey: String?
    ) -> RenderResult {
        let util = gpu?.utilization ?? 0.0
        let tip = gpu != nil ? String(format: "GPU: %.1f%%", util) : "GPU: --%"
        let valStr = gpu?.utilization != nil ? String(format: "%.0f%%", util) : "--%"
        let a11y = gpu?.utilization != nil ? String(format: "GPU utilization %.0f percent", util) : "GPU utilization unavailable"
        let status = StatusThresholds.gpu(utilizationPercent: util)

        switch config.style {
        case .gauge, .symbol:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawGPUGauge(percentage: util, tempCelsius: gpu?.tempCelsius, label: config.showLabel ? "GPU" : nil)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .bar:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawGPUBar(percentage: util)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .sparkline:
            let img = drawGPUSparkline(history: history, label: config.showLabel ? "GPU" : nil)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        case .text:
            let valColor: NSColor? = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : nil
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "GPU", value: valStr, fixedWidth: 32.0, valueColor: valColor)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        default:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "GPU", value: valStr, fixedWidth: 32.0)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)
        }
    }

    // MARK: - 4. Thermal Rendering

    public static func findThermalSensor(
        in thermal: ThermalSample?,
        matching keywords: [String]
    ) -> SensorReading? {
        guard let sensors = thermal?.sensors, !sensors.isEmpty else { return nil }
        let matches = sensors.filter { sensor in
            keywords.contains { kw in sensor.name.localizedCaseInsensitiveContains(kw) }
        }
        return matches.max(by: { $0.celsius < $1.celsius })
    }

    private static func renderThermal(
        config: MenuBarItemConfig,
        thermal: ThermalSample?,
        history: [Double],
        unit: Units.TemperatureUnit,
        visualKey: String?
    ) -> RenderResult {
        let (sensor, title, componentLabel) = resolveThermalSensor(style: config.style, source: config.source, thermal: thermal)
        let source = config.source ?? .peak

        let tempC = sensor?.celsius ?? 0.0
        let status = StatusThresholds.temperature(celsius: tempC, source: source, pressure: thermal?.pressure)
        let isSeriousPressure = (thermal?.pressure == .serious || thermal?.pressure == .critical)

        let formattedTemp = Units.formatTemperature(tempC, unit: unit, fractionDigits: 0)
        let formattedPreciseTemp = Units.formatTemperature(tempC, unit: unit, fractionDigits: 1)

        let tip = sensor != nil
            ? "\(componentLabel) Thermal: \(formattedPreciseTemp) (\(sensor!.name))"
            : "\(componentLabel) Thermal: --"
        let valStr = sensor != nil ? formattedTemp : "--°"
        let a11y = sensor != nil
            ? "\(componentLabel) temperature \(formattedTemp)"
            : "\(componentLabel) thermal unavailable"

        switch config.style {
        case .glyph:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawThermometerGlyph(celsius: sensor?.celsius, formattedTemp: valStr, status: status)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .sparkline:
            let img = drawThermalSparkline(history: history, label: config.showLabel ? title : nil)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        case .text, .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .batteryTemp:
            let valColor: NSColor? = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : nil
            let dotColor: NSColor? = isSeriousPressure ? CategoryPalette.statusNSColor(for: status) : nil
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: title, value: valStr, fixedWidth: 32.0, valueColor: valColor, statusDotColor: dotColor)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .gauge:
            let pct = min(max((tempC - 30.0) / (100.0 - 30.0) * 100.0, 0.0), 100.0)
            let img = cachedOrDraw(visualKey: visualKey) {
                drawThermalGauge(percentage: pct, celsius: tempC)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .bar:
            let pct = min(max((tempC - 30.0) / (100.0 - 30.0) * 100.0, 0.0), 100.0)
            let img = cachedOrDraw(visualKey: visualKey) {
                drawThermalBar(percentage: pct, celsius: tempC)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        default:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawThermometerGlyph(celsius: sensor?.celsius, formattedTemp: valStr, status: status)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)
        }
    }

    // MARK: - 5. Fan Rendering

    public static func fanPercentage(for fan: FanReading) -> Double {
        if let maxRPM = fan.maxRPM, let minRPM = fan.minRPM, maxRPM > minRPM {
            return Swift.min(Swift.max(Double(fan.rpm - minRPM) / Double(maxRPM - minRPM) * 100.0, 0.0), 100.0)
        } else if let maxRPM = fan.maxRPM, maxRPM > 0 {
            return Swift.min(Swift.max(Double(fan.rpm) / Double(maxRPM) * 100.0, 0.0), 100.0)
        } else {
            return Swift.min(Swift.max(Double(fan.rpm) / 6000.0 * 100.0, 0.0), 100.0)
        }
    }

    private static func renderFan(
        config: MenuBarItemConfig,
        fan: FanSample?,
        history: [Double],
        visualKey: String?
    ) -> RenderResult {
        let fans = fan?.fans ?? []
        let primaryFan = fans.max(by: { fanPercentage(for: $0) < fanPercentage(for: $1) }) ?? fans.first
        let rpm = primaryFan?.rpm ?? 0
        let isFanless = fan?.isFanless == true || (fan != nil && fans.isEmpty)
        let status = isFanless ? StatusLevel.fine : StatusThresholds.fan(
            rpm: Double(rpm),
            minRPM: Double(primaryFan?.minRPM ?? 0),
            maxRPM: Double(primaryFan?.maxRPM ?? 6000)
        )

        let tip: String
        let a11y: String
        if isFanless {
            tip = config.style == .text ? "Fans: Passive cooling" : "Fans: Fanless System"
            a11y = config.style == .text ? "Passive cooling" : "Fanless system"
        } else if let f = primaryFan {
            let desc = fans.count > 1 ? fans.map { "\($0.name): \($0.rpm) RPM" }.joined(separator: ", ") : "\(f.name): \(rpm) RPM"
            tip = "Fans: \(desc)"
            a11y = "Fans running at \(rpm) RPM"
        } else {
            tip = "Fans: -- RPM"
            a11y = "Fans unavailable"
        }

        let pct: Double = primaryFan != nil ? fanPercentage(for: primaryFan!) : 0.0

        switch config.style {
        case .text:
            let valStr = isFanless ? "—" : (primaryFan != nil ? "\(rpm)" : "--")
            let valColor: NSColor? = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : nil
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "FAN", value: valStr, fixedWidth: 32.0, valueColor: valColor)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .throughput:
            let img = cachedOrDraw(visualKey: visualKey) {
                if isFanless {
                    return drawCategoryStackedText(title: "FAN", value: "—", fixedWidth: 32.0)
                } else if fans.count >= 2 {
                    return drawStackedTwoLineText(
                        prefix1: "L",
                        value1: "\(fans[0].rpm)",
                        prefix2: "R",
                        value2: "\(fans[1].rpm)",
                        minWidth: 36.0,
                        color1: CategoryPalette.nsColor(for: .fan),
                        color2: CategoryPalette.nsColor(for: .disk),
                        prefixColor1: CategoryPalette.nsColor(for: .fan),
                        prefixColor2: CategoryPalette.nsColor(for: .disk)
                    )
                } else {
                    return drawCategoryStackedText(title: "FAN", value: primaryFan != nil ? "\(primaryFan!.rpm)" : "--", fixedWidth: 32.0)
                }
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .glyph:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawFanGlyph(rpm: primaryFan?.rpm, isFanless: isFanless, status: status)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .bar:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawFanBar(fan: fan, primaryPct: pct)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .sparkline:
            let img = drawFanSparkline(history: history, label: config.showLabel ? "FAN" : nil)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        case .gauge:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawFanTachometer(percentage: pct, rpm: primaryFan?.rpm)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .symbol:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawFanBlades(percentage: pct, rpm: primaryFan?.rpm)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        default:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawFanGlyph(rpm: primaryFan?.rpm, isFanless: isFanless, status: status)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)
        }
    }

    // MARK: - 6. Network Rendering

    private static func renderNetwork(
        config: MenuBarItemConfig,
        network: NetworkSample?,
        inHistory: [Double],
        outHistory: [Double],
        unit: Units.NetworkUnit,
        standard: Units.ByteUnitStandard,
        visualKey: String?
    ) -> RenderResult {
        let inBytes = network?.totalBytesInPerSec ?? 0.0
        let outBytes = network?.totalBytesOutPerSec ?? 0.0
        let inFormatted = Units.formatNetworkRate(inBytes, unit: unit, standard: standard, fractionDigits: 1)
        let outFormatted = Units.formatNetworkRate(outBytes, unit: unit, standard: standard, fractionDigits: 1)
        let tip = "Network: ↓ \(inFormatted)  ↑ \(outFormatted)"
        let a11y = "Network download \(inFormatted), upload \(outFormatted)"

        switch config.style {
        case .throughput:
            let inCompact = Units.formatCompactRate(inBytes, unit: unit, standard: standard)
            let outCompact = Units.formatCompactRate(outBytes, unit: unit, standard: standard)
            let img = cachedOrDraw(visualKey: visualKey) {
                if config.throughputLayout == .singleLine {
                    return drawSingleLineThroughput(
                        prefix1: "↓",
                        value1: inCompact,
                        prefix2: "↑",
                        value2: outCompact,
                        fixedWidth: 82.0,
                        color1: CategoryPalette.nsColor(for: .network),
                        color2: CategoryPalette.nsColor(for: .power)
                    )
                } else {
                    return drawNetworkStackedThroughput(inBytes: inBytes, outBytes: outBytes, unit: unit, standard: standard)
                }
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .sparkline:
            let img = drawNetworkSplitDuplexGraph(inHistory: inHistory, outHistory: outHistory, label: config.showLabel ? "NET" : nil)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        case .symbol:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawNetworkActivityArrows(inBytes: inBytes, outBytes: outBytes)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .bar:
            let img = drawNetworkBar(inBytes: inBytes, outBytes: outBytes, inHistory: inHistory, outHistory: outHistory)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        default:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawNetworkActivityArrows(inBytes: inBytes, outBytes: outBytes)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)
        }
    }

    // MARK: - 7. Disk Rendering

    private static func renderDisk(
        config: MenuBarItemConfig,
        disk: DiskSample?,
        history: [Double],
        readHistory: [Double] = [],
        writeHistory: [Double] = [],
        standard: Units.ByteUnitStandard,
        visualKey: String?
    ) -> RenderResult {
        let readBytes = disk?.io?.bytesReadPerSec ?? 0.0
        let writeBytes = disk?.io?.bytesWrittenPerSec ?? 0.0
        let rStr = Units.formatDiskRate(readBytes, standard: standard, fractionDigits: 1)
        let wStr = Units.formatDiskRate(writeBytes, standard: standard, fractionDigits: 1)
        let tip = "Disk I/O: Read \(rStr), Write \(wStr)"
        let a11y = "Disk read \(rStr), write \(wStr)"

        let primaryVol = disk?.volumes.first(where: { $0.mountPoint == "/" }) ?? disk?.volumes.first
        let volRatio: Double = (primaryVol != nil && primaryVol!.total > 0)
            ? (Double(primaryVol!.used) / Double(primaryVol!.total)) * 100.0
            : 0.0
        let status = StatusThresholds.disk(usedPercent: volRatio)

        switch config.style {
        case .throughput:
            let rCompact = Units.formatCompactRate(readBytes, unit: .bytesPerSecond, standard: standard)
            let wCompact = Units.formatCompactRate(writeBytes, unit: .bytesPerSecond, standard: standard)
            let img = cachedOrDraw(visualKey: visualKey) {
                if config.throughputLayout == .singleLine {
                    return drawSingleLineThroughput(
                        prefix1: "R",
                        value1: rCompact,
                        prefix2: "W",
                        value2: wCompact,
                        fixedWidth: 82.0,
                        color1: CategoryPalette.nsColor(for: .disk),
                        color2: NSColor.systemOrange
                    )
                } else {
                    return drawDiskStackedThroughput(readBytes: readBytes, writeBytes: writeBytes, standard: standard)
                }
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .symbol:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawDiskActivityLeds(readBytes: readBytes, writeBytes: writeBytes)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .gauge:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawDiskGauge(percentage: volRatio, label: config.showLabel ? "SSD" : nil)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: String(format: "Storage %.0f percent full", volRatio), visualKey: visualKey)

        case .text:
            let freeStr = primaryVol != nil ? formatCompactBytes(primaryVol!.free) : "--G"
            let valColor: NSColor? = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : nil
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "SSD", value: freeStr, fixedWidth: 32.0, valueColor: valColor)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: String(format: "Storage %.0f percent full", volRatio), visualKey: visualKey)

        case .sparkline:
            let img = drawDiskSplitDuplexGraph(readHistory: readHistory, writeHistory: writeHistory, label: config.showLabel ? "SSD" : nil)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        case .bar:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawDiskBar(percentage: volRatio)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: String(format: "Storage %.0f percent full", volRatio), visualKey: visualKey)

        default:
            let freeStr = primaryVol != nil ? formatCompactBytes(primaryVol!.free) : "--G"
            let img = cachedOrDraw(visualKey: visualKey) {
                drawCategoryStackedText(title: "SSD", value: freeStr, fixedWidth: 32.0)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)
        }
    }

    // MARK: - 8. Power Rendering

    private static func renderPower(
        config: MenuBarItemConfig,
        power: PowerSample?,
        history: [Double],
        visualKey: String?
    ) -> RenderResult {
        let charge = power?.charge ?? 0.0
        let variant = power?.variant ?? .unavailable
        let tip: String
        let a11y: String
        if let pwr = power {
            if pwr.hasBattery {
                let stateStr: String
                let a11yState: String
                switch variant {
                case .charging:
                    stateStr = " (Charging)"
                    a11yState = ", charging"
                case .onHold:
                    stateStr = " (Charging On Hold - Optimized)"
                    a11yState = ", charging on hold"
                case .powerDeficit:
                    if let draw = pwr.powerDrawWatts, let adapter = pwr.adapterWatts {
                        stateStr = String(format: " (Power Deficit: %.0fW > %.0fW)", draw, adapter)
                    } else {
                        stateStr = " (Power Deficit)"
                    }
                    a11yState = ", power deficit"
                case .charged:
                    stateStr = " (Fully Charged - Power Adapter)"
                    a11yState = ", fully charged"
                case .lowBattery:
                    stateStr = " (Low Battery)"
                    a11yState = ", low battery"
                case .discharging:
                    stateStr = " (On Battery)"
                    a11yState = ", on battery"
                case .acDesktop:
                    stateStr = " (AC Power)"
                    a11yState = ", on AC power"
                case .unavailable:
                    stateStr = ""
                    a11yState = ""
                }
                tip = String(format: "Battery: %.0f%%%@", charge, stateStr)
                a11y = String(format: "Battery %.0f percent%@", charge, a11yState)
            } else {
                let wattsStr = power?.powerDrawWatts != nil ? String(format: " (%.1f W)", power!.powerDrawWatts!) : ""
                tip = "Power: Connected to AC\(wattsStr)"
                a11y = "Connected to AC power"
            }
        } else {
            tip = "Battery: --%"
            a11y = "Power unavailable"
        }

        let hasBattery = power?.hasBattery ?? true

        switch config.style {
        case .symbol, .gauge, .bar:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawBatteryInstrument(charge: power?.charge, state: power?.state, hasBattery: hasBattery, variant: variant)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .text:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawPowerStackedText(charge: power?.charge, state: power?.state, timeRemaining: power?.timeRemaining, watts: power?.powerDrawWatts)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .throughput:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawPowerBudgetText(drawWatts: power?.powerDrawWatts, adapterWatts: power?.adapterWatts)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)

        case .sparkline:
            let img = drawPowerSparkline(history: history, label: config.showLabel ? "PWR" : nil)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)

        default:
            let img = cachedOrDraw(visualKey: visualKey) {
                drawBatteryInstrument(charge: power?.charge, state: power?.state, hasBattery: hasBattery, variant: variant)
            }
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y, visualKey: visualKey)
        }
    }

    // MARK: - Core iStat Menus Instrument Drawing Primitives

    /// Formats raw byte counts into compact single-letter unit representations (e.g. "412G", "1.2T").
    public static func formatCompactBytes(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000.0
        if gigabytes >= 1000.0 {
            let terabytes = gigabytes / 1000.0
            return String(format: "%.1fT", terabytes)
        } else if gigabytes >= 100.0 {
            return String(format: "%.0fG", gigabytes)
        } else if gigabytes >= 10.0 {
            return String(format: "%.0fG", gigabytes)
        } else if gigabytes >= 1.0 {
            return String(format: "%.1fG", gigabytes)
        } else {
            let megabytes = Double(bytes) / 1_000_000.0
            return String(format: "%.0fM", megabytes)
        }
    }

    /// Helper that formats numeric values with a clean suffix symbol (%, °, k, etc.)
    /// matching the modern elegant typography preferred by the user.
    private static func formatCompactValueAttributedString(
        value: String,
        color: NSColor
    ) -> NSAttributedString {
        let attrString = NSMutableAttributedString()
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        let digits = String(trimmed.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" }))
        let suffix = String(trimmed.dropFirst(digits.count))

        let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
        let suffixFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)

        let digitAttrs: [NSAttributedString.Key: Any] = [
            .font: digitFont,
            .foregroundColor: color
        ]
        attrString.append(NSAttributedString(string: digits.isEmpty ? trimmed : digits, attributes: digitAttrs))

        if !digits.isEmpty && !suffix.isEmpty {
            let offset: CGFloat = suffix.contains("°") ? 1.5 : 0.5
            let suffixAttrs: [NSAttributedString.Key: Any] = [
                .font: suffixFont,
                .foregroundColor: color,
                .baselineOffset: offset
            ]
            attrString.append(NSAttributedString(string: suffix, attributes: suffixAttrs))
        }

        return attrString
    }

    /// Draws clean, elegant 2-line stacked high-density typography with generous vertical spacing
    /// and strict invariant fixed-width preventing menu bar horizontal jitter.
    public static func drawCategoryStackedText(
        title: String,
        value: String,
        fixedWidth: CGFloat = 32.0,
        titleColor: NSColor? = nil,
        valueColor: NSColor? = nil,
        statusDotColor: NSColor? = nil
    ) -> NSImage {
        let isTemplate = (titleColor == nil && valueColor == nil && statusDotColor == nil)
        let dotHash = statusDotColor?.hashValue ?? 0
        let cacheKey = "stacked:\(title):\(value):\(fixedWidth):\(isTemplate ? 0 : (titleColor?.hashValue ?? 0)):\(isTemplate ? 0 : (valueColor?.hashValue ?? 0)):\(dotHash)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let tColor = titleColor ?? NSColor.labelColor.withAlphaComponent(0.90)
        let vColor = valueColor ?? NSColor.labelColor

        let titleFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)
        let tAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: tColor,
            .kern: 0.10
        ]
        let titleAttrString = NSAttributedString(string: title.uppercased(), attributes: tAttrs)
        let valueAttrString = formatCompactValueAttributedString(value: value, color: vColor)

        let tSize = titleAttrString.size()
        let vSize = valueAttrString.size()

        let canvasWidth = max(fixedWidth, max(tSize.width, vSize.width) + 2.0)
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let tX = floor(max(0.0, (bounds.width - tSize.width) / 2.0))
            let vX = floor(max(0.0, (bounds.width - vSize.width) / 2.0))

            let vY: CGFloat = -1.8
            let tY: CGFloat = 10.5

            titleAttrString.draw(at: NSPoint(x: tX, y: tY))
            valueAttrString.draw(at: NSPoint(x: vX, y: vY))

            if let dotColor = statusDotColor {
                let dotRect = NSRect(x: bounds.maxX - 4.5, y: bounds.maxY - 4.5, width: 3.0, height: 3.0)
                let dot = NSBezierPath(ovalIn: dotRect)
                dotColor.setFill()
                dot.fill()
            }

            return true
        }
        image.isTemplate = isTemplate
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Draws authentic iStat Menus 3-Segment Pie / Tri-Blade Instrument (as seen in official iStat Menus).
    public static func drawTriSegmentPie(
        ratio: Double? = nil,
        activeRatio: Double? = nil,
        wiredRatio: Double? = nil,
        compressedRatio: Double? = nil
    ) -> NSImage {
        let cacheKey = "triSegmentPie" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let outerRadius: CGFloat = 8.0
            let innerRadius: CGFloat = 2.2

            let segmentSpan: CGFloat = 108.0
            let gap: CGFloat = 12.0

            let segments: [(start: CGFloat, color: NSColor)] = [
                (90.0 - gap / 2.0, NSColor.labelColor),
                (330.0 - gap / 2.0, NSColor.labelColor),
                (210.0 - gap / 2.0, NSColor.labelColor)
            ]

            for (startAngle, color) in segments {
                let path = NSBezierPath()
                let endAngle = startAngle - segmentSpan
                path.appendArc(withCenter: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                path.appendArc(withCenter: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: false)
                path.close()

                color.setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Draws single-line tabular monospaced text right-aligned within a fixed-width template canvas.
    public static func drawSingleLineText(
        text: String,
        fixedWidth: CGFloat = 60.0
    ) -> NSImage {
        let cacheKey = "singleLine:\(text):\(fixedWidth)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let str = text as NSString
        let textSize = str.size(withAttributes: attrs)
        let canvasWidth = max(textSize.width + 4.0, fixedWidth)
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let point = NSPoint(x: bounds.maxX - textSize.width - 2.0, y: (bounds.height - textSize.height) / 2.0)
            str.draw(at: point, withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Helper that extracts a leading icon/prefix (e.g. "↑", "↓", "R", "W", "▲", "▼") from a stacked text line.
    private static func splitPrefixAndValue(_ text: String) -> (prefix: String, value: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ("", "") }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let first = String(parts[0])
            let rest = String(parts[1])
            if first.count <= 4 && !first.allSatisfy({ $0.isNumber }) {
                return (first, rest)
            }
        }
        return ("", trimmed)
    }

    /// Draws authentic iStat Menus 2-line stacked typography with left-aligned prefix icons/labels
    /// within a fixed invariant width canvas that prevents menu bar horizontal jitter.
    public static func drawStackedTwoLineText(
        prefix1: String,
        value1: String,
        prefix2: String,
        value2: String,
        minWidth: CGFloat = 60.0,
        color1: NSColor? = nil,
        color2: NSColor? = nil,
        prefixColor1: NSColor? = nil,
        prefixColor2: NSColor? = nil
    ) -> NSImage {
        let pFont = NSFont.systemFont(ofSize: 8.5, weight: .bold)
        let vFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)

        let pAttrs1: [NSAttributedString.Key: Any] = [
            .font: pFont,
            .foregroundColor: prefixColor1 ?? color1 ?? NSColor.labelColor
        ]
        let pAttrs2: [NSAttributedString.Key: Any] = [
            .font: pFont,
            .foregroundColor: prefixColor2 ?? color2 ?? NSColor.labelColor
        ]
        let vAttrs1: [NSAttributedString.Key: Any] = [
            .font: vFont,
            .foregroundColor: color1 ?? NSColor.labelColor
        ]
        let vAttrs2: [NSAttributedString.Key: Any] = [
            .font: vFont,
            .foregroundColor: color2 ?? NSColor.labelColor
        ]

        let sp1 = (prefix1 as NSString).size(withAttributes: pAttrs1)
        let sp2 = (prefix2 as NSString).size(withAttributes: pAttrs2)
        let sv1 = (value1 as NSString).size(withAttributes: vAttrs1)
        let sv2 = (value2 as NSString).size(withAttributes: vAttrs2)

        let hasPrefix = !prefix1.isEmpty || !prefix2.isEmpty
        let maxPrefixWidth = hasPrefix ? max(sp1.width, sp2.width) : 0.0
        let maxValWidth = max(sv1.width, sv2.width)

        let leftPadding: CGFloat = 2.0
        let rightPadding: CGFloat = 2.0
        let prefixGap: CGFloat = hasPrefix ? 2.0 : 0.0

        let neededWidth = leftPadding + maxPrefixWidth + prefixGap + maxValWidth + rightPadding
        let canvasWidth = max(minWidth, ceil(neededWidth))
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let y1: CGFloat = 11.5
            let y2: CGFloat = 2.0

            if hasPrefix {
                if !prefix1.isEmpty {
                    (prefix1 as NSString).draw(at: NSPoint(x: leftPadding, y: y1), withAttributes: pAttrs1)
                }
                if !prefix2.isEmpty {
                    (prefix2 as NSString).draw(at: NSPoint(x: leftPadding, y: y2), withAttributes: pAttrs2)
                }

                let vX1 = bounds.maxX - rightPadding - sv1.width
                let vX2 = bounds.maxX - rightPadding - sv2.width
                (value1 as NSString).draw(at: NSPoint(x: max(leftPadding + maxPrefixWidth + 1.0, vX1), y: y1), withAttributes: vAttrs1)
                (value2 as NSString).draw(at: NSPoint(x: max(leftPadding + maxPrefixWidth + 1.0, vX2), y: y2), withAttributes: vAttrs2)
            } else {
                let vX1 = floor((bounds.width - sv1.width) / 2.0)
                let vX2 = floor((bounds.width - sv2.width) / 2.0)
                (value1 as NSString).draw(at: NSPoint(x: max(leftPadding, vX1), y: y1), withAttributes: vAttrs1)
                (value2 as NSString).draw(at: NSPoint(x: max(leftPadding, vX2), y: y2), withAttributes: vAttrs2)
            }

            return true
        }
        image.isTemplate = (color1 == nil && color2 == nil && prefixColor1 == nil && prefixColor2 == nil)
        return image
    }

    /// Draws authentic iStat Menus 2-line stacked typography with left-aligned icons and right-aligned metrics.
    public static func drawStackedText(
        line1: String,
        line2: String,
        minWidth: CGFloat = 60.0,
        color1: NSColor? = nil,
        color2: NSColor? = nil
    ) -> NSImage {
        let (p1, v1) = splitPrefixAndValue(line1)
        let (p2, v2) = splitPrefixAndValue(line2)
        return drawStackedTwoLineText(
            prefix1: p1,
            value1: v1,
            prefix2: p2,
            value2: v2,
            minWidth: minWidth,
            color1: color1,
            color2: color2
        )
    }

    /// Draws single-line throughput with fixed-width tabular slots preventing menu bar jitter.
    public static func drawSingleLineThroughput(
        prefix1: String,
        value1: String,
        prefix2: String,
        value2: String,
        fixedWidth: CGFloat = 82.0,
        color1: NSColor? = nil,
        color2: NSColor? = nil,
        prefixColor1: NSColor? = nil,
        prefixColor2: NSColor? = nil
    ) -> NSImage {
        let cacheKey = "singleLineTp:\(prefix1):\(value1):\(prefix2):\(value2):\(fixedWidth)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let pFont = NSFont.systemFont(ofSize: 9.0, weight: .bold)
        let vFont = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)

        let pAttrs1: [NSAttributedString.Key: Any] = [
            .font: pFont,
            .foregroundColor: prefixColor1 ?? color1 ?? NSColor.labelColor
        ]
        let pAttrs2: [NSAttributedString.Key: Any] = [
            .font: pFont,
            .foregroundColor: prefixColor2 ?? color2 ?? NSColor.labelColor
        ]
        let vAttrs1: [NSAttributedString.Key: Any] = [
            .font: vFont,
            .foregroundColor: color1 ?? NSColor.labelColor
        ]
        let vAttrs2: [NSAttributedString.Key: Any] = [
            .font: vFont,
            .foregroundColor: color2 ?? NSColor.labelColor
        ]

        let sp1 = (prefix1 as NSString).size(withAttributes: pAttrs1)
        let sp2 = (prefix2 as NSString).size(withAttributes: pAttrs2)
        let sv1 = (value1 as NSString).size(withAttributes: vAttrs1)
        let sv2 = (value2 as NSString).size(withAttributes: vAttrs2)

        let size = NSSize(width: fixedWidth, height: 22)
        let halfWidth = (fixedWidth - 6.0) / 2.0

        let image = NSImage(size: size, flipped: false) { bounds in
            let y = floor((bounds.height - max(sp1.height, sv1.height)) / 2.0)

            // Slot 1: [2.0 ... 2.0 + halfWidth]
            let slot1X: CGFloat = 2.0
            (prefix1 as NSString).draw(at: NSPoint(x: slot1X, y: y), withAttributes: pAttrs1)
            let v1X = slot1X + halfWidth - sv1.width
            (value1 as NSString).draw(at: NSPoint(x: max(slot1X + sp1.width + 1.0, v1X), y: y), withAttributes: vAttrs1)

            // Slot 2: [slot2X ... bounds.maxX - 2.0]
            let slot2X: CGFloat = slot1X + halfWidth + 2.0
            (prefix2 as NSString).draw(at: NSPoint(x: slot2X, y: y), withAttributes: pAttrs2)
            let v2X = bounds.maxX - 2.0 - sv2.width
            (value2 as NSString).draw(at: NSPoint(x: max(slot2X + sp2.width + 1.0, v2X), y: y), withAttributes: vAttrs2)

            return true
        }
        image.isTemplate = (color1 == nil && color2 == nil && prefixColor1 == nil && prefixColor2 == nil)
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Draws the signature iStat Menus 2-line stacked network bandwidth throughput (`↑ Out` over `↓ In`).
    public static func drawNetworkStackedThroughput(
        inBytes: Double,
        outBytes: Double,
        unit: Units.NetworkUnit,
        standard: Units.ByteUnitStandard
    ) -> NSImage {
        let outStr = Units.formatCompactRate(outBytes, unit: unit, standard: standard)
        let inStr = Units.formatCompactRate(inBytes, unit: unit, standard: standard)
        return drawStackedTwoLineText(
            prefix1: "↑",
            value1: outStr,
            prefix2: "↓",
            value2: inStr,
            minWidth: 60.0
        )
    }

    /// Draws the signature iStat Menus 2-line stacked disk I/O throughput (`R read` over `W write`).
    public static func drawDiskStackedThroughput(
        readBytes: Double,
        writeBytes: Double,
        standard: Units.ByteUnitStandard
    ) -> NSImage {
        let readStr = Units.formatCompactRate(readBytes, unit: .bytesPerSecond, standard: standard)
        let writeStr = Units.formatCompactRate(writeBytes, unit: .bytesPerSecond, standard: standard)
        return drawStackedTwoLineText(
            prefix1: "R",
            value1: readStr,
            prefix2: "W",
            value2: writeStr,
            minWidth: 60.0
        )
    }

    /// Draws mirrored duplex network history graph (Inbound indigo above midline, Outbound pink below midline).
    public static func drawNetworkSplitDuplexGraph(
        inHistory: [Double],
        outHistory: [Double],
        label: String? = nil
    ) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 50.0 : 36.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 16.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let graphBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 3.0, width: 9.5, height: 16.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                graphBounds = NSRect(x: 13.5, y: 3.0, width: 35.0, height: 16.0)
            } else {
                graphBounds = bounds
            }

            let midY = graphBounds.midY

            // Baseline center divider line
            let centerLine = NSBezierPath()
            centerLine.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))
            centerLine.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
            centerLine.lineWidth = 0.6
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            centerLine.stroke()

            let inMax = max(inHistory.max() ?? 1024.0, 1024.0)
            let outMax = max(outHistory.max() ?? 1024.0, 1024.0)

            let count = max(max(inHistory.count, outHistory.count), 2)
            let stepX = (graphBounds.width - 2.0) / CGFloat(count - 1)

            // 1. Inbound (Download) - Waves scrolling above midline (System Indigo)
            if inHistory.count >= 2 {
                let inFill = NSBezierPath()
                let inLine = NSBezierPath()
                inFill.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))

                for (idx, val) in inHistory.enumerated() {
                    let clamped = min(max(val, 0.0), inMax)
                    let h = CGFloat(clamped / inMax) * (graphBounds.height / 2.0 - 1.0)
                    let x = graphBounds.minX + 1.0 + CGFloat(idx) * stepX
                    let y = midY + h
                    let pt = NSPoint(x: x, y: y)

                    if idx == 0 {
                        inLine.move(to: pt)
                        inFill.line(to: pt)
                    } else {
                        inLine.line(to: pt)
                        inFill.line(to: pt)
                    }
                }
                inFill.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
                inFill.close()
                CategoryPalette.nsColor(for: .network).withAlphaComponent(0.28).setFill()
                inFill.fill()

                inLine.lineWidth = 1.2
                inLine.lineJoinStyle = .round
                CategoryPalette.nsColor(for: .network).setStroke()
                inLine.stroke()
            }

            // 2. Outbound (Upload) - Waves scrolling below midline (System Pink)
            if outHistory.count >= 2 {
                let outFill = NSBezierPath()
                let outLine = NSBezierPath()
                outFill.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))

                for (idx, val) in outHistory.enumerated() {
                    let clamped = min(max(val, 0.0), outMax)
                    let h = CGFloat(clamped / outMax) * (graphBounds.height / 2.0 - 1.0)
                    let x = graphBounds.minX + 1.0 + CGFloat(idx) * stepX
                    let y = midY - h
                    let pt = NSPoint(x: x, y: y)

                    if idx == 0 {
                        outLine.move(to: pt)
                        outFill.line(to: pt)
                    } else {
                        outLine.line(to: pt)
                        outFill.line(to: pt)
                    }
                }
                outFill.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
                outFill.close()
                CategoryPalette.nsColor(for: .power).withAlphaComponent(0.25).setFill()
                outFill.fill()

                outLine.lineWidth = 1.2
                outLine.lineJoinStyle = .round
                CategoryPalette.nsColor(for: .power).setStroke()
                outLine.stroke()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws mirrored duplex disk I/O history graph (Read teal above midline, Write orange below midline).
    public static func drawDiskSplitDuplexGraph(
        readHistory: [Double],
        writeHistory: [Double],
        label: String? = nil
    ) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 50.0 : 36.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 16.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let graphBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 3.0, width: 9.5, height: 16.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                graphBounds = NSRect(x: 13.5, y: 3.0, width: 35.0, height: 16.0)
            } else {
                graphBounds = bounds
            }

            let midY = graphBounds.midY

            let centerLine = NSBezierPath()
            centerLine.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))
            centerLine.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
            centerLine.lineWidth = 0.6
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            centerLine.stroke()

            let rMax = computeDecayMax(values: readHistory, floor: 1024.0 * 1024.0)
            let wMax = computeDecayMax(values: writeHistory, floor: 1024.0 * 1024.0)

            let count = max(max(readHistory.count, writeHistory.count), 2)
            let stepX = (graphBounds.width - 2.0) / CGFloat(count - 1)

            // Read - Teal above midline
            if readHistory.count >= 2 {
                let rFill = NSBezierPath()
                let rLine = NSBezierPath()
                rFill.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))

                for (idx, val) in readHistory.enumerated() {
                    let clamped = min(max(val, 0.0), rMax)
                    let h = CGFloat(clamped / rMax) * (graphBounds.height / 2.0 - 1.0)
                    let x = graphBounds.minX + 1.0 + CGFloat(idx) * stepX
                    let y = midY + h
                    let pt = NSPoint(x: x, y: y)

                    if idx == 0 {
                        rLine.move(to: pt)
                        rFill.line(to: pt)
                    } else {
                        rLine.line(to: pt)
                        rFill.line(to: pt)
                    }
                }
                rFill.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
                rFill.close()
                CategoryPalette.nsColor(for: .disk).withAlphaComponent(0.28).setFill()
                rFill.fill()

                rLine.lineWidth = 1.2
                rLine.lineJoinStyle = .round
                CategoryPalette.nsColor(for: .disk).setStroke()
                rLine.stroke()
            }

            // Write - Orange below midline
            if writeHistory.count >= 2 {
                let wFill = NSBezierPath()
                let wLine = NSBezierPath()
                wFill.move(to: NSPoint(x: graphBounds.minX + 1.0, y: midY))

                for (idx, val) in writeHistory.enumerated() {
                    let clamped = min(max(val, 0.0), wMax)
                    let h = CGFloat(clamped / wMax) * (graphBounds.height / 2.0 - 1.0)
                    let x = graphBounds.minX + 1.0 + CGFloat(idx) * stepX
                    let y = midY - h
                    let pt = NSPoint(x: x, y: y)

                    if idx == 0 {
                        wLine.move(to: pt)
                        wFill.line(to: pt)
                    } else {
                        wLine.line(to: pt)
                        wFill.line(to: pt)
                    }
                }
                wFill.line(to: NSPoint(x: graphBounds.maxX - 1.0, y: midY))
                wFill.close()
                NSColor.systemOrange.withAlphaComponent(0.25).setFill()
                wFill.fill()

                wLine.lineWidth = 1.2
                wLine.lineJoinStyle = .round
                NSColor.systemOrange.setStroke()
                wLine.stroke()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Capsule Bar & Vertical Label Drawing Primitives

    /// Draws category acronym letters (e.g. "SSD", "CPU", "RAM") stacked vertically one above the other.
    public static func drawVerticalCategoryText(
        _ text: String,
        in rect: NSRect,
        color: NSColor = .labelColor
    ) {
        let chars = Array(text.uppercased())
        guard !chars.isEmpty else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let count = CGFloat(chars.count)
        let fontSize: CGFloat
        if count <= 1 {
            fontSize = 9.5
        } else if count == 2 {
            fontSize = 8.4
        } else if count == 3 {
            fontSize = 7.4
        } else {
            fontSize = 5.8
        }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .heavy)
        let ctFont = font as CTFont

        struct GlyphInfo {
            let path: CGPath
            let bounds: CGRect
            let advance: CGSize
        }

        var glyphInfos: [GlyphInfo] = []
        for char in chars {
            var unichars = [UniChar](String(char).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
            if CTFontGetGlyphsForCharacters(ctFont, &unichars, &glyphs, unichars.count) {
                let glyph = glyphs[0]
                var advance = CGSize.zero
                CTFontGetAdvancesForGlyphs(ctFont, .horizontal, [glyph], &advance, 1)

                if let rawPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                    let bounds = rawPath.boundingBoxOfPath
                    glyphInfos.append(GlyphInfo(path: rawPath, bounds: bounds, advance: advance))
                }
            }
        }

        guard glyphInfos.count == chars.count else { return }

        let totalInkHeight = glyphInfos.reduce(0.0) { $0 + $1.bounds.height }
        let topPadding: CGFloat = count == 1 ? (rect.height - totalInkHeight) / 2.0 : 0.6
        let bottomPadding: CGFloat = count == 1 ? topPadding : 0.6
        let availableHeight = max(rect.height - topPadding - bottomPadding, 0.0)
        let totalGaps = count > 1 ? max(availableHeight - totalInkHeight, 0.0) : 0.0
        let gap = count > 1 ? (totalGaps / (count - 1.0)) : 0.0

        var currentTopY = rect.maxY - topPadding

        context.saveGState()
        context.setFillColor(color.cgColor)

        for info in glyphInfos {
            let inkHeight = info.bounds.height
            let targetCenterY = currentTopY - (inkHeight / 2.0)
            let dx = rect.midX - (info.advance.width / 2.0)
            let dy = targetCenterY - info.bounds.midY

            var transform = CGAffineTransform(translationX: dx, y: dy)
            if let transformedPath = info.path.copy(using: &transform) {
                context.addPath(transformedPath)
                context.fillPath()
            }

            currentTopY -= (inkHeight + gap)
        }

        context.restoreGState()
    }

    /// Draws an authentic iStat Menus high-DPI rounded capsule pill load bar.
    public static func drawCapsulePill(
        in rect: NSRect,
        percentage: Double,
        fillColor: NSColor? = nil,
        borderColor: NSColor? = nil,
        trackColor: NSColor? = nil
    ) {
        let radius = rect.width / 2.0
        let outerPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let bg = trackColor ?? NSColor.labelColor.withAlphaComponent(0.12)
        bg.setFill()
        outerPath.fill()

        let border = borderColor ?? NSColor.labelColor.withAlphaComponent(0.50)
        outerPath.lineWidth = 1.2
        border.setStroke()
        outerPath.stroke()

        let clamped = min(max(percentage, 0.0), 100.0)
        if clamped > 0 {
            let innerInset: CGFloat = 1.4
            let innerRect = rect.insetBy(dx: innerInset, dy: innerInset)
            let innerRadius = max(innerRect.width / 2.0, 1.0)
            let innerClipPath = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)

            NSGraphicsContext.saveGraphicsState()
            innerClipPath.addClip()

            let fillHeight = max(innerRect.height * CGFloat(clamped / 100.0), 2.0)
            let fillRect = NSRect(
                x: innerRect.minX,
                y: innerRect.minY,
                width: innerRect.width,
                height: fillHeight
            )
            let fill = fillColor ?? NSColor.labelColor
            fill.setFill()
            fillRect.fill()

            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Draws a dual capsule load bar widget with vertical category label on the left.
    public static func drawDualCapsuleBar(
        label: String,
        leftPercentage: Double,
        rightPercentage: Double,
        leftColor: NSColor? = nil,
        rightColor: NSColor? = nil,
        labelColor: NSColor? = nil
    ) -> NSImage {
        let size = NSSize(width: 36, height: 22)
        let image = NSImage(size: size, flipped: false) { bounds in
            let barWidth: CGFloat = 8.5
            let barHeight: CGFloat = 20.0
            let barY: CGFloat = (bounds.height - barHeight) / 2.0

            let textRect = NSRect(x: 2.0, y: barY, width: 9.5, height: barHeight)
            let leftBarRect = NSRect(x: 14.5, y: barY, width: barWidth, height: barHeight)
            let rightBarRect = NSRect(x: 25.5, y: barY, width: barWidth, height: barHeight)

            drawVerticalCategoryText(label, in: textRect, color: labelColor ?? .labelColor)
            drawCapsulePill(in: leftBarRect, percentage: leftPercentage, fillColor: leftColor)
            drawCapsulePill(in: rightBarRect, percentage: rightPercentage, fillColor: rightColor)

            return true
        }
        image.isTemplate = (leftColor == nil && rightColor == nil && labelColor == nil)
        return image
    }

    /// Draws a single capsule load bar widget with a vertical category label on the left.
    public static func drawSingleCapsuleBar(
        label: String,
        percentage: Double,
        barColor: NSColor? = nil,
        labelColor: NSColor? = nil
    ) -> NSImage {
        let canvasWidth: CGFloat = label.isEmpty ? 13.0 : 25.0
        let size = NSSize(width: canvasWidth, height: 22)
        let image = NSImage(size: size, flipped: false) { bounds in
            let barWidth: CGFloat = 8.5
            let barHeight: CGFloat = 20.0
            let barY: CGFloat = (bounds.height - barHeight) / 2.0

            if label.isEmpty {
                let barRect = NSRect(x: (bounds.width - barWidth) / 2.0, y: barY, width: barWidth, height: barHeight)
                drawCapsulePill(in: barRect, percentage: percentage, fillColor: barColor)
            } else {
                let textRect = NSRect(x: 2.0, y: barY, width: 9.5, height: barHeight)
                let barRect = NSRect(x: 14.5, y: barY, width: barWidth, height: barHeight)

                drawVerticalCategoryText(label, in: textRect, color: labelColor ?? .labelColor)
                drawCapsulePill(in: barRect, percentage: percentage, fillColor: barColor)
            }
            return true
        }
        image.isTemplate = (barColor == nil && labelColor == nil)
        return image
    }

    /// Draws per-core CPU micro-bar cluster with vertical "CPU" label on the left, grouped E | P with 2 pt gap.
    public static func drawCPUCoreClusterBar(
        cores: [Double],
        label: String = "CPU",
        barColor: NSColor? = .systemBlue,
        eCoreCount: Int = 0,
        pCoreCount: Int = 0
    ) -> NSImage {
        let textWidth: CGFloat = 9.5
        let gap: CGFloat = 3.0
        let clusterWidth: CGFloat = 24.5
        let totalWidth = 2.0 + textWidth + gap + clusterWidth + 2.0
        let size = NSSize(width: totalWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let barHeight: CGFloat = 20.0
            let barY: CGFloat = (bounds.height - barHeight) / 2.0

            let textRect = NSRect(x: 2.0, y: barY, width: textWidth, height: barHeight)
            drawVerticalCategoryText(label, in: textRect, color: .labelColor)

            let clusterX: CGFloat = 2.0 + textWidth + gap

            if cores.count > 16 {
                // Above 16 cores, render cluster summary bars
                let eAvg: Double
                let pAvg: Double
                if eCoreCount > 0 && pCoreCount > 0 && eCoreCount + pCoreCount == cores.count {
                    eAvg = cores.prefix(eCoreCount).reduce(0.0, +) / Double(eCoreCount)
                    pAvg = cores.suffix(from: eCoreCount).reduce(0.0, +) / Double(pCoreCount)
                } else {
                    let half = cores.count / 2
                    eAvg = cores.prefix(half).reduce(0.0, +) / Double(max(half, 1))
                    pAvg = cores.suffix(from: half).reduce(0.0, +) / Double(max(cores.count - half, 1))
                }
                let barW = (clusterWidth - 2.0) / 2.0
                let eRect = NSRect(x: clusterX, y: barY, width: barW, height: barHeight)
                let pRect = NSRect(x: clusterX + barW + 2.0, y: barY, width: barW, height: barHeight)
                drawCapsulePill(in: eRect, percentage: eAvg, fillColor: barColor)
                drawCapsulePill(in: pRect, percentage: pAvg, fillColor: barColor)
            } else {
                let n = cores.count
                let hasClusters = eCoreCount > 0 && pCoreCount > 0 && (eCoreCount + pCoreCount == n)
                let clusterGap: CGFloat = hasClusters ? 2.0 : 0.0
                let interCoreGap: CGFloat = 0.5
                let totalGaps = (CGFloat(n - 1) * interCoreGap) + clusterGap
                let coreWidth = max(1.0, (clusterWidth - totalGaps) / CGFloat(n))

                var currentX = clusterX
                for (idx, coreUsage) in cores.enumerated() {
                    let trackRect = NSRect(x: currentX, y: barY, width: coreWidth, height: barHeight)
                    drawCapsulePill(in: trackRect, percentage: coreUsage, fillColor: barColor)
                    currentX += coreWidth + interCoreGap
                    if hasClusters && idx == eCoreCount - 1 {
                        currentX += clusterGap - interCoreGap
                    }
                }
            }
            return true
        }
        image.isTemplate = (barColor == nil)
        return image
    }

    /// Draws modern capsule load bar for CPU.
    public static func drawCPUBar(
        perCore: [Double]?,
        user: Double? = nil,
        system: Double? = nil,
        eCoreCount: Int = 0,
        pCoreCount: Int = 0
    ) -> NSImage {
        if let cores = perCore, cores.count >= 2 {
            return drawCPUCoreClusterBar(cores: cores, label: "CPU", barColor: .systemBlue, eCoreCount: eCoreCount, pCoreCount: pCoreCount)
        } else {
            let usr = user ?? 0.0
            let sys = system ?? 0.0
            if sys > 0 {
                return drawDualCapsuleBar(
                    label: "CPU",
                    leftPercentage: usr,
                    rightPercentage: sys,
                    leftColor: .systemBlue,
                    rightColor: .systemOrange
                )
            } else {
                return drawSingleCapsuleBar(
                    label: "CPU",
                    percentage: usr + sys,
                    barColor: .systemBlue
                )
            }
        }
    }

    /// Draws authentic iStat Menus segmented CPU Donut Pie (User vs. System load) with 2.6 pt ring stroke.
    public static func drawCPUDonutPie(user: Double, system: Double, label: String? = nil) -> NSImage {
        let qUser = Int(round(min(max(user, 0.0), 100.0)))
        let qSys = Int(round(min(max(system, 0.0), 100.0 - Double(qUser))))
        let hasLabel = (label != nil && !label!.isEmpty)
        let cacheKey = "cpuDonut:\(qUser):\(qSys):\(hasLabel ? label! : "none")" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let canvasWidth: CGFloat = hasLabel ? 32.0 : 18.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 18.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let gaugeBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 2.0, width: 9.5, height: 18.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                gaugeBounds = NSRect(x: 13.5, y: 2.0, width: 18.0, height: 18.0)
            } else {
                gaugeBounds = bounds
            }

            let center = NSPoint(x: gaugeBounds.midX, y: gaugeBounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 2.6

            let track = NSBezierPath(ovalIn: gaugeBounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            let uClamped = Double(qUser)
            let sClamped = Double(qSys)

            if uClamped > 0 {
                let uArc = NSBezierPath()
                let startAngle: CGFloat = 90.0
                let endAngle: CGFloat = 90.0 - CGFloat(360.0 * (uClamped / 100.0))
                uArc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                uArc.lineWidth = lineWidth
                uArc.lineCapStyle = .round
                CategoryPalette.nsColor(for: .cpu).setStroke()
                uArc.stroke()
            }

            if sClamped > 0 {
                let sArc = NSBezierPath()
                let startAngle: CGFloat = 90.0 - CGFloat(360.0 * (uClamped / 100.0))
                let endAngle: CGFloat = startAngle - CGFloat(360.0 * (sClamped / 100.0))
                sArc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                sArc.lineWidth = lineWidth
                sArc.lineCapStyle = .butt
                NSColor.systemRed.withAlphaComponent(0.70).setStroke()
                sArc.stroke()
            }

            return true
        }
        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Draws authentic iStat Menus Memory Pressure Ring with 2.6 pt ring stroke.
    public static func drawMemoryDonutPie(sample: MemorySample?, ratio: Double, label: String? = nil) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 32.0 : 18.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 18.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let gaugeBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 2.0, width: 9.5, height: 18.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                gaugeBounds = NSRect(x: 13.5, y: 2.0, width: 18.0, height: 18.0)
            } else {
                gaugeBounds = bounds
            }

            let center = NSPoint(x: gaugeBounds.midX, y: gaugeBounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 2.6

            let track = NSBezierPath(ovalIn: gaugeBounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            let clamped = min(max(ratio, 0.0), 100.0)
            let pressure = sample?.pressure ?? .normal
            let status = StatusThresholds.memory(pressure: pressure, swapUsedBytes: sample?.swapUsed ?? 0)
            let strokeColor = CategoryPalette.statusNSColor(for: status)

            if clamped > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90.0, endAngle: 90.0 - CGFloat(360.0 * (clamped / 100.0)), clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                strokeColor.setStroke()
                arc.stroke()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws authentic 3-segment Memory allocation bar (App: Blue, Wired: Red, Compressed: Gold)
    /// with vertical "RAM" category label on the left.
    public static func drawMemoryStackedBar(sample: MemorySample?, ratio: Double) -> NSImage {
        let textWidth: CGFloat = 9.5
        let barWidth: CGFloat = 8.5
        let barHeight: CGFloat = 20.0
        let canvasWidth: CGFloat = 25.0
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let barY: CGFloat = (bounds.height - barHeight) / 2.0
            let textRect = NSRect(x: 2.0, y: barY, width: textWidth, height: barHeight)
            let barRect = NSRect(x: 14.5, y: barY, width: barWidth, height: barHeight)

            drawVerticalCategoryText("RAM", in: textRect, color: .labelColor)

            let radius = barRect.width / 2.0
            let outerPath = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
            let bg = NSColor.labelColor.withAlphaComponent(0.12)
            bg.setFill()
            outerPath.fill()

            outerPath.lineWidth = 1.2
            NSColor.labelColor.withAlphaComponent(0.50).setStroke()
            outerPath.stroke()

            let innerInset: CGFloat = 1.4
            let innerRect = barRect.insetBy(dx: innerInset, dy: innerInset)
            let innerRadius = max(innerRect.width / 2.0, 1.0)
            let innerClipPath = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)

            NSGraphicsContext.saveGraphicsState()
            innerClipPath.addClip()

            if let mem = sample, mem.total > 0 {
                let total = Double(mem.total)
                // 3 segments only: App (Blue), Wired (Red), Compressed (Gold)
                let activeBytes = Double(mem.appMemory ?? mem.active ?? (mem.used - min(mem.used, mem.wired + mem.compressed)))
                let wiredBytes = Double(mem.wired)
                let compBytes = Double(mem.compressed)

                let segments: [(bytes: Double, color: NSColor)] = [
                    (activeBytes, NSColor.systemBlue),
                    (wiredBytes, NSColor.systemRed),
                    (compBytes, NSColor(srgbRed: 0.85, green: 0.65, blue: 0.10, alpha: 1.0))
                ]

                var currentY = innerRect.minY
                let gap: CGFloat = 0.5

                for seg in segments where seg.bytes > 0 {
                    let segH = max(innerRect.height * CGFloat(seg.bytes / total), 1.0)
                    let segRect = NSRect(
                        x: innerRect.minX,
                        y: currentY,
                        width: innerRect.width,
                        height: max(segH - gap, 0.5)
                    )
                    seg.color.setFill()
                    segRect.fill()
                    currentY += segH
                }
            } else {
                let clamped = min(max(ratio, 0.0), 100.0)
                if clamped > 0 {
                    let fillHeight = max(innerRect.height * CGFloat(clamped / 100.0), 2.0)
                    let fillRect = NSRect(x: innerRect.minX, y: innerRect.minY, width: innerRect.width, height: fillHeight)
                    NSColor.systemGreen.setFill()
                    fillRect.fill()
                }
            }

            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws authentic iStat Menus horizontal Battery Instrument with live proportional level fill & multi-state overlays.
    public static func drawBatteryInstrument(
        charge: Double?,
        state: BatteryState?,
        hasBattery: Bool,
        variant: PowerStateVariant? = nil
    ) -> NSImage {
        let activeVariant = variant ?? PowerStateVariant.resolve(charge: charge, state: state, hasBattery: hasBattery)
        let size = NSSize(width: 25, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            if hasBattery && activeVariant != .acDesktop {
                let roundedCharge = round(charge ?? 0.0)
                let isCritical = activeVariant == .lowBattery && roundedCharge <= 10.0

                // Battery Body Frame
                let bodyRect = NSRect(x: 1.0, y: 2.0, width: 19.5, height: 12.0)
                let body = NSBezierPath(roundedRect: bodyRect, xRadius: 2.5, yRadius: 2.5)
                body.lineWidth = 1.2
                if isCritical {
                    NSColor.systemRed.setStroke()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                }
                body.stroke()

                // Battery Terminal Cap
                let capRect = NSRect(x: 21.0, y: 5.5, width: 2.0, height: 5.0)
                let cap = NSBezierPath(roundedRect: capRect, xRadius: 1.0, yRadius: 1.0)
                if isCritical {
                    NSColor.systemRed.setFill()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.85).setFill()
                }
                cap.fill()

                if let chg = charge {
                    let clamped = min(max(chg, 0.0), 100.0)
                    let maxFillWidth: CGFloat = 15.5
                    let fillWidth = max(maxFillWidth * CGFloat(clamped / 100.0), 1.5)
                    let fillRect = NSRect(x: 3.0, y: 4.0, width: fillWidth, height: 8.0)
                    let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.2, yRadius: 1.2)

                    let fillColor: NSColor
                    switch activeVariant {
                    case .lowBattery:
                        fillColor = NSColor.systemRed
                    case .powerDeficit:
                        fillColor = NSColor.systemOrange
                    case .onHold:
                        fillColor = NSColor.systemGreen
                    case .charging, .charged:
                        fillColor = NSColor.systemGreen
                    case .discharging:
                        let qClamped = round(clamped)
                        fillColor = qClamped <= 20.0 ? NSColor.systemRed : (qClamped <= 40.0 ? NSColor.systemYellow : NSColor.systemGreen)
                    case .acDesktop, .unavailable:
                        fillColor = NSColor.systemGreen
                    }
                    fillColor.setFill()
                    fillPath.fill()

                    // Multi-State Overlay Badges
                    switch activeVariant {
                    case .charging:
                        let bolt = NSBezierPath()
                        bolt.move(to: NSPoint(x: 11.5, y: 13.0))
                        bolt.line(to: NSPoint(x: 8.0, y: 8.0))
                        bolt.line(to: NSPoint(x: 10.8, y: 8.0))
                        bolt.line(to: NSPoint(x: 9.5, y: 3.0))
                        bolt.line(to: NSPoint(x: 14.0, y: 9.0))
                        bolt.line(to: NSPoint(x: 11.2, y: 9.0))
                        bolt.close()
                        NSColor.systemYellow.setFill()
                        bolt.fill()
                        bolt.lineWidth = 0.5
                        NSColor.black.withAlphaComponent(0.6).setStroke()
                        bolt.stroke()

                    case .onHold:
                        let p1 = NSBezierPath(roundedRect: NSRect(x: 8.8, y: 5.0, width: 1.8, height: 6.0), xRadius: 0.9, yRadius: 0.9)
                        let p2 = NSBezierPath(roundedRect: NSRect(x: 11.8, y: 5.0, width: 1.8, height: 6.0), xRadius: 0.9, yRadius: 0.9)
                        NSColor.systemOrange.setFill()
                        p1.fill()
                        p2.fill()
                        p1.lineWidth = 0.5
                        p2.lineWidth = 0.5
                        NSColor.black.withAlphaComponent(0.65).setStroke()
                        p1.stroke()
                        p2.stroke()

                    case .powerDeficit:
                        let bolt = NSBezierPath()
                        bolt.move(to: NSPoint(x: 9.0, y: 12.8))
                        bolt.line(to: NSPoint(x: 6.6, y: 8.2))
                        bolt.line(to: NSPoint(x: 8.8, y: 8.2))
                        bolt.line(to: NSPoint(x: 7.6, y: 3.2))
                        bolt.line(to: NSPoint(x: 11.0, y: 8.8))
                        bolt.line(to: NSPoint(x: 8.8, y: 8.8))
                        bolt.close()
                        NSColor.systemOrange.setFill()
                        bolt.fill()
                        bolt.lineWidth = 0.4
                        NSColor.black.withAlphaComponent(0.65).setStroke()
                        bolt.stroke()

                        let arrow = NSBezierPath()
                        arrow.move(to: NSPoint(x: 13.5, y: 11.8))
                        arrow.line(to: NSPoint(x: 13.5, y: 4.8))
                        arrow.move(to: NSPoint(x: 11.5, y: 6.8))
                        arrow.line(to: NSPoint(x: 13.5, y: 4.2))
                        arrow.line(to: NSPoint(x: 15.5, y: 6.8))
                        arrow.lineWidth = 1.3
                        arrow.lineCapStyle = .round
                        arrow.lineJoinStyle = .round
                        NSColor.white.setStroke()
                        arrow.stroke()

                    case .lowBattery:
                        let stem = NSBezierPath(roundedRect: NSRect(x: 9.8, y: 6.8, width: 2.0, height: 4.8), xRadius: 1.0, yRadius: 1.0)
                        let dot = NSBezierPath(ovalIn: NSRect(x: 9.8, y: 4.0, width: 2.0, height: 2.0))
                        NSColor.white.setFill()
                        stem.fill()
                        dot.fill()
                        stem.lineWidth = 0.5
                        dot.lineWidth = 0.5
                        NSColor.black.withAlphaComponent(0.7).setStroke()
                        stem.stroke()
                        dot.stroke()

                    case .charged:
                        let prong1 = NSBezierPath(rect: NSRect(x: 7.0, y: 6.0, width: 2.2, height: 1.2))
                        let prong2 = NSBezierPath(rect: NSRect(x: 7.0, y: 8.8, width: 2.2, height: 1.2))
                        let plugBody = NSBezierPath(roundedRect: NSRect(x: 9.2, y: 5.0, width: 4.2, height: 6.0), xRadius: 1.0, yRadius: 1.0)
                        let stub = NSBezierPath(rect: NSRect(x: 13.4, y: 7.2, width: 1.6, height: 1.6))
                        NSColor.white.setFill()
                        prong1.fill()
                        prong2.fill()
                        plugBody.fill()
                        stub.fill()
                        plugBody.lineWidth = 0.5
                        NSColor.black.withAlphaComponent(0.6).setStroke()
                        plugBody.stroke()

                    case .discharging, .acDesktop, .unavailable:
                        break
                    }
                } else {
                    let dashLine = NSBezierPath()
                    dashLine.move(to: NSPoint(x: 5.0, y: 8.0))
                    dashLine.line(to: NSPoint(x: 16.0, y: 8.0))
                    let dashes: [CGFloat] = [2.0, 2.0]
                    dashLine.setLineDash(dashes, count: 2, phase: 0.0)
                    dashLine.lineWidth = 1.0
                    NSColor.secondaryLabelColor.withAlphaComponent(0.5).setStroke()
                    dashLine.stroke()
                }
            } else {
                let plug = NSBezierPath(roundedRect: NSRect(x: 5.0, y: 3.0, width: 12.0, height: 10.0), xRadius: 2.5, yRadius: 2.5)
                plug.lineWidth = 1.2
                NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                plug.stroke()

                let p1 = NSBezierPath(rect: NSRect(x: 17.0, y: 5.0, width: 4.0, height: 2.0))
                let p2 = NSBezierPath(rect: NSRect(x: 17.0, y: 9.0, width: 4.0, height: 2.0))
                NSColor.systemGreen.setFill()
                p1.fill()
                p2.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws authentic iStat Menus 2-line stacked battery readout (`Charge %` over `Time Remaining` or `Wattage`).
    public static func drawPowerStackedText(
        charge: Double?,
        state: BatteryState?,
        timeRemaining: TimeInterval?,
        watts: Double?
    ) -> NSImage {
        let lines = powerStackedTextLines(charge: charge, state: state, timeRemaining: timeRemaining, watts: watts)
        return drawStackedText(line1: lines.line1, line2: lines.line2, minWidth: 34.0)
    }

    /// Draws dynamic Dual Activity Arrows (`↓` Download and `↑` Upload) with signature colors.
    public static func drawNetworkActivityArrows(inBytes: Double, outBytes: Double) -> NSImage {
        let inActive = inBytes > 1024.0
        let outActive = outBytes > 1024.0
        let cacheKey = "netArrows:\(inActive):\(outActive)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let down = NSBezierPath()
            down.move(to: NSPoint(x: 5.0, y: 15.0))
            down.line(to: NSPoint(x: 5.0, y: 4.0))
            down.move(to: NSPoint(x: 2.0, y: 7.0))
            down.line(to: NSPoint(x: 5.0, y: 3.0))
            down.line(to: NSPoint(x: 8.0, y: 7.0))
            down.lineWidth = inActive ? 2.0 : 1.3
            down.lineCapStyle = .round
            down.lineJoinStyle = .round
            (inActive ? CategoryPalette.nsColor(for: .network) : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            down.stroke()

            let up = NSBezierPath()
            up.move(to: NSPoint(x: 13.0, y: 3.0))
            up.line(to: NSPoint(x: 13.0, y: 14.0))
            up.move(to: NSPoint(x: 10.0, y: 11.0))
            up.line(to: NSPoint(x: 13.0, y: 15.0))
            up.line(to: NSPoint(x: 16.0, y: 11.0))
            up.lineWidth = outActive ? 2.0 : 1.3
            up.lineCapStyle = .round
            up.lineJoinStyle = .round
            (outActive ? CategoryPalette.nsColor(for: .power) : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            up.stroke()

            return true
        }
        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Draws dynamic Disk Read / Write Activity LEDs (`R` and `W`) with signature colors.
    public static func drawDiskActivityLeds(readBytes: Double, writeBytes: Double) -> NSImage {
        let rActive = readBytes > 10240.0
        let wActive = writeBytes > 10240.0
        let cacheKey = "diskLeds:\(rActive):\(wActive)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let font = NSFont.systemFont(ofSize: 9.5, weight: .black)

            let rBadge = NSBezierPath(roundedRect: NSRect(x: 1.0, y: 2.0, width: 8.5, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            if rActive {
                CategoryPalette.nsColor(for: .disk).setFill()
                rBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                ("R" as NSString).draw(at: NSPoint(x: 2.2, y: 3.0), withAttributes: attrs)
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                rBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.40)]
                ("R" as NSString).draw(at: NSPoint(x: 2.2, y: 3.0), withAttributes: attrs)
            }

            let wBadge = NSBezierPath(roundedRect: NSRect(x: 10.5, y: 2.0, width: 8.5, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            if wActive {
                NSColor.systemOrange.setFill()
                wBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                ("W" as NSString).draw(at: NSPoint(x: 11.0, y: 3.0), withAttributes: attrs)
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                wBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.40)]
                ("W" as NSString).draw(at: NSPoint(x: 11.0, y: 3.0), withAttributes: attrs)
            }

            return true
        }
        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    // MARK: - Compatibility Drawings, Rationalized Instruments & Decay-Max Scaler

    public static func computeDecayMax(values: [Double], floor: Double) -> Double {
        let peak = values.max() ?? floor
        return max(peak, floor)
    }

    public static func drawCPUSymbol(usage: Double? = nil) -> NSImage {
        drawTriSegmentPie(ratio: usage)
    }

    public static func drawCPUGauge(percentage: Double, label: String? = nil) -> NSImage {
        drawCPUDonutPie(user: percentage, system: 0.0, label: label)
    }

    public static func drawCPUSparkline(
        history: [Double],
        userHistory: [Double] = [],
        systemHistory: [Double] = [],
        label: String? = nil
    ) -> NSImage {
        guard userHistory.count == history.count && systemHistory.count == history.count && history.count >= 2 else {
            return drawColoredSparkline(values: history, maxValue: 100.0, strokeColor: .systemBlue, fillColor: .systemBlue.withAlphaComponent(0.25), label: label)
        }

        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 50.0 : 36.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 16.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let sparkBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 3.0, width: 9.5, height: 16.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                sparkBounds = NSRect(x: 13.5, y: 3.0, width: 35.0, height: 16.0)
            } else {
                sparkBounds = bounds
            }

            let innerBounds = sparkBounds.insetBy(dx: 1.5, dy: 1.5)
            let stepX = innerBounds.width / CGFloat(max(history.count - 1, 1))

            let userLine = NSBezierPath()
            let userFill = NSBezierPath()
            userFill.move(to: NSPoint(x: innerBounds.minX, y: innerBounds.minY))

            let totalLine = NSBezierPath()
            let totalFill = NSBezierPath()
            totalFill.move(to: NSPoint(x: innerBounds.minX, y: innerBounds.minY))

            var lastUserPt = NSPoint(x: innerBounds.minX, y: innerBounds.minY)
            var lastTotalPt = NSPoint(x: innerBounds.minX, y: innerBounds.minY)

            for (idx, uVal) in userHistory.enumerated() {
                let sVal = systemHistory[idx]
                let totalVal = min(max(uVal + sVal, 0.0), 100.0)
                let clampedU = min(max(uVal, 0.0), 100.0)

                let x = innerBounds.minX + (CGFloat(idx) * stepX)
                let uY = innerBounds.minY + (innerBounds.height * CGFloat(clampedU / 100.0))
                let tY = innerBounds.minY + (innerBounds.height * CGFloat(totalVal / 100.0))

                let uPt = NSPoint(x: x, y: uY)
                let tPt = NSPoint(x: x, y: tY)
                lastUserPt = uPt
                lastTotalPt = tPt

                if idx == 0 {
                    userLine.move(to: uPt)
                    userFill.line(to: uPt)
                    totalLine.move(to: tPt)
                    totalFill.line(to: tPt)
                } else {
                    userLine.line(to: uPt)
                    userFill.line(to: uPt)
                    totalLine.line(to: tPt)
                    totalFill.line(to: tPt)
                }
            }

            totalFill.line(to: NSPoint(x: lastTotalPt.x, y: innerBounds.minY))
            totalFill.close()
            NSColor.systemRed.withAlphaComponent(0.25).setFill()
            totalFill.fill()

            userFill.line(to: NSPoint(x: lastUserPt.x, y: innerBounds.minY))
            userFill.close()
            NSColor.systemBlue.withAlphaComponent(0.35).setFill()
            userFill.fill()

            userLine.lineWidth = 1.2
            userLine.lineJoinStyle = .round
            NSColor.systemBlue.setStroke()
            userLine.stroke()

            totalLine.lineWidth = 1.2
            totalLine.lineJoinStyle = .round
            NSColor.systemRed.withAlphaComponent(0.70).setStroke()
            totalLine.stroke()

            let dotRect = NSRect(x: lastTotalPt.x - 1.4, y: lastTotalPt.y - 1.4, width: 2.8, height: 2.8)
            let dot = NSBezierPath(ovalIn: dotRect)
            NSColor.systemBlue.setFill()
            dot.fill()

            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawCPUBar(percentage: Double, user: Double? = nil, system: Double? = nil) -> NSImage {
        drawCPUBar(perCore: nil, user: user ?? percentage, system: system)
    }

    public static func drawMemorySymbol(ratio: Double? = nil, pressure: MemoryPressure? = nil) -> NSImage {
        drawMemoryPressureBadge(pressure: pressure)
    }

    public static func drawMemoryPressureBadge(pressure: MemoryPressure?) -> NSImage {
        let p = pressure ?? .normal
        let cacheKey = "memPressure:\(p.rawValue)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)

            let pillRect = NSRect(x: center.x - 7.0, y: center.y - 8.0, width: 14.0, height: 16.0)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: 3.5, yRadius: 3.5)
            NSColor.labelColor.withAlphaComponent(0.15).setStroke()
            pill.lineWidth = 1.0
            pill.stroke()

            let barW: CGFloat = 8.5
            let barH: CGFloat = 2.8
            let barX: CGFloat = center.x - barW / 2.0

            let levels: [(y: CGFloat, active: Bool)] = [
                (center.y - 5.5, true),
                (center.y - 1.4, p == .warning || p == .critical),
                (center.y + 2.7, p == .critical)
            ]

            let fillCol: NSColor = (p == .critical) ? NSColor.systemRed : ((p == .warning) ? NSColor.systemYellow : NSColor.systemGreen)

            for lvl in levels {
                let rect = NSRect(x: barX, y: lvl.y, width: barW, height: barH)
                let bPath = NSBezierPath(roundedRect: rect, xRadius: 1.0, yRadius: 1.0)
                if lvl.active {
                    fillCol.setFill()
                    bPath.fill()
                } else {
                    NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                    bPath.fill()
                }
            }

            return true
        }
        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    public static func drawMemoryGauge(ratio: Double, label: String? = nil) -> NSImage {
        drawMemoryDonutPie(sample: nil, ratio: ratio, label: label)
    }

    public static func drawMemoryBar(ratio: Double) -> NSImage {
        drawSingleCapsuleBar(label: "RAM", percentage: ratio, barColor: .systemGreen)
    }

    public static func drawMemorySparkline(history: [Double], pressure: MemoryPressure? = nil, label: String? = nil) -> NSImage {
        let p = pressure ?? .normal
        let col = CategoryPalette.statusNSColor(for: StatusThresholds.memory(pressure: p))
        return drawColoredSparkline(values: history, maxValue: 100.0, strokeColor: col, fillColor: col.withAlphaComponent(0.25), label: label)
    }

    public static func drawGPUSymbol(utilization: Double? = nil, tempCelsius: Double? = nil) -> NSImage {
        drawGPUDieSymbol(utilization: utilization, tempCelsius: tempCelsius)
    }

    public static func drawGPUDieSymbol(utilization: Double? = nil, tempCelsius: Double? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let util = min(max(utilization ?? 0.0, 0.0), 100.0)

            let frameRect = NSRect(x: center.x - 7.0, y: center.y - 7.0, width: 14.0, height: 14.0)
            let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 2.5, yRadius: 2.5)

            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            framePath.fill()

            framePath.lineWidth = 1.0
            NSColor.labelColor.withAlphaComponent(0.40).setStroke()
            framePath.stroke()

            let pinLength: CGFloat = 1.0
            let pinColor = NSColor.secondaryLabelColor.withAlphaComponent(0.50)
            pinColor.setStroke()

            for py in [center.y - 3.5, center.y + 3.5] {
                let lPin = NSBezierPath()
                lPin.move(to: NSPoint(x: frameRect.minX - pinLength, y: py))
                lPin.line(to: NSPoint(x: frameRect.minX, y: py))
                lPin.lineWidth = 0.8
                lPin.stroke()

                let rPin = NSBezierPath()
                rPin.move(to: NSPoint(x: frameRect.maxX, y: py))
                rPin.line(to: NSPoint(x: frameRect.maxX + pinLength, y: py))
                rPin.lineWidth = 0.8
                rPin.stroke()
            }

            let dieRect = NSRect(x: center.x - 5.0, y: center.y - 5.0, width: 10.0, height: 10.0)
            let dieClip = NSBezierPath(roundedRect: dieRect, xRadius: 1.5, yRadius: 1.5)

            NSGraphicsContext.saveGraphicsState()
            dieClip.addClip()

            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            dieClip.fill()

            let col = CategoryPalette.nsColor(for: .gpu)
            if util > 0 {
                let fillH = max(dieRect.height * CGFloat(util / 100.0), 1.5)
                let fillRect = NSRect(x: dieRect.minX, y: dieRect.minY, width: dieRect.width, height: fillH)
                col.setFill()
                fillRect.fill()
            }

            let gridPath = NSBezierPath()
            gridPath.move(to: NSPoint(x: center.x, y: dieRect.minY))
            gridPath.line(to: NSPoint(x: center.x, y: dieRect.maxY))
            gridPath.move(to: NSPoint(x: dieRect.minX, y: center.y))
            gridPath.line(to: NSPoint(x: dieRect.maxX, y: center.y))
            gridPath.lineWidth = 0.5
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            gridPath.stroke()

            NSGraphicsContext.restoreGraphicsState()

            dieClip.lineWidth = 0.8
            col.withAlphaComponent(0.60).setStroke()
            dieClip.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawGPUGauge(
        percentage: Double,
        tempCelsius: Double? = nil,
        label: String? = nil
    ) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 32.0 : 18.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 18.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let gaugeBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 2.0, width: 9.5, height: 18.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                gaugeBounds = NSRect(x: 13.5, y: 2.0, width: 18.0, height: 18.0)
            } else {
                gaugeBounds = bounds
            }

            let center = NSPoint(x: gaugeBounds.midX, y: gaugeBounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 2.6

            let track = NSBezierPath(ovalIn: gaugeBounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            let clamped = min(max(percentage, 0.0), 100.0)
            if clamped > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90.0, endAngle: 90.0 - CGFloat(360.0 * (clamped / 100.0)), clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round

                let status = StatusThresholds.gpu(utilizationPercent: clamped)
                let strokeColor = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : CategoryPalette.nsColor(for: .gpu)
                strokeColor.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawGPUBar(percentage: Double) -> NSImage {
        drawSingleCapsuleBar(label: "GPU", percentage: percentage, barColor: CategoryPalette.nsColor(for: .gpu))
    }

    public static func drawGPUSparkline(history: [Double], label: String? = nil) -> NSImage {
        drawColoredSparkline(values: history, maxValue: 100.0, strokeColor: CategoryPalette.nsColor(for: .gpu), fillColor: CategoryPalette.nsColor(for: .gpu).withAlphaComponent(0.25), label: label)
    }

    public static func thermalColor(for celsius: Double) -> NSColor {
        let status = StatusThresholds.temperature(celsius: celsius, source: .peak)
        return CategoryPalette.statusNSColor(for: status)
    }

    public static func drawThermalSymbol(celsius: Double? = nil) -> NSImage {
        let c = celsius ?? 45.0
        let pct = min(max((c - 30.0) / 70.0 * 100.0, 0.0), 100.0)
        return drawThermalGauge(percentage: pct, celsius: c)
    }

    public static func drawThermalGauge(percentage: Double, celsius: Double? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 2.6

            let track = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            let clamped = min(max(percentage, 0.0), 100.0)
            if clamped > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90.0, endAngle: 90.0 - CGFloat(360.0 * (clamped / 100.0)), clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                let c = round(celsius ?? (30.0 + (clamped / 100.0) * 70.0))
                thermalColor(for: c).setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawThermalBar(percentage: Double, celsius: Double? = nil) -> NSImage {
        let c = round(celsius ?? (30.0 + (min(max(percentage, 0.0), 100.0) / 100.0) * 70.0))
        let col = thermalColor(for: c)
        return drawSingleCapsuleBar(label: "TMP", percentage: percentage, barColor: col)
    }

    public static func drawThermometerGlyph(
        celsius: Double?,
        formattedTemp: String,
        status: StatusLevel
    ) -> NSImage {
        let fixedWidth: CGFloat = 36.0
        let cacheKey = "thermGlyph:\(celsius != nil ? "\(Int(round(celsius!)))" : "nil"):\(formattedTemp):\(status.rawValue)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let size = NSSize(width: fixedWidth, height: 22)
        let statusColor = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : CategoryPalette.nsColor(for: .thermal)
        let valColor = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : NSColor.labelColor

        let image = NSImage(size: size, flipped: false) { bounds in
            let centerX: CGFloat = 6.0
            let bulbCenterY: CGFloat = 6.0
            let bulbRadius: CGFloat = 3.0
            let stemWidth: CGFloat = 2.4
            let stemTop: CGFloat = 17.5
            let stemBottom: CGFloat = bulbCenterY + 1.5

            let stemRect = NSRect(x: centerX - stemWidth / 2.0, y: stemBottom, width: stemWidth, height: stemTop - stemBottom)
            let stemPath = NSBezierPath(roundedRect: stemRect, xRadius: stemWidth / 2.0, yRadius: stemWidth / 2.0)
            let bulbRect = NSRect(x: centerX - bulbRadius, y: bulbCenterY - bulbRadius, width: bulbRadius * 2.0, height: bulbRadius * 2.0)
            let bulbPath = NSBezierPath(ovalIn: bulbRect)

            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
            stemPath.fill()
            bulbPath.fill()

            statusColor.setFill()
            bulbPath.fill()

            if let c = celsius {
                let clamped = min(max((c - 30.0) / 70.0, 0.0), 1.0)
                let fillH = max(CGFloat(clamped) * (stemTop - stemBottom), 1.0)
                let fillRect = NSRect(x: centerX - (stemWidth - 0.4) / 2.0, y: stemBottom - 1.0, width: stemWidth - 0.4, height: fillH + 1.0)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: (stemWidth - 0.4) / 2.0, yRadius: (stemWidth - 0.4) / 2.0)
                fillPath.fill()
            }

            let valAttr = formatCompactValueAttributedString(value: formattedTemp, color: valColor)
            let valSize = valAttr.size()
            let valX = 12.0
            let valY = floor((bounds.height - valSize.height) / 2.0) - 1.0
            valAttr.draw(at: NSPoint(x: valX, y: valY))

            return true
        }
        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    public static func drawThermalSparkline(history: [Double], label: String? = nil) -> NSImage {
        let maxVal = max(history.max() ?? 100.0, 100.0)
        let latest = history.last ?? 50.0
        let col = thermalColor(for: latest)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: col, fillColor: col.withAlphaComponent(0.25), label: label)
    }

    public static func drawFanSymbol(rpm: Int? = nil, percentage: Double? = nil) -> NSImage {
        drawFanBlades(percentage: percentage ?? 0.0, rpm: rpm)
    }

    public static func drawFanGauge(percentage: Double) -> NSImage {
        drawFanTachometer(percentage: percentage)
    }

    public static func drawFanBar(fan: FanSample?, primaryPct: Double? = nil) -> NSImage {
        let fans = fan?.fans ?? []
        if fans.count >= 2 {
            let pct0 = fanPercentage(for: fans[0])
            let pct1 = fanPercentage(for: fans[1])
            return drawDualCapsuleBar(
                label: "FAN",
                leftPercentage: pct0,
                rightPercentage: pct1,
                leftColor: .systemCyan,
                rightColor: .systemTeal
            )
        } else {
            let pct = primaryPct ?? (fans.first != nil ? fanPercentage(for: fans[0]) : 0.0)
            return drawSingleCapsuleBar(label: "FAN", percentage: pct, barColor: .systemCyan)
        }
    }

    public static func drawFanBar(percentage: Double) -> NSImage {
        drawSingleCapsuleBar(label: "FAN", percentage: percentage, barColor: .systemCyan)
    }

    public static func drawFanStackedThroughput(fan: FanSample?, primaryPct: Double? = nil) -> NSImage {
        let fans = fan?.fans ?? []
        if fans.count >= 2 {
            let f0 = fans[0]
            let f1 = fans[1]
            return drawStackedTwoLineText(
                prefix1: "L",
                value1: "\(f0.rpm)",
                prefix2: "R",
                value2: "\(f1.rpm)",
                minWidth: 36.0,
                color1: .systemCyan,
                color2: .systemTeal,
                prefixColor1: .systemCyan,
                prefixColor2: .systemTeal
            )
        } else if let f0 = fans.first {
            let pct = primaryPct ?? fanPercentage(for: f0)
            let pStr = String(format: "%.0f%%", pct)
            let rStr = "\(f0.rpm)"
            return drawStackedTwoLineText(
                prefix1: "FAN",
                value1: pStr,
                prefix2: "RPM",
                value2: rStr,
                minWidth: 44.0,
                color1: .systemCyan,
                color2: .labelColor,
                prefixColor1: .systemCyan,
                prefixColor2: .secondaryLabelColor
            )
        } else {
            return drawStackedTwoLineText(
                prefix1: "FAN",
                value1: "0%",
                prefix2: "RPM",
                value2: "0",
                minWidth: 44.0,
                color1: .systemCyan,
                color2: .labelColor,
                prefixColor1: .systemCyan,
                prefixColor2: .secondaryLabelColor
            )
        }
    }

    public static func drawFanTachometer(percentage: Double, rpm: Int? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 6.8
            let lineWidth: CGFloat = 2.2

            let startAngle: CGFloat = 215.0
            let totalSpan: CGFloat = 250.0
            let endAngle: CGFloat = startAngle - totalSpan

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            track.lineWidth = lineWidth
            track.lineCapStyle = .round
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            let tickAngles: [CGFloat] = [startAngle, startAngle - totalSpan * 0.5, endAngle]
            for angle in tickAngles {
                let rad = angle * .pi / 180.0
                let innerPt = NSPoint(x: center.x + cos(rad) * 4.6, y: center.y + sin(rad) * 4.6)
                let outerPt = NSPoint(x: center.x + cos(rad) * (radius + 1.2), y: center.y + sin(rad) * (radius + 1.2))
                let tick = NSBezierPath()
                tick.move(to: innerPt)
                tick.line(to: outerPt)
                tick.lineWidth = 0.8
                NSColor.secondaryLabelColor.withAlphaComponent(0.40).setStroke()
                tick.stroke()
            }

            let clamped = min(max(percentage, 0.0), 100.0)
            if clamped > 0 {
                let activeSweep = totalSpan * CGFloat(clamped / 100.0)
                let activeEnd = startAngle - activeSweep
                let activeArc = NSBezierPath()
                activeArc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: activeEnd, clockwise: true)
                activeArc.lineWidth = lineWidth
                activeArc.lineCapStyle = .round

                let strokeColor = clamped > 80.0 ? NSColor.systemTeal : NSColor.systemCyan
                strokeColor.setStroke()
                activeArc.stroke()
            }

            let hub = NSBezierPath(ovalIn: NSRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6))
            (clamped > 0 ? NSColor.systemCyan : NSColor.secondaryLabelColor.withAlphaComponent(0.60)).setFill()
            hub.fill()

            let needleAngle = startAngle - totalSpan * CGFloat(clamped / 100.0)
            let needleRad = needleAngle * .pi / 180.0
            let needleLen: CGFloat = 5.2
            let needleTip = NSPoint(x: center.x + cos(needleRad) * needleLen, y: center.y + sin(needleRad) * needleLen)
            let needle = NSBezierPath()
            needle.move(to: center)
            needle.line(to: needleTip)
            needle.lineWidth = 1.3
            needle.lineCapStyle = .round
            (clamped > 0 ? NSColor.labelColor : NSColor.secondaryLabelColor.withAlphaComponent(0.70)).setStroke()
            needle.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawFanBlades(percentage: Double, rpm: Int? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let outerRadius: CGFloat = 7.5
            let hubRadius: CGFloat = 2.4

            let shroud = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.2, dy: 1.2))
            shroud.lineWidth = 1.0
            NSColor.secondaryLabelColor.withAlphaComponent(0.28).setStroke()
            shroud.stroke()

            let isActive = (rpm ?? 0) > 0 || percentage > 0.0
            let clamped = min(max(percentage, 0.0), 100.0)

            let bladeAngles: [CGFloat] = [45.0, 135.0, 225.0, 315.0]
            let bladeColor: NSColor
            if isActive {
                let alpha = min(max(0.45 + (clamped / 100.0) * 0.55, 0.45), 1.0)
                bladeColor = NSColor.systemCyan.withAlphaComponent(alpha)
            } else {
                bladeColor = NSColor.secondaryLabelColor.withAlphaComponent(0.35)
            }

            for angle in bladeAngles {
                let path = NSBezierPath()
                let rootAngle = angle * .pi / 180.0
                let tipAngle = (angle + 32.0) * .pi / 180.0
                let trailAngle = (angle - 18.0) * .pi / 180.0

                let pRoot = NSPoint(x: center.x + cos(rootAngle) * hubRadius, y: center.y + sin(rootAngle) * hubRadius)
                let pTip = NSPoint(x: center.x + cos(tipAngle) * (outerRadius - 0.5), y: center.y + sin(tipAngle) * (outerRadius - 0.5))
                let pTrail = NSPoint(x: center.x + cos(trailAngle) * hubRadius, y: center.y + sin(trailAngle) * hubRadius)

                path.move(to: pRoot)
                let ctrl1 = NSPoint(x: center.x + cos(tipAngle - 0.1) * (outerRadius * 0.7), y: center.y + sin(tipAngle - 0.1) * (outerRadius * 0.7))
                path.curve(to: pTip, controlPoint1: pRoot, controlPoint2: ctrl1)
                let ctrl2 = NSPoint(x: center.x + cos(rootAngle - 0.1) * (outerRadius * 0.5), y: center.y + sin(rootAngle - 0.1) * (outerRadius * 0.5))
                path.curve(to: pTrail, controlPoint1: pTip, controlPoint2: ctrl2)
                path.close()

                bladeColor.setFill()
                path.fill()

                if isActive {
                    NSColor.systemCyan.withAlphaComponent(0.80).setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                }
            }

            let hubRect = NSRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2.0, height: hubRadius * 2.0)
            let hub = NSBezierPath(ovalIn: hubRect)
            if isActive {
                NSColor.systemCyan.setFill()
                hub.fill()

                let pin = NSBezierPath(ovalIn: NSRect(x: center.x - 0.8, y: center.y - 0.8, width: 1.6, height: 1.6))
                NSColor.white.withAlphaComponent(0.90).setFill()
                pin.fill()
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.50).setFill()
                hub.fill()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawFanGlyph(
        rpm: Int?,
        isFanless: Bool = false,
        status: StatusLevel
    ) -> NSImage {
        let fixedWidth: CGFloat = 44.0
        let rpmStr = isFanless ? "—" : (rpm != nil ? "\(rpm!)" : "--")
        let cacheKey = "fanGlyph:\(rpmStr):\(isFanless):\(status.rawValue)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let size = NSSize(width: fixedWidth, height: 22)
        let iconColor = isFanless
            ? NSColor.secondaryLabelColor.withAlphaComponent(0.50)
            : ((status >= .warning) ? CategoryPalette.statusNSColor(for: status) : CategoryPalette.nsColor(for: .fan))
        let valColor = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : NSColor.labelColor

        let image = NSImage(size: size, flipped: false) { bounds in
            if let sfSymbol = NSImage(systemSymbolName: "fan", accessibilityDescription: nil) {
                let symConfig = NSImage.SymbolConfiguration(pointSize: 10.0, weight: .bold)
                if let configured = sfSymbol.withSymbolConfiguration(symConfig) {
                    let iconRect = NSRect(x: 2.0, y: (bounds.height - 11.0) / 2.0, width: 11.0, height: 11.0)
                    iconColor.set()
                    configured.draw(in: iconRect)
                }
            }

            let font = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: valColor
            ]
            let str = NSAttributedString(string: rpmStr, attributes: attrs)
            let strSize = str.size()
            let textX = max(15.0, bounds.maxX - 2.0 - strSize.width)
            let textY = (bounds.height - strSize.height) / 2.0
            str.draw(at: NSPoint(x: textX, y: textY))

            return true
        }
        image.isTemplate = false
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    public static func drawFanSparkline(history: [Double], label: String? = nil) -> NSImage {
        let maxVal = max(history.max() ?? 6000.0, 2000.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: CategoryPalette.nsColor(for: .fan), fillColor: CategoryPalette.nsColor(for: .fan).withAlphaComponent(0.25), label: label)
    }

    public static func drawNetworkSymbol(inBytes: Double? = nil, outBytes: Double? = nil) -> NSImage {
        drawNetworkActivityArrows(inBytes: inBytes ?? 0.0, outBytes: outBytes ?? 0.0)
    }

    public static func drawNetworkBar(
        inBytes: Double,
        outBytes: Double,
        inHistory: [Double],
        outHistory: [Double]
    ) -> NSImage {
        let inMax = computeDecayMax(values: inHistory, floor: 1024.0 * 1024.0)
        let outMax = computeDecayMax(values: outHistory, floor: 1024.0 * 1024.0)
        let inPct = min(max((inBytes / inMax) * 100.0, 0.0), 100.0)
        let outPct = min(max((outBytes / outMax) * 100.0, 0.0), 100.0)
        return drawDualCapsuleBar(
            label: "NET",
            leftPercentage: inPct,
            rightPercentage: outPct,
            leftColor: .systemTeal,
            rightColor: .systemPurple
        )
    }

    public static func drawNetworkBar(inPct: Double, outPct: Double) -> NSImage {
        drawDualCapsuleBar(
            label: "NET",
            leftPercentage: inPct,
            rightPercentage: outPct,
            leftColor: .systemTeal,
            rightColor: .systemPurple
        )
    }

    public static func drawNetworkSparkline(history: [Double]) -> NSImage {
        let maxVal = computeDecayMax(values: history, floor: 1024.0 * 1024.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: CategoryPalette.nsColor(for: .network), fillColor: CategoryPalette.nsColor(for: .network).withAlphaComponent(0.25))
    }

    public static func drawDiskSymbol(readBytes: Double? = nil, writeBytes: Double? = nil) -> NSImage {
        drawDiskActivityLeds(readBytes: readBytes ?? 0.0, writeBytes: writeBytes ?? 0.0)
    }

    public static func drawDiskGauge(percentage: Double, label: String? = nil) -> NSImage {
        let volRatio = min(max(percentage, 0.0), 100.0)
        let status = StatusThresholds.disk(usedPercent: volRatio)
        let stroke = (status >= .warning) ? CategoryPalette.statusNSColor(for: status) : CategoryPalette.nsColor(for: .disk)
        return drawCircularGauge(percentage: volRatio, strokeColor: stroke, label: label)
    }

    public static func drawDiskBar(percentage: Double) -> NSImage {
        drawSingleCapsuleBar(
            label: "SSD",
            percentage: percentage,
            barColor: CategoryPalette.nsColor(for: .disk)
        )
    }

    public static func drawDiskBar(readPct: Double, writePct: Double) -> NSImage {
        drawDualCapsuleBar(
            label: "SSD",
            leftPercentage: readPct,
            rightPercentage: writePct,
            leftColor: CategoryPalette.nsColor(for: .disk),
            rightColor: .systemOrange
        )
    }

    public static func drawDiskSparkline(history: [Double], label: String? = nil) -> NSImage {
        let maxVal = computeDecayMax(values: history, floor: 10.0 * 1024.0 * 1024.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: CategoryPalette.nsColor(for: .disk), fillColor: CategoryPalette.nsColor(for: .disk).withAlphaComponent(0.25), label: label)
    }

    public static func drawPowerSymbol(
        charge: Double? = nil,
        state: BatteryState? = nil,
        hasBattery: Bool = true,
        variant: PowerStateVariant? = nil
    ) -> NSImage {
        drawBatteryInstrument(charge: charge, state: state, hasBattery: hasBattery, variant: variant)
    }

    public static func drawPowerBudgetText(drawWatts: Double?, adapterWatts: Double?) -> NSImage {
        let drawStr = drawWatts != nil ? String(format: "%.0fW", drawWatts!) : "--W"
        let adaptStr = adapterWatts != nil ? String(format: "%.0fW", adapterWatts!) : "AC"
        return drawStackedTwoLineText(
            prefix1: "",
            value1: drawStr,
            prefix2: "",
            value2: adaptStr,
            minWidth: 34.0,
            color1: .systemGreen,
            color2: .secondaryLabelColor
        )
    }

    public static func drawPowerGauge(percentage: Double, isCharging: Bool = false, variant: PowerStateVariant? = nil) -> NSImage {
        let v: PowerStateVariant = variant ?? (isCharging ? .charging : (percentage <= 20.0 ? .lowBattery : .discharging))
        let icon: String
        switch v {
        case .charging:
            icon = "bolt.fill"
        case .onHold:
            icon = "pause.fill"
        case .powerDeficit:
            icon = "bolt.trianglebadge.exclamationmark.fill"
        case .lowBattery:
            icon = "exclamationmark"
        case .charged, .acDesktop:
            icon = "powerplug.fill"
        case .discharging:
            icon = percentage <= 20.0 ? "battery.25percent" : "battery.100percent"
        case .unavailable:
            icon = "battery.slash"
        }
        return drawCircularGauge(percentage: percentage, iconName: icon)
    }

    public static func drawPowerBar(percentage: Double, isCharging: Bool = false, variant: PowerStateVariant? = nil) -> NSImage {
        let v: PowerStateVariant = variant ?? (isCharging ? .charging : (percentage <= 20.0 ? .lowBattery : .discharging))
        let clamped = min(max(percentage, 0.0), 100.0)
        let color: NSColor
        let label: String
        switch v {
        case .powerDeficit:
            color = NSColor.systemOrange
            label = "DEF"
        case .onHold:
            color = NSColor.systemTeal
            label = "HLD"
        case .lowBattery:
            color = NSColor.systemRed
            label = "LOW"
        case .charging:
            color = NSColor.systemGreen
            label = "CHG"
        case .charged:
            color = NSColor.systemGreen
            label = "PWR"
        case .discharging, .acDesktop, .unavailable:
            let qClamped = round(clamped)
            color = qClamped <= 20.0 ? NSColor.systemRed : (qClamped <= 40.0 ? NSColor.systemYellow : NSColor.systemGreen)
            label = "BAT"
        }
        return drawSingleCapsuleBar(label: label, percentage: percentage, barColor: color)
    }

    public static func drawPowerSparkline(history: [Double], label: String? = nil) -> NSImage {
        let maxVal = computeDecayMax(values: history, floor: 5.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: CategoryPalette.nsColor(for: .power), fillColor: CategoryPalette.nsColor(for: .power).withAlphaComponent(0.25), label: label)
    }

    /// Generic circular gauge template.
    public static func drawCircularGauge(
        percentage: Double,
        iconName: String? = nil,
        strokeColor: NSColor? = nil,
        label: String? = nil,
        lineWidth: CGFloat = 2.6
    ) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 32.0 : 18.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 18.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let gaugeBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 2.0, width: 9.5, height: 18.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                gaugeBounds = NSRect(x: 13.5, y: 2.0, width: 18.0, height: 18.0)
            } else {
                gaugeBounds = bounds
            }

            let center = NSPoint(x: gaugeBounds.midX, y: gaugeBounds.midY)
            let radius: CGFloat = 7.2

            let track = NSBezierPath(ovalIn: gaugeBounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            let clamped = min(max(percentage, 0.0), 100.0)
            if clamped > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90.0, endAngle: 90.0 - CGFloat(360.0 * (clamped / 100.0)), clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                (strokeColor ?? NSColor.labelColor).setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = (strokeColor == nil)
        return image
    }

    /// Generic vertical bar graph template.
    public static func drawBarGraph(percentage: Double) -> NSImage {
        drawSingleCapsuleBar(label: "", percentage: percentage)
    }

    /// Generic history sparkline chart template.
    public static func drawSparkline(values: [Double], maxValue: Double) -> NSImage {
        let size = NSSize(width: 36, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            guard values.count >= 2 else {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 1.0, y: 2.0))
                path.line(to: NSPoint(x: bounds.maxX - 1.0, y: 2.0))
                path.lineWidth = 1.0
                NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
                path.stroke()
                return true
            }

            let maxVal = max(maxValue, 1.0)
            let innerBounds = bounds.insetBy(dx: 1.5, dy: 1.5)
            let stepX = innerBounds.width / CGFloat(max(values.count - 1, 1))

            let linePath = NSBezierPath()
            let fillPath = NSBezierPath()
            fillPath.move(to: NSPoint(x: innerBounds.minX, y: innerBounds.minY))

            var lastPoint = NSPoint(x: innerBounds.minX, y: innerBounds.minY)

            for (index, val) in values.enumerated() {
                let clamped = min(max(val, 0.0), maxVal)
                let y = innerBounds.minY + (innerBounds.height * CGFloat(clamped / maxVal))
                let x = innerBounds.minX + (CGFloat(index) * stepX)
                let pt = NSPoint(x: x, y: y)
                lastPoint = pt

                if index == 0 {
                    linePath.move(to: pt)
                    fillPath.line(to: pt)
                } else {
                    linePath.line(to: pt)
                    fillPath.line(to: pt)
                }
            }

            fillPath.line(to: NSPoint(x: lastPoint.x, y: innerBounds.minY))
            fillPath.close()
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            fillPath.fill()

            linePath.lineWidth = 1.4
            linePath.lineJoinStyle = .round
            linePath.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            linePath.stroke()

            let dotRect = NSRect(x: lastPoint.x - 1.3, y: lastPoint.y - 1.3, width: 2.6, height: 2.6)
            let dot = NSBezierPath(ovalIn: dotRect)
            NSColor.labelColor.setFill()
            dot.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws a colored history sparkline chart with gradient area fill and glowing peak dot.
    public static func drawColoredSparkline(
        values: [Double],
        maxValue: Double,
        strokeColor: NSColor,
        fillColor: NSColor,
        label: String? = nil
    ) -> NSImage {
        let hasLabel = (label != nil && !label!.isEmpty)
        let canvasWidth: CGFloat = hasLabel ? 50.0 : 36.0
        let canvasHeight: CGFloat = hasLabel ? 22.0 : 16.0
        let size = NSSize(width: canvasWidth, height: canvasHeight)

        let image = NSImage(size: size, flipped: false) { bounds in
            let sparkBounds: NSRect
            if hasLabel {
                let textRect = NSRect(x: 2.0, y: 3.0, width: 9.5, height: 16.0)
                drawVerticalCategoryText(label!, in: textRect, color: .labelColor)
                sparkBounds = NSRect(x: 13.5, y: 3.0, width: 35.0, height: 16.0)
            } else {
                sparkBounds = bounds
            }

            guard values.count >= 2 else {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: sparkBounds.minX + 1.0, y: sparkBounds.minY + 2.0))
                path.line(to: NSPoint(x: sparkBounds.maxX - 1.0, y: sparkBounds.minY + 2.0))
                path.lineWidth = 1.0
                NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
                path.stroke()
                return true
            }

            let maxVal = max(maxValue, 1.0)
            let innerBounds = sparkBounds.insetBy(dx: 1.5, dy: 1.5)
            let stepX = innerBounds.width / CGFloat(max(values.count - 1, 1))

            let linePath = NSBezierPath()
            let fillPath = NSBezierPath()
            fillPath.move(to: NSPoint(x: innerBounds.minX, y: innerBounds.minY))

            var lastPoint = NSPoint(x: innerBounds.minX, y: innerBounds.minY)

            for (index, val) in values.enumerated() {
                let clamped = min(max(val, 0.0), maxVal)
                let y = innerBounds.minY + (innerBounds.height * CGFloat(clamped / maxVal))
                let x = innerBounds.minX + (CGFloat(index) * stepX)
                let pt = NSPoint(x: x, y: y)
                lastPoint = pt

                if index == 0 {
                    linePath.move(to: pt)
                    fillPath.line(to: pt)
                } else {
                    linePath.line(to: pt)
                    fillPath.line(to: pt)
                }
            }

            fillPath.line(to: NSPoint(x: lastPoint.x, y: innerBounds.minY))
            fillPath.close()
            fillColor.setFill()
            fillPath.fill()

            linePath.lineWidth = 1.4
            linePath.lineJoinStyle = .round
            linePath.lineCapStyle = .round
            strokeColor.setStroke()
            linePath.stroke()

            let dotRect = NSRect(x: lastPoint.x - 1.4, y: lastPoint.y - 1.4, width: 2.8, height: 2.8)
            let dot = NSBezierPath(ovalIn: dotRect)
            strokeColor.setFill()
            dot.fill()

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Loads an SF Symbol image formatted for menu bar presentation.
    public static func symbolImage(name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(config) else {
            return nil
        }
        img.isTemplate = true
        return img
    }
}
