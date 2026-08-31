import AppKit
import CoreText
import SwiftUI
import iStatsCore

/// Pure rendering engine that generates authentic iStat Menus high-DPI `NSImage` graphics and formatted title text
/// for any `MenuBarItemConfig` across all `MetricCategory` and `MetricDisplayStyle` options (ADR 0007).
@MainActor
public struct MenuBarIconRenderer {
    public struct RenderResult {
        public let image: NSImage?
        public let title: String
        public let toolTip: String
        public let accessibilityLabel: String

        public init(
            image: NSImage? = nil,
            title: String = "",
            toolTip: String = "",
            accessibilityLabel: String = ""
        ) {
            self.image = image
            self.title = title
            self.toolTip = toolTip
            self.accessibilityLabel = accessibilityLabel.isEmpty ? toolTip : accessibilityLabel
        }
    }

    /// Primary entry point: renders image, title, tooltip, and accessibility label for a given menu bar item configuration.
    public static func render(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator,
        preferences: PreferencesStore
    ) -> RenderResult {
        switch config.category {
        case .cpu:
            let cpu = coordinator.latestCPU?.value
            let history = coordinator.cpuHistory.map { $0.value.totalUsage }
            return renderCPU(style: config.style, cpu: cpu, history: history)

        case .memory:
            let memory = coordinator.latestMemory?.value
            let ratio: Double = (memory != nil && memory!.total > 0)
                ? (Double(memory!.used) / Double(memory!.total)) * 100.0
                : 0.0
            let history = coordinator.memoryHistory.map {
                $0.value.total > 0 ? (Double($0.value.used) / Double($0.value.total)) * 100.0 : 0.0
            }
            return renderMemory(style: config.style, memory: memory, ratio: ratio, history: history, standard: preferences.byteUnitStandard)

        case .gpu:
            let gpu = coordinator.latestGPU?.value
            let history = coordinator.gpuHistory.compactMap { $0.value.utilization }
            return renderGPU(style: config.style, gpu: gpu, history: history)

        case .thermal:
            let thermal = coordinator.latestThermal?.value
            let history = coordinator.thermalHistory.compactMap { sample in
                sample.value.sensors.map(\.celsius).max()
            }
            return renderThermal(style: config.style, thermal: thermal, history: history, unit: preferences.temperatureUnit)

        case .fan:
            let fan = coordinator.latestFan?.value
            let history = coordinator.fanHistory.compactMap { Double($0.value.fans.first?.rpm ?? 0) }
            return renderFan(style: config.style, fan: fan, history: history)

        case .network:
            let network = coordinator.latestNetwork?.value
            let inHistory = coordinator.networkHistory.map { Double($0.value.totalBytesInPerSec) }
            let outHistory = coordinator.networkHistory.map { Double($0.value.totalBytesOutPerSec) }
            return renderNetwork(
                style: config.style,
                network: network,
                inHistory: inHistory,
                outHistory: outHistory,
                unit: preferences.networkUnit,
                standard: preferences.byteUnitStandard
            )

        case .disk:
            let disk = coordinator.latestDisk?.value
            let history = coordinator.diskHistory.compactMap {
                Double(($0.value.io?.bytesReadPerSec ?? 0) + ($0.value.io?.bytesWrittenPerSec ?? 0))
            }
            return renderDisk(style: config.style, disk: disk, history: history, standard: preferences.byteUnitStandard)

        case .power:
            let power = coordinator.latestPower?.value
            let history = coordinator.powerHistory.compactMap { $0.value.powerDrawWatts }
            return renderPower(style: config.style, power: power, history: history)
        }
    }

    // MARK: - 1. CPU Rendering

