import Foundation

/// Hardware-aware starter presets for the menu bar (Task 9.8, used by onboarding in 9.11).
public enum MenuBarPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case minimal
    case balanced
    case everything

    public var id: String { rawValue }

    /// User-facing preset name.
    public var title: String {
        switch self {
        case .minimal: return "Minimal"
        case .balanced: return "Balanced"
        case .everything: return "Everything"
        }
    }

    /// Short description of the preset's footprint.
    public var summary: String {
        switch self {
        case .minimal: return "Single CPU value indicator."
        case .balanced: return "CPU bar, Memory bar, and Network throughput."
        case .everything: return "One compact widget for each available hardware sensor."
        }
    }

    /// Produces valid, deduplicated menu bar widget configs tailored to the Mac's hardware.
    ///
    /// Omits Battery widgets when `hasBattery == false` and Fan widgets when `hasFans == false`.
    public func configs(hasBattery: Bool = true, hasFans: Bool = true) -> [MenuBarItemConfig] {
        switch self {
        case .minimal:
            return [
                MenuBarItemConfig(category: .cpu, style: .text)
            ]

        case .balanced:
            return MenuBarItemConfig.defaultConfigs()

        case .everything:
            var items: [MenuBarItemConfig] = [
                MenuBarItemConfig(category: .cpu, style: .bar),
                MenuBarItemConfig(category: .memory, style: .bar),
                MenuBarItemConfig(category: .gpu, style: .bar),
                MenuBarItemConfig(category: .thermal, style: .glyph, source: .peak)
            ]
            if hasFans {
                items.append(MenuBarItemConfig(category: .fan, style: .glyph))
            }
            items.append(MenuBarItemConfig(category: .network, style: .throughput))
            items.append(MenuBarItemConfig(category: .disk, style: .throughput))
            if hasBattery {
                items.append(MenuBarItemConfig(category: .power, style: .glyph))
            }
            return items
        }
    }

    /// Static convenience returning hardware-aware configs for `preset`.
    public static func configs(for preset: MenuBarPreset, hasBattery: Bool = true, hasFans: Bool = true) -> [MenuBarItemConfig] {
        preset.configs(hasBattery: hasBattery, hasFans: hasFans)
    }

    /// Static convenience matching onboarding design naming (`MenuBarPreset.items(for:hasBattery:hasFans:)`).
    public static func items(for preset: MenuBarPreset, hasBattery: Bool = true, hasFans: Bool = true) -> [MenuBarItemConfig] {
        preset.configs(hasBattery: hasBattery, hasFans: hasFans)
    }
}
