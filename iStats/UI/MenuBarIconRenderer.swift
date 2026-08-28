import AppKit
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

        switch style {
        case .gauge:
            // Segmented Donut Pie (User vs Kernel load)
            let img = drawCPUDonutPie(user: cpu?.user ?? usage, system: cpu?.system ?? 0.0)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            // Live Per-Core Micro-Bar Cluster (or stacked bar)
            let img = drawCPUBar(perCore: cpu?.perCore, user: cpu?.user, system: cpu?.system)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            // Real-Time Scrolling History Graph
            let img = drawCPUSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        case .throughput:
            // Two-Line Stacked Text (CPU / Usage%)
            let l1 = "CPU"
            let l2 = cpu != nil ? String(format: "%.0f%%", usage) : "--%"
            let img = drawStackedText(line1: l1, line2: l2)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let text = cpu != nil ? String(format: "CPU %.0f%%", usage) : "CPU --%"
            return RenderResult(title: text, toolTip: tip)
        case .symbol:
            // Activity Instrument (Donut with core dot)
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
            tip = "RAM: \(usedStr) / \(totalStr) (\(String(format: "%.1f%%", ratio))) - Pressure: \(mem.pressure.displayName)"
        } else {
            tip = "RAM: --%"
        }

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
        case .throughput:
            // Two-Line Stacked Text (RAM / Used GB or %)
            let l1 = "RAM"
            let l2 = memory != nil ? (Units.formatBytes(memory!.used, standard: standard, fractionDigits: 1)) : "--"
            let img = drawStackedText(line1: l1, line2: l2)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let text = memory != nil ? String(format: "RAM %.0f%%", ratio) : "RAM --%"
            return RenderResult(title: text, toolTip: tip)
        case .symbol:
            // Activity Instrument
            let img = drawMemorySymbol(ratio: ratio, pressure: memory?.pressure)
            return RenderResult(image: img, toolTip: tip)
        }
    }

    // MARK: - 3. GPU Rendering

    private static func renderGPU(style: MetricDisplayStyle, gpu: GPUSample?, history: [Double]) -> RenderResult {
        let util = gpu?.utilization ?? 0.0
        let tip = gpu != nil ? String(format: "GPU: %.1f%%", util) : "GPU: --%"

        switch style {
        case .gauge:
            let img = drawCircularGauge(percentage: util, iconName: "display")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawGPUBar(percentage: util)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawGPUSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        case .throughput:
            let l1 = "GPU"
            let l2 = gpu?.utilization != nil ? String(format: "%.0f%%", util) : "--%"
            let img = drawStackedText(line1: l1, line2: l2)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let text = gpu?.utilization != nil ? String(format: "GPU %.0f%%", util) : "GPU --%"
            return RenderResult(title: text, toolTip: tip)
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

        switch style {
        case .gauge:
            let img = drawThermalGauge(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawThermalBar(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawThermalSparkline(history: history)
            return RenderResult(image: img, toolTip: tip)
        case .throughput:
            let l1 = "CPU"
            let l2 = sensor != nil ? Units.formatTemperature(tempC, unit: unit, fractionDigits: 0) : "--"
            let img = drawStackedText(line1: l1, line2: l2)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let text = sensor != nil ? Units.formatTemperature(tempC, unit: unit, fractionDigits: 0) : (unit == .celsius ? "--°C" : "--°F")
            return RenderResult(title: text, toolTip: tip)
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
        case .throughput:
            let l1 = "FAN"
            let l2 = primaryFan != nil ? (rpm >= 1000 ? String(format: "%.1fk", Double(rpm)/1000.0) : "\(rpm)") : "--"
            let img = drawStackedText(line1: l1, line2: l2)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let text = primaryFan != nil ? "\(rpm) RPM" : "-- RPM"
            return RenderResult(title: text, toolTip: tip)
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
        let inStr = Units.formatNetworkRate(inBytes, unit: unit, standard: standard, fractionDigits: 0)
        let outStr = Units.formatNetworkRate(outBytes, unit: unit, standard: standard, fractionDigits: 0)
        let tip = "Network: ↓ \(Units.formatNetworkRate(inBytes, unit: unit, standard: standard, fractionDigits: 1))  ↑ \(Units.formatNetworkRate(outBytes, unit: unit, standard: standard, fractionDigits: 1))"

        let total = inBytes + outBytes
        let pct = min((total / (10 * 1024 * 1024)) * 100.0, 100.0) // Scale to 10 MB/s
        let inPct = min((inBytes / (10 * 1024 * 1024)) * 100.0, 100.0)
        let outPct = min((outBytes / (10 * 1024 * 1024)) * 100.0, 100.0)

        switch style {
        case .throughput:
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
        case .text:
            let text = network != nil ? "↓ \(inStr) ↑ \(outStr)" : "Net --"
            return RenderResult(title: text, toolTip: tip)
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
        let readStr = Units.formatDiskRate(readBytes, standard: standard, fractionDigits: 0)
        let writeStr = Units.formatDiskRate(writeBytes, standard: standard, fractionDigits: 0)
        let tip = "Disk I/O: Read \(Units.formatDiskRate(readBytes, standard: standard, fractionDigits: 1)), Write \(Units.formatDiskRate(writeBytes, standard: standard, fractionDigits: 1))"

        let readPct = min((readBytes / (50 * 1024 * 1024)) * 100.0, 100.0)
        let writePct = min((writeBytes / (50 * 1024 * 1024)) * 100.0, 100.0)

        // Volume capacity ratio
        let primaryVol = disk?.volumes.first(where: { $0.mountPoint == "/" }) ?? disk?.volumes.first
        let volRatio: Double = (primaryVol != nil && primaryVol!.total > 0)
            ? (Double(primaryVol!.used) / Double(primaryVol!.total)) * 100.0
            : 0.0

        switch style {
        case .throughput:
            // Two-Line Stacked Read / Write Speeds
            let l1 = "R \(readStr)"
            let l2 = "W \(writeStr)"
            let img = drawStackedText(line1: l1, line2: l2)
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
        case .text:
            let text = disk?.io != nil ? "R: \(readStr) W: \(writeStr)" : "Disk --"
            return RenderResult(title: text, toolTip: tip)
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
        case .throughput:
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
        case .text:
            if let pwr = power {
                if !pwr.hasBattery {
                    return RenderResult(title: "AC", toolTip: tip)
                } else {
                    let bolt = (pwr.state == .charging) ? " ⚡" : ""
                    return RenderResult(title: String(format: "%.0f%%%@", charge, bolt), toolTip: tip)
                }
            } else {
                return RenderResult(title: "Bat --%", toolTip: tip)
            }
        }
    }

    // MARK: - Core iStat Menus Instrument Drawing Primitives

    /// Draws authentic iStat Menus 2-line stacked high-density monospaced typography (8.5 pt).
    public static func drawStackedText(
        line1: String,
        line2: String,
        minWidth: CGFloat = 0.0
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
        let attrs1: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attrs2: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        let s1 = (line1 as NSString).size(withAttributes: attrs1)
        let s2 = (line2 as NSString).size(withAttributes: attrs2)
        let textWidth = max(s1.width, s2.width)
        let canvasWidth = max(textWidth + 3.0, minWidth)
        let size = NSSize(width: canvasWidth, height: 18)

        let image = NSImage(size: size, flipped: false) { bounds in
            let p1 = NSPoint(x: bounds.maxX - s1.width - 1.0, y: 9.0)
            let p2 = NSPoint(x: bounds.maxX - s2.width - 1.0, y: 0.5)

            (line1 as NSString).draw(at: p1, withAttributes: attrs1)
            (line2 as NSString).draw(at: p2, withAttributes: attrs2)
            return true
        }
        image.isTemplate = true
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
        return drawStackedText(line1: l1, line2: l2, minWidth: 38.0)
    }

    /// Draws the signature iStat Menus split duplex history graph (Download above midline, Upload below midline).
    public static func drawNetworkSplitDuplexGraph(
        inHistory: [Double],
        outHistory: [Double]
    ) -> NSImage {
        let size = NSSize(width: 34, height: 14)
        let image = NSImage(size: size, flipped: false) { bounds in
            let midY: CGFloat = 7.0

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

            // 1. Inbound (Download) - Waves scrolling above midline (y in [7.0, 13.5])
            if inHistory.count >= 2 {
                let inFill = NSBezierPath()
                let inLine = NSBezierPath()
                inFill.move(to: NSPoint(x: 1.0, y: midY))

                for (idx, val) in inHistory.enumerated() {
                    let clamped = min(max(val, 0.0), inMax)
                    let h = CGFloat(clamped / inMax) * 6.0
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
                NSColor.labelColor.withAlphaComponent(0.25).setFill()
                inFill.fill()

                inLine.lineWidth = 1.1
                inLine.lineJoinStyle = .round
                NSColor.labelColor.setStroke()
                inLine.stroke()
            }

            // 2. Outbound (Upload) - Waves scrolling below midline (y in [0.5, 7.0])
            if outHistory.count >= 2 {
                let outFill = NSBezierPath()
                let outLine = NSBezierPath()
                outFill.move(to: NSPoint(x: 1.0, y: midY))

                for (idx, val) in outHistory.enumerated() {
                    let clamped = min(max(val, 0.0), outMax)
                    let h = CGFloat(clamped / outMax) * 6.0
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
                NSColor.labelColor.withAlphaComponent(0.20).setFill()
                outFill.fill()

                outLine.lineWidth = 1.1
                outLine.lineJoinStyle = .round
                NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                outLine.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws authentic iStat Menus per-core CPU micro-bar cluster.
    public static func drawCPUBar(
        perCore: [Double]?,
        user: Double? = nil,
        system: Double? = nil
    ) -> NSImage {
        if let cores = perCore, cores.count >= 2 {
            // Authentic Per-Core Micro-Bar Cluster!
            let coreWidth: CGFloat = 1.6
            let gap: CGFloat = 0.6
            let totalWidth = CGFloat(cores.count) * (coreWidth + gap) + 2.0
            let size = NSSize(width: max(totalWidth, 14.0), height: 18)

            let image = NSImage(size: size, flipped: false) { bounds in
                for (idx, coreUsage) in cores.enumerated() {
                    let x = 1.0 + CGFloat(idx) * (coreWidth + gap)
                    let trackRect = NSRect(x: x, y: 2.0, width: coreWidth, height: 14.0)
                    let track = NSBezierPath(roundedRect: trackRect, xRadius: 0.5, yRadius: 0.5)
                    NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
                    track.fill()

                    let clamped = min(max(coreUsage, 0.0), 100.0)
                    if clamped > 0 {
                        let fillHeight = max(CGFloat(14.0 * (clamped / 100.0)), 1.5)
                        let fillRect = NSRect(x: x, y: 2.0, width: coreWidth, height: fillHeight)
                        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 0.5, yRadius: 0.5)
                        NSColor.labelColor.setFill()
                        fillPath.fill()
                    }
                }
                return true
            }
            image.isTemplate = true
            return image
        } else {
            // Dual-tone aggregate bar (User on top, System on bottom)
            let size = NSSize(width: 10, height: 18)
            let image = NSImage(size: size, flipped: false) { _ in
                let trackRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: 14.0)
                let track = NSBezierPath(roundedRect: trackRect, xRadius: 2.5, yRadius: 2.5)
                NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
                track.fill()

                let usr = user ?? 0.0
                let sys = system ?? 0.0
                let total = min(max(usr + sys, 0.0), 100.0)

                if total > 0 {
                    let totalHeight = max(CGFloat(14.0 * (total / 100.0)), 2.0)
                    let sysHeight = (sys / total) * totalHeight

                    // Bottom system segment
                    if sysHeight > 0 {
                        let sysRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: max(sysHeight, 1.5))
                        let sysPath = NSBezierPath(roundedRect: sysRect, xRadius: 2.5, yRadius: 2.5)
                        NSColor.labelColor.withAlphaComponent(0.55).setFill()
                        sysPath.fill()
                    }

                    // Top user segment
                    let usrHeight = totalHeight - sysHeight
                    if usrHeight > 0 {
                        let usrRect = NSRect(x: 2.0, y: 2.0 + sysHeight, width: 6.0, height: max(usrHeight, 1.5))
                        let usrPath = NSBezierPath(roundedRect: usrRect, xRadius: 2.5, yRadius: 2.5)
                        NSColor.labelColor.setFill()
                        usrPath.fill()
                    }
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    /// Draws authentic iStat Menus segmented CPU Donut Pie (User vs. System load).
    public static func drawCPUDonutPie(user: Double, system: Double) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 6.2
            let lineWidth: CGFloat = 2.8

            // Background full ring track
            let track = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.8, dy: 1.8))
            track.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.20).setStroke()
            track.stroke()

            let uClamped = min(max(user, 0.0), 100.0)
            let sClamped = min(max(system, 0.0), 100.0 - uClamped)

            // User Space slice (Starts at 12 o'clock, sweeps clockwise)
            if uClamped > 0 {
                let uArc = NSBezierPath()
                let startAngle: CGFloat = 90.0
                let endAngle: CGFloat = 90.0 - CGFloat(360.0 * (uClamped / 100.0))
                uArc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                uArc.lineWidth = lineWidth
                uArc.lineCapStyle = .round
                NSColor.labelColor.setStroke()
                uArc.stroke()
            }

            // System / Kernel Space slice (Continues immediately after user slice)
            if sClamped > 0 {
                let sArc = NSBezierPath()
                let startAngle: CGFloat = 90.0 - CGFloat(360.0 * (uClamped / 100.0))
                let endAngle: CGFloat = startAngle - CGFloat(360.0 * (sClamped / 100.0))
                sArc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                sArc.lineWidth = lineWidth
                sArc.lineCapStyle = .butt
                NSColor.labelColor.withAlphaComponent(0.55).setStroke()
                sArc.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws authentic iStat Menus Memory Breakdown Donut Ring.
    public static func drawMemoryDonutPie(sample: MemorySample?, ratio: Double) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 6.2
            let lineWidth: CGFloat = 2.8

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

                // 1. Wired (Solid)
                if wiredRatio > 0 {
                    let wAngle = CGFloat(360.0 * wiredRatio)
                    let wArc = NSBezierPath()
                    wArc.appendArc(withCenter: center, radius: radius, startAngle: currentAngle, endAngle: currentAngle - wAngle, clockwise: true)
                    wArc.lineWidth = lineWidth
                    NSColor.labelColor.setStroke()
                    wArc.stroke()
                    currentAngle -= wAngle
                }

                // 2. Active / App Memory (0.75 alpha)
                if activeRatio > 0 {
                    let aAngle = CGFloat(360.0 * activeRatio)
                    let aArc = NSBezierPath()
                    aArc.appendArc(withCenter: center, radius: radius, startAngle: currentAngle, endAngle: currentAngle - aAngle, clockwise: true)
                    aArc.lineWidth = lineWidth
                    NSColor.labelColor.withAlphaComponent(0.70).setStroke()
                    aArc.stroke()
                    currentAngle -= aAngle
                }

                // 3. Compressed (0.45 alpha)
                if compressedRatio > 0 {
                    let cAngle = CGFloat(360.0 * compressedRatio)
                    let cArc = NSBezierPath()
                    cArc.appendArc(withCenter: center, radius: radius, startAngle: currentAngle, endAngle: currentAngle - cAngle, clockwise: true)
                    cArc.lineWidth = lineWidth
                    NSColor.labelColor.withAlphaComponent(0.40).setStroke()
                    cArc.stroke()
                }
            } else {
                let clamped = min(max(ratio, 0.0), 100.0)
                if clamped > 0 {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: radius, startAngle: 90.0, endAngle: 90.0 - CGFloat(360.0 * (clamped / 100.0)), clockwise: true)
                    arc.lineWidth = lineWidth
                    arc.lineCapStyle = .round
                    NSColor.labelColor.setStroke()
                    arc.stroke()
                }
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws authentic iStat Menus segmented stacked memory vertical bar.
    public static func drawMemoryStackedBar(sample: MemorySample?, ratio: Double) -> NSImage {
        let size = NSSize(width: 10, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let trackRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: 14.0)
            let track = NSBezierPath(roundedRect: trackRect, xRadius: 2.5, yRadius: 2.5)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            track.fill()

            let totalH: CGFloat = 14.0

            if let mem = sample, mem.total > 0 {
                let total = Double(mem.total)
                let wiredH = max(CGFloat(Double(mem.wired) / total) * totalH, 0.0)
                let activeH = max(CGFloat(Double(mem.active ?? (mem.used - mem.wired)) / total) * totalH, 0.0)
                let compH = max(CGFloat(Double(mem.compressed) / total) * totalH, 0.0)

                var currentY: CGFloat = 2.0

                if wiredH > 0 {
                    let r = NSRect(x: 2.0, y: currentY, width: 6.0, height: wiredH)
                    NSColor.labelColor.setFill()
                    NSBezierPath(roundedRect: r, xRadius: 1.0, yRadius: 1.0).fill()
                    currentY += wiredH
                }
                if activeH > 0 {
                    let r = NSRect(x: 2.0, y: currentY, width: 6.0, height: activeH)
                    NSColor.labelColor.withAlphaComponent(0.70).setFill()
                    NSBezierPath(roundedRect: r, xRadius: 1.0, yRadius: 1.0).fill()
                    currentY += activeH
                }
                if compH > 0 {
                    let r = NSRect(x: 2.0, y: currentY, width: 6.0, height: compH)
                    NSColor.labelColor.withAlphaComponent(0.40).setFill()
                    NSBezierPath(roundedRect: r, xRadius: 1.0, yRadius: 1.0).fill()
                }
            } else {
                let clamped = min(max(ratio, 0.0), 100.0)
                if clamped > 0 {
                    let fillH = max(CGFloat(totalH * (clamped / 100.0)), 2.0)
                    let fillRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: fillH)
                    NSColor.labelColor.setFill()
                    NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws authentic iStat Menus horizontal Battery Instrument with live proportional level fill & charging bolt.
    public static func drawBatteryInstrument(
        charge: Double?,
        state: BatteryState?,
        hasBattery: Bool
    ) -> NSImage {
        let size = NSSize(width: 22, height: 14)
        let image = NSImage(size: size, flipped: false) { bounds in
            if hasBattery {
                let chg = charge ?? 80.0
                let clamped = min(max(chg, 0.0), 100.0)

                // Battery Body Frame
                let bodyRect = NSRect(x: 1.0, y: 2.0, width: 17.0, height: 10.0)
                let body = NSBezierPath(roundedRect: bodyRect, xRadius: 2.0, yRadius: 2.0)
                body.lineWidth = 1.0
                NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                body.stroke()

                // Battery Terminal Cap
                let capRect = NSRect(x: 18.5, y: 5.0, width: 1.8, height: 4.0)
                let cap = NSBezierPath(roundedRect: capRect, xRadius: 0.8, yRadius: 0.8)
                NSColor.labelColor.withAlphaComponent(0.85).setFill()
                cap.fill()

                // Proportional Level Fill
                let maxFillWidth: CGFloat = 13.6
                let fillWidth = max(maxFillWidth * CGFloat(clamped / 100.0), 1.5)
                let fillRect = NSRect(x: 2.7, y: 3.7, width: fillWidth, height: 6.6)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.0, yRadius: 1.0)
                NSColor.labelColor.setFill()
                fillPath.fill()

                // Charging Lightning Bolt Overlay
                if state == .charging {
                    let bolt = NSBezierPath()
                    bolt.move(to: NSPoint(x: 10.5, y: 11.5))
                    bolt.line(to: NSPoint(x: 7.5, y: 7.2))
                    bolt.line(to: NSPoint(x: 9.8, y: 7.2))
                    bolt.line(to: NSPoint(x: 8.8, y: 3.0))
                    bolt.line(to: NSPoint(x: 12.5, y: 8.0))
                    bolt.line(to: NSPoint(x: 10.2, y: 8.0))
                    bolt.close()
                    NSColor.windowBackgroundColor.setFill()
                    bolt.fill()
                    bolt.lineWidth = 0.6
                    NSColor.labelColor.setStroke()
                    bolt.stroke()
                }
            } else {
                // Desktop Mac: AC Plug
                let plug = NSBezierPath(roundedRect: NSRect(x: 5.0, y: 2.5, width: 10.0, height: 9.0), xRadius: 2.0, yRadius: 2.0)
                plug.lineWidth = 1.0
                NSColor.labelColor.withAlphaComponent(0.85).setStroke()
                plug.stroke()

                let p1 = NSBezierPath(rect: NSRect(x: 15.0, y: 4.5, width: 3.5, height: 1.5))
                let p2 = NSBezierPath(rect: NSRect(x: 15.0, y: 8.0, width: 3.5, height: 1.5))
                NSColor.labelColor.setFill()
                p1.fill()
                p2.fill()
            }
            return true
        }
        image.isTemplate = true
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

        return drawStackedText(line1: l1, line2: l2)
    }

    /// Draws dynamic Dual Activity Arrows (`↓` Download and `↑` Upload).
    public static func drawNetworkActivityArrows(inBytes: Double, outBytes: Double) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let inActive = inBytes > 1024.0
            let outActive = outBytes > 1024.0

            // Download Arrow (Left, pointing Down)
            let down = NSBezierPath()
            down.move(to: NSPoint(x: 4.5, y: 13.5))
            down.line(to: NSPoint(x: 4.5, y: 3.5))
            down.move(to: NSPoint(x: 2.0, y: 6.0))
            down.line(to: NSPoint(x: 4.5, y: 2.5))
            down.line(to: NSPoint(x: 7.0, y: 6.0))
            down.lineWidth = inActive ? 1.8 : 1.1
            down.lineCapStyle = .round
            down.lineJoinStyle = .round
            (inActive ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.35)).setStroke()
            down.stroke()

            // Upload Arrow (Right, pointing Up)
            let up = NSBezierPath()
            up.move(to: NSPoint(x: 11.5, y: 2.5))
            up.line(to: NSPoint(x: 11.5, y: 12.5))
            up.move(to: NSPoint(x: 9.0, y: 10.0))
            up.line(to: NSPoint(x: 11.5, y: 13.5))
            up.line(to: NSPoint(x: 14.0, y: 10.0))
            up.lineWidth = outActive ? 1.8 : 1.1
            up.lineCapStyle = .round
            up.lineJoinStyle = .round
            (outActive ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.35)).setStroke()
            up.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws dynamic Disk Read / Write Activity LEDs (`R` and `W`).
    public static func drawDiskActivityLeds(readBytes: Double, writeBytes: Double) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            let rActive = readBytes > 10240.0
            let wActive = writeBytes > 10240.0

            let font = NSFont.systemFont(ofSize: 8.5, weight: .black)

            // Read badge
            let rBadge = NSBezierPath(roundedRect: NSRect(x: 1.0, y: 2.0, width: 7.5, height: 12.0), xRadius: 1.5, yRadius: 1.5)
            if rActive {
                NSColor.labelColor.setFill()
                rBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.windowBackgroundColor]
                ("R" as NSString).draw(at: NSPoint(x: 2.0, y: 2.5), withAttributes: attrs)
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                rBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.40)]
                ("R" as NSString).draw(at: NSPoint(x: 2.0, y: 2.5), withAttributes: attrs)
            }

            // Write badge
            let wBadge = NSBezierPath(roundedRect: NSRect(x: 9.5, y: 2.0, width: 7.5, height: 12.0), xRadius: 1.5, yRadius: 1.5)
            if wActive {
                NSColor.labelColor.setFill()
                wBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.windowBackgroundColor]
                ("W" as NSString).draw(at: NSPoint(x: 10.0, y: 2.5), withAttributes: attrs)
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.20).setFill()
                wBadge.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.40)]
                ("W" as NSString).draw(at: NSPoint(x: 10.0, y: 2.5), withAttributes: attrs)
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Compatibility Drawings & Helpers

    public static func drawCPUSymbol(usage: Double? = nil) -> NSImage {
        drawCPUDonutPie(user: usage ?? 20.0, system: 0.0)
    }

    public static func drawCPUGauge(percentage: Double) -> NSImage {
        drawCPUDonutPie(user: percentage, system: 0.0)
    }

    public static func drawCPUSparkline(history: [Double]) -> NSImage {
        drawSparkline(values: history, maxValue: 100.0)
    }

    public static func drawCPUBar(percentage: Double, user: Double? = nil, system: Double? = nil) -> NSImage {
        drawCPUBar(perCore: nil, user: user ?? percentage, system: system)
    }

    public static func drawMemorySymbol(ratio: Double? = nil, pressure: MemoryPressure? = nil) -> NSImage {
        drawMemoryDonutPie(sample: nil, ratio: ratio ?? 40.0)
    }

    public static func drawMemoryGauge(ratio: Double) -> NSImage {
        drawMemoryDonutPie(sample: nil, ratio: ratio)
    }

    public static func drawMemoryBar(ratio: Double) -> NSImage {
        drawMemoryStackedBar(sample: nil, ratio: ratio)
    }

    public static func drawMemorySparkline(history: [Double]) -> NSImage {
        drawSparkline(values: history, maxValue: 100.0)
    }

    public static func drawGPUSymbol(utilization: Double? = nil) -> NSImage {
        drawCircularGauge(percentage: utilization ?? 0.0, iconName: "display")
    }

    public static func drawGPUGauge(percentage: Double) -> NSImage {
        drawCircularGauge(percentage: percentage, iconName: "display")
    }

    public static func drawGPUBar(percentage: Double) -> NSImage {
        drawBarGraph(percentage: percentage)
    }

    public static func drawGPUSparkline(history: [Double]) -> NSImage {
        drawSparkline(values: history, maxValue: 100.0)
    }

    public static func drawThermalSymbol(celsius: Double? = nil) -> NSImage {
        let c = celsius ?? 45.0
        let pct = min(max((c - 30.0) / 70.0 * 100.0, 0.0), 100.0)
        return drawThermalGauge(percentage: pct)
    }

    public static func drawThermalGauge(percentage: Double) -> NSImage {
        drawCircularGauge(percentage: percentage, iconName: "thermometer.medium")
    }

    public static func drawThermalBar(percentage: Double) -> NSImage {
        drawBarGraph(percentage: percentage)
    }

    public static func drawThermalSparkline(history: [Double]) -> NSImage {
        let maxVal = max(history.max() ?? 100.0, 100.0)
        return drawSparkline(values: history, maxValue: maxVal)
    }

    public static func drawFanSymbol(rpm: Int? = nil, percentage: Double? = nil) -> NSImage {
        drawFanGauge(percentage: percentage ?? 0.0)
    }

    public static func drawFanGauge(percentage: Double) -> NSImage {
        drawCircularGauge(percentage: percentage, iconName: "fan")
    }

    public static func drawFanBar(percentage: Double) -> NSImage {
        drawBarGraph(percentage: percentage)
    }

    public static func drawFanSparkline(history: [Double]) -> NSImage {
        let maxVal = max(history.max() ?? 6000.0, 2000.0)
        return drawSparkline(values: history, maxValue: maxVal)
    }

    public static func drawNetworkSymbol(inBytes: Double? = nil, outBytes: Double? = nil) -> NSImage {
        drawNetworkActivityArrows(inBytes: inBytes ?? 0.0, outBytes: outBytes ?? 0.0)
    }

    public static func drawNetworkGauge(percentage: Double) -> NSImage {
        drawCircularGauge(percentage: percentage, iconName: "network")
    }

    public static func drawNetworkBar(inPct: Double, outPct: Double) -> NSImage {
        let size = NSSize(width: 14, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let inTrack = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.0, width: 5.0, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            inTrack.fill()

            let inClamped = min(max(inPct, 0.0), 100.0)
            if inClamped > 0 {
                let inFill = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.0, width: 5.0, height: max(14.0 * (inClamped / 100.0), 2.0)), xRadius: 2.0, yRadius: 2.0)
                NSColor.labelColor.setFill()
                inFill.fill()
            }

            let outTrack = NSBezierPath(roundedRect: NSRect(x: 7.5, y: 2.0, width: 5.0, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            outTrack.fill()

            let outClamped = min(max(outPct, 0.0), 100.0)
            if outClamped > 0 {
                let outFill = NSBezierPath(roundedRect: NSRect(x: 7.5, y: 2.0, width: 5.0, height: max(14.0 * (outClamped / 100.0), 2.0)), xRadius: 2.0, yRadius: 2.0)
                NSColor.labelColor.setFill()
                outFill.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    public static func drawNetworkSparkline(history: [Double]) -> NSImage {
        let maxVal = max(history.max() ?? 1024.0, 1024.0)
        return drawSparkline(values: history, maxValue: maxVal)
    }

    public static func drawDiskSymbol(readBytes: Double? = nil, writeBytes: Double? = nil) -> NSImage {
        drawDiskActivityLeds(readBytes: readBytes ?? 0.0, writeBytes: writeBytes ?? 0.0)
    }

    public static func drawDiskGauge(percentage: Double) -> NSImage {
        drawCircularGauge(percentage: percentage, iconName: "internaldrive")
    }

    public static func drawDiskBar(readPct: Double, writePct: Double) -> NSImage {
        let size = NSSize(width: 14, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let readTrack = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.0, width: 5.0, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            readTrack.fill()

            let rClamped = min(max(readPct, 0.0), 100.0)
            if rClamped > 0 {
                let rFill = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.0, width: 5.0, height: max(14.0 * (rClamped / 100.0), 2.0)), xRadius: 2.0, yRadius: 2.0)
                NSColor.labelColor.setFill()
                rFill.fill()
            }

            let writeTrack = NSBezierPath(roundedRect: NSRect(x: 7.5, y: 2.0, width: 5.0, height: 14.0), xRadius: 2.0, yRadius: 2.0)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            writeTrack.fill()

            let wClamped = min(max(writePct, 0.0), 100.0)
            if wClamped > 0 {
                let wFill = NSBezierPath(roundedRect: NSRect(x: 7.5, y: 2.0, width: 5.0, height: max(14.0 * (wClamped / 100.0), 2.0)), xRadius: 2.0, yRadius: 2.0)
                NSColor.labelColor.setFill()
                wFill.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    public static func drawDiskSparkline(history: [Double]) -> NSImage {
        let maxVal = max(history.max() ?? 1024.0, 1024.0)
        return drawSparkline(values: history, maxValue: maxVal)
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
        let size = NSSize(width: 10, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let trackRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: 14.0)
            let track = NSBezierPath(roundedRect: trackRect, xRadius: 2.5, yRadius: 2.5)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            track.fill()

            let clamped = min(max(percentage, 0.0), 100.0)
            if clamped > 0 {
                let fillHeight = max(CGFloat(14.0 * (clamped / 100.0)), 2.0)
                let fillRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: fillHeight)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5)
                NSColor.labelColor.setFill()
                fillPath.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    public static func drawPowerSparkline(history: [Double]) -> NSImage {
        drawSparkline(values: history, maxValue: 100.0)
    }

    /// Generic circular gauge.
    public static func drawCircularGauge(
        percentage: Double,
        iconName: String? = nil
    ) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 6.2
            let lineWidth: CGFloat = 2.4

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

    /// Generic vertical bar graph.
    public static func drawBarGraph(percentage: Double) -> NSImage {
        let size = NSSize(width: 10, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let pillRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: 14.0)
            let track = NSBezierPath(roundedRect: pillRect, xRadius: 2.5, yRadius: 2.5)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            track.fill()

            let clamped = min(max(percentage, 0.0), 100.0)
            if clamped > 0 {
                let fillHeight = max(CGFloat(14.0 * (clamped / 100.0)), 2.0)
                let fillRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: fillHeight)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5)
                NSColor.labelColor.setFill()
                fillPath.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Generic history sparkline chart.
    public static func drawSparkline(values: [Double], maxValue: Double) -> NSImage {
        let size = NSSize(width: 32, height: 14)
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

            linePath.lineWidth = 1.2
            linePath.lineJoinStyle = .round
            linePath.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            linePath.stroke()

            let dotRect = NSRect(x: lastPoint.x - 1.1, y: lastPoint.y - 1.1, width: 2.2, height: 2.2)
            let dot = NSBezierPath(ovalIn: dotRect)
            NSColor.labelColor.setFill()
            dot.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Loads an SF Symbol image formatted for menu bar presentation.
    public static func symbolImage(name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(config) else {
            return nil
        }
        img.isTemplate = true
        return img
    }
}
