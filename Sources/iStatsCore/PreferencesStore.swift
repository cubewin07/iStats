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
    }

    /// The metric representation shown directly in the macOS menu bar status item (Requirement 9.4).
    public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
        case icon = "icon"
        case cpu = "cpu"
        case memory = "memory"
        case both = "both"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .icon: return "Icon Only"
            case .cpu: return "CPU Usage"
            case .memory: return "Memory Usage"
            case .both: return "CPU & Memory"
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

    /// The metric display mode active in the macOS menu bar status item (Requirement 9.4).
    @Published public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode)
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
    }
}
