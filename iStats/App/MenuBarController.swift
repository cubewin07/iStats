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
        // Observe menu bar display mode changes
        preferences.$menuBarDisplayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemDisplay()
            }
            .store(in: &cancellables)

        // Observe live CPU samples
        coordinator.$latestCPU
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemDisplay()
            }
            .store(in: &cancellables)

        // Observe live Memory samples
        coordinator.$latestMemory
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

        switch mode {
        case .icon:
            button.image = defaultIcon
            button.imagePosition = .imageOnly
            button.title = ""
        case .cpu, .memory, .both:
            let title = Self.formatTitle(mode: mode, cpu: cpu, memory: memory)
            button.image = nil
            button.imagePosition = .noImage
            button.title = title
        }

        // Set rich tooltip
        button.toolTip = Self.formatToolTip(cpu: cpu, memory: memory)
    }

    /// Pure formatting logic for menu bar text representation across display modes.
    public static func formatTitle(
        mode: PreferencesStore.MenuBarDisplayMode,
        cpu: CPUSample?,
        memory: MemorySample?
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
        }
    }

    /// Formats tooltip text displaying current snapshot stats.
    public static func formatToolTip(cpu: CPUSample?, memory: MemorySample?) -> String {
        var parts: [String] = ["iStats"]
        if let cpu = cpu {
            parts.append(String(format: "CPU: %.1f%%", cpu.totalUsage))
        }
        if let mem = memory, mem.total > 0 {
            let ratio = (Double(mem.used) / Double(mem.total)) * 100.0
            parts.append(String(format: "RAM: %.1f%% (%@)", ratio, mem.pressure.displayName))
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
