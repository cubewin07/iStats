import Foundation

/// Tooltip and accessibility strings for a menu bar widget. Kept out of `WidgetModel` because they carry
/// precise live values that must not trigger a redraw.
public struct WidgetDescription: Equatable, Sendable {
    public var toolTip: String
    public var accessibilityLabel: String

    public static func make(
        config: MenuBarItemConfig,
        snapshot s: WidgetSnapshot,
        options o: WidgetOptions = WidgetOptions()
    ) -> WidgetDescription {
        switch config.category {
        case .cpu:
            guard let cpu = s.cpu else { return .init(toolTip: "CPU: --%", accessibilityLabel: "CPU load unavailable") }
            return .init(
                toolTip: String(format: "CPU: %.1f%% (User: %.1f%%, Sys: %.1f%%)", cpu.totalUsage, cpu.user, cpu.system),
                accessibilityLabel: String(format: "CPU load %.0f percent", cpu.totalUsage)
            )

        case .memory:
            guard let mem = s.memory else { return .init(toolTip: "MEM: --%", accessibilityLabel: "Memory telemetry unavailable") }
            let ratio = mem.total > 0 ? Double(mem.used) / Double(mem.total) * 100.0 : 0.0
            let used = Units.formatBytes(mem.used, standard: o.byteUnitStandard)
            let total = Units.formatBytes(mem.total, standard: o.byteUnitStandard)
            return .init(
                toolTip: "MEM: \(used) / \(total) (\(String(format: "%.1f%%", ratio))) - Pressure: \(mem.pressure.displayName)",
                accessibilityLabel: String(format: "Memory pressure %@, %@ used of %@", mem.pressure.displayName, used, total)
            )

        case .gpu:
            guard let gpu = s.gpu else { return .init(toolTip: "GPU: --%", accessibilityLabel: "GPU utilization unavailable") }
            let util = gpu.utilization ?? 0.0
            return .init(
                toolTip: String(format: "GPU: %.1f%%", util),
                accessibilityLabel: gpu.utilization != nil ? String(format: "GPU utilization %.0f percent", util) : "GPU utilization unavailable"
            )

        case .thermal:
            let (sensor, _, label) = WidgetModel.resolveThermalSensor(style: config.style, source: config.source, thermal: s.thermal)
            guard let sensor else { return .init(toolTip: "\(label) Thermal: --", accessibilityLabel: "\(label) thermal unavailable") }
            let precise = Units.formatTemperature(sensor.celsius, unit: o.temperatureUnit, fractionDigits: 1)
            let rounded = Units.formatTemperature(sensor.celsius, unit: o.temperatureUnit, fractionDigits: 0)
            return .init(toolTip: "\(label) Thermal: \(precise) (\(sensor.name))", accessibilityLabel: "\(label) temperature \(rounded)")

        case .fan:
            let fans = s.fan?.fans ?? []
            let primary = fans.max(by: { WidgetModel.fanPercentage(for: $0) < WidgetModel.fanPercentage(for: $1) }) ?? fans.first
            let isFanless = s.fan?.isFanless == true || (s.fan != nil && fans.isEmpty)
            if isFanless {
                let text = config.style == .text
                return .init(toolTip: text ? "Fans: Passive cooling" : "Fans: Fanless System", accessibilityLabel: text ? "Passive cooling" : "Fanless system")
            } else if let f = primary {
                let desc = fans.count > 1 ? fans.map { "\($0.name): \($0.rpm) RPM" }.joined(separator: ", ") : "\(f.name): \(f.rpm) RPM"
                return .init(toolTip: "Fans: \(desc)", accessibilityLabel: "Fans running at \(f.rpm) RPM")
            }
            return .init(toolTip: "Fans: -- RPM", accessibilityLabel: "Fans unavailable")

        case .network:
            let i = Units.formatNetworkRate(s.network?.totalBytesInPerSec ?? 0, unit: o.networkUnit, standard: o.byteUnitStandard, fractionDigits: 1)
            let u = Units.formatNetworkRate(s.network?.totalBytesOutPerSec ?? 0, unit: o.networkUnit, standard: o.byteUnitStandard, fractionDigits: 1)
            return .init(toolTip: "Network: ↓ \(i)  ↑ \(u)", accessibilityLabel: "Network download \(i), upload \(u)")

        case .disk:
            let r = Units.formatDiskRate(s.disk?.io?.bytesReadPerSec ?? 0, standard: o.byteUnitStandard, fractionDigits: 1)
            let w = Units.formatDiskRate(s.disk?.io?.bytesWrittenPerSec ?? 0, standard: o.byteUnitStandard, fractionDigits: 1)
            let tip = "Disk I/O: Read \(r), Write \(w)"
            switch config.style {
            case .gauge, .text, .bar:
                let vol = s.disk?.volumes.first(where: { $0.mountPoint == "/" }) ?? s.disk?.volumes.first
                let ratio = (vol != nil && vol!.total > 0) ? Double(vol!.used) / Double(vol!.total) * 100.0 : 0.0
                return .init(toolTip: tip, accessibilityLabel: String(format: "Storage %.0f percent full", ratio))
            default:
                return .init(toolTip: tip, accessibilityLabel: "Disk read \(r), write \(w)")
            }

        case .power:
            guard let p = s.power else { return .init(toolTip: "Battery: --%", accessibilityLabel: "Power unavailable") }
            guard p.hasBattery else {
                let watts = p.powerDrawWatts.map { String(format: " (%.1f W)", $0) } ?? ""
                return .init(toolTip: "Power: Connected to AC\(watts)", accessibilityLabel: "Connected to AC power")
            }
            let charge = p.charge ?? 0.0
            let state: String
            let a11yState: String
            switch p.variant {
            case .charging: state = " (Charging)"; a11yState = ", charging"
            case .onHold: state = " (Charging On Hold - Optimized)"; a11yState = ", charging on hold"
            case .powerDeficit:
                if let draw = p.powerDrawWatts, let adapter = p.adapterWatts {
                    state = String(format: " (Power Deficit: %.0fW > %.0fW)", draw, adapter)
                } else {
                    state = " (Power Deficit)"
                }
                a11yState = ", power deficit"
            case .charged: state = " (Fully Charged - Power Adapter)"; a11yState = ", fully charged"
            case .lowBattery: state = " (Low Battery)"; a11yState = ", low battery"
            case .discharging: state = " (On Battery)"; a11yState = ", on battery"
            case .acDesktop: state = " (AC Power)"; a11yState = ", on AC power"
            case .unavailable: state = ""; a11yState = ""
            }
            return .init(
                toolTip: String(format: "Battery: %.0f%%%@", charge, state),
                accessibilityLabel: String(format: "Battery %.0f percent%@", charge, a11yState)
            )
        }
    }
}
