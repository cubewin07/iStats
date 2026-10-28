import Foundation
import Combine

/// A thread-safe, persisted preferences store managing user configuration
/// for sampling intervals, metric categories, display units, and app behaviors
/// (Requirements 11.1, 11.2, 11.3, 11.4, 11.5, ADR 0006).
public final class PreferencesStore: ObservableObject, @unchecked Sendable {
    // MARK: - Constants & Bounds

    /// Minimum allowable sampling interval in seconds (Requirement 11.2).
    public static let minRefreshInterval: TimeInterval = 0.5

    /// Maximum allowable sampling interval in seconds (Requirement 11.2).
    public static let maxRefreshInterval: TimeInterval = 60.0

    /// Default sampling interval in seconds.
    public static let defaultRefreshInterval: TimeInterval = 2.0

    // MARK: - Keys

    public enum Keys {
        public static let refreshInterval = "iStats.refreshInterval"
        public static let enabledCategories = "iStats.enabledCategories"
        public static let temperatureUnit = "iStats.temperatureUnit"
        public static let networkUnit = "iStats.networkUnit"
        public static let byteUnitStandard = "iStats.byteUnitStandard"
        public static let showDockIcon = "iStats.showDockIcon"
        public static let launchAtLogin = "iStats.launchAtLogin"
        public static let menuBarDisplayMode = "iStats.menuBarDisplayMode"
        public static let menuBarItems = "iStats.menuBarItems"
        public static let widgetPopoverStyles = "iStats.widgetPopoverStyles"
        public static let isSamplingPaused = "iStats.isSamplingPaused"
        public static let isAutoPausedByLowPowerMode = "iStats.isAutoPausedByLowPowerMode"
        public static let autoPauseOnLowPowerMode = "iStats.autoPauseOnLowPowerMode"

        // Notification & Alert Keys
        public static let notificationsEnabled = "iStats.notificationsEnabled"
        public static let cpuAlertEnabled = "iStats.cpuAlertEnabled"
        public static let cpuAlertThreshold = "iStats.cpuAlertThreshold"
        public static let memoryAlertEnabled = "iStats.memoryAlertEnabled"
        public static let memoryAlertThreshold = "iStats.memoryAlertThreshold"
        public static let memoryAlertCriticalPressureOnly = "iStats.memoryAlertCriticalPressureOnly"
        public static let batteryLowAlertEnabled = "iStats.batteryLowAlertEnabled"
        public static let batteryLowThreshold = "iStats.batteryLowThreshold"
        public static let batteryFullAlertEnabled = "iStats.batteryFullAlertEnabled"
        public static let thermalAlertEnabled = "iStats.thermalAlertEnabled"
        public static let thermalAlertThreshold = "iStats.thermalAlertThreshold"
        public static let diskAlertEnabled = "iStats.diskAlertEnabled"
        public static let diskAlertThreshold = "iStats.diskAlertThreshold"
        public static let alertCooldownInterval = "iStats.alertCooldownInterval"
    }

