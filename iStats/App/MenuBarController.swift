import AppKit
import SwiftUI
import Combine
import iStatsCore

@MainActor
public final class MenuBarController: NSObject {
    /// Active status items in the macOS menu bar, mapped by item configuration ID (ADR 0007).
    public private(set) var statusItems: [String: NSStatusItem] = [:]

    /// Active dedicated popovers in the macOS menu bar, mapped by item configuration ID (ADR 0007).
    /// Each category configuration owns its own dedicated NSPopover instance.
    public private(set) var popovers: [String: NSPopover] = [:]

    private let fallbackPopover: NSPopover
    public let preferences: PreferencesStore
    public let coordinator: MetricsCoordinator

    private var cancellables = Set<AnyCancellable>()
    private var pendingCategories = Set<MetricCategory>()
    private var isCategoryUpdateScheduled = false
    public private(set) var currentlyShownButton: NSStatusBarButton?
    private var lastConfiguredPopoverStyles: [String: PopoverStyle] = [:]
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    // MARK: - Render State & Performance Instrumentation (Stage 3 Energy Optimization)

    public struct ItemRenderState: Equatable {
        public let title: String
        public let toolTip: String
        public let accessibilityLabel: String
        public let imagePosition: NSControl.ImagePosition
        public let imageRef: ObjectIdentifier?
        public let visualKey: String?

        public init(
            title: String,
            toolTip: String,
            accessibilityLabel: String,
            imagePosition: NSControl.ImagePosition,
            imageRef: ObjectIdentifier?,
            visualKey: String? = nil
        ) {
            self.title = title
            self.toolTip = toolTip
            self.accessibilityLabel = accessibilityLabel
            self.imagePosition = imagePosition
            self.imageRef = imageRef
            self.visualKey = visualKey
        }
    }

    public private(set) var previousRenderStates: [String: ItemRenderState] = [:]

    /// Count of times a status item button was actually modified in AppKit.
    public private(set) var buttonMutationCount: Int = 0

    /// Count of times dirty-checking bypassed AppKit button modifications.
    public private(set) var dirtyCheckBypassCount: Int = 0

    /// Resets mutation/bypass telemetry counters (primarily for tests).
    public func resetPerformanceCounters() {
        buttonMutationCount = 0
        dirtyCheckBypassCount = 0
    }

    /// Returns the currently active popover, or the popover matching currentlyShownButton,
    /// or fallback/primary popover for backward compatibility.
    public var popover: NSPopover {
        if let button = currentlyShownButton,
           let rawId = button.identifier?.rawValue,
           let p = popovers[rawId] {
            ensurePopoverContent(for: rawId, popover: p)
            return p
        }
        for (id, p) in popovers where p.isShown {
            ensurePopoverContent(for: id, popover: p)
            return p
        }
        if let fallbackP = popovers[Self.fallbackStatusItemId] {
            ensurePopoverContent(for: Self.fallbackStatusItemId, popover: fallbackP)
            return fallbackP
        }
        if let (firstId, firstP) = popovers.first {
            ensurePopoverContent(for: firstId, popover: firstP)
            return firstP
        }
        ensurePopoverContent(for: Self.fallbackStatusItemId, popover: fallbackPopover)
        return fallbackPopover
    }

    /// Helper to retrieve the dedicated popover for a specific category config ID.
    public func popover(for configId: String) -> NSPopover? {
        guard let p = popovers[configId] else { return nil }
        ensurePopoverContent(for: configId, popover: p)
        return p
    }

    public init(
        preferences: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.fallbackPopover = NSPopover()
        self.preferences = preferences
        self.coordinator = coordinator
        super.init()

        fallbackPopover.behavior = .transient
        fallbackPopover.animates = true
        fallbackPopover.delegate = self

        syncStatusItems()
        setupSubscriptions()
    }

    isolated deinit {
        stopScrubbingMonitor()
    }

