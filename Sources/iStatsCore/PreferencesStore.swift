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
        public static let menuBarItems = "iStats.menuBarItems"
        public static let categoryLastTabs = "iStats.categoryLastTabs"
        public static let categoryHistoryRanges = "iStats.categoryHistoryRanges"
        public static let pinnedPanelOrigins = "iStats.pinnedPanelOrigins"
        public static let isSamplingPaused = "iStats.isSamplingPaused"
        public static let isAutoPausedByLowPowerMode = "iStats.isAutoPausedByLowPowerMode"
        public static let autoPauseOnLowPowerMode = "iStats.autoPauseOnLowPowerMode"

        // Schema v2 (Phase 9)
        public static let schemaVersion = PreferencesMigration.Keys.schemaVersion
        public static let hasCompletedOnboarding = PreferencesMigration.Keys.hasCompletedOnboarding
        public static let alertRules = PreferencesMigration.Keys.alertRules
        public static let lastPanelDestination = "iStats.lastPanelDestination"
        public static let lastSettingsSection = "iStats.lastSettingsSection"
        public static let menuBarAppearance = "iStats.menuBarAppearance"
        public static let networkInterfaceSelection = "iStats.networkInterfaceSelection"

        // Notification keys that are not part of an `AlertRule`
        public static let notificationsEnabled = "iStats.notificationsEnabled"
        public static let memoryAlertCriticalPressureOnly = "iStats.memoryAlertCriticalPressureOnly"
    }

    /// v1 per-alert keys. Read only by `PreferencesMigration`; the store no longer writes them.
    public enum LegacyAlertKeys {
        public static let cpuEnabled = "iStats.cpuAlertEnabled"
        public static let cpuThreshold = "iStats.cpuAlertThreshold"
        public static let memoryEnabled = "iStats.memoryAlertEnabled"
        public static let memoryThreshold = "iStats.memoryAlertThreshold"
        public static let batteryLowEnabled = "iStats.batteryLowAlertEnabled"
        public static let batteryLowThreshold = "iStats.batteryLowThreshold"
        public static let batteryFullEnabled = "iStats.batteryFullAlertEnabled"
        public static let thermalEnabled = "iStats.thermalAlertEnabled"
        public static let thermalThreshold = "iStats.thermalAlertThreshold"
        public static let diskEnabled = "iStats.diskAlertEnabled"
        public static let diskThreshold = "iStats.diskAlertThreshold"
        public static let cooldown = "iStats.alertCooldownInterval"
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

    /// User-configured modular menu bar items/widgets (ADR 0007).
    @Published public var menuBarItems: [MenuBarItemConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(menuBarItems) {
                userDefaults.set(data, forKey: Keys.menuBarItems)
            }
        }
    }

    /// Remembered active tab, one per category (ADR 0008; per-item "remember last tab" was removed in schema v2).
    @Published public var categoryLastTabs: [String: String] {
        didSet {
            userDefaults.set(categoryLastTabs, forKey: Keys.categoryLastTabs)
        }
    }

    /// Remembered history time range per category (Tasks 7.5, 8.10).
    @Published public var categoryHistoryRanges: [String: String] {
        didSet {
            userDefaults.set(categoryHistoryRanges, forKey: Keys.categoryHistoryRanges)
        }
    }

    /// Remembered pinned window origins keyed by `PanelDestination.storageKey`
    /// ("overview" or a category raw value, so pre-v2 entries remain valid).
    @Published public var pinnedPanelOrigins: [String: [Double]] {
        didSet {
            userDefaults.set(pinnedPanelOrigins, forKey: Keys.pinnedPanelOrigins)
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

    /// If true, only trigger memory alert on kernel critical pressure; if false, trigger on custom % threshold.
    @Published public var memoryAlertCriticalPressureOnly: Bool {
        didSet {
            userDefaults.set(memoryAlertCriticalPressureOnly, forKey: Keys.memoryAlertCriticalPressureOnly)
        }
    }

    /// One rule per `AlertKind` (always all kinds, in `AlertKind.allCases` order).
    @Published public var alertRules: [AlertRule] {
        didSet {
            let normalized = Self.normalizedRules(alertRules)
            if normalized != alertRules {
                alertRules = normalized
                return
            }
            if let data = try? JSONEncoder().encode(normalized) {
                userDefaults.set(data, forKey: Keys.alertRules)
            }
        }
    }

    // MARK: - Schema v2 settings

    /// False until the first-run walkthrough completes; migration sets it true for existing users.
    @Published public var hasCompletedOnboarding: Bool {
        didSet { userDefaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// The popover destination last shown (restored when the popover reopens).
    @Published public var lastPanelDestination: PanelDestination {
        didSet { userDefaults.set(lastPanelDestination.storageKey, forKey: Keys.lastPanelDestination) }
    }

    /// Identifier of the Settings section last shown, if any.
    @Published public var lastSettingsSection: String? {
        didSet { Self.setOptionalString(lastSettingsSection, forKey: Keys.lastSettingsSection, in: userDefaults) }
    }

    @Published public var menuBarAppearance: MenuBarAppearance {
        didSet { userDefaults.set(menuBarAppearance.rawValue, forKey: Keys.menuBarAppearance) }
    }

    /// Network interface to chart (BSD name such as "en0"); nil means automatic.
    @Published public var networkInterfaceSelection: String? {
        didSet { Self.setOptionalString(networkInterfaceSelection, forKey: Keys.networkInterfaceSelection, in: userDefaults) }
    }

    // MARK: - Alert Rule Helpers

    /// Returns the active `AlertRule` for `kind` (always normalized).
    public func alertRule(for kind: AlertKind) -> AlertRule {
        alertRules.first { $0.kind == kind } ?? .default(for: kind)
    }

    /// Replaces the stored rule for `updated.kind` (clamped).
    public func setAlertRule(_ updated: AlertRule) {
        updateAlertRule(updated.kind) { $0 = updated }
    }

    /// Mutates the stored rule for `kind` in place.
    public func updateAlertRule(_ kind: AlertKind, _ change: (inout AlertRule) -> Void) {
        var rules = alertRules
        guard let index = rules.firstIndex(where: { $0.kind == kind }) else { return }
        change(&rules[index])
        alertRules = rules
    }

    /// Default cooldown applied across all rules when adjusted globally in Notifications settings.
    public var defaultAlertCooldownSeconds: TimeInterval {
        get { alertRule(for: .cpu).cooldownSeconds }
        set {
            let clamped = max(AlertRule.minCooldownSeconds, newValue)
            alertRules = alertRules.map { var r = $0; r.cooldownSeconds = clamped; return r }
        }
    }

    private func rule(_ kind: AlertKind) -> AlertRule {
        alertRule(for: kind)
    }

    private func updateRule(_ kind: AlertKind, _ change: (inout AlertRule) -> Void) {
        updateAlertRule(kind, change)
    }

    public var cpuAlertEnabled: Bool {
        get { rule(.cpu).enabled }
        set { updateRule(.cpu) { $0.enabled = newValue } }
    }
    /// CPU usage percentage threshold (50 - 100).
    public var cpuAlertThreshold: Double {
        get { rule(.cpu).threshold }
        set { updateRule(.cpu) { $0.threshold = newValue } }
    }
    public var memoryAlertEnabled: Bool {
        get { rule(.memory).enabled }
        set { updateRule(.memory) { $0.enabled = newValue } }
    }
    /// Memory usage percentage threshold (50 - 100).
    public var memoryAlertThreshold: Double {
        get { rule(.memory).threshold }
        set { updateRule(.memory) { $0.threshold = newValue } }
    }
    public var batteryLowAlertEnabled: Bool {
        get { rule(.batteryLow).enabled }
        set { updateRule(.batteryLow) { $0.enabled = newValue } }
    }
    /// Low battery percentage threshold (5 - 50).
    public var batteryLowThreshold: Int {
        get { Int(rule(.batteryLow).threshold.rounded()) }
        set { updateRule(.batteryLow) { $0.threshold = Double(newValue) } }
    }
    public var batteryFullAlertEnabled: Bool {
        get { rule(.batteryFull).enabled }
        set { updateRule(.batteryFull) { $0.enabled = newValue } }
    }
    public var thermalAlertEnabled: Bool {
        get { rule(.temperature).enabled }
        set { updateRule(.temperature) { $0.enabled = newValue } }
    }
    /// Temperature threshold in Celsius (60 - 105).
    public var thermalAlertThreshold: Double {
        get { rule(.temperature).threshold }
        set { updateRule(.temperature) { $0.threshold = newValue } }
    }
    public var diskAlertEnabled: Bool {
        get { rule(.disk).enabled }
        set { updateRule(.disk) { $0.enabled = newValue } }
    }
    /// Primary disk usage percentage threshold (70 - 98).
    public var diskAlertThreshold: Double {
        get { rule(.disk).threshold }
        set { updateRule(.disk) { $0.threshold = newValue } }
    }
    /// Cooldown between repeat alerts in seconds (minimum 30); applied to every rule.
    public var alertCooldownInterval: TimeInterval {
        get { rule(.cpu).cooldownSeconds }
        set { alertRules = alertRules.map { var r = $0; r.cooldownSeconds = newValue; return r } }
    }

    /// Ensures exactly one clamped rule per kind, in `AlertKind.allCases` order.
    static func normalizedRules(_ rules: [AlertRule]) -> [AlertRule] {
        AlertKind.allCases.map { kind in
            (rules.first { $0.kind == kind } ?? .default(for: kind)).clamped()
        }
    }

    private static func setOptionalString(_ value: String?, forKey key: String, in defaults: UserDefaults) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    // MARK: - Initialization

    /// Creates a new `PreferencesStore` instance.
    /// - Parameter userDefaults: The `UserDefaults` suite to persist settings to.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        PreferencesMigration.migrate(defaults: userDefaults)

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

        // Load modular menuBarItems (ADR 0007)
        let baseItems: [MenuBarItemConfig]
        if let data = userDefaults.data(forKey: Keys.menuBarItems),
           let items = try? JSONDecoder().decode([MenuBarItemConfig].self, from: data) {
            // Deduplicate migrated items and drop styles no longer supported for the category.
            let sanitized = MenuBarItemConfig.deduplicated(items).filter {
                MetricDisplayStyle.supportedStyles(for: $0.category).contains($0.style)
            }
            baseItems = sanitized.isEmpty ? MenuBarItemConfig.defaultConfigs() : sanitized
        } else {
            baseItems = MenuBarItemConfig.defaultConfigs()
        }
        self.menuBarItems = baseItems
        self.categoryLastTabs = userDefaults.dictionary(forKey: Keys.categoryLastTabs) as? [String: String] ?? [:]
        self.categoryHistoryRanges = userDefaults.dictionary(forKey: Keys.categoryHistoryRanges) as? [String: String] ?? [:]
        self.pinnedPanelOrigins = userDefaults.dictionary(forKey: Keys.pinnedPanelOrigins) as? [String: [Double]] ?? [:]

        // Load sampling pause state (default: false) and Low Power Mode auto-pause (default: true)
        let paused = userDefaults.bool(forKey: Keys.isSamplingPaused)
        self.isSamplingPaused = paused
        self.isAutoPausedByLowPowerMode = paused && userDefaults.bool(forKey: Keys.isAutoPausedByLowPowerMode)
        self.autoPauseOnLowPowerMode = userDefaults.object(forKey: Keys.autoPauseOnLowPowerMode) as? Bool ?? true

        // Load notifications and alert preferences
        self.notificationsEnabled = userDefaults.bool(forKey: Keys.notificationsEnabled)
        self.memoryAlertCriticalPressureOnly = userDefaults.object(forKey: Keys.memoryAlertCriticalPressureOnly) as? Bool ?? true

        let storedRules = userDefaults.data(forKey: Keys.alertRules)
            .flatMap { try? JSONDecoder().decode([AlertRule].self, from: $0) } ?? []
        self.alertRules = Self.normalizedRules(storedRules)

        // Schema v2 settings
        self.hasCompletedOnboarding = userDefaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.lastPanelDestination = userDefaults.string(forKey: Keys.lastPanelDestination)
            .flatMap(PanelDestination.init(storageKey:)) ?? .overview
        self.lastSettingsSection = userDefaults.string(forKey: Keys.lastSettingsSection)
        self.menuBarAppearance = userDefaults.string(forKey: Keys.menuBarAppearance)
            .flatMap(MenuBarAppearance.init(rawValue:)) ?? .statusTint
        self.networkInterfaceSelection = userDefaults.string(forKey: Keys.networkInterfaceSelection)
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

    // MARK: - Menu Bar Item Management (ADR 0007 / ADR 0008)
    
    /// Returns whether an exact menu bar config matching category, style, and source is enabled.
    public func isExactItemEnabled(category: MetricCategory, style: MetricDisplayStyle, source: MetricSource? = nil) -> Bool {
        menuBarItems.contains { item in
            guard item.category == category && item.style == style else { return false }
            return item.source == source
        }
    }

    /// Returns the active item matching category, style, and optional source.
    public func item(category: MetricCategory, style: MetricDisplayStyle, source: MetricSource? = nil) -> MenuBarItemConfig? {
        menuBarItems.first { item in
            guard item.category == category && item.style == style else { return false }
            if let src = source {
                return (item.source ?? .peak) == src
            }
            return true
        }
    }

    /// Sets the enablement status of a specific menu bar widget.
    public func setItemEnabled(
        category: MetricCategory,
        style: MetricDisplayStyle,
        source: MetricSource? = nil,
        throughputLayout: ThroughputLayout? = nil,
        showLabel: Bool = false,
        isEnabled: Bool
    ) {
        if isEnabled {
            if let idx = menuBarItems.firstIndex(where: {
                $0.category == category && $0.style == style && $0.source == source
            }) {
                if let layout = throughputLayout {
                    menuBarItems[idx].throughputLayout = layout
                }
                menuBarItems[idx].showLabel = showLabel
            } else {
                let config = MenuBarItemConfig(
                    category: category,
                    style: style,
                    source: source,
                    throughputLayout: throughputLayout,
                    showLabel: showLabel
                )
                menuBarItems.append(config)
            }
        } else {
            menuBarItems.removeAll {
                $0.category == category && $0.style == style && $0.source == source
            }
        }
    }

    /// Returns the remembered active tab for a category, if any.
    public func lastSelectedTab(for category: MetricCategory) -> PopoverTab? {
        guard let raw = categoryLastTabs[category.rawValue],
              let tab = PopoverTab(rawValue: raw) else {
            return nil
        }
        return tab
    }

    /// Sets the remembered active tab for a category.
    public func setLastSelectedTab(_ tab: PopoverTab, for category: MetricCategory) {
        categoryLastTabs[category.rawValue] = tab.rawValue
    }

    /// Returns the remembered history time range for a category (default: .oneMinute).
    public func historyRange(for category: MetricCategory) -> HistoryTimeRange {
        guard let raw = categoryHistoryRanges[category.rawValue],
              let range = HistoryTimeRange(rawValue: raw) else {
            return .oneMinute
        }
        return range
    }

    /// Sets the remembered history time range for a category.
    public func setHistoryRange(_ range: HistoryTimeRange, for category: MetricCategory) {
        categoryHistoryRanges[category.rawValue] = range.rawValue
    }

    /// Returns the remembered pinned origin for a destination, keyed by `PanelDestination.storageKey`.
    public func pinnedOrigin(forDestinationKey key: String) -> CGPoint? {
        guard let coords = pinnedPanelOrigins[key], coords.count >= 2 else {
            return nil
        }
        return CGPoint(x: coords[0], y: coords[1])
    }

    /// Sets or clears the remembered pinned origin for a destination key.
    public func setPinnedOrigin(_ origin: CGPoint?, forDestinationKey key: String) {
        if let origin = origin {
            pinnedPanelOrigins[key] = [Double(origin.x), Double(origin.y)]
        } else {
            pinnedPanelOrigins.removeValue(forKey: key)
        }
    }

    public func pinnedOrigin(for destination: PanelDestination) -> CGPoint? {
        pinnedOrigin(forDestinationKey: destination.storageKey)
    }

    public func setPinnedOrigin(_ origin: CGPoint?, for destination: PanelDestination) {
        setPinnedOrigin(origin, forDestinationKey: destination.storageKey)
    }

    /// Returns the remembered pinned origin for a category panel, if any.
    public func pinnedOrigin(for category: MetricCategory) -> CGPoint? {
        pinnedOrigin(for: PanelDestination.category(category))
    }

    /// Sets or clears the remembered pinned origin for a category panel.
    public func setPinnedOrigin(_ origin: CGPoint?, for category: MetricCategory) {
        setPinnedOrigin(origin, for: PanelDestination.category(category))
    }

    /// Returns all active menu bar items whose parent category is currently enabled.
    /// When sampling is paused (`isSamplingPaused == true`), returns an empty array so the
    /// menu bar collapses to the single minimal app icon.
    public var activeMenuBarItems: [MenuBarItemConfig] {
        guard !isSamplingPaused else { return [] }
        return menuBarItems.filter { isCategoryEnabled($0.category) }
    }

    /// Applies a full left-to-right order to the active items. Ignored unless `ids` is exactly the active set.
    public func setActiveMenuBarOrder(_ ids: [String]) {
        let active = menuBarItems.filter { isCategoryEnabled($0.category) }
        let byId = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard ids.count == active.count, Set(ids) == Set(byId.keys), ids != active.map(\.id) else { return }
        let disabled = menuBarItems.filter { !isCategoryEnabled($0.category) }
        menuBarItems = ids.compactMap { byId[$0] } + disabled
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
        self.menuBarItems = MenuBarItemConfig.defaultConfigs()
        self.categoryLastTabs = [:]
        self.categoryHistoryRanges = [:]
        self.pinnedPanelOrigins = [:]
        self.isAutoPausedByLowPowerMode = false
        self.isSamplingPaused = false
        self.autoPauseOnLowPowerMode = true

        self.notificationsEnabled = false
        self.memoryAlertCriticalPressureOnly = true
        self.alertRules = AlertRule.defaults

        self.lastPanelDestination = .overview
        self.lastSettingsSection = nil
        self.menuBarAppearance = .statusTint
        self.networkInterfaceSelection = nil
    }
}

