import AppKit
import Foundation

/// Manages application activation policy and Dock icon visibility.
///
/// Under `LSUIElement = true`, the application defaults to `.accessory` mode
/// (no Dock icon, menu bar agent behavior). This manager allows toggling
/// between `.accessory` and `.regular` (Dock icon visible) based on user preference.
@MainActor
public final class DockIconManager {
    public static let shared = DockIconManager()

    public static let showDockIconDefaultsKey = "iStats.showDockIcon"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Whether the Dock icon is currently configured to be visible.
    public var isDockIconVisible: Bool {
        get {
            userDefaults.bool(forKey: Self.showDockIconDefaultsKey)
        }
        set {
            userDefaults.set(newValue, forKey: Self.showDockIconDefaultsKey)
            applyCurrentPolicy()
        }
    }

    /// Applies the appropriate NSApplication.ActivationPolicy based on settings.
    public func applyCurrentPolicy() {
        let policy: NSApplication.ActivationPolicy = isDockIconVisible ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    /// Sets the activation policy explicitly.
    public func setDockIconVisible(_ visible: Bool) {
        isDockIconVisible = visible
    }
}