    /// Identifier for the fallback status item displayed when all menu items are disabled.
    public static let fallbackStatusItemId = "app.istats.fallback"

    // MARK: - Popover Factory (ADR 0007)

    /// Instantiates the dedicated NSHostingController for a given menu bar item configuration.
    public func makeHostingController(for config: MenuBarItemConfig) -> NSViewController {
        ConfigPopoverFactory.makeHostingController(
            config: config,
            coordinator: coordinator,
            preferences: preferences
        )
    }

    /// Backward-compatible category-only hosting controller factory.
    public func makeHostingController(for category: MetricCategory) -> NSViewController {
        let config = MenuBarItemConfig(category: category, style: .text)
        return makeHostingController(for: config)
    }

    private func createPopover(for config: MenuBarItemConfig) -> NSPopover {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        return p
    }

    private func createFallbackPopover() -> NSPopover {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        return p
    }

    private func ensurePopoverContent(for configId: String, popover: NSPopover) {
        guard popover.contentViewController == nil else { return }
        if configId == Self.fallbackStatusItemId {
            popover.contentViewController = NSHostingController(
                rootView: DetailPopoverView(coordinator: coordinator, preferences: preferences)
            )
            return
        }
        if let activeConfig = preferences.menuBarItems.first(where: { $0.id == configId }) {
            popover.contentViewController = makeHostingController(for: activeConfig)
            return
        }
        let parts = configId.components(separatedBy: ".")
        let categoryRaw = parts.first ?? configId
        let styleRaw = parts.dropFirst().joined(separator: ".")
        if let category = MetricCategory(rawValue: categoryRaw) {
            let style = MetricDisplayStyle(rawValue: styleRaw) ?? .text
            let popoverStyle = preferences.popoverStyle(for: category, widgetStyle: style)
            let config = MenuBarItemConfig(category: category, style: style, popoverStyle: popoverStyle)
            popover.contentViewController = makeHostingController(for: config)
        }
    }

    // MARK: - Status Item Lifecycle & Synchronization (ADR 0007)

    /// Synchronizes active NSStatusItems with the current preferences (activeMenuBarItems).
    public func syncStatusItems() {
        let activeConfigs = preferences.activeMenuBarItems
        let activeIds = Set(activeConfigs.map(\.id))

        if activeConfigs.isEmpty {
            // Remove any leftover category status items and popovers
            for (id, item) in statusItems where id != Self.fallbackStatusItemId {
                NSStatusBar.system.removeStatusItem(item)
                statusItems.removeValue(forKey: id)
                previousRenderStates.removeValue(forKey: id)
                lastConfiguredPopoverStyles.removeValue(forKey: id)
                if let p = popovers.removeValue(forKey: id), p.isShown {
                    p.performClose(nil)
                }
            }

            // Install or keep fallback status item with iStats app icon so user is never orphaned
            let fallbackItem: NSStatusItem
            if let existing = statusItems[Self.fallbackStatusItemId] {
                fallbackItem = existing
                if popovers[Self.fallbackStatusItemId] == nil {
                    popovers[Self.fallbackStatusItemId] = createFallbackPopover()
                }
            } else {
                let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItems[Self.fallbackStatusItemId] = created
                popovers[Self.fallbackStatusItemId] = createFallbackPopover()
                fallbackItem = created
            }

            if let button = fallbackItem.button {
                let isPaused = preferences.isSamplingPaused
                let image = NSImage(
                    systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                    accessibilityDescription: isPaused ? "iStats (Sampling Paused)" : "iStats"
                )
                image?.isTemplate = true
                button.image = image
                button.title = ""
                button.toolTip = isPaused
                    ? "iStats (Sampling Paused — Click to resume or open settings)"
                    : "iStats (All menu items disabled - Click for settings)"
                button.setAccessibilityLabel(isPaused ? "iStats (Sampling Paused)" : "iStats")
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.identifier = NSUserInterfaceItemIdentifier(Self.fallbackStatusItemId)
            }
            return
        }

        // Active items exist: clean up fallback item if present
        if let fallbackItem = statusItems.removeValue(forKey: Self.fallbackStatusItemId) {
            NSStatusBar.system.removeStatusItem(fallbackItem)
            previousRenderStates.removeValue(forKey: Self.fallbackStatusItemId)
            if let p = popovers.removeValue(forKey: Self.fallbackStatusItemId), p.isShown {
                p.performClose(nil)
            }
        }

        // 1. Remove status items and popovers for items/categories that have been disabled or deleted
        for (id, item) in statusItems where !activeIds.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems.removeValue(forKey: id)
            previousRenderStates.removeValue(forKey: id)
            lastConfiguredPopoverStyles.removeValue(forKey: id)
            if let p = popovers.removeValue(forKey: id), p.isShown {
                p.performClose(nil)
            }
        }

