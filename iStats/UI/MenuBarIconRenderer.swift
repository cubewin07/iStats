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

        public init(image: NSImage? = nil, title: String = "", toolTip: String = "") {
            self.image = image
            self.title = title
            self.toolTip = toolTip
        }
    }

    /// Primary entry point: renders image, title, and tooltip for a given menu bar item configuration.
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
            let history = coordinator.thermalHistory.compactMap { $0.value.sensors.first?.celsius }
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
            let history = coordinator.powerHistory.compactMap { $0.value.charge }
            return renderPower(style: config.style, power: power, history: history)
        }
    }

    // MARK: - 1. CPU Rendering

    private static func renderCPU(style: MetricDisplayStyle, cpu: CPUSample?, history: [Double]) -> RenderResult {
        let usage = cpu?.totalUsage ?? 0.0
        let tip = cpu != nil ? String(format: "CPU: %.1f%% (User: %.1f%%, Sys: %.1f%%)", cpu!.totalUsage, cpu!.user, cpu!.system) : "CPU: --%"
        let valStr = cpu != nil ? String(format: "%.0f%%", usage) : "--%"

        switch style {
        case .gauge:
            // Segmented Donut Pie (User vs Kernel load) with vibrant signature colors
            let img = drawCPUDonutPie(user: cpu?.user ?? usage, system: cpu?.system ?? 0.0)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            // Live Per-Core Micro-Bar Cluster (or stacked bar)
            let img = drawCPUBar(perCore: cpu?.perCore, user: cpu?.user, system: cpu?.system)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            // Real-Time Scrolling History Graph with signature blue gradient
            let img = drawCPUSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        case .throughput, .text:
            // Invariant Jitter-Free Stacked Text (CPU over Usage%)
            let img = drawCategoryStackedText(title: "CPU", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip)
        case .symbol:
            // Activity Instrument (Tri-Segment / 3-Blade Pie)
            let img = drawCPUSymbol(usage: usage)
            return RenderResult(image: img, toolTip: tip)
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
        if let mem = memory {
            let usedStr = Units.formatBytes(mem.used, standard: standard)
            let totalStr = Units.formatBytes(mem.total, standard: standard)
            tip = "MEM: \(usedStr) / \(totalStr) (\(String(format: "%.1f%%", ratio))) - Pressure: \(mem.pressure.displayName)"
        } else {
            tip = "MEM: --%"
        }

        let valStr = memory != nil ? String(format: "%.0f%%", ratio) : "--%"

        switch style {
        case .gauge:
            // Memory Breakdown Donut Ring (Wired / Active / Compressed / Free)
            let img = drawMemoryDonutPie(sample: memory, ratio: ratio)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            // Segmented Stacked Memory Bar
            let img = drawMemoryStackedBar(sample: memory, ratio: ratio)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            // Rolling Memory History Graph
            let img = drawMemorySparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        case .throughput, .text:
            // Two-Line Jitter-Free Stacked Text (MEM / Used %)
            let img = drawCategoryStackedText(title: "MEM", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip)
        case .symbol:
            // Activity Instrument (Tri-Segment Pie)
            let img = drawMemorySymbol(ratio: ratio, pressure: memory?.pressure)
            return RenderResult(image: img, toolTip: tip)
        }
    }

    // MARK: - 3. GPU Rendering

    private static func renderGPU(style: MetricDisplayStyle, gpu: GPUSample?, history: [Double]) -> RenderResult {
        let util = gpu?.utilization ?? 0.0
        let tip = gpu != nil ? String(format: "GPU: %.1f%%", util) : "GPU: --%"
        let valStr = gpu?.utilization != nil ? String(format: "%.0f%%", util) : "--%"

        switch style {
        case .gauge:
            let img = drawGPUGauge(percentage: util)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawGPUBar(percentage: util)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawGPUSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        case .throughput, .text:
            let img = drawCategoryStackedText(title: "GPU", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip)
        case .symbol:
            let img = drawGPUSymbol(utilization: gpu?.utilization)
            return RenderResult(image: img, toolTip: tip)
        }
    }

    // MARK: - 4. Thermal Rendering

    private static func renderThermal(
        style: MetricDisplayStyle,
        thermal: ThermalSample?,
        history: [Double],
        unit: Units.TemperatureUnit
    ) -> RenderResult {
        let sensor = thermal?.sensors.first(where: { $0.name.contains("Package") || $0.name.contains("CPU") || $0.name.contains("SoC") }) ?? thermal?.sensors.first
        let tempC = sensor?.celsius ?? 0.0
        let pct = min(max((tempC - 30.0) / (100.0 - 30.0) * 100.0, 0.0), 100.0)
        let tip = sensor != nil ? "Thermal: \(Units.formatTemperature(tempC, unit: unit, fractionDigits: 1))" : "Thermal: --"
        let valStr = sensor != nil ? (unit == .celsius ? String(format: "%.0f°", tempC) : String(format: "%.0f°", Units.celsiusToFahrenheit(tempC))) : (unit == .celsius ? "--°" : "--°")

        switch style {
        case .gauge:
            let img = drawThermalGauge(percentage: pct, celsius: sensor?.celsius)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawThermalBar(percentage: pct, celsius: sensor?.celsius)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawThermalSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        case .throughput, .text:
            let img = drawCategoryStackedText(title: "CPU", value: valStr, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip)
        case .symbol:
            let img = drawThermalSymbol(celsius: sensor?.celsius)
            return RenderResult(image: img, toolTip: tip)
        }
    }

    // MARK: - 5. Fan Rendering

    private static func renderFan(style: MetricDisplayStyle, fan: FanSample?, history: [Double]) -> RenderResult {
        let primaryFan = fan?.fans.first
        let rpm = primaryFan?.rpm ?? 0
        let tip = primaryFan != nil ? "Fans: \(rpm) RPM (\(primaryFan!.name))" : "Fans: -- RPM"

        let pct: Double
        if let f = primaryFan, let max = f.maxRPM, let min = f.minRPM, max > min {
            pct = Double(f.rpm - min) / Double(max - min) * 100.0
        } else if let f = primaryFan, let max = f.maxRPM, max > 0 {
            pct = Double(f.rpm) / Double(max) * 100.0
        } else {
            pct = min(Double(rpm) / 6000.0 * 100.0, 100.0)
        }

        let fanVal = primaryFan != nil ? (rpm >= 1000 ? String(format: "%.1fk", Double(rpm)/1000.0) : "\(rpm)") : "--"

        switch style {
        case .gauge:
            let img = drawFanGauge(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawFanBar(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawFanSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        case .throughput, .text:
            let img = drawCategoryStackedText(title: "FAN", value: fanVal, fixedWidth: 32.0)
            return RenderResult(image: img, toolTip: tip)
        case .symbol:
            let img = drawFanSymbol(rpm: primaryFan?.rpm, percentage: pct)
            return RenderResult(image: img, toolTip: tip)
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
        let tip = "Network: ↓ \(Units.formatNetworkRate(inBytes, unit: unit, standard: standard, fractionDigits: 1))  ↑ \(Units.formatNetworkRate(outBytes, unit: unit, standard: standard, fractionDigits: 1))"

        let total = inBytes + outBytes
        let pct = min((total / (10 * 1024 * 1024)) * 100.0, 100.0)
        let inPct = min((inBytes / (10 * 1024 * 1024)) * 100.0, 100.0)
        let outPct = min((outBytes / (10 * 1024 * 1024)) * 100.0, 100.0)

        switch style {
        case .throughput, .text:
            // Signature iStat Menus 2-Line Stacked Download (↓) & Upload (↑) Speeds
            let img = drawNetworkStackedThroughput(inBytes: inBytes, outBytes: outBytes, unit: unit, standard: standard)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            // Signature iStat Menus Split Duplex Graph (Download top half, Upload bottom half)
            let img = drawNetworkSplitDuplexGraph(inHistory: inHistory, outHistory: outHistory)
            return RenderResult(image: img, toolTip: tip)
        case .symbol:
            // Dynamic Dual Activity Arrows
            let img = drawNetworkActivityArrows(inBytes: inBytes, outBytes: outBytes)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            // Dual In/Out Saturation Bars
            let img = drawNetworkBar(inPct: inPct, outPct: outPct)
            return RenderResult(image: img, toolTip: tip)
        case .gauge:
            let img = drawNetworkGauge(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
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
        let tip = "Disk I/O: Read \(Units.formatDiskRate(readBytes, standard: standard, fractionDigits: 1)), Write \(Units.formatDiskRate(writeBytes, standard: standard, fractionDigits: 1))"

        let readPct = min((readBytes / (50 * 1024 * 1024)) * 100.0, 100.0)
        let writePct = min((writeBytes / (50 * 1024 * 1024)) * 100.0, 100.0)

        // Volume capacity ratio
        let primaryVol = disk?.volumes.first(where: { $0.mountPoint == "/" }) ?? disk?.volumes.first
        let volRatio: Double = (primaryVol != nil && primaryVol!.total > 0)
            ? (Double(primaryVol!.used) / Double(primaryVol!.total)) * 100.0
            : 0.0

        switch style {
        case .throughput, .text:
            // Two-Line Stacked Read / Write Speeds
            let img = drawDiskStackedThroughput(readBytes: readBytes, writeBytes: writeBytes, standard: standard)
            return RenderResult(image: img, toolTip: tip)
        case .symbol:
            // Dynamic Read / Write Activity LEDs
            let img = drawDiskActivityLeds(readBytes: readBytes, writeBytes: writeBytes)
            return RenderResult(image: img, toolTip: tip)
        case .gauge:
            // Volume Capacity Donut Pie
            let img = drawCircularGauge(percentage: volRatio, iconName: "internaldrive")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            // Dual Read / Write Activity Bars
            let img = drawDiskBar(readPct: readPct, writePct: writePct)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawDiskSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        }
    }

    // MARK: - 8. Power Rendering

    private static func renderPower(style: MetricDisplayStyle, power: PowerSample?, history: [Double]) -> RenderResult {
        let charge = power?.charge ?? 0.0
        let tip: String
        if let pwr = power {
            if pwr.hasBattery {
                let stateStr = pwr.state == .charging ? " (Charging)" : ""
                tip = String(format: "Battery: %.0f%%%@", charge, stateStr)
            } else {
                tip = "Power: Connected to AC"
            }
        } else {
            tip = "Battery: --%"
        }

        let isCharging = power?.state == .charging
        let hasBattery = power?.hasBattery ?? true

        switch style {
        case .symbol:
            // Authentic Battery Shell Instrument with Live Fill & Charging Bolt
            let img = drawBatteryInstrument(charge: power?.charge, state: power?.state, hasBattery: hasBattery)
            return RenderResult(image: img, toolTip: tip)
        case .throughput, .text:
            // Two-Line Stacked Battery Charge% + Time Remaining / Wattage
            let img = drawPowerStackedText(charge: power?.charge, state: power?.state, timeRemaining: power?.timeRemaining, watts: power?.powerDrawWatts)
            return RenderResult(image: img, toolTip: tip)
        case .gauge:
            let img = drawPowerGauge(percentage: charge, isCharging: isCharging)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawPowerBar(percentage: charge, isCharging: isCharging)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawPowerSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
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

    /// Draws authentic iStat Menus 2-line stacked typography with right-aligned tabular numbers.
    public static func drawStackedText(
        line1: String,
        line2: String,
        minWidth: CGFloat = 0.0,
        color1: NSColor? = nil,
        color2: NSColor? = nil
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
        let attrs1: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color1 ?? NSColor.labelColor
        ]
        let attrs2: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color2 ?? NSColor.labelColor
        ]

        let s1 = (line1 as NSString).size(withAttributes: attrs1)
        let s2 = (line2 as NSString).size(withAttributes: attrs2)
        let textWidth = max(s1.width, s2.width)
        let canvasWidth = max(textWidth + 4.0, minWidth)
        let size = NSSize(width: canvasWidth, height: 22)

        let image = NSImage(size: size, flipped: false) { bounds in
            let p1 = NSPoint(x: max(1.0, bounds.width - s1.width - 2.0), y: 11.5)
            let p2 = NSPoint(x: max(1.0, bounds.width - s2.width - 2.0), y: 2.0)

            (line1 as NSString).draw(at: p1, withAttributes: attrs1)
            (line2 as NSString).draw(at: p2, withAttributes: attrs2)
            return true
        }
        image.isTemplate = (color1 == nil && color2 == nil)
        return image
    }

    /// Draws the signature iStat Menus 2-line stacked network bandwidth throughput (`↓ In` over `↑ Out`).
    public static func drawNetworkStackedThroughput(
        inBytes: Double,
        outBytes: Double,
        unit: Units.NetworkUnit,
        standard: Units.ByteUnitStandard
    ) -> NSImage {
        let inStr = Units.formatNetworkRate(inBytes, unit: unit, standard: standard, fractionDigits: 0)
        let outStr = Units.formatNetworkRate(outBytes, unit: unit, standard: standard, fractionDigits: 0)
        let l1 = "↓ \(inStr)"
        let l2 = "↑ \(outStr)"
        return drawStackedText(line1: l1, line2: l2, minWidth: 44.0)
    }

    /// Draws the signature iStat Menus 2-line stacked disk I/O throughput (`R read` over `W write`).
    public static func drawDiskStackedThroughput(
        readBytes: Double,
        writeBytes: Double,
        standard: Units.ByteUnitStandard
    ) -> NSImage {
        let readStr = Units.formatDiskRate(readBytes, standard: standard, fractionDigits: 0)
        let writeStr = Units.formatDiskRate(writeBytes, standard: standard, fractionDigits: 0)
        let l1 = "R \(readStr)"
        let l2 = "W \(writeStr)"
        return drawStackedText(line1: l1, line2: l2, minWidth: 44.0)
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

    /// Draws modern capsule load bar for Memory / RAM (with vertical "RAM" category label).
    public static func drawMemoryStackedBar(sample: MemorySample?, ratio: Double) -> NSImage {
        drawSingleCapsuleBar(label: "RAM", percentage: ratio)
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

    // MARK: - Compatibility Drawings & Helpers

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
        drawTriSegmentPie(ratio: ratio)
    }

    public static func drawMemoryGauge(ratio: Double) -> NSImage {
        drawMemoryDonutPie(sample: nil, ratio: ratio)
    }

    public static func drawMemoryBar(ratio: Double) -> NSImage {
        drawSingleCapsuleBar(label: "RAM", percentage: ratio, barColor: .systemGreen)
    }

    public static func drawMemorySparkline(history: [Double]) -> NSImage {
        drawColoredSparkline(values: history, maxValue: 100.0, strokeColor: NSColor.systemGreen, fillColor: NSColor.systemGreen.withAlphaComponent(0.25))
    }

    public static func drawGPUSymbol(utilization: Double? = nil) -> NSImage {
        drawGPUGauge(percentage: utilization ?? 0.0)
    }

    public static func drawGPUGauge(percentage: Double) -> NSImage {
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
                NSColor.systemPurple.setStroke()
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

    private static func thermalColor(for celsius: Double) -> NSColor {
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
        drawFanGauge(percentage: percentage ?? 0.0)
    }

    public static func drawFanGauge(percentage: Double) -> NSImage {
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
                NSColor.systemCyan.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawFanBar(percentage: Double) -> NSImage {
        drawSingleCapsuleBar(label: "FAN", percentage: percentage, barColor: .systemCyan)
    }

    public static func drawFanSparkline(history: [Double]) -> NSImage {
        let maxVal = max(history.max() ?? 6000.0, 2000.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: NSColor.systemCyan, fillColor: NSColor.systemCyan.withAlphaComponent(0.25))
    }

    public static func drawNetworkSymbol(inBytes: Double? = nil, outBytes: Double? = nil) -> NSImage {
        drawNetworkActivityArrows(inBytes: inBytes ?? 0.0, outBytes: outBytes ?? 0.0)
    }

    public static func drawNetworkGauge(percentage: Double) -> NSImage {
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
                NSColor.systemTeal.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    public static func drawNetworkBar(inPct: Double, outPct: Double) -> NSImage {
        drawDualCapsuleBar(
            label: "NET",
            leftPercentage: inPct,
            rightPercentage: outPct,
            leftColor: .systemTeal,
            rightColor: .systemBlue
        )
    }

    public static func drawNetworkSparkline(history: [Double]) -> NSImage {
        let maxVal = max(history.max() ?? 1024.0, 1024.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: NSColor.systemBlue, fillColor: NSColor.systemBlue.withAlphaComponent(0.25))
    }

    public static func drawDiskSymbol(readBytes: Double? = nil, writeBytes: Double? = nil) -> NSImage {
        drawDiskActivityLeds(readBytes: readBytes ?? 0.0, writeBytes: writeBytes ?? 0.0)
    }

    public static func drawDiskGauge(percentage: Double) -> NSImage {
        drawCircularGauge(percentage: percentage, iconName: "internaldrive")
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
        let maxVal = max(history.max() ?? 1024.0, 1024.0)
        return drawColoredSparkline(values: history, maxValue: maxVal, strokeColor: NSColor.systemBlue, fillColor: NSColor.systemBlue.withAlphaComponent(0.25))
    }

    public static func drawPowerSymbol(
        charge: Double? = nil,
        state: BatteryState? = nil,
        hasBattery: Bool = true
    ) -> NSImage {
        drawBatteryInstrument(charge: charge, state: state, hasBattery: hasBattery)
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
        drawColoredSparkline(values: history, maxValue: 100.0, strokeColor: NSColor.systemGreen, fillColor: NSColor.systemGreen.withAlphaComponent(0.25))
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