    private static func renderCPU(style: MetricDisplayStyle, cpu: CPUSample?, history: [Double]) -> RenderResult {
        let usage = cpu?.totalUsage ?? 0.0
        let tip = cpu != nil ? String(format: "CPU: %.1f%% (User: %.1f%%, Sys: %.1f%%)", cpu!.totalUsage, cpu!.user, cpu!.system) : "CPU: --%"
        let valStr = cpu != nil ? String(format: "%.0f%%", usage) : "--%"
        let a11y = cpu != nil ? String(format: "CPU load %.0f percent", usage) : "CPU load unavailable"

        switch style {
        case .gauge:
            // Segmented Donut Pie (User vs Kernel load) with vibrant signature colors
            let img = drawCPUDonutPie(user: cpu?.user ?? usage, system: cpu?.system ?? 0.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .bar:
            // Live Per-Core Micro-Bar Cluster (or stacked bar)
            let img = drawCPUBar(perCore: cpu?.perCore, user: cpu?.user, system: cpu?.system)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .sparkline:
            // Real-Time Scrolling History Graph with signature blue gradient
            let img = drawCPUSparkline(history: history)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .text:
            // Invariant Jitter-Free Stacked Text (CPU over Usage%)
            let img = drawCategoryStackedText(title: "CPU", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        default:
            let img = drawCategoryStackedText(title: "CPU", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        }
    }

    // MARK: - 2. Memory Rendering

    private static func renderMemory(
        style: MetricDisplayStyle,
        memory: MemorySample?,
        ratio: Double,
        history: [Double],
        standard: Units.ByteUnitStandard
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

        switch style {
        case .gauge:
            // Memory Breakdown Donut Ring (Wired / Active / Compressed / Free)
            let img = drawMemoryDonutPie(sample: memory, ratio: ratio)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .bar:
            // Segmented Allocation Memory Bar (Apps, Wired, Compressed, Cached)
            let img = drawMemoryStackedBar(sample: memory, ratio: ratio)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .sparkline:
            // Rolling Memory History Graph with pressure tint
            let img = drawMemorySparkline(history: history, pressure: memory?.pressure)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .symbol:
            // Dedicated 3-state Pressure Badge / Pill (OK / WARN / CRIT)
            let img = drawMemoryPressureBadge(pressure: memory?.pressure)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .text:
            // Two-Line Jitter-Free Stacked Text (MEM / Used %)
            let img = drawCategoryStackedText(title: "MEM", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        default:
            let img = drawCategoryStackedText(title: "MEM", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        }
    }

    // MARK: - 3. GPU Rendering

    private static func renderGPU(style: MetricDisplayStyle, gpu: GPUSample?, history: [Double]) -> RenderResult {
        let util = gpu?.utilization ?? 0.0
        let tip = gpu != nil ? String(format: "GPU: %.1f%%", util) : "GPU: --%"
        let valStr = gpu?.utilization != nil ? String(format: "%.0f%%", util) : "--%"
        let a11y = gpu?.utilization != nil ? String(format: "GPU utilization %.0f percent", util) : "GPU utilization unavailable"

        switch style {
        case .gauge:
            // Util ring tinted by GPU temperature stops
            let img = drawGPUGauge(percentage: util, tempCelsius: gpu?.tempCelsius)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .bar:
            let img = drawGPUBar(percentage: util)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .sparkline:
            let img = drawGPUSparkline(history: history)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .symbol:
            // Mini GPU-die glyph (fill = util, color = temp)
            let img = drawGPUDieSymbol(utilization: gpu?.utilization, tempCelsius: gpu?.tempCelsius)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .text:
            let img = drawCategoryStackedText(title: "GPU", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        default:
            let img = drawCategoryStackedText(title: "GPU", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        }
    }

    // MARK: - 4. Thermal Rendering

    private static func findThermalSensor(
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
        style: MetricDisplayStyle,
        thermal: ThermalSample?,
        history: [Double],
        unit: Units.TemperatureUnit
    ) -> RenderResult {
        let sensor: SensorReading?
        let title: String
        let componentLabel: String

        switch style {
        case .cpuTemp:
            sensor = findThermalSensor(in: thermal, matching: ["CPU", "Efficiency Cores", "Package"])
            title = "CPU"
            componentLabel = "CPU"
        case .gpuTemp:
            sensor = findThermalSensor(in: thermal, matching: ["GPU"])
            title = "GPU"
            componentLabel = "GPU"
        case .memoryTemp:
            sensor = findThermalSensor(in: thermal, matching: ["Memory", "RAM"])
            title = "MEM"
            componentLabel = "Memory"
        case .storageTemp:
            sensor = findThermalSensor(in: thermal, matching: ["Flash", "NAND", "SSD", "Storage", "Disk"])
            title = "SSD"
            componentLabel = "Storage"
        case .batteryTemp:
            sensor = findThermalSensor(in: thermal, matching: ["Battery"])
            title = "BAT"
            componentLabel = "Battery"
        case .text, .gauge, .bar, .sparkline, .symbol, .throughput:
            sensor = thermal?.sensors.max(by: { $0.celsius < $1.celsius }) ?? thermal?.sensors.first
            title = "TMP"
            componentLabel = "Peak"
        }

        let tempC = sensor?.celsius ?? 0.0
        let pct = min(max((tempC - 30.0) / (100.0 - 30.0) * 100.0, 0.0), 100.0)
        let formattedTemp = Units.formatTemperature(tempC, unit: unit, fractionDigits: 0)
        let formattedPreciseTemp = Units.formatTemperature(tempC, unit: unit, fractionDigits: 1)

        let tip = sensor != nil
            ? "\(componentLabel) Thermal: \(formattedPreciseTemp) (\(sensor!.name))"
            : "\(componentLabel) Thermal: --"
        let valStr = sensor != nil ? formattedTemp : "--°"
        let a11y = sensor != nil
            ? "\(componentLabel) temperature \(formattedTemp)"
            : "\(componentLabel) thermal unavailable"

        switch style {
        case .gauge:
            let img = drawThermalGauge(percentage: pct, celsius: tempC)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .sparkline:
            let img = drawThermalSparkline(history: history)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .bar:
            // Legacy fallback if requested directly
            let img = drawThermalBar(percentage: pct, celsius: tempC)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .cpuTemp, .gpuTemp, .memoryTemp, .storageTemp, .batteryTemp, .text:
            let img = drawCategoryStackedText(title: title, value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        default:
            let img = drawCategoryStackedText(title: title, value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
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

    private static func renderFan(style: MetricDisplayStyle, fan: FanSample?, history: [Double]) -> RenderResult {
        let fans = fan?.fans ?? []
        let primaryFan = fans.max(by: { fanPercentage(for: $0) < fanPercentage(for: $1) }) ?? fans.first
        let rpm = primaryFan?.rpm ?? 0
        let tip: String
        let a11y: String
        if let f = primaryFan {
            let desc = fans.count > 1 ? fans.map { "\($0.name): \($0.rpm) RPM" }.joined(separator: ", ") : "\(f.name): \(rpm) RPM"
            tip = "Fans: \(desc)"
            a11y = "Fans running at \(rpm) RPM"
        } else if fan?.isFanless == true {
            tip = "Fans: Fanless System"
            a11y = "Fanless system"
        } else {
            tip = "Fans: -- RPM"
            a11y = "Fans unavailable"
        }

        let pct: Double = primaryFan != nil ? fanPercentage(for: primaryFan!) : 0.0
        let valStr = primaryFan != nil ? String(format: "%.0f%%", pct) : (fan?.isFanless == true ? "0%" : "--%")

        switch style {
        case .gauge:
            // 240° tachometer with ticks + needle
            let img = drawFanTachometer(percentage: pct, rpm: primaryFan?.rpm)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .bar:
            let img = drawFanBar(fan: fan, primaryPct: pct)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .sparkline:
            let img = drawFanSparkline(history: history)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .text:
            let img = drawCategoryStackedText(title: "FAN", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .throughput:
            let img = drawFanStackedThroughput(fan: fan, primaryPct: pct)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .symbol:
            // 4-blade cooling turbine with speed-based opacity
            let img = drawFanBlades(percentage: pct, rpm: primaryFan?.rpm)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        default:
            let img = drawCategoryStackedText(title: "FAN", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        }
    }

    // MARK: - 6. Network Rendering

    private static func renderNetwork(
        style: MetricDisplayStyle,
        network: NetworkSample?,
        inHistory: [Double],
        outHistory: [Double],
        unit: Units.NetworkUnit,
        standard: Units.ByteUnitStandard
    ) -> RenderResult {
        let inBytes = network?.totalBytesInPerSec ?? 0.0
        let outBytes = network?.totalBytesOutPerSec ?? 0.0
        let inFormatted = Units.formatNetworkRate(inBytes, unit: unit, standard: standard, fractionDigits: 1)
        let outFormatted = Units.formatNetworkRate(outBytes, unit: unit, standard: standard, fractionDigits: 1)
        let tip = "Network: ↓ \(inFormatted)  ↑ \(outFormatted)"
        let a11y = "Network download \(inFormatted), upload \(outFormatted)"

        switch style {
        case .throughput:
            // Signature iStat Menus 2-Line Stacked Download (↓) & Upload (↑) Speeds
            let img = drawNetworkStackedThroughput(inBytes: inBytes, outBytes: outBytes, unit: unit, standard: standard)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .sparkline:
            // Split Duplex Graph with decay-max scaling
            let img = drawNetworkSplitDuplexGraph(inHistory: inHistory, outHistory: outHistory)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .symbol:
            // Dynamic Dual Activity Arrows
            let img = drawNetworkActivityArrows(inBytes: inBytes, outBytes: outBytes)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .bar:
            // Dual In/Out Saturation Bars with decay-max scaling
            let img = drawNetworkBar(inBytes: inBytes, outBytes: outBytes, inHistory: inHistory, outHistory: outHistory)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        default:
            let img = drawNetworkStackedThroughput(inBytes: inBytes, outBytes: outBytes, unit: unit, standard: standard)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        }
    }

    // MARK: - 7. Disk Rendering

    private static func renderDisk(
        style: MetricDisplayStyle,
        disk: DiskSample?,
        history: [Double],
        standard: Units.ByteUnitStandard
    ) -> RenderResult {
        let readBytes = disk?.io?.bytesReadPerSec ?? 0.0
        let writeBytes = disk?.io?.bytesWrittenPerSec ?? 0.0
        let rStr = Units.formatDiskRate(readBytes, standard: standard, fractionDigits: 1)
        let wStr = Units.formatDiskRate(writeBytes, standard: standard, fractionDigits: 1)
        let tip = "Disk I/O: Read \(rStr), Write \(wStr)"
        let a11y = "Disk read \(rStr), write \(wStr)"

        // Volume capacity ratio
        let primaryVol = disk?.volumes.first(where: { $0.mountPoint == "/" }) ?? disk?.volumes.first
        let volRatio: Double = (primaryVol != nil && primaryVol!.total > 0)
            ? (Double(primaryVol!.used) / Double(primaryVol!.total)) * 100.0
            : 0.0

        switch style {
        case .throughput:
            // Two-Line Stacked Read / Write Speeds
            let img = drawDiskStackedThroughput(readBytes: readBytes, writeBytes: writeBytes, standard: standard)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .symbol:
            // Dynamic Read / Write Activity LEDs
            let img = drawDiskActivityLeds(readBytes: readBytes, writeBytes: writeBytes)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .gauge:
            // Volume Capacity Donut Ring (Boot volume used %)
            let img = drawDiskGauge(percentage: volRatio)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: String(format: "Storage %.0f percent full", volRatio))
        case .bar:
            // "SSD" + Boot Volume Used-% Capsule Bar
            let img = drawDiskBar(percentage: volRatio)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: String(format: "Storage %.0f percent full", volRatio))
        case .sparkline:
            // Combined I/O History with decay-max scaling
            let img = drawDiskSparkline(history: history)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        default:
            let img = drawDiskStackedThroughput(readBytes: readBytes, writeBytes: writeBytes, standard: standard)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        }
    }

    // MARK: - 8. Power Rendering

    private static func renderPower(style: MetricDisplayStyle, power: PowerSample?, history: [Double]) -> RenderResult {
        let charge = power?.charge ?? 0.0
        let tip: String
        let a11y: String
        if let pwr = power {
            if pwr.hasBattery {
                let stateStr: String
                let a11yState: String
                switch pwr.state {
                case .charging:
                    stateStr = " (Charging)"
                    a11yState = ", charging"
                case .charged:
                    stateStr = " (Fully Charged)"
                    a11yState = ", fully charged"
                case .acConnected:
                    stateStr = " (AC Connected)"
                    a11yState = ", on AC power"
                case .discharging:
                    stateStr = " (On Battery)"
                    a11yState = ", on battery"
                case .unknown, .none:
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

        let isCharging = power?.state == .charging
        let hasBattery = power?.hasBattery ?? true

        switch style {
        case .symbol:
            // Authentic Battery Shell Instrument with Live Fill & Charging Bolt
            let img = drawBatteryInstrument(charge: power?.charge, state: power?.state, hasBattery: hasBattery)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .text:
            // Two-Line Stacked Battery Charge% + Time Remaining / Wattage
            let img = drawPowerStackedText(charge: power?.charge, state: power?.state, timeRemaining: power?.timeRemaining, watts: power?.powerDrawWatts)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .throughput:
            // Live Power Budget (Draw W over Adapter W)
            let img = drawPowerBudgetText(drawWatts: power?.powerDrawWatts, adapterWatts: power?.adapterWatts)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .gauge:
            let img = drawPowerGauge(percentage: charge, isCharging: isCharging)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .bar:
            let img = drawPowerBar(percentage: charge, isCharging: isCharging)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        case .sparkline:
            // Live Power Draw Watts History with decay-max scaling
            let img = drawPowerSparkline(history: history)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        default:
            let img = drawBatteryInstrument(charge: power?.charge, state: power?.state, hasBattery: hasBattery)
            return RenderResult(image: img, toolTip: tip, accessibilityLabel: a11y)
        }
    }

    // MARK: - Core iStat Menus Instrument Drawing Primitives

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
        valueColor: NSColor? = nil
    ) -> NSImage {
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

            // Lowered vertical baselines with large 11.0pt digits and generous ~4.0pt interline gap:
            // Value baseline sits at y = 0.52pt (digits top at 8.27pt)
            // Title baseline sits at y = 12.29pt (title top at 18.28pt)
            // Top margin: 3.72pt, Bottom margin: 0.52pt, Interline gap: 4.02pt
            let vY: CGFloat = -1.8
            let tY: CGFloat = 10.5

            titleAttrString.draw(at: NSPoint(x: tX, y: tY))
            valueAttrString.draw(at: NSPoint(x: vX, y: vY))
            return true
        }
        image.isTemplate = (titleColor == nil && valueColor == nil)
        return image
    }

    /// Draws authentic iStat Menus 3-Segment Pie / Tri-Blade Instrument (as seen in official iStat Menus).
    public static func drawTriSegmentPie(
        ratio: Double? = nil,
        activeRatio: Double? = nil,
        wiredRatio: Double? = nil,
        compressedRatio: Double? = nil
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let outerRadius: CGFloat = 8.0
            let innerRadius: CGFloat = 2.2
            
            // 3 segments at 90°, 210°, 330° with 12° angular gaps
            let segmentSpan: CGFloat = 108.0 // 120 - 12 gap
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
        return image
    }

    /// Draws single-line tabular monospaced text right-aligned within a fixed-width template canvas.
    public static func drawSingleLineText(
        text: String,
        fixedWidth: CGFloat = 60.0
    ) -> NSImage {
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
    /// (e.g. `↑`/`↓`, `R`/`W`) in a left column and right-aligned tabular numeric metrics in a right column
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
                // Left-align prefixes starting at leftPadding
                if !prefix1.isEmpty {
                    (prefix1 as NSString).draw(at: NSPoint(x: leftPadding, y: y1), withAttributes: pAttrs1)
                }
                if !prefix2.isEmpty {
                    (prefix2 as NSString).draw(at: NSPoint(x: leftPadding, y: y2), withAttributes: pAttrs2)
                }

                // Right-align values ending at bounds.maxX - rightPadding
                let vX1 = bounds.maxX - rightPadding - sv1.width
                let vX2 = bounds.maxX - rightPadding - sv2.width
                (value1 as NSString).draw(at: NSPoint(x: max(leftPadding + maxPrefixWidth + 1.0, vX1), y: y1), withAttributes: vAttrs1)
                (value2 as NSString).draw(at: NSPoint(x: max(leftPadding + maxPrefixWidth + 1.0, vX2), y: y2), withAttributes: vAttrs2)
            } else {
                // Centered if no prefixes (e.g. Battery percentage + time)
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

    /// Draws the signature iStat Menus split duplex history graph (Download Blue above midline, Upload Purple below midline).
    public static func drawNetworkSplitDuplexGraph(
        inHistory: [Double],
        outHistory: [Double]
    ) -> NSImage {
        let size = NSSize(width: 36, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            let midY: CGFloat = 8.0

            // Baseline center divider line
            let centerLine = NSBezierPath()
            centerLine.move(to: NSPoint(x: 1.0, y: midY))
            centerLine.line(to: NSPoint(x: bounds.maxX - 1.0, y: midY))
            centerLine.lineWidth = 0.6
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            centerLine.stroke()

            let inMax = max(inHistory.max() ?? 1024.0, 1024.0)
            let outMax = max(outHistory.max() ?? 1024.0, 1024.0)

            let count = max(max(inHistory.count, outHistory.count), 2)
            let stepX = (bounds.width - 2.0) / CGFloat(count - 1)

            // 1. Inbound (Download) - Waves scrolling above midline (System Blue)
            if inHistory.count >= 2 {
                let inFill = NSBezierPath()
                let inLine = NSBezierPath()
                inFill.move(to: NSPoint(x: 1.0, y: midY))

                for (idx, val) in inHistory.enumerated() {
                    let clamped = min(max(val, 0.0), inMax)
                    let h = CGFloat(clamped / inMax) * 7.0
                    let x = 1.0 + CGFloat(idx) * stepX
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
                inFill.line(to: NSPoint(x: bounds.maxX - 1.0, y: midY))
                inFill.close()
                NSColor.systemBlue.withAlphaComponent(0.28).setFill()
                inFill.fill()

                inLine.lineWidth = 1.2
                inLine.lineJoinStyle = .round
                NSColor.systemBlue.setStroke()
                inLine.stroke()
            }

            // 2. Outbound (Upload) - Waves scrolling below midline (System Purple)
            if outHistory.count >= 2 {
                let outFill = NSBezierPath()
                let outLine = NSBezierPath()
                outFill.move(to: NSPoint(x: 1.0, y: midY))

                for (idx, val) in outHistory.enumerated() {
                    let clamped = min(max(val, 0.0), outMax)
                    let h = CGFloat(clamped / outMax) * 7.0
                    let x = 1.0 + CGFloat(idx) * stepX
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
                outFill.line(to: NSPoint(x: bounds.maxX - 1.0, y: midY))
                outFill.close()
                NSColor.systemPurple.withAlphaComponent(0.25).setFill()
                outFill.fill()

                outLine.lineWidth = 1.2
                outLine.lineJoinStyle = .round
                NSColor.systemPurple.setStroke()
                outLine.stroke()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Capsule Bar & Vertical Label Drawing Primitives

    /// Draws category acronym letters (e.g. "SSD", "CPU", "RAM") stacked vertically one above the other
    /// using exact CoreText vector glyphs and monospaced advance alignment for pixel-perfect vertical and horizontal alignment.
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

    /// Draws an authentic iStat Menus high-DPI rounded capsule pill load bar with clear background track,
    /// clipped proportional floating fill rising from bottom, and crisp prominent outer border stroke.
    public static func drawCapsulePill(
        in rect: NSRect,
        percentage: Double,
        fillColor: NSColor? = nil,
        borderColor: NSColor? = nil,
        trackColor: NSColor? = nil
    ) {
        let radius = rect.width / 2.0
        let outerPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // Background track fill - clear and visible even at 0%
        let bg = trackColor ?? NSColor.labelColor.withAlphaComponent(0.12)
        bg.setFill()
        outerPath.fill()

        // Outer border stroke
        let border = borderColor ?? NSColor.labelColor.withAlphaComponent(0.50)
        outerPath.lineWidth = 1.2
        border.setStroke()
        outerPath.stroke()

        // Filled level inside the capsule with signature floating inner margin
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

    /// Draws a dual capsule load bar widget with vertical category label on the left
    /// and dual load bars side by side on the right (e.g. SSD [Read Bar] [Write Bar] or NET [In Bar] [Out Bar]).
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

    /// Draws a single capsule load bar widget with a vertical category label on the left
    /// (e.g. [RAM] [Bar], [GPU] [Bar], [BAT] [Bar]).
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

    /// Draws per-core CPU micro-bar cluster with vertical "CPU" label on the left.
    public static func drawCPUCoreClusterBar(
        cores: [Double],
        label: String = "CPU",
        barColor: NSColor? = .systemBlue
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

            let n = cores.count
            let clusterX: CGFloat = 2.0 + textWidth + gap
            let totalGap = CGFloat(n - 1) * 0.5
            let coreWidth = max(1.0, (clusterWidth - totalGap) / CGFloat(n))
            let actualGap = n > 1 ? (clusterWidth - CGFloat(n) * coreWidth) / CGFloat(n - 1) : 0.0

            for (idx, coreUsage) in cores.enumerated() {
                let x = clusterX + CGFloat(idx) * (coreWidth + actualGap)
                let trackRect = NSRect(x: x, y: barY, width: coreWidth, height: barHeight)
                drawCapsulePill(in: trackRect, percentage: coreUsage, fillColor: barColor)
            }
            return true
        }
        image.isTemplate = (barColor == nil)
        return image
    }

    /// Draws modern capsule load bar for CPU (with vertical "CPU" category label and signature colors).
    public static func drawCPUBar(
        perCore: [Double]?,
        user: Double? = nil,
        system: Double? = nil
    ) -> NSImage {
        if let cores = perCore, cores.count >= 2 {
            return drawCPUCoreClusterBar(cores: cores, label: "CPU", barColor: .systemBlue)
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

    /// Draws authentic iStat Menus segmented CPU Donut Pie (User vs. System load) with signature vibrant colors.
    public static func drawCPUDonutPie(user: Double, system: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 3.0

            // Background full ring track
            let track = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            let uClamped = min(max(user, 0.0), 100.0)
            let sClamped = min(max(system, 0.0), 100.0 - uClamped)

            // User Space slice (Starts at 12 o'clock, sweeps clockwise) - System Blue
            if uClamped > 0 {
                let uArc = NSBezierPath()
                let startAngle: CGFloat = 90.0
                let endAngle: CGFloat = 90.0 - CGFloat(360.0 * (uClamped / 100.0))
                uArc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                uArc.lineWidth = lineWidth
                uArc.lineCapStyle = .round
                NSColor.systemBlue.setStroke()
                uArc.stroke()
            }

            // System / Kernel Space slice (Continues immediately after user slice) - System Orange
            if sClamped > 0 {
                let sArc = NSBezierPath()
                let startAngle: CGFloat = 90.0 - CGFloat(360.0 * (uClamped / 100.0))
                let endAngle: CGFloat = startAngle - CGFloat(360.0 * (sClamped / 100.0))
                sArc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                sArc.lineWidth = lineWidth
                sArc.lineCapStyle = .butt
                NSColor.systemOrange.setStroke()
                sArc.stroke()
            }

            // Central Micro-Indicator Dot
            let dotRect = NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3.0, height: 3.0)
            let dot = NSBezierPath(ovalIn: dotRect)
            (uClamped > 50.0 ? NSColor.systemBlue : NSColor.secondaryLabelColor.withAlphaComponent(0.40)).setFill()
            dot.fill()

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws authentic iStat Menus Memory Breakdown Donut Ring with signature colors.
    public static func drawMemoryDonutPie(sample: MemorySample?, ratio: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 3.0

            // Background track
            let track = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            if let mem = sample, mem.total > 0 {
                let total = Double(mem.total)
                let wiredRatio = Double(mem.wired) / total
                let activeRatio = Double(mem.active ?? (mem.used - mem.wired)) / total
                let compressedRatio = Double(mem.compressed) / total

                var currentAngle: CGFloat = 90.0

                // 1. Wired (Red)
                if wiredRatio > 0 {
                    let wAngle = CGFloat(360.0 * wiredRatio)
                    let wArc = NSBezierPath()
                    wArc.appendArc(withCenter: center, radius: radius, startAngle: currentAngle, endAngle: currentAngle - wAngle, clockwise: true)
                    wArc.lineWidth = lineWidth
                    NSColor.systemRed.setStroke()
                    wArc.stroke()
                    currentAngle -= wAngle
                }

                // 2. Active / App Memory (Blue)
                if activeRatio > 0 {
                    let aAngle = CGFloat(360.0 * activeRatio)
                    let aArc = NSBezierPath()
                    aArc.appendArc(withCenter: center, radius: radius, startAngle: currentAngle, endAngle: currentAngle - aAngle, clockwise: true)
                    aArc.lineWidth = lineWidth
                    NSColor.systemBlue.setStroke()
                    aArc.stroke()
                    currentAngle -= aAngle
                }

                // 3. Compressed (Yellow)
                if compressedRatio > 0 {
                    let cAngle = CGFloat(360.0 * compressedRatio)
                    let cArc = NSBezierPath()
                    cArc.appendArc(withCenter: center, radius: radius, startAngle: currentAngle, endAngle: currentAngle - cAngle, clockwise: true)
                    cArc.lineWidth = lineWidth
                    NSColor.systemYellow.setStroke()
                    cArc.stroke()
                }
            } else {
                let clamped = min(max(ratio, 0.0), 100.0)
                if clamped > 0 {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: radius, startAngle: 90.0, endAngle: 90.0 - CGFloat(360.0 * (clamped / 100.0)), clockwise: true)
                    arc.lineWidth = lineWidth
                    arc.lineCapStyle = .round
                    NSColor.systemGreen.setStroke()
                    arc.stroke()
                }
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws authentic segmented Memory allocation bar (Apps/Active: Blue, Wired: Red, Compressed: Gold, Cached: Gray)
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
                // Color tokens:
                // Active/Apps: blue, Wired: red, Compressed: gold (0.85, 0.65, 0.10), Cached: gray
                let activeBytes = Double(mem.appMemory ?? mem.active ?? (mem.used - min(mem.used, mem.wired + mem.compressed)))
                let wiredBytes = Double(mem.wired)
                let compBytes = Double(mem.compressed)
                let cachedBytes = Double(mem.cached)

                let segments: [(bytes: Double, color: NSColor)] = [
                    (activeBytes, NSColor.systemBlue),
                    (wiredBytes, NSColor.systemRed),
                    (compBytes, NSColor(srgbRed: 0.85, green: 0.65, blue: 0.10, alpha: 1.0)),
                    (cachedBytes, NSColor.secondaryLabelColor.withAlphaComponent(0.50))
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

    /// Draws authentic iStat Menus horizontal Battery Instrument with live proportional level fill & charging bolt.
    public static func drawBatteryInstrument(
        charge: Double?,
        state: BatteryState?,
        hasBattery: Bool
    ) -> NSImage {
        let size = NSSize(width: 25, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            if hasBattery {
                // Battery Body Frame
                let bodyRect = NSRect(x: 1.0, y: 2.0, width: 19.5, height: 12.0)
                let body = NSBezierPath(roundedRect: bodyRect, xRadius: 2.5, yRadius: 2.5)
                body.lineWidth = 1.2
                NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                body.stroke()

                // Battery Terminal Cap
                let capRect = NSRect(x: 21.0, y: 5.5, width: 2.0, height: 5.0)
                let cap = NSBezierPath(roundedRect: capRect, xRadius: 1.0, yRadius: 1.0)
                NSColor.labelColor.withAlphaComponent(0.85).setFill()
                cap.fill()

                if let chg = charge {
                    let clamped = min(max(chg, 0.0), 100.0)
                    // Proportional Level Fill
                    let maxFillWidth: CGFloat = 15.5
                    let fillWidth = max(maxFillWidth * CGFloat(clamped / 100.0), 1.5)
                    let fillRect = NSRect(x: 3.0, y: 4.0, width: fillWidth, height: 8.0)
                    let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.2, yRadius: 1.2)
                    
                    let fillColor: NSColor
                    if clamped <= 20.0 {
                        fillColor = NSColor.systemRed
                    } else if state == .charging {
                        fillColor = NSColor.systemGreen
                    } else {
                        fillColor = NSColor.systemGreen
                    }
                    fillColor.setFill()
                    fillPath.fill()

                    // Charging Lightning Bolt Overlay (Gold / Yellow)
                    if state == .charging {
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
                    }
                } else {
                    // Unavailable/Unmetered: dashed line across center
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
                // Desktop Mac: AC Plug
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

        return drawStackedText(line1: l1, line2: l2, minWidth: 34.0)
    }

    /// Draws dynamic Dual Activity Arrows (`↓` Download and `↑` Upload) with signature colors.
    public static func drawNetworkActivityArrows(inBytes: Double, outBytes: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let inActive = inBytes > 1024.0
            let outActive = outBytes > 1024.0

            // Download Arrow (Left, pointing Down) - System Blue
            let down = NSBezierPath()
            down.move(to: NSPoint(x: 5.0, y: 15.0))
            down.line(to: NSPoint(x: 5.0, y: 4.0))
            down.move(to: NSPoint(x: 2.0, y: 7.0))
            down.line(to: NSPoint(x: 5.0, y: 3.0))
            down.line(to: NSPoint(x: 8.0, y: 7.0))
            down.lineWidth = inActive ? 2.0 : 1.3
            down.lineCapStyle = .round
            down.lineJoinStyle = .round
            (inActive ? NSColor.systemBlue : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            down.stroke()

            // Upload Arrow (Right, pointing Up) - System Purple
            let up = NSBezierPath()
            up.move(to: NSPoint(x: 13.0, y: 3.0))
            up.line(to: NSPoint(x: 13.0, y: 14.0))
            up.move(to: NSPoint(x: 10.0, y: 11.0))
            up.line(to: NSPoint(x: 13.0, y: 15.0))
            up.line(to: NSPoint(x: 16.0, y: 11.0))
            up.lineWidth = outActive ? 2.0 : 1.3
            up.lineCapStyle = .round
            up.lineJoinStyle = .round
            (outActive ? NSColor.systemPurple : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            up.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws dynamic Disk Read / Write Activity LEDs (`R` and `W`) with signature colors.
    public static func drawDiskActivityLeds(readBytes: Double, writeBytes: Double) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let rActive = readBytes > 10240.0
            let wActive = writeBytes > 10240.0

            let font = NSFont.systemFont(ofSize: 9.5, weight: .black)

            // Read badge (Blue)
            let rBadge = NSBezierPath(roundedRect: NSRect(x: 1.0, y: 2.0, width: 8.5, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            if rActive {
                NSColor.systemBlue.setFill()
                rBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                ("R" as NSString).draw(at: NSPoint(x: 2.2, y: 3.0), withAttributes: attrs)
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                rBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.40)]
                ("R" as NSString).draw(at: NSPoint(x: 2.2, y: 3.0), withAttributes: attrs)
            }

            // Write badge (Red)
            let wBadge = NSBezierPath(roundedRect: NSRect(x: 10.5, y: 2.0, width: 8.5, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            if wActive {
                NSColor.systemRed.setFill()
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
        return image
    }

    // MARK: - Compatibility Drawings, Rationalized Instruments & Decay-Max Scaler

    /// Computes the dynamic scaling ceiling for unbounded series with a minimum floor.
    /// Uses peak value in recent window with decay-max protection against flattening spikes.
    public static func computeDecayMax(values: [Double], floor: Double) -> Double {
        let peak = values.max() ?? floor
        return max(peak, floor)
    }

    public static func drawCPUSymbol(usage: Double? = nil) -> NSImage {
        drawTriSegmentPie(ratio: usage)
    }

    public static func drawCPUGauge(percentage: Double) -> NSImage {
        drawCPUDonutPie(user: percentage, system: 0.0)
    }

    public static func drawCPUSparkline(history: [Double]) -> NSImage {
        drawColoredSparkline(values: history, maxValue: 100.0, strokeColor: NSColor.systemBlue, fillColor: NSColor.systemBlue.withAlphaComponent(0.25))
    }

    public static func drawCPUBar(percentage: Double, user: Double? = nil, system: Double? = nil) -> NSImage {
        drawCPUBar(perCore: nil, user: user ?? percentage, system: system)
    }

    public static func drawMemorySymbol(ratio: Double? = nil, pressure: MemoryPressure? = nil) -> NSImage {
        drawMemoryPressureBadge(pressure: pressure)
    }

    /// Draws dedicated 3-state Memory Pressure Pill/Badge (OK / WARN / CRIT) with high-DPI micro-indicators.
    public static func drawMemoryPressureBadge(pressure: MemoryPressure?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let p = pressure ?? .normal

            // Outer capsule pill container (14w x 16h)
            let pillRect = NSRect(x: center.x - 7.0, y: center.y - 8.0, width: 14.0, height: 16.0)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: 3.5, yRadius: 3.5)
            NSColor.labelColor.withAlphaComponent(0.15).setStroke()
            pill.lineWidth = 1.0
            pill.stroke()

            // 3 horizontal stepped bars rising from bottom to top
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
        return image
    }

    public static func drawMemoryGauge(ratio: Double) -> NSImage {
        drawMemoryDonutPie(sample: nil, ratio: ratio)
    }

    public static func drawMemoryBar(ratio: Double) -> NSImage {
        drawSingleCapsuleBar(label: "RAM", percentage: ratio, barColor: .systemGreen)
    }

    public static func drawMemorySparkline(history: [Double], pressure: MemoryPressure? = nil) -> NSImage {
        let p = pressure ?? .normal
        let col: NSColor = (p == .critical) ? .systemRed : ((p == .warning) ? .systemYellow : .systemGreen)
        return drawColoredSparkline(values: history, maxValue: 100.0, strokeColor: col, fillColor: col.withAlphaComponent(0.25))
    }

    public static func drawGPUSymbol(utilization: Double? = nil, tempCelsius: Double? = nil) -> NSImage {
        drawGPUDieSymbol(utilization: utilization, tempCelsius: tempCelsius)
    }

    /// Draws authentic mini GPU silicon die glyph with load fill level, temperature-tinted hue, and package outline.
    public static func drawGPUDieSymbol(utilization: Double? = nil, tempCelsius: Double? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let util = min(max(utilization ?? 0.0, 0.0), 100.0)

            // 1. Silicon Package Frame (14×14 pt rounded square)
            let frameRect = NSRect(x: center.x - 7.0, y: center.y - 7.0, width: 14.0, height: 14.0)
            let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 2.5, yRadius: 2.5)

            // Package substrate background
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            framePath.fill()

            // Substrate border
            framePath.lineWidth = 1.0
            NSColor.labelColor.withAlphaComponent(0.40).setStroke()
            framePath.stroke()

            // 2. Micro Chip Perimeter Pins (Left & Right notch ticks)
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

            // 3. Inner Silicon Die Cavity (10×10 pt)
            let dieRect = NSRect(x: center.x - 5.0, y: center.y - 5.0, width: 10.0, height: 10.0)
            let dieClip = NSBezierPath(roundedRect: dieRect, xRadius: 1.5, yRadius: 1.5)

            NSGraphicsContext.saveGraphicsState()
            dieClip.addClip()

            // Unfilled die base
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            dieClip.fill()

            // Active core utilization fill from bottom up
            let col = (tempCelsius != nil) ? thermalColor(for: tempCelsius!) : NSColor.systemPurple
            if util > 0 {
                let fillH = max(dieRect.height * CGFloat(util / 100.0), 1.5)
                let fillRect = NSRect(x: dieRect.minX, y: dieRect.minY, width: dieRect.width, height: fillH)
                col.setFill()
                fillRect.fill()
            }

            // Micro-grid silicon lattice lines
            let gridPath = NSBezierPath()
            gridPath.move(to: NSPoint(x: center.x, y: dieRect.minY))
            gridPath.line(to: NSPoint(x: center.x, y: dieRect.maxY))
            gridPath.move(to: NSPoint(x: dieRect.minX, y: center.y))
            gridPath.line(to: NSPoint(x: dieRect.maxX, y: center.y))
            gridPath.lineWidth = 0.5
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            gridPath.stroke()

            NSGraphicsContext.restoreGraphicsState()

            // Die cavity border
            dieClip.lineWidth = 0.8
            col.withAlphaComponent(0.60).setStroke()
            dieClip.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawGPUGauge(percentage: Double, tempCelsius: Double? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 2.8

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

                let strokeColor = (tempCelsius != nil) ? thermalColor(for: tempCelsius!) : NSColor.systemPurple
                strokeColor.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawGPUBar(percentage: Double) -> NSImage {
        drawSingleCapsuleBar(label: "GPU", percentage: percentage, barColor: .systemPurple)
    }

    public static func drawGPUSparkline(history: [Double]) -> NSImage {
        drawColoredSparkline(values: history, maxValue: 100.0, strokeColor: NSColor.systemPurple, fillColor: NSColor.systemPurple.withAlphaComponent(0.25))
    }

    public static func thermalColor(for celsius: Double) -> NSColor {
        if celsius >= 85.0 {
            return NSColor.systemRed
        } else if celsius >= 70.0 {
            return NSColor.systemOrange
        } else if celsius >= 50.0 {
            return NSColor.systemYellow
        } else {
            return NSColor.systemGreen
        }
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
            let lineWidth: CGFloat = 2.8

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
                let c = celsius ?? (30.0 + (clamped / 100.0) * 70.0)
                thermalColor(for: c).setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawThermalBar(percentage: Double, celsius: Double? = nil) -> NSImage {
        let c = celsius ?? (30.0 + (min(max(percentage, 0.0), 100.0) / 100.0) * 70.0)
        let col = thermalColor(for: c)
        return drawSingleCapsuleBar(label: "TMP", percentage: percentage, barColor: col)
    }

    public static func drawThermalSparkline(history: [Double]) -> NSImage {
        let maxVal = max(history.max() ?? 100.0, 100.0)
        let latest = history.last ?? 50.0
        let col = thermalColor(for: latest)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: col, fillColor: col.withAlphaComponent(0.25))
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

    /// Draws high-DPI 240° instrument-cluster Speed Tachometer with graduation ticks, progressive cyan arc, and pointer needle.
    public static func drawFanTachometer(percentage: Double, rpm: Int? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 6.8
            let lineWidth: CGFloat = 2.2

            let startAngle: CGFloat = 215.0
            let totalSpan: CGFloat = 250.0
            let endAngle: CGFloat = startAngle - totalSpan // -35°

            // 1. Background full gauge track
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            track.lineWidth = lineWidth
            track.lineCapStyle = .round
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            // 2. Dial tick marks at 0%, 50%, 100%
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

            // 3. Active speed arc
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

            // 4. Center hub and pointer needle
            let hub = NSBezierPath(ovalIn: NSRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6))
            (clamped > 0 ? NSColor.systemCyan : NSColor.secondaryLabelColor.withAlphaComponent(0.60)).setFill()
            hub.fill()

            // Needle
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

    /// Draws aerodynamic 4-blade fan turbine with dynamic speed-responsive cyan blade fill and central spinner hub.
    public static func drawFanBlades(percentage: Double, rpm: Int? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let outerRadius: CGFloat = 7.5
            let hubRadius: CGFloat = 2.4

            // 1. Shroud outer bezel ring
            let shroud = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.2, dy: 1.2))
            shroud.lineWidth = 1.0
            NSColor.secondaryLabelColor.withAlphaComponent(0.28).setStroke()
            shroud.stroke()

            let isActive = (rpm ?? 0) > 0 || percentage > 0.0
            let clamped = min(max(percentage, 0.0), 100.0)

            // 2. 4 Aerodynamic Curved Turbine Blades
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
                // Curved leading edge
                let ctrl1 = NSPoint(x: center.x + cos(tipAngle - 0.1) * (outerRadius * 0.7), y: center.y + sin(tipAngle - 0.1) * (outerRadius * 0.7))
                path.curve(to: pTip, controlPoint1: pRoot, controlPoint2: ctrl1)
                // Curved trailing edge back to hub
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

            // 3. Central Spinner Hub
            let hubRect = NSRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2.0, height: hubRadius * 2.0)
            let hub = NSBezierPath(ovalIn: hubRect)
            if isActive {
                NSColor.systemCyan.setFill()
                hub.fill()

                // Center micro pin
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

    public static func drawFanSparkline(history: [Double]) -> NSImage {
        let maxVal = max(history.max() ?? 6000.0, 2000.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: NSColor.systemCyan, fillColor: NSColor.systemCyan.withAlphaComponent(0.25))
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
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: NSColor.systemBlue, fillColor: NSColor.systemBlue.withAlphaComponent(0.25))
    }

    public static func drawDiskSymbol(readBytes: Double? = nil, writeBytes: Double? = nil) -> NSImage {
        drawDiskActivityLeds(readBytes: readBytes ?? 0.0, writeBytes: writeBytes ?? 0.0)
    }

    public static func drawDiskGauge(percentage: Double) -> NSImage {
        drawCircularGauge(percentage: percentage, iconName: "internaldrive")
    }

    /// Draws boot volume storage capacity used-% capsule bar (Linear capacity).
    public static func drawDiskBar(percentage: Double) -> NSImage {
        drawSingleCapsuleBar(
            label: "SSD",
            percentage: percentage,
            barColor: .systemIndigo
        )
    }

    public static func drawDiskBar(readPct: Double, writePct: Double) -> NSImage {
        drawDualCapsuleBar(
            label: "SSD",
            leftPercentage: readPct,
            rightPercentage: writePct,
            leftColor: .systemIndigo,
            rightColor: .systemPurple
        )
    }

    public static func drawDiskSparkline(history: [Double]) -> NSImage {
        let maxVal = computeDecayMax(values: history, floor: 10.0 * 1024.0 * 1024.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: NSColor.systemIndigo, fillColor: NSColor.systemIndigo.withAlphaComponent(0.25))
    }

    public static func drawPowerSymbol(
        charge: Double? = nil,
        state: BatteryState? = nil,
        hasBattery: Bool = true
    ) -> NSImage {
        drawBatteryInstrument(charge: charge, state: state, hasBattery: hasBattery)
    }

    /// Draws 2-line stacked live power draw wattage over adapter capacity (e.g. `28W` over `68W`).
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

    public static func drawPowerGauge(percentage: Double, isCharging: Bool = false) -> NSImage {
        drawCircularGauge(percentage: percentage, iconName: isCharging ? "bolt.fill" : "battery.100percent")
    }

    public static func drawPowerBar(percentage: Double, isCharging: Bool = false) -> NSImage {
        let clamped = min(max(percentage, 0.0), 100.0)
        let color: NSColor = clamped <= 20.0 ? NSColor.systemRed : (clamped <= 40.0 ? NSColor.systemYellow : NSColor.systemGreen)
        return drawSingleCapsuleBar(label: "BAT", percentage: percentage, barColor: color)
    }

    public static func drawPowerSparkline(history: [Double]) -> NSImage {
        let maxVal = computeDecayMax(values: history, floor: 5.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: NSColor.systemGreen, fillColor: NSColor.systemGreen.withAlphaComponent(0.25))
    }

    /// Generic circular gauge template.
    public static func drawCircularGauge(
        percentage: Double,
        iconName: String? = nil
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 7.2
            let lineWidth: CGFloat = 2.8

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
                NSColor.labelColor.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
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
        fillColor: NSColor
    ) -> NSImage {
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