    /// The metric representation shown directly in the macOS menu bar status item (Requirement 9.4).
    public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
        case icon = "icon"
        case cpu = "cpu"
        case memory = "memory"
        case both = "both"
        case network = "network"
        case battery = "battery"
        case thermal = "thermal"
        case gpu = "gpu"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .icon: return "Icon Only"
            case .cpu: return "CPU Usage"
            case .memory: return "Memory Usage"
            case .both: return "CPU & Memory"
            case .network: return "Network Rate"
            case .battery: return "Battery Level"
            case .thermal: return "SoC Temperature"
            case .gpu: return "GPU Usage"
            }
        }
    }

    // MARK: - Singleton

    /// Shared singleton instance backed by standard UserDefaults.
    public static let shared = PreferencesStore()

    // MARK: - Storage

    private let userDefaults: UserDefaults
    private let lock = NSLock()

    // MARK: - Published Properties

    /// The sampling refresh interval in seconds, clamped within `[minRefreshInterval, maxRefreshInterval]`.
    @Published public var refreshInterval: TimeInterval {
        didSet {
            let clamped = Self.clampRefreshInterval(refreshInterval)
            if clamped != refreshInterval {
                refreshInterval = clamped
                return
            }
            userDefaults.set(clamped, forKey: Keys.refreshInterval)
        }
    }

    /// The set of metric categories currently enabled for sampling and display.
    @Published public var enabledCategories: Set<MetricCategory> {
        didSet {
            let rawValues = enabledCategories.map(\.rawValue)
            userDefaults.set(rawValues, forKey: Keys.enabledCategories)
        }
    }

    /// The temperature unit to display throughout the app (°C vs °F).
    @Published public var temperatureUnit: Units.TemperatureUnit {
        didSet {
            userDefaults.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit)
        }
    }

    /// The network rate unit to display (Bytes/sec vs Bits/sec).
    @Published public var networkUnit: Units.NetworkUnit {
        didSet {
            userDefaults.set(networkUnit.rawValue, forKey: Keys.networkUnit)
        }
    }

    /// The byte grouping standard to display (SI/Decimal vs IEC/Binary).
    @Published public var byteUnitStandard: Units.ByteUnitStandard {
        didSet {
            userDefaults.set(byteUnitStandard.rawValue, forKey: Keys.byteUnitStandard)
        }
    }

    /// Whether the Dock icon is shown (synced with activation policy).
    @Published public var showDockIcon: Bool {
        didSet {
            userDefaults.set(showDockIcon, forKey: Keys.showDockIcon)
        }
    }

    /// Whether the app is configured to launch automatically at login.
    @Published public var launchAtLogin: Bool {
        didSet {
            userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    /// The metric display mode active in the macOS menu bar status item (Legacy fallback, Requirement 9.4).
    @Published public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode)
        }
    }

    /// User-configured modular menu bar items/widgets (ADR 0007).
    @Published public var menuBarItems: [MenuBarItemConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(menuBarItems) {
                userDefaults.set(data, forKey: Keys.menuBarItems)
            }
        }
    }

    /// User-selected popover style overrides mapped by widget config ID (e.g. "cpu.gauge").
    @Published public var widgetPopoverStyles: [String: PopoverStyle] {
        didSet {
            if let data = try? JSONEncoder().encode(widgetPopoverStyles) {
                userDefaults.set(data, forKey: Keys.widgetPopoverStyles)
            }
        }
    }

    /// Whether background hardware sampling is paused to save battery (Issue #12).
    /// When true, all background samplers stop and the menu bar shows a single minimal app icon.
    @Published public var isSamplingPaused: Bool {
        didSet {
            userDefaults.set(isSamplingPaused, forKey: Keys.isSamplingPaused)
            if !isSamplingPaused && isAutoPausedByLowPowerMode {
                isAutoPausedByLowPowerMode = false
            }
        }
    }

    /// Whether the current sampling pause was triggered automatically by macOS Low Power Mode (Issue #12).
    @Published public var isAutoPausedByLowPowerMode: Bool {
        didSet {
            userDefaults.set(isAutoPausedByLowPowerMode, forKey: Keys.isAutoPausedByLowPowerMode)
        }
    }

    /// Whether to automatically pause sampling when macOS Low Power Mode is enabled (Issue #12).
    /// Once auto-paused, sampling stays paused until the user explicitly turns it back on.
    @Published public var autoPauseOnLowPowerMode: Bool {
        didSet {
            userDefaults.set(autoPauseOnLowPowerMode, forKey: Keys.autoPauseOnLowPowerMode)
        }
    }

    // MARK: - Notifications & Alerts

    /// Master toggle enabling or disabling all metric alert notifications.
    @Published public var notificationsEnabled: Bool {
        didSet {
            userDefaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    /// Whether CPU high-usage alert notifications are enabled.
    @Published public var cpuAlertEnabled: Bool {
        didSet {
            userDefaults.set(cpuAlertEnabled, forKey: Keys.cpuAlertEnabled)
        }
    }

    /// CPU usage percentage threshold for triggering an alert (50.0 - 100.0).
    @Published public var cpuAlertThreshold: Double {
        didSet {
            let clamped = min(max(cpuAlertThreshold, 50.0), 100.0)
            if clamped != cpuAlertThreshold {
                cpuAlertThreshold = clamped
                return
            }
            userDefaults.set(clamped, forKey: Keys.cpuAlertThreshold)
        }
    }

    /// Whether memory pressure alert notifications are enabled.
    @Published public var memoryAlertEnabled: Bool {
        didSet {
            userDefaults.set(memoryAlertEnabled, forKey: Keys.memoryAlertEnabled)
        }
    }

    /// Memory usage percentage threshold for triggering an alert (50.0 - 100.0).
    @Published public var memoryAlertThreshold: Double {
        didSet {
            let clamped = min(max(memoryAlertThreshold, 50.0), 100.0)
            if clamped != memoryAlertThreshold {
                memoryAlertThreshold = clamped
                return
            }
            userDefaults.set(clamped, forKey: Keys.memoryAlertThreshold)
        }
    }

    /// If true, only trigger memory alert on kernel critical pressure; if false, trigger on custom % threshold.
    @Published public var memoryAlertCriticalPressureOnly: Bool {
        didSet {
            userDefaults.set(memoryAlertCriticalPressureOnly, forKey: Keys.memoryAlertCriticalPressureOnly)
        }
    }

    /// Whether low battery alert notifications are enabled.
    @Published public var batteryLowAlertEnabled: Bool {
        didSet {
            userDefaults.set(batteryLowAlertEnabled, forKey: Keys.batteryLowAlertEnabled)
        }
    }

    /// Low battery percentage threshold (5 - 50%).
    @Published public var batteryLowThreshold: Int {
        didSet {
            let clamped = min(max(batteryLowThreshold, 5), 50)
            if clamped != batteryLowThreshold {
                batteryLowThreshold = clamped
                return
            }
            userDefaults.set(clamped, forKey: Keys.batteryLowThreshold)
        }
    }

    /// Whether full battery (100% charged) alert notifications are enabled.
    @Published public var batteryFullAlertEnabled: Bool {
        didSet {
            userDefaults.set(batteryFullAlertEnabled, forKey: Keys.batteryFullAlertEnabled)
        }
    }

    /// Whether thermal high temperature alert notifications are enabled.
    @Published public var thermalAlertEnabled: Bool {
        didSet {
            userDefaults.set(thermalAlertEnabled, forKey: Keys.thermalAlertEnabled)
        }
    }

    /// Thermal temperature threshold in Celsius (60.0 - 105.0 °C).
    @Published public var thermalAlertThreshold: Double {
        didSet {
            let clamped = min(max(thermalAlertThreshold, 60.0), 105.0)
            if clamped != thermalAlertThreshold {
                thermalAlertThreshold = clamped
                return
            }
            userDefaults.set(clamped, forKey: Keys.thermalAlertThreshold)
        }
    }

    /// Whether low disk space alert notifications are enabled.
    @Published public var diskAlertEnabled: Bool {
        didSet {
            userDefaults.set(diskAlertEnabled, forKey: Keys.diskAlertEnabled)
        }
    }

    /// Primary disk usage percentage threshold (70.0 - 98.0%).
    @Published public var diskAlertThreshold: Double {
        didSet {
            let clamped = min(max(diskAlertThreshold, 70.0), 98.0)
            if clamped != diskAlertThreshold {
                diskAlertThreshold = clamped
                return
            }
            userDefaults.set(clamped, forKey: Keys.diskAlertThreshold)
        }
    }

    /// Cooldown debounce interval in seconds between alerts for the same category (e.g. 300s = 5m).
    @Published public var alertCooldownInterval: TimeInterval {
        didSet {
            let clamped = max(alertCooldownInterval, 30.0)
            if clamped != alertCooldownInterval {
                alertCooldownInterval = clamped
                return
            }
            userDefaults.set(clamped, forKey: Keys.alertCooldownInterval)
        }
    }

    // MARK: - Initialization

    /// Creates a new `PreferencesStore` instance.
    /// - Parameter userDefaults: The `UserDefaults` suite to persist settings to.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load refreshInterval
        let storedInterval = userDefaults.object(forKey: Keys.refreshInterval) as? Double
        self.refreshInterval = Self.clampRefreshInterval(storedInterval ?? Self.defaultRefreshInterval)

        // Load enabledCategories
        if let storedCategories = userDefaults.stringArray(forKey: Keys.enabledCategories) {
            let loaded = storedCategories.compactMap { MetricCategory(rawValue: $0) }
            self.enabledCategories = Set(loaded)
        } else {
            self.enabledCategories = Set(MetricCategory.allCases)
        }

        // Load temperatureUnit
        if let storedTemp = userDefaults.string(forKey: Keys.temperatureUnit),
           let unit = Units.TemperatureUnit(rawValue: storedTemp) {
            self.temperatureUnit = unit
        } else {
            self.temperatureUnit = .celsius
        }

        // Load networkUnit
        if let storedNet = userDefaults.string(forKey: Keys.networkUnit),
           let unit = Units.NetworkUnit(rawValue: storedNet) {
            self.networkUnit = unit
        } else {
            self.networkUnit = .bytesPerSecond
        }

        // Load byteUnitStandard
        if let storedByte = userDefaults.string(forKey: Keys.byteUnitStandard),
           let standard = Units.ByteUnitStandard(rawValue: storedByte) {
            self.byteUnitStandard = standard
        } else {
            self.byteUnitStandard = .iec
        }

        // Load showDockIcon
        self.showDockIcon = userDefaults.bool(forKey: Keys.showDockIcon)

        // Load launchAtLogin
        self.launchAtLogin = userDefaults.bool(forKey: Keys.launchAtLogin)

        // Load menuBarDisplayMode (default: .cpu)
        if let storedMode = userDefaults.string(forKey: Keys.menuBarDisplayMode),
           let mode = MenuBarDisplayMode(rawValue: storedMode) {
            self.menuBarDisplayMode = mode
        } else {
            self.menuBarDisplayMode = .cpu
        }

        // Load widgetPopoverStyles
        var loadedPopoverStyles: [String: PopoverStyle] = [:]
        if let data = userDefaults.data(forKey: Keys.widgetPopoverStyles),
           let styles = try? JSONDecoder().decode([String: PopoverStyle].self, from: data) {
            loadedPopoverStyles = styles
        }

        // Load modular menuBarItems (ADR 0007)
        if let data = userDefaults.data(forKey: Keys.menuBarItems),
           let items = try? JSONDecoder().decode([MenuBarItemConfig].self, from: data) {
            // Deduplicate items resulting from migration (e.g. if tachometer & gauge both present)
            // and filter out styles that are no longer supported for that category.
            var seen = Set<String>()
            var sanitized: [MenuBarItemConfig] = []
            for var item in items {
                let supported = MetricDisplayStyle.supportedStyles(for: item.category)
                if supported.contains(item.style) {
                    if !seen.contains(item.id) {
                        seen.insert(item.id)
                        // Sync custom popover style if persisted
                        if item.popoverStyle == nil, let savedStyle = loadedPopoverStyles[item.id] {
                            item.popoverStyle = savedStyle
                        } else if let popover = item.popoverStyle {
                            loadedPopoverStyles[item.id] = popover
                        }
                        sanitized.append(item)
                    }
                }
            }
            self.menuBarItems = sanitized.isEmpty ? MenuBarItemConfig.defaultConfigs() : sanitized
        } else {
            self.menuBarItems = MenuBarItemConfig.defaultConfigs()
        }
        self.widgetPopoverStyles = loadedPopoverStyles

        // Load sampling pause state (default: false) and Low Power Mode auto-pause (default: true)
        let paused = userDefaults.bool(forKey: Keys.isSamplingPaused)
        self.isSamplingPaused = paused
        self.isAutoPausedByLowPowerMode = paused && userDefaults.bool(forKey: Keys.isAutoPausedByLowPowerMode)
        self.autoPauseOnLowPowerMode = userDefaults.object(forKey: Keys.autoPauseOnLowPowerMode) as? Bool ?? true

        // Load notifications and alert preferences
        self.notificationsEnabled = userDefaults.bool(forKey: Keys.notificationsEnabled)
        self.cpuAlertEnabled = userDefaults.bool(forKey: Keys.cpuAlertEnabled)
        let storedCPUThreshold = userDefaults.object(forKey: Keys.cpuAlertThreshold) as? Double
        self.cpuAlertThreshold = storedCPUThreshold ?? 90.0

        self.memoryAlertEnabled = userDefaults.bool(forKey: Keys.memoryAlertEnabled)
        let storedMemThreshold = userDefaults.object(forKey: Keys.memoryAlertThreshold) as? Double
        self.memoryAlertThreshold = storedMemThreshold ?? 85.0
        self.memoryAlertCriticalPressureOnly = userDefaults.object(forKey: Keys.memoryAlertCriticalPressureOnly) as? Bool ?? true

        self.batteryLowAlertEnabled = userDefaults.bool(forKey: Keys.batteryLowAlertEnabled)
        let storedBatteryThreshold = userDefaults.object(forKey: Keys.batteryLowThreshold) as? Int
        self.batteryLowThreshold = storedBatteryThreshold ?? 20
        self.batteryFullAlertEnabled = userDefaults.bool(forKey: Keys.batteryFullAlertEnabled)

        self.thermalAlertEnabled = userDefaults.bool(forKey: Keys.thermalAlertEnabled)
        let storedThermalThreshold = userDefaults.object(forKey: Keys.thermalAlertThreshold) as? Double
        self.thermalAlertThreshold = storedThermalThreshold ?? 90.0

        self.diskAlertEnabled = userDefaults.bool(forKey: Keys.diskAlertEnabled)
        let storedDiskThreshold = userDefaults.object(forKey: Keys.diskAlertThreshold) as? Double
        self.diskAlertThreshold = storedDiskThreshold ?? 90.0

        let storedCooldown = userDefaults.object(forKey: Keys.alertCooldownInterval) as? Double
        self.alertCooldownInterval = storedCooldown ?? 300.0
    }

    // MARK: - Helpers

    /// Clamps an interval value to the allowable min/max bounds.
    public static func clampRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        min(max(interval, minRefreshInterval), maxRefreshInterval)
    }

    /// Checks whether a specific metric category is enabled.
    public func isCategoryEnabled(_ category: MetricCategory) -> Bool {
        enabledCategories.contains(category)
    }

    /// Sets the enablement status of a specific metric category.
    public func setCategory(_ category: MetricCategory, isEnabled: Bool) {
        if isEnabled {
            enabledCategories.insert(category)
        } else {
            enabledCategories.remove(category)
        }
    }

    /// Toggles the enablement status of a specific metric category.
    public func toggleCategory(_ category: MetricCategory) {
        if isCategoryEnabled(category) {
            enabledCategories.remove(category)
        } else {
            enabledCategories.insert(category)
        }
    }

    // MARK: - Menu Bar Item Management (ADR 0007)
    
    /// Returns whether a specific menu bar widget (category + style) is enabled.
    public func isItemEnabled(category: MetricCategory, style: MetricDisplayStyle) -> Bool {
        menuBarItems.contains { $0.category == category && $0.style == style }
    }

    /// Returns whether a specific menu bar config is enabled.
    public func isItemEnabled(_ item: MenuBarItemConfig) -> Bool {
        menuBarItems.contains { $0.category == item.category && $0.style == item.style }
    }

    /// Sets the enablement status of a specific menu bar widget.
    public func setItemEnabled(category: MetricCategory, style: MetricDisplayStyle, isEnabled: Bool) {
        let popover = popoverStyle(for: category, widgetStyle: style)
        let config = MenuBarItemConfig(category: category, style: style, popoverStyle: popover)
        if isEnabled {
            if let idx = menuBarItems.firstIndex(where: { $0.category == category && $0.style == style }) {
                menuBarItems[idx].popoverStyle = popover
            } else {
                menuBarItems.append(config)
            }
        } else {
            menuBarItems.removeAll { $0.category == category && $0.style == style }
        }
    }

    /// Toggles the enablement status of a specific menu bar widget.
    public func toggleItem(category: MetricCategory, style: MetricDisplayStyle) {
        let currentlyEnabled = isItemEnabled(category: category, style: style)
        setItemEnabled(category: category, style: style, isEnabled: !currentlyEnabled)
    }

    // MARK: - Popover Style Management (ADR 0007 Decoupled Popover Customization)

    /// Returns the explicitly configured popover style for a widget, or nil if unset.
    public func popoverStyle(for category: MetricCategory, widgetStyle: MetricDisplayStyle) -> PopoverStyle? {
        let id = "\(category.rawValue).\(widgetStyle.rawValue)"
        if let item = menuBarItems.first(where: { $0.category == category && $0.style == widgetStyle }) {
            return item.popoverStyle ?? widgetPopoverStyles[id]
        }
        return widgetPopoverStyles[id]
    }

    /// Returns the resolved effective popover style for a widget, falling back to its natural default style if unset.
    public func resolvedPopoverStyle(for category: MetricCategory, widgetStyle: MetricDisplayStyle) -> PopoverStyle {
        popoverStyle(for: category, widgetStyle: widgetStyle)
            ?? PopoverStyle.defaultStyle(for: category, widgetStyle: widgetStyle)
    }

    /// Sets or clears the custom popover style for a specific menu bar widget.
    public func setPopoverStyle(_ popoverStyle: PopoverStyle?, for category: MetricCategory, widgetStyle: MetricDisplayStyle) {
        let id = "\(category.rawValue).\(widgetStyle.rawValue)"
        if let style = popoverStyle {
            widgetPopoverStyles[id] = style
        } else {
            widgetPopoverStyles.removeValue(forKey: id)
        }
        if let idx = menuBarItems.firstIndex(where: { $0.category == category && $0.style == widgetStyle }) {
            menuBarItems[idx].popoverStyle = popoverStyle
        }
    }

    /// Returns all active menu bar items whose parent category is currently enabled.
    /// When sampling is paused (`isSamplingPaused == true`), returns an empty array so the
    /// menu bar collapses to the single minimal app icon.
    public var activeMenuBarItems: [MenuBarItemConfig] {
        guard !isSamplingPaused else { return [] }
        return menuBarItems.filter { isCategoryEnabled($0.category) }
    }

    /// Sets whether background sampling is paused.
    public func setSamplingPaused(_ paused: Bool) {
        isSamplingPaused = paused
    }

    /// Toggles whether background sampling is paused.
    public func toggleSamplingPaused() {
        isSamplingPaused.toggle()
    }

    /// Returns all enabled items for a specific category.
    public func items(for category: MetricCategory) -> [MenuBarItemConfig] {
        menuBarItems.filter { $0.category == category }
    }

    /// Resets all preferences back to factory defaults.
    public func resetToDefaults() {
        self.refreshInterval = Self.defaultRefreshInterval
        self.enabledCategories = Set(MetricCategory.allCases)
        self.temperatureUnit = .celsius
        self.networkUnit = .bytesPerSecond
        self.byteUnitStandard = .iec
        self.showDockIcon = false
        self.launchAtLogin = false
        self.menuBarDisplayMode = .cpu
        self.menuBarItems = MenuBarItemConfig.defaultConfigs()
        self.widgetPopoverStyles = [:]
        self.isAutoPausedByLowPowerMode = false
        self.isSamplingPaused = false
        self.autoPauseOnLowPowerMode = true

        self.notificationsEnabled = false
        self.cpuAlertEnabled = false
        self.cpuAlertThreshold = 90.0
        self.memoryAlertEnabled = false
        self.memoryAlertThreshold = 85.0
        self.memoryAlertCriticalPressureOnly = true
        self.batteryLowAlertEnabled = false
        self.batteryLowThreshold = 20
        self.batteryFullAlertEnabled = false
        self.thermalAlertEnabled = false
        self.thermalAlertThreshold = 90.0
        self.diskAlertEnabled = false
        self.diskAlertThreshold = 90.0
        self.alertCooldownInterval = 300.0
    }
}

