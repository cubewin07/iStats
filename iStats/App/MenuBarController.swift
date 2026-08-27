import AppKit
import SwiftUI
import Combine
import iStatsCore

@MainActor
public final class MenuBarController: NSObject {
    public let statusItem: NSStatusItem
    public let popover: NSPopover
    public let preferences: PreferencesStore
    public let coordinator: MetricsCoordinator

    private var cancellables = Set<AnyCancellable>()
    private var defaultIcon: NSImage?

    public init(
        preferences: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.preferences = preferences
        self.coordinator = coordinator
        super.init()

        loadDefaultIcon()
        configureStatusItem()
        configurePopover()
        setupSubscriptions()
        updateStatusItemDisplay()
    }

    private func loadDefaultIcon() {
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let image = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent", accessibilityDescription: "iStats")?.withSymbolConfiguration(iconConfig) {
            image.isTemplate = true
            self.defaultIcon = image
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DetailPopoverView(coordinator: coordinator, preferences: preferences)
        )
    }

    private func setupSubscriptions() {
        // Observe preference changes affecting display
        Publishers.Merge4(
            preferences.$menuBarDisplayMode.map { _ in () }.eraseToAnyPublisher(),
            preferences.$temperatureUnit.map { _ in () }.eraseToAnyPublisher(),
            preferences.$networkUnit.map { _ in () }.eraseToAnyPublisher(),
            preferences.$byteUnitStandard.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateStatusItemDisplay()
        }
        .store(in: &cancellables)

        // Observe live telemetry samples
        Publishers.Merge4(
            coordinator.$latestCPU.map { _ in () }.eraseToAnyPublisher(),
            coordinator.$latestMemory.map { _ in () }.eraseToAnyPublisher(),
            coordinator.$latestNetwork.map { _ in () }.eraseToAnyPublisher(),
            coordinator.$latestGPU.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateStatusItemDisplay()
        }
        .store(in: &cancellables)

        Publishers.Merge(
            coordinator.$latestPower.map { _ in () }.eraseToAnyPublisher(),
            coordinator.$latestThermal.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateStatusItemDisplay()
        }
        .store(in: &cancellables)
    }

    /// Formats the menu bar title and icon according to the active `MenuBarDisplayMode` (Requirement 9.4).
    public func updateStatusItemDisplay() {
        guard let button = statusItem.button else { return }

        let mode = preferences.menuBarDisplayMode
        let cpu = coordinator.latestCPU?.value
        let memory = coordinator.latestMemory?.value
        let network = coordinator.latestNetwork?.value
        let power = coordinator.latestPower?.value
        let thermal = coordinator.latestThermal?.value
        let gpu = coordinator.latestGPU?.value
        let tempUnit = preferences.temperatureUnit
        let netUnit = preferences.networkUnit
        let byteStd = preferences.byteUnitStandard

        switch mode {
        case .icon:
            button.image = defaultIcon
            button.imagePosition = .imageOnly
            button.title = ""
        case .cpu, .memory, .both, .network, .battery, .thermal, .gpu:
            let title = Self.formatTitle(
                mode: mode,
                cpu: cpu,
                memory: memory,
                network: network,
                power: power,
                thermal: thermal,
                gpu: gpu,
                temperatureUnit: tempUnit,
                networkUnit: netUnit,
                byteUnitStandard: byteStd
            )
            button.image = nil
            button.imagePosition = .noImage
            button.title = title
        }

        // Set rich tooltip
        button.toolTip = Self.formatToolTip(
            cpu: cpu,
            memory: memory,
            network: network,
            power: power,
            thermal: thermal,
            gpu: gpu,
            temperatureUnit: tempUnit,
            networkUnit: netUnit,
            byteUnitStandard: byteStd
        )
    }

    /// Pure formatting logic for menu bar text representation across display modes.
    public static func formatTitle(
        mode: PreferencesStore.MenuBarDisplayMode,
        cpu: CPUSample? = nil,
        memory: MemorySample? = nil,
        network: NetworkSample? = nil,
        power: PowerSample? = nil,
        thermal: ThermalSample? = nil,
        gpu: GPUSample? = nil,
        temperatureUnit: Units.TemperatureUnit = .celsius,
        networkUnit: Units.NetworkUnit = .bytesPerSecond,
        byteUnitStandard: Units.ByteUnitStandard = .iec
    ) -> String {
        switch mode {
        case .icon:
            return ""
        case .cpu:
            if let cpu = cpu {
                return String(format: "CPU %.0f%%", cpu.totalUsage)
            } else {
                return "CPU --%"
            }
        case .memory:
            if let mem = memory, mem.total > 0 {
                let ratio = (Double(mem.used) / Double(mem.total)) * 100.0
                return String(format: "RAM %.0f%%", ratio)
            } else {
                return "RAM --%"
            }
        case .both:
            let cpuStr = cpu != nil ? String(format: "%.0f%%", cpu!.totalUsage) : "--%"
            let memStr: String
            if let mem = memory, mem.total > 0 {
                let ratio = (Double(mem.used) / Double(mem.total)) * 100.0
                memStr = String(format: "%.0f%%", ratio)
            } else {
                memStr = "--%"
            }
            return "CPU \(cpuStr)  RAM \(memStr)"
        case .network:
            if let net = network {
                let inStr = Units.formatNetworkRate(net.totalBytesInPerSec, unit: networkUnit, standard: byteUnitStandard, fractionDigits: 0)
                let outStr = Units.formatNetworkRate(net.totalBytesOutPerSec, unit: networkUnit, standard: byteUnitStandard, fractionDigits: 0)
                return "↓ \(inStr)  ↑ \(outStr)"
            } else {
                return "Net --"
            }
        case .battery:
            if let pwr = power {
                if !pwr.hasBattery {
                    return "AC Power"
                } else if let charge = pwr.charge {
                    let bolt = (pwr.state == .charging) ? " ⚡" : ""
                    return String(format: "%.0f%%%@", charge, bolt)
                } else {
                    return "Bat --%"
                }
            } else {
                return "Bat --%"
            }
        case .thermal:
            if let th = thermal, let sensor = th.sensors.first(where: { $0.name.contains("Package") || $0.name.contains("CPU") || $0.name.contains("SoC") }) ?? th.sensors.first {
                return Units.formatTemperature(sensor.celsius, unit: temperatureUnit, fractionDigits: 0)
            } else {
                return temperatureUnit == .celsius ? "--°C" : "--°F"
            }
        case .gpu:
            if let g = gpu, let util = g.utilization {
                return String(format: "GPU %.0f%%", util)
            } else {
                return "GPU --%"
            }
        }
    }

    /// Formats tooltip text displaying current snapshot stats.
    public static func formatToolTip(
        cpu: CPUSample? = nil,
        memory: MemorySample? = nil,
        network: NetworkSample? = nil,
        power: PowerSample? = nil,
        thermal: ThermalSample? = nil,
        gpu: GPUSample? = nil,
        temperatureUnit: Units.TemperatureUnit = .celsius,
        networkUnit: Units.NetworkUnit = .bytesPerSecond,
        byteUnitStandard: Units.ByteUnitStandard = .iec
    ) -> String {
        var parts: [String] = ["iStats"]
        if let cpu = cpu {
            parts.append(String(format: "CPU: %.1f%%", cpu.totalUsage))
        }
        if let mem = memory, mem.total > 0 {
            let ratio = (Double(mem.used) / Double(mem.total)) * 100.0
            parts.append(String(format: "RAM: %.1f%% (%@)", ratio, mem.pressure.displayName))
        }
        if let g = gpu, let util = g.utilization {
            parts.append(String(format: "GPU: %.1f%%", util))
        }
        if let net = network {
            let inStr = Units.formatNetworkRate(net.totalBytesInPerSec, unit: networkUnit, standard: byteUnitStandard, fractionDigits: 1)
            let outStr = Units.formatNetworkRate(net.totalBytesOutPerSec, unit: networkUnit, standard: byteUnitStandard, fractionDigits: 1)
            parts.append("Net: ↓ \(inStr) ↑ \(outStr)")
        }
        if let th = thermal, let sensor = th.sensors.first(where: { $0.name.contains("Package") || $0.name.contains("CPU") }) ?? th.sensors.first {
            parts.append("Temp: \(Units.formatTemperature(sensor.celsius, unit: temperatureUnit, fractionDigits: 1))")
        }
        if let pwr = power {
            if pwr.hasBattery, let charge = pwr.charge {
                let stateStr = pwr.state == .charging ? " (Charging)" : ""
                parts.append(String(format: "Bat: %.0f%%%@", charge, stateStr))
            } else if !pwr.hasBattery {
                parts.append("Power: AC Connected")
            }
        }
        return parts.joined(separator: " • ")
    }

    @objc public func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    public func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    public func hidePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}
