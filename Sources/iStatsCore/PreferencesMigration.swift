import Foundation

/// Versioned, idempotent migration of persisted preferences (Phase 9, task 9.2).
///
/// v1 -> v2:
/// - folds the 15 scattered alert keys into `AlertRule`s (legacy keys are left in place);
/// - marks existing users as onboarded (any `iStats.*` key present before migration);
/// - folds `widgetPopoverStyles` / per-item `popoverStyle` into per-item `popover` configs;
/// - drops `widgetPopoverStyles` and `menuBarDisplayMode`.
/// Unknown keys and unknown values inside `menuBarItems` are preserved.
public enum PreferencesMigration {
    public static let currentVersion = 2

    public enum Keys {
        public static let schemaVersion = "iStats.preferencesSchemaVersion"
        public static let alertRules = "iStats.alertRules"
        public static let hasCompletedOnboarding = "iStats.hasCompletedOnboarding"
    }

    public struct Result: Equatable, Sendable {
        public let fromVersion: Int
        public let toVersion: Int
        public var didMigrate: Bool { fromVersion != toVersion }
        public let isExistingUser: Bool
    }

    private static let ownedPrefix = "iStats."
    private static let removedKeys = ["iStats.widgetPopoverStyles", "iStats.menuBarDisplayMode"]

    /// Runs any pending migrations. Running twice is a no-op.
    @discardableResult
    public static func migrate(defaults: UserDefaults) -> Result {
        let stored = defaults.object(forKey: Keys.schemaVersion) as? Int
        // Absent = v1 (before versioning); a future version is left untouched.
        let fromVersion = stored ?? 1
        let hadKeys = defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(ownedPrefix) && $0 != Keys.schemaVersion
        }
        guard fromVersion < currentVersion else {
            return Result(fromVersion: fromVersion, toVersion: fromVersion, isExistingUser: hadKeys)
        }

        if fromVersion < 2 { migrateV1ToV2(defaults, isExistingUser: hadKeys) }

        defaults.set(currentVersion, forKey: Keys.schemaVersion)
        return Result(fromVersion: fromVersion, toVersion: currentVersion, isExistingUser: hadKeys)
    }

    // MARK: - v1 -> v2

    private static func migrateV1ToV2(_ defaults: UserDefaults, isExistingUser: Bool) {
        if defaults.object(forKey: Keys.hasCompletedOnboarding) == nil {
            defaults.set(isExistingUser, forKey: Keys.hasCompletedOnboarding)
        }
        if defaults.data(forKey: Keys.alertRules) == nil,
           let data = try? JSONEncoder().encode(legacyAlertRules(defaults)) {
            defaults.set(data, forKey: Keys.alertRules)
        }
        foldPopoverStyles(defaults)
        for key in removedKeys { defaults.removeObject(forKey: key) }
    }

    /// Builds rules from the v1 keys, falling back to factory defaults for anything unset.
    static func legacyAlertRules(_ defaults: UserDefaults) -> [AlertRule] {
        let keys = PreferencesStore.LegacyAlertKeys.self
        let cooldown = defaults.object(forKey: keys.cooldown) as? Double ?? AlertRule.defaultCooldownSeconds

        func rule(_ kind: AlertKind, enabledKey: String, thresholdKey: String?) -> AlertRule {
            var threshold: Double?
            if let thresholdKey {
                if let d = defaults.object(forKey: thresholdKey) as? Double {
                    threshold = d
                } else if let i = defaults.object(forKey: thresholdKey) as? Int {
                    threshold = Double(i)
                }
            }
            return AlertRule(
                kind: kind,
                enabled: defaults.bool(forKey: enabledKey),
                threshold: threshold,
                cooldownSeconds: cooldown
            ).clamped()
        }

        return [
            rule(.cpu, enabledKey: keys.cpuEnabled, thresholdKey: keys.cpuThreshold),
            rule(.memory, enabledKey: keys.memoryEnabled, thresholdKey: keys.memoryThreshold),
            rule(.batteryLow, enabledKey: keys.batteryLowEnabled, thresholdKey: keys.batteryLowThreshold),
            rule(.batteryFull, enabledKey: keys.batteryFullEnabled, thresholdKey: nil),
            rule(.temperature, enabledKey: keys.thermalEnabled, thresholdKey: keys.thermalThreshold),
            rule(.disk, enabledKey: keys.diskEnabled, thresholdKey: keys.diskThreshold)
        ]
    }

    /// Rewrites `menuBarItems` JSON so legacy popover styles live in `popover`.
    /// Works on raw dictionaries so unknown fields and values survive.
    private static func foldPopoverStyles(_ defaults: UserDefaults) {
        guard let data = defaults.data(forKey: PreferencesStore.Keys.menuBarItems),
              var items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }

        var overrides: [String: String] = [:]
        if let styleData = defaults.data(forKey: "iStats.widgetPopoverStyles"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: styleData) {
            overrides = decoded
        }

        var changed = false
        for index in items.indices {
            var item = items[index]
            let legacyInline = item["popoverStyle"] as? String
            if item["popover"] == nil,
               let categoryRaw = item["category"] as? String,
               let category = MetricCategory(rawValue: categoryRaw) {
                let styleRaw = item["style"] as? String ?? ""
                if let legacy = legacyInline ?? overrides["\(categoryRaw).\(styleRaw)"] {
                    let source = (item["source"] as? String).flatMap(MetricSource.init(rawValue:))
                    let config = PopoverConfig.migrated(fromLegacyRawValue: legacy, category: category, widgetSource: source)
                    if let encoded = try? JSONEncoder().encode(config),
                       let object = try? JSONSerialization.jsonObject(with: encoded) {
                        item["popover"] = object
                        changed = true
                    }
                }
            }
            if item.removeValue(forKey: "popoverStyle") != nil { changed = true }
            items[index] = item
        }

        if changed, let out = try? JSONSerialization.data(withJSONObject: items) {
            defaults.set(out, forKey: PreferencesStore.Keys.menuBarItems)
        }
    }
}
