import Foundation

/// A page of the Settings window sidebar (ADR 0011).
///
/// Sidebar order is three groups: `[general, appearance, menuBar]`, one page per
/// `MetricCategory`, then `[notifications, about]`.
public enum SettingsSection: Hashable, Sendable, Identifiable {
    case general
    case appearance
    case menuBar
    case category(MetricCategory)
    case notifications
    case about

    public var id: String { storageKey }

    /// The page shown when nothing (or something stale) was saved.
    public static let fallback: SettingsSection = .general

    /// Name of the notification other code posts to open Settings on a given page.
    /// `userInfo[SettingsSection.deepLinkUserInfoKey]` carries a `storageKey` string.
    public static let openNotificationName = Notification.Name("iStats.openSettingsSection")
    public static let deepLinkUserInfoKey = "section"

    /// Name of the notification the About page posts to replay the first-run walkthrough (9.11).
    public static let showWelcomeNotificationName = Notification.Name("iStats.showWelcomeAgain")

    // MARK: - Persistence

    /// `"general"`, `"appearance"`, `"menuBar"`, `"notifications"`, `"about"` or a `MetricCategory` raw value.
    public var storageKey: String {
        switch self {
        case .general: return "general"
        case .appearance: return "appearance"
        case .menuBar: return "menuBar"
        case .category(let category): return category.rawValue
        case .notifications: return "notifications"
        case .about: return "about"
        }
    }

    /// Parses a storage key. `"alerts"` (the pre-9.9 name) is an alias for `.notifications`.
    /// Returns nil for unknown keys; use `resolved(storageKey:)` to fall back instead.
    public init?(storageKey: String) {
        switch storageKey {
        case "general": self = .general
        case "appearance": self = .appearance
        case "menuBar": self = .menuBar
        case "notifications", "alerts": self = .notifications
        case "about": self = .about
        default:
            guard let category = MetricCategory(rawValue: storageKey) else { return nil }
            self = .category(category)
        }
    }

    /// Resolves a possibly missing or stale key; anything unknown becomes `.general`.
    public static func resolved(storageKey: String?) -> SettingsSection {
        guard let storageKey, let section = SettingsSection(storageKey: storageKey) else { return fallback }
        return section
    }

    // MARK: - Presentation metadata

    public func title(hasBattery: Bool = true) -> String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .menuBar: return "Menu Bar"
        case .category(let category): return category.displayName(hasBattery: hasBattery)
        case .notifications: return "Notifications"
        case .about: return "About"
        }
    }

    public func symbolName(hasBattery: Bool = true) -> String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .menuBar: return "menubar.rectangle"
        case .category(let category): return category.symbolName(hasBattery: hasBattery)
        case .notifications: return "bell.badge"
        case .about: return "info.circle"
        }
    }

    // MARK: - Ordering

    /// The three sidebar groups in display order. `activeCategories` filters the category group
    /// (pass the default to list every category); `hasBattery` only changes Power's label, so the
    /// Power page is always present and reads "Battery" or "Power".
    public static func groups(
        hasBattery: Bool = true,
        activeCategories: Set<MetricCategory> = Set(MetricCategory.allCases)
    ) -> [[SettingsSection]] {
        let categories = MetricCategory.allCases
            .filter { activeCategories.contains($0) }
            .map { SettingsSection.category($0) }
        return [
            [.general, .appearance, .menuBar],
            categories,
            [.notifications, .about]
        ]
    }

    /// Flattened `groups(hasBattery:activeCategories:)`.
    public static func allSections(
        hasBattery: Bool = true,
        activeCategories: Set<MetricCategory> = Set(MetricCategory.allCases)
    ) -> [SettingsSection] {
        groups(hasBattery: hasBattery, activeCategories: activeCategories).flatMap { $0 }
    }
}
