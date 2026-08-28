import AppKit
import SwiftUI
import iStatsCore

/// Pure rendering engine that generates high-DPI `NSImage` graphics and formatted title text
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
            let util = gpu?.utilization ?? 0.0
            let history = coordinator.gpuHistory.compactMap { $0.value.utilization }
            return renderGPU(style: config.style, gpu: gpu, history: history)

        case .thermal:
            let thermal = coordinator.latestThermal?.value
            return renderThermal(style: config.style, thermal: thermal, unit: preferences.temperatureUnit)

        case .fan:
            let fan = coordinator.latestFan?.value
            return renderFan(style: config.style, fan: fan)

        case .network:
            let network = coordinator.latestNetwork?.value
            let history = coordinator.networkHistory.map { Double($0.value.totalBytesInPerSec + $0.value.totalBytesOutPerSec) }
            return renderNetwork(style: config.style, network: network, history: history, unit: preferences.networkUnit, standard: preferences.byteUnitStandard)

        case .disk:
            let disk = coordinator.latestDisk?.value
            return renderDisk(style: config.style, disk: disk, standard: preferences.byteUnitStandard)

        case .power:
            let power = coordinator.latestPower?.value
            return renderPower(style: config.style, power: power)
        }
    }

    // MARK: - CPU Rendering

    private static func renderCPU(style: MetricDisplayStyle, cpu: CPUSample?, history: [Double]) -> RenderResult {
        let usage = cpu?.totalUsage ?? 0.0
        let tip = cpu != nil ? String(format: "CPU: %.1f%% (User: %.1f%%, Sys: %.1f%%)", cpu!.totalUsage, cpu!.user, cpu!.system) : "CPU: --%"

        switch style {
        case .gauge:
            let img = drawCircularGauge(percentage: usage, iconName: "cpu")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawBarGraph(percentage: usage)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawSparkline(values: history, maxValue: 100.0)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let text = cpu != nil ? String(format: "CPU %.0f%%", usage) : "CPU --%"
            return RenderResult(title: text, toolTip: tip)
        case .symbol:
            let img = symbolImage(name: "cpu")
            return RenderResult(image: img, toolTip: tip)
        case .throughput:
            let text = cpu != nil ? String(format: "%.0f%%", usage) : "--%"
            return RenderResult(title: text, toolTip: tip)
        }
    }

    // MARK: - Memory Rendering

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
            let img = drawCircularGauge(percentage: ratio, iconName: "memorychip")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawBarGraph(percentage: ratio)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawSparkline(values: history, maxValue: 100.0)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let text = memory != nil ? String(format: "RAM %.0f%%", ratio) : "RAM --%"
            return RenderResult(title: text, toolTip: tip)
        case .symbol:
            let img = symbolImage(name: "memorychip")
            return RenderResult(image: img, toolTip: tip)
        case .throughput:
            let text = memory != nil ? String(format: "%.0f%%", ratio) : "--%"
            return RenderResult(title: text, toolTip: tip)
        }
    }

    // MARK: - GPU Rendering

    private static func renderGPU(style: MetricDisplayStyle, gpu: GPUSample?, history: [Double]) -> RenderResult {
        let util = gpu?.utilization ?? 0.0
        let tip = gpu != nil ? String(format: "GPU: %.1f%%", util) : "GPU: --%"

        switch style {
        case .gauge:
            let img = drawCircularGauge(percentage: util, iconName: "display")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawBarGraph(percentage: util)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = drawSparkline(values: history, maxValue: 100.0)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let text = gpu?.utilization != nil ? String(format: "GPU %.0f%%", util) : "GPU --%"
            return RenderResult(title: text, toolTip: tip)
        case .symbol:
            let img = symbolImage(name: "display")
            return RenderResult(image: img, toolTip: tip)
        case .throughput:
            let text = gpu?.utilization != nil ? String(format: "%.0f%%", util) : "--%"
            return RenderResult(title: text, toolTip: tip)
        }
    }

    // MARK: - Thermal Rendering

    private static func renderThermal(style: MetricDisplayStyle, thermal: ThermalSample?, unit: Units.TemperatureUnit) -> RenderResult {
        let sensor = thermal?.sensors.first(where: { $0.name.contains("Package") || $0.name.contains("CPU") || $0.name.contains("SoC") }) ?? thermal?.sensors.first
        let tempC = sensor?.celsius ?? 0.0
        let tip = sensor != nil ? "Thermal: \(Units.formatTemperature(tempC, unit: unit, fractionDigits: 1))" : "Thermal: --"

        switch style {
        case .gauge:
            let pct = min(max((tempC - 30.0) / (100.0 - 30.0) * 100.0, 0.0), 100.0)
            let img = drawCircularGauge(percentage: pct, iconName: "thermometer.medium")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let pct = min(max((tempC - 30.0) / 70.0 * 100.0, 0.0), 100.0)
            let img = drawBarGraph(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline:
            let img = symbolImage(name: "thermometer.medium")
            return RenderResult(image: img, toolTip: tip)
        case .text, .throughput:
            let text = sensor != nil ? Units.formatTemperature(tempC, unit: unit, fractionDigits: 0) : (unit == .celsius ? "--°C" : "--°F")
            return RenderResult(title: text, toolTip: tip)
        case .symbol:
            let img = symbolImage(name: "thermometer.medium")
            return RenderResult(image: img, toolTip: tip)
        }
    }

    // MARK: - Fan Rendering

    private static func renderFan(style: MetricDisplayStyle, fan: FanSample?) -> RenderResult {
        let primaryFan = fan?.fans.first
        let rpm = primaryFan?.rpm ?? 0
        let tip = primaryFan != nil ? "Fans: \(rpm) RPM (\(primaryFan!.name))" : "Fans: -- RPM"

        switch style {
        case .gauge:
            let pct: Double
            if let f = primaryFan, let max = f.maxRPM, let min = f.minRPM, max > min {
                pct = Double(f.rpm - min) / Double(max - min) * 100.0
            } else if let f = primaryFan, let max = f.maxRPM, max > 0 {
                pct = Double(f.rpm) / Double(max) * 100.0
            } else {
                pct = 0.0
            }
            let img = drawCircularGauge(percentage: pct, iconName: "fan")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let pct: Double
            if let f = primaryFan, let max = f.maxRPM, max > 0 {
                pct = Double(f.rpm) / Double(max) * 100.0
            } else {
                pct = 0.0
            }
            let img = drawBarGraph(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline, .symbol:
            let img = symbolImage(name: "fan")
            return RenderResult(image: img, toolTip: tip)
        case .text, .throughput:
            let text = primaryFan != nil ? "\(rpm) RPM" : "-- RPM"
            return RenderResult(title: text, toolTip: tip)
        }
    }

    // MARK: - Network Rendering

    private static func renderNetwork(
        style: MetricDisplayStyle,
        network: NetworkSample?,
        history: [Double],
        unit: Units.NetworkUnit,
        standard: Units.ByteUnitStandard
    ) -> RenderResult {
        let inBytes = network?.totalBytesInPerSec ?? 0
        let outBytes = network?.totalBytesOutPerSec ?? 0
        let inStr = Units.formatNetworkRate(inBytes, unit: unit, standard: standard, fractionDigits: 0)
        let outStr = Units.formatNetworkRate(outBytes, unit: unit, standard: standard, fractionDigits: 0)
        let tip = "Network: ↓ \(Units.formatNetworkRate(inBytes, unit: unit, standard: standard, fractionDigits: 1))  ↑ \(Units.formatNetworkRate(outBytes, unit: unit, standard: standard, fractionDigits: 1))"

        switch style {
        case .throughput:
            let text = network != nil ? "↓ \(inStr) ↑ \(outStr)" : "Net --"
            return RenderResult(title: text, toolTip: tip)
        case .sparkline:
            let img = drawSparkline(values: history, maxValue: max(history.max() ?? 1024.0, 1024.0))
            return RenderResult(image: img, toolTip: tip)
        case .gauge:
            let total = Double(inBytes + outBytes)
            let pct = min((total / (10 * 1024 * 1024)) * 100.0, 100.0) // Scale to 10 MB/s
            let img = drawCircularGauge(percentage: pct, iconName: "network")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let total = Double(inBytes + outBytes)
            let pct = min((total / (10 * 1024 * 1024)) * 100.0, 100.0)
            let img = drawBarGraph(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
        case .text:
            let total = inBytes + outBytes
            let text = network != nil ? Units.formatNetworkRate(total, unit: unit, standard: standard, fractionDigits: 0) : "Net --"
            return RenderResult(title: text, toolTip: tip)
        case .symbol:
            let img = symbolImage(name: "network")
            return RenderResult(image: img, toolTip: tip)
        }
    }

    // MARK: - Disk Rendering

    private static func renderDisk(style: MetricDisplayStyle, disk: DiskSample?, standard: Units.ByteUnitStandard) -> RenderResult {
        let readBytes = disk?.io?.bytesReadPerSec ?? 0.0
        let writeBytes = disk?.io?.bytesWrittenPerSec ?? 0.0
        let readStr = Units.formatDiskRate(readBytes, standard: standard, fractionDigits: 0)
        let writeStr = Units.formatDiskRate(writeBytes, standard: standard, fractionDigits: 0)
        let tip = "Disk I/O: Read \(Units.formatDiskRate(readBytes, standard: standard, fractionDigits: 1)), Write \(Units.formatDiskRate(writeBytes, standard: standard, fractionDigits: 1))"

        switch style {
        case .throughput:
            let text = disk?.io != nil ? "R: \(readStr) W: \(writeStr)" : "Disk --"
            return RenderResult(title: text, toolTip: tip)
        case .text:
            let total = readBytes + writeBytes
            let text = disk?.io != nil ? Units.formatDiskRate(total, standard: standard, fractionDigits: 0) : "Disk --"
            return RenderResult(title: text, toolTip: tip)
        case .gauge:
            let total = readBytes + writeBytes
            let pct = min((total / (50 * 1024 * 1024)) * 100.0, 100.0)
            let img = drawCircularGauge(percentage: pct, iconName: "internaldrive")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let total = readBytes + writeBytes
            let pct = min((total / (50 * 1024 * 1024)) * 100.0, 100.0)
            let img = drawBarGraph(percentage: pct)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline, .symbol:
            let img = symbolImage(name: "internaldrive")
            return RenderResult(image: img, toolTip: tip)
        }
    }

    // MARK: - Power Rendering

    private static func renderPower(style: MetricDisplayStyle, power: PowerSample?) -> RenderResult {
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

        switch style {
        case .gauge:
            let img = drawCircularGauge(percentage: charge, iconName: "bolt.fill")
            return RenderResult(image: img, toolTip: tip)
        case .bar:
            let img = drawBarGraph(percentage: charge)
            return RenderResult(image: img, toolTip: tip)
        case .sparkline, .symbol:
            let iconName = (power?.hasBattery == true) ? (charge > 20 ? "battery.100percent" : "battery.25percent") : "bolt.fill"
            let img = symbolImage(name: iconName)
            return RenderResult(image: img, toolTip: tip)
        case .text, .throughput:
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

    // MARK: - Drawing Helpers

    /// Draws a high-DPI circular gauge icon (18x18 pt).
    public static func drawCircularGauge(percentage: Double, iconName: String? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius: CGFloat = 7.0
            let lineWidth: CGFloat = 2.2

            // Track background ring
            let trackPath = NSBezierPath(ovalIn: bounds.insetBy(dx: 2.0, dy: 2.0))
            trackPath.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setStroke()
            trackPath.stroke()

            // Active progress arc
            let clamped = min(max(percentage, 0.0), 100.0)
            if clamped > 0 {
                let arcPath = NSBezierPath()
                let startAngle: CGFloat = 90.0
                let endAngle: CGFloat = 90.0 - CGFloat(360.0 * (clamped / 100.0))
                arcPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                arcPath.lineWidth = lineWidth
                arcPath.lineCapStyle = .round
                NSColor.labelColor.setStroke()
                arcPath.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws a mini vertical load bar icon (10x18 pt).
    public static func drawBarGraph(percentage: Double) -> NSImage {
        let size = NSSize(width: 10, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let pillRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: 14.0)
            let track = NSBezierPath(roundedRect: pillRect, xRadius: 3.0, yRadius: 3.0)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            track.fill()

            let clamped = min(max(percentage, 0.0), 100.0)
            if clamped > 0 {
                let fillHeight = max(CGFloat(14.0 * (clamped / 100.0)), 2.0)
                let fillRect = NSRect(x: 2.0, y: 2.0, width: 6.0, height: fillHeight)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 3.0, yRadius: 3.0)
                NSColor.labelColor.setFill()
                fillPath.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws a mini history sparkline line chart (28x16 pt).
    public static func drawSparkline(values: [Double], maxValue: Double) -> NSImage {
        let size = NSSize(width: 28, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            guard values.count >= 2 else {
                // Draw a simple placeholder baseline
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 2.0, y: 3.0))
                path.line(to: NSPoint(x: bounds.maxX - 2.0, y: 3.0))
                path.lineWidth = 1.2
                NSColor.secondaryLabelColor.withAlphaComponent(0.4).setStroke()
                path.stroke()
                return true
            }

            let maxVal = max(maxValue, 1.0)
            let innerBounds = bounds.insetBy(dx: 2.0, dy: 2.0)
            let stepX = innerBounds.width / CGFloat(max(values.count - 1, 1))

            let linePath = NSBezierPath()
            for (index, val) in values.enumerated() {
                let clamped = min(max(val, 0.0), maxVal)
                let y = innerBounds.minY + (innerBounds.height * CGFloat(clamped / maxVal))
                let x = innerBounds.minX + (CGFloat(index) * stepX)
                if index == 0 {
                    linePath.move(to: NSPoint(x: x, y: y))
                } else {
                    linePath.line(to: NSPoint(x: x, y: y))
                }
            }

            linePath.lineWidth = 1.3
            linePath.lineJoinStyle = .round
            linePath.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            linePath.stroke()
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
