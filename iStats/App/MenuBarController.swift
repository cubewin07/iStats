import AppKit
import SwiftUI
import Combine
import iStatsCore

@MainActor
public final class MenuBarController: NSObject {
    /// Active status items in the macOS menu bar, mapped by item configuration UUID (ADR 0007).
    public private(set) var statusItems: [UUID: NSStatusItem] = [:]

    public let popover: NSPopover
    public let preferences: PreferencesStore
    public let coordinator: MetricsCoordinator

    private var cancellables = Set<AnyCancellable>()
    private var currentlyShownButton: NSStatusBarButton?

    public init(
        preferences: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.popover = NSPopover()
        self.preferences = preferences
        self.coordinator = coordinator
        super.init()

        configurePopover()
        syncStatusItems()
        setupSubscriptions()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
    }

    // MARK: - Status Item Lifecycle & Synchronization (ADR 0007)

    /// Synchronizes active NSStatusItems with the current preferences (activeMenuBarItems).
    public func syncStatusItems() {
        let activeConfigs = preferences.activeMenuBarItems
        let activeIds = Set(activeConfigs.map(\.id))

        // 1. Remove status items for items/categories that have been disabled or deleted
        for (id, item) in statusItems where !activeIds.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems.removeValue(forKey: id)
        }

        // 2. Create and configure status items for newly active items
        for config in activeConfigs where statusItems[config.id] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.identifier = NSUserInterfaceItemIdentifier(config.id.uuidString)
            }
            statusItems[config.id] = item
        }

        // 3. Re-render all active status items
        updateAllStatusItems()
    }

    // MARK: - Subscriptions

    private func setupSubscriptions() {
        // Observe configuration and display formatting changes
        Publishers.Merge3(
            preferences.$menuBarItems.map { _ in () }.eraseToAnyPublisher(),
            preferences.$enabledCategories.map { _ in () }.eraseToAnyPublisher(),
            preferences.$menuBarDisplayMode.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.syncStatusItems()
        }
        .store(in: &cancellables)

        Publishers.Merge3(
            preferences.$temperatureUnit.map { _ in () }.eraseToAnyPublisher(),
            preferences.$networkUnit.map { _ in () }.eraseToAnyPublisher(),
            preferences.$byteUnitStandard.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateAllStatusItems()
        }
        .store(in: &cancellables)

        // Observe telemetry streams and update matching category items
        coordinator.$latestCPU
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems(for: .cpu) }
            .store(in: &cancellables)

        coordinator.$latestMemory
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems(for: .memory) }
            .store(in: &cancellables)

        coordinator.$latestGPU
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems(for: .gpu) }
            .store(in: &cancellables)

        coordinator.$latestThermal
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems(for: .thermal) }
            .store(in: &cancellables)

        coordinator.$latestFan
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems(for: .fan) }
            .store(in: &cancellables)

        coordinator.$latestNetwork
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems(for: .network) }
            .store(in: &cancellables)

        coordinator.$latestDisk
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems(for: .disk) }
            .store(in: &cancellables)

        coordinator.$latestPower
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems(for: .power) }
            .store(in: &cancellables)
    }

    // MARK: - Rendering & Updates

    /// Updates all active status item representations.
    public func updateAllStatusItems() {
        for config in preferences.activeMenuBarItems {
            updateStatusItem(config: config)
        }
    }

    /// Updates all active status items belonging to a specific metric category.
    public func updateItems(for category: MetricCategory) {
        let matching = preferences.activeMenuBarItems.filter { $0.category == category }
        for config in matching {
            updateStatusItem(config: config)
        }
    }

    private func updateStatusItem(config: MenuBarItemConfig) {
        guard let item = statusItems[config.id], let button = item.button else { return }

        let result = MenuBarIconRenderer.render(
            config: config,
            coordinator: coordinator,
            preferences: preferences
        )

        button.image = result.image
        button.title = result.title
        button.toolTip = result.toolTip

        if result.image != nil && !result.title.isEmpty {
            button.imagePosition = .imageLeading
        } else if result.image != nil {
            button.imagePosition = .imageOnly
        } else {
            button.imagePosition = .noImage
        }
    }

    // MARK: - Popover Actions & Category Routing (ADR 0007)

    @objc public func statusItemClicked(_ sender: AnyObject?) {
        guard let button = sender as? NSStatusBarButton,
              let rawId = button.identifier?.rawValue,
              let uuid = UUID(uuidString: rawId),
              let config = preferences.menuBarItems.first(where: { $0.id == uuid })
        else {
            return
        }

        if popover.isShown && currentlyShownButton == button {
            hidePopover()
        } else {
            showPopover(for: config.category, relativeTo: button)
        }
    }

    /// Shows the dedicated popover for a specific category anchored to a menu bar button.
    public func showPopover(for category: MetricCategory, relativeTo button: NSStatusBarButton) {
        popover.contentViewController = NSHostingController(
            rootView: CategoryDetailPopoverView(
                category: category,
                coordinator: coordinator,
                preferences: preferences
            )
        )
        currentlyShownButton = button
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    public func hidePopover() {
        if popover.isShown {
            popover.performClose(nil)
            currentlyShownButton = nil
        }
    }

    // MARK: - Legacy Formatting Helpers (Preserved for compatibility)

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
            return cpu != nil ? String(format: "CPU %.0f%%", cpu!.totalUsage) : "CPU --%"
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
}
