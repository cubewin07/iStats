import AppKit
import SwiftUI
import Combine
import iStatsCore

@MainActor
public final class MenuBarController: NSObject {
    /// Active status items in the macOS menu bar, mapped by item configuration ID (ADR 0007).
    public private(set) var statusItems: [String: NSStatusItem] = [:]

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

    /// Identifier for the fallback status item displayed when all menu items are disabled.
    public static let fallbackStatusItemId = "app.istats.fallback"

    // MARK: - Status Item Lifecycle & Synchronization (ADR 0007)

    /// Synchronizes active NSStatusItems with the current preferences (activeMenuBarItems).
    public func syncStatusItems() {
        let activeConfigs = preferences.activeMenuBarItems
        let activeIds = Set(activeConfigs.map(\.id))

        if activeConfigs.isEmpty {
            // Remove any leftover category status items
            for (id, item) in statusItems where id != Self.fallbackStatusItemId {
                NSStatusBar.system.removeStatusItem(item)
                statusItems.removeValue(forKey: id)
            }

            // Install or keep fallback status item with iStats app icon so user is never orphaned
            if statusItems[Self.fallbackStatusItemId] == nil {
                let fallbackItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = fallbackItem.button {
                    button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent", accessibilityDescription: "iStats")
                    button.title = ""
                    button.toolTip = "iStats (All menu items disabled - Click for settings)"
                    button.target = self
                    button.action = #selector(statusItemClicked(_:))
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                    button.identifier = NSUserInterfaceItemIdentifier(Self.fallbackStatusItemId)
                }
                statusItems[Self.fallbackStatusItemId] = fallbackItem
            }
            return
        }

        // Active items exist: clean up fallback item if present
        if let fallbackItem = statusItems.removeValue(forKey: Self.fallbackStatusItemId) {
            NSStatusBar.system.removeStatusItem(fallbackItem)
        }

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
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.identifier = NSUserInterfaceItemIdentifier(config.id)
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
        button.setAccessibilityLabel(result.accessibilityLabel)

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
              let rawId = button.identifier?.rawValue
        else {
            return
        }

        let isRightClick = (NSApp.currentEvent?.type == .rightMouseUp) ||
                           ((NSApp.currentEvent?.modifierFlags.contains(.control)) ?? false)

        if isRightClick {
            showContextMenu(for: button)
            return
        }

        if rawId == Self.fallbackStatusItemId {
            if popover.isShown && currentlyShownButton == button {
                hidePopover()
            } else {
                showUniversalPopover(relativeTo: button)
            }
            return
        }

        let categoryRaw = rawId.components(separatedBy: ".").first ?? rawId
        guard let category = MetricCategory(rawValue: categoryRaw) else { return }

        if popover.isShown && currentlyShownButton == button {
            hidePopover()
        } else {
            showPopover(for: category, relativeTo: button)
        }
    }

    /// Shows a standard macOS context menu on right-click.
    private func showContextMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "iStats", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(string: "iStats", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let prefItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)

        let activityMonitorItem = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        activityMonitorItem.target = self
        menu.addItem(activityMonitorItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit iStats", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showPreferences()
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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

    /// Shows the universal popover displaying all metrics or app overview.
    public func showUniversalPopover(relativeTo button: NSStatusBarButton) {
        popover.contentViewController = NSHostingController(
            rootView: DetailPopoverView(
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
