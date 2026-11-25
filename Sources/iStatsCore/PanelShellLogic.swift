import Foundation

// Pure logic behind the popover shell (Task 9.3): key routing, footer copy, contextual quick actions and the
// Settings deep-link payload. Kept free of AppKit so SwiftPM tests cover it.

/// A key press reduced to the facts the shell cares about.
public struct PanelKeyInput: Sendable, Equatable {
    public var keyCode: UInt16
    /// `charactersIgnoringModifiers` of the event (Shift still applies, so `?` arrives as `?`).
    public var characters: String
    public var command: Bool
    public var control: Bool
    public var shift: Bool
    public var option: Bool

    public init(
        keyCode: UInt16,
        characters: String = "",
        command: Bool = false,
        control: Bool = false,
        shift: Bool = false,
        option: Bool = false
    ) {
        self.keyCode = keyCode
        self.characters = characters
        self.command = command
        self.control = control
        self.shift = shift
        self.option = option
    }
}

/// What a recognised shortcut asks the shell to do.
public enum PanelKeyAction: Sendable, Equatable {
    case close
    case unpin
    /// Key was recognised and swallowed on purpose (Esc on a pinned HUD).
    case noOp
    /// 0-based strip position: 0 is Overview, 1... are enabled categories.
    case selectDestination(Int)
    case nextDestination
    case previousDestination
    case previousPage
    case nextPage
    case togglePin
    case openSettings
    case quit
    case showGlossary
    case copy
}

public enum PanelKeyMap {
    public static let escapeKeyCode: UInt16 = 53
    public static let tabKeyCode: UInt16 = 48
    public static let leftArrowKeyCode: UInt16 = 123
    public static let rightArrowKeyCode: UInt16 = 124

    /// Maps a key press to a shell action, or `nil` when the key is not a shell shortcut
    /// (so it falls through to the responder chain). Space is deliberately unmapped.
    public static func action(for input: PanelKeyInput, isPinned: Bool) -> PanelKeyAction? {
        if input.keyCode == escapeKeyCode {
            return isPinned ? .noOp : .close
        }

        if input.control && !input.command && input.keyCode == tabKeyCode {
            return input.shift ? .previousDestination : .nextDestination
        }

        let chars = input.characters.lowercased()

        if input.command && !input.control {
            if chars.count == 1, let digit = Int(chars), (1...9).contains(digit) {
                return .selectDestination(digit - 1)
            }
            switch chars {
            case "p": return .togglePin
            case "w": return isPinned ? .unpin : .close
            case ",": return .openSettings
            case "q": return .quit
            case "c": return .copy
            default: return nil
            }
        }

        if !input.command && !input.control {
            switch input.keyCode {
            case leftArrowKeyCode: return .previousPage
            case rightArrowKeyCode: return .nextPage
            default: break
            }
            if chars == "?" || (chars == "/" && input.shift) {
                return .showGlossary
            }
        }
        return nil
    }
}

/// A contextual shortcut shown in the footer, the `⋯` menu and the warning ribbon.
public struct PanelQuickAction: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case activityMonitor
        case systemSettings(String)
    }

    public let title: String
    public let systemImage: String
    public let target: Target

    public init(title: String, systemImage: String, target: Target) {
        self.title = title
        self.systemImage = systemImage
        self.target = target
    }

    public static let activityMonitorPath = "/System/Applications/Utilities/Activity Monitor.app"

    /// Footer link, for example `Activity Monitor ↗`.
    public static func footer(for destination: PanelDestination, hasBattery: Bool = true) -> PanelQuickAction {
        switch destination.category {
        case .network?:
            return PanelQuickAction(title: "Network Settings ↗", systemImage: "network",
                                    target: .systemSettings("x-apple.systempreferences:com.apple.Network-Settings.extension"))
        case .disk?:
            return PanelQuickAction(title: "Storage ↗", systemImage: "internaldrive",
                                    target: .systemSettings("x-apple.systempreferences:com.apple.settings.Storage"))
        case .power?:
            return PanelQuickAction(title: hasBattery ? "Battery Settings ↗" : "Energy Settings ↗",
                                    systemImage: hasBattery ? "battery.100percent" : "powerplug",
                                    target: .systemSettings("x-apple.systempreferences:com.apple.preference.battery"))
        default:
            return PanelQuickAction(title: "Activity Monitor ↗", systemImage: "waveform.path.ecg", target: .activityMonitor)
        }
    }

    /// `⋯` menu entry.
    public static func menu(for destination: PanelDestination, hasBattery: Bool = true) -> PanelQuickAction {
        switch destination.category {
        case .network?:
            return PanelQuickAction(title: "Open Network Settings", systemImage: "network", target: footer(for: destination).target)
        case .disk?:
            return PanelQuickAction(title: "Open Storage Settings", systemImage: "internaldrive", target: footer(for: destination).target)
        case .power?:
            let base = footer(for: destination, hasBattery: hasBattery)
            return PanelQuickAction(title: hasBattery ? "Open Battery Settings" : "Open Energy Settings",
                                    systemImage: base.systemImage, target: base.target)
        default:
            return PanelQuickAction(title: "Open Activity Monitor", systemImage: "waveform.path.ecg", target: .activityMonitor)
        }
    }

    /// Button on a warning (or worse) ribbon: always a real action for the category.
    public static func ribbon(for category: MetricCategory) -> PanelQuickAction {
        switch category {
        case .power:
            return PanelQuickAction(title: "Battery Settings…", systemImage: "battery.100percent",
                                    target: .systemSettings("x-apple.systempreferences:com.apple.preference.battery"))
        case .disk:
            return PanelQuickAction(title: "Manage Storage…", systemImage: "internaldrive",
                                    target: .systemSettings("x-apple.systempreferences:com.apple.settings.Storage"))
        case .network:
            return PanelQuickAction(title: "Wi-Fi Settings…", systemImage: "wifi",
                                    target: .systemSettings("x-apple.systempreferences:com.apple.wifi-settings-extension"))
        case .cpu, .memory, .gpu, .thermal, .fan:
            return PanelQuickAction(title: "Open Activity Monitor", systemImage: "waveform.path.ecg", target: .activityMonitor)
        }
    }
}

/// Footer centre caption.
public enum PanelFooterCaption {
    public static func text(isPaused: Bool, refreshInterval: TimeInterval) -> String {
        if isPaused { return "Paused" }
        let seconds: String
        if refreshInterval.rounded() == refreshInterval {
            seconds = String(Int(refreshInterval))
        } else {
            seconds = String(format: "%.1f", refreshInterval)
        }
        return "Updated · every \(seconds) s"
    }
}

/// Contract with the Settings window (Task 9.9): after `showPreferences()`, the shell posts
/// `iStats.openSettingsSection` with `userInfo["section"]` set to a category raw value or `"general"`.
public enum PanelSettingsLink {
    public static let notificationName = "iStats.openSettingsSection"
    public static let sectionKey = "section"
    public static let generalSection = "general"

    public static func section(for destination: PanelDestination) -> String {
        destination.category?.rawValue ?? generalSection
    }
}