        // 2. Create and configure status items and dedicated popovers for newly active items
        for config in activeConfigs where statusItems[config.id] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.identifier = NSUserInterfaceItemIdentifier(config.id)
            }
            statusItems[config.id] = item
            popovers[config.id] = createPopover(for: config)
        }

        // 3. Invalidate or swap cached popover content if custom popover style was updated
        for config in activeConfigs {
            let resolved = preferences.resolvedPopoverStyle(for: config.category, widgetStyle: config.style)
            if lastConfiguredPopoverStyles[config.id] != resolved {
                lastConfiguredPopoverStyles[config.id] = resolved
                if let p = popovers[config.id] {
                    if p.isShown {
                        p.contentViewController = makeHostingController(for: config)
                    } else {
                        p.contentViewController = nil
                    }
                }
            }
        }

        // 4. Re-render all active status items
        updateAllStatusItems()
    }

    // MARK: - Subscriptions

    private func setupSubscriptions() {
        // Observe configuration, pause state, and display formatting changes
        Publishers.Merge5(
            preferences.$menuBarItems.map { _ in () }.eraseToAnyPublisher(),
            preferences.$widgetPopoverStyles.map { _ in () }.eraseToAnyPublisher(),
            preferences.$enabledCategories.map { _ in () }.eraseToAnyPublisher(),
            preferences.$menuBarDisplayMode.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isSamplingPaused.map { _ in () }.eraseToAnyPublisher()
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
            self?.previousRenderStates.removeAll()
            self?.updateAllStatusItems()
        }
        .store(in: &cancellables)

        // Clear cached non-template menu bar icons and render states when macOS switches Light/Dark appearance
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MenuBarIconRenderer.clearImageCache()
                self?.previousRenderStates.removeAll()
                self?.updateAllStatusItems()
            }
            .store(in: &cancellables)

        // Observe telemetry streams and coalesce updates into a single main runloop pass per batch
        coordinator.$latestCPU
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleCategoryUpdate(.cpu) }
            .store(in: &cancellables)

        coordinator.$latestMemory
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleCategoryUpdate(.memory) }
            .store(in: &cancellables)

        coordinator.$latestGPU
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleCategoryUpdate(.gpu) }
            .store(in: &cancellables)

        coordinator.$latestThermal
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleCategoryUpdate(.thermal) }
            .store(in: &cancellables)

        coordinator.$latestFan
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleCategoryUpdate(.fan) }
            .store(in: &cancellables)

        coordinator.$latestNetwork
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleCategoryUpdate(.network) }
            .store(in: &cancellables)

        coordinator.$latestDisk
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleCategoryUpdate(.disk) }
            .store(in: &cancellables)

        coordinator.$latestPower
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleCategoryUpdate(.power) }
            .store(in: &cancellables)
    }

    private func scheduleCategoryUpdate(_ category: MetricCategory) {
        pendingCategories.insert(category)
        guard !isCategoryUpdateScheduled else { return }
        isCategoryUpdateScheduled = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                self?.flushPendingCategoryUpdates()
            }
        }
    }

    private func flushPendingCategoryUpdates() {
        isCategoryUpdateScheduled = false
        guard !pendingCategories.isEmpty else { return }
        let categories = pendingCategories
        pendingCategories.removeAll()
        for config in preferences.activeMenuBarItems where categories.contains(config.category) {
            updateStatusItem(config: config)
        }
    }

    // MARK: - Rendering & Updates

    /// Updates all active status item representations.
    public func updateAllStatusItems() {
        pendingCategories.removeAll()
        for config in preferences.activeMenuBarItems {
            updateStatusItem(config: config)
        }
    }

    /// Updates all active status items belonging to a specific metric category.
    public func updateItems(for category: MetricCategory) {
        pendingCategories.remove(category)
        let matching = preferences.activeMenuBarItems.filter { $0.category == category }
        for config in matching {
            updateStatusItem(config: config)
        }
    }

    private func updateStatusItem(config: MenuBarItemConfig) {
        guard let item = statusItems[config.id], let button = item.button else { return }

        let visualKey = MenuBarIconRenderer.computeVisualKey(
            config: config,
            coordinator: coordinator,
            preferences: preferences
        )

        let result = MenuBarIconRenderer.render(
            config: config,
            coordinator: coordinator,
            preferences: preferences,
            visualKey: visualKey
        )

        let targetPosition: NSControl.ImagePosition
        if result.image != nil && !result.title.isEmpty {
            targetPosition = .imageLeading
        } else if result.image != nil {
            targetPosition = .imageOnly
        } else {
            targetPosition = .noImage
        }

        let imageRef = result.image.map { ObjectIdentifier($0) }
        let newState = ItemRenderState(
            title: result.title,
            toolTip: result.toolTip,
            accessibilityLabel: result.accessibilityLabel,
            imagePosition: targetPosition,
            imageRef: imageRef,
            visualKey: result.visualKey
        )

        // Dirty checking: if image, title, tooltip, and accessibility label match the previous render state,
        // bypass AppKit mutations completely.
        if let previous = previousRenderStates[config.id] {
            let imageUnchanged = (previous.imageRef == newState.imageRef) ||
                (previous.visualKey != nil && previous.visualKey == newState.visualKey)

            if imageUnchanged &&
               previous.title == newState.title &&
               previous.toolTip == newState.toolTip &&
               previous.accessibilityLabel == newState.accessibilityLabel &&
               previous.imagePosition == newState.imagePosition {
                dirtyCheckBypassCount += 1
                return
            }
        }

        previousRenderStates[config.id] = newState
        buttonMutationCount += 1

        if button.image !== result.image {
            button.image = result.image
        }
        if button.title != result.title {
            button.title = result.title
        }
        if button.toolTip != result.toolTip {
            button.toolTip = result.toolTip
        }
        if button.accessibilityLabel() != result.accessibilityLabel {
            button.setAccessibilityLabel(result.accessibilityLabel)
        }
        if button.imagePosition != targetPosition {
            button.imagePosition = targetPosition
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

        if currentlyShownButton === button {
            hidePopover()
            return
        }

        showPopover(forConfigId: rawId, relativeTo: button, animated: true)
    }

    /// Shows a standard macOS context menu on right-click.
    private func showContextMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "iStats", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(string: "iStats", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let pauseTitle = preferences.isSamplingPaused
            ? "Resume Sampling"
            : "Pause Sampling (Save Battery)"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(toggleSamplingPaused), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
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

    @objc public func toggleSamplingPaused() {
        coordinator.toggleSamplingPaused()
        syncStatusItems()
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
        let rawId = button.identifier?.rawValue ?? category.rawValue
        showPopover(forConfigId: rawId, relativeTo: button, animated: true)
    }

    /// Shows the universal popover displaying all metrics or app overview.
    public func showUniversalPopover(relativeTo button: NSStatusBarButton) {
        showPopover(forConfigId: Self.fallbackStatusItemId, relativeTo: button, animated: true)
    }

    /// Dedicated popover presenter with optional animation (disabled during hover scrubbing for instantaneous switching).
    public func showPopover(forConfigId rawId: String, relativeTo button: NSStatusBarButton, animated: Bool = true) {
        let targetPopover: NSPopover
        if let existing = popovers[rawId] {
            targetPopover = existing
        } else if rawId == Self.fallbackStatusItemId {
            let p = createFallbackPopover()
            popovers[rawId] = p
            targetPopover = p
        } else {
            let parts = rawId.components(separatedBy: ".")
            let categoryRaw = parts.first ?? rawId
            let styleRaw = parts.dropFirst().joined(separator: ".")
            if let category = MetricCategory(rawValue: categoryRaw) {
                let style = MetricDisplayStyle(rawValue: styleRaw) ?? .text
                let popoverStyle = preferences.popoverStyle(for: category, widgetStyle: style)
                let config = MenuBarItemConfig(category: category, style: style, popoverStyle: popoverStyle)
                let p = createPopover(for: config)
                popovers[rawId] = p
                targetPopover = p
            } else {
                let p = createFallbackPopover()
                popovers[rawId] = p
                targetPopover = p
            }
        }

        // Close any currently visible popover without destroying view controllers
        for (_, p) in popovers where p !== targetPopover && p.isShown {
            p.animates = animated
            p.performClose(nil)
            p.animates = true
        }
        if fallbackPopover !== targetPopover && fallbackPopover.isShown {
            fallbackPopover.animates = animated
            fallbackPopover.performClose(nil)
            fallbackPopover.animates = true
        }

        ensurePopoverContent(for: rawId, popover: targetPopover)
        currentlyShownButton = button
        targetPopover.animates = animated
        targetPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        targetPopover.contentViewController?.view.window?.makeKey()
        targetPopover.animates = true

        startScrubbingMonitor()
    }

    public func hidePopover() {
        stopScrubbingMonitor()
        if let button = currentlyShownButton,
           let rawId = button.identifier?.rawValue,
           let activePopover = popovers[rawId] {
            if activePopover.isShown {
                activePopover.performClose(nil)
            }
        }
        for (_, p) in popovers where p.isShown {
            p.performClose(nil)
        }
        if fallbackPopover.isShown {
            fallbackPopover.performClose(nil)
        }
        currentlyShownButton = nil
    }

    // MARK: - Menu Bar Scrubbing (ADR 0007 & iStat Parity)

    /// Handles cursor motion across status item buttons when a popover is actively presented.
    public func handleMouseMovedDuringScrubbing(to mouseLocation: NSPoint) {
        guard let currentButton = currentlyShownButton else {
            stopScrubbingMonitor()
            return
        }

        for (id, item) in statusItems {
            guard let button = item.button, button !== currentButton, let window = button.window else {
                continue
            }
            let buttonScreenRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let hitRect = buttonScreenRect.insetBy(dx: 0, dy: -6)
            if hitRect.contains(mouseLocation) {
                showPopover(forConfigId: id, relativeTo: button, animated: false)
                break
            }
        }
    }

    private func startScrubbingMonitor() {
        guard globalMouseMonitor == nil && localMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouseMovedDuringScrubbing(to: NSEvent.mouseLocation)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseMovedDuringScrubbing(to: NSEvent.mouseLocation)
            }
            return event
        }
    }

    private func stopScrubbingMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
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

// MARK: - NSPopoverDelegate

extension MenuBarController: NSPopoverDelegate {
    public func popoverDidClose(_ notification: Notification) {
        if let closed = notification.object as? NSPopover {
            // Keep contentViewController warm across closes for instantaneous reopening.
            if let button = currentlyShownButton,
               let rawId = button.identifier?.rawValue,
               popovers[rawId] === closed || fallbackPopover === closed {
                currentlyShownButton = nil
                stopScrubbingMonitor()
            }
        }
    }
}
