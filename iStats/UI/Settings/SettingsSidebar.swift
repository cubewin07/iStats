import SwiftUI
import iStatsCore

/// Sidebar for the Settings window: a native `List(selection:)` in three groups
/// (General / Appearance / Menu Bar, one page per category, Notifications / About).
/// Native list selection gives arrow-key navigation and VoiceOver row semantics for free.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection?
    let hasBattery: Bool
    let activeCategories: Set<MetricCategory>

    init(
        selection: Binding<SettingsSection?>,
        hasBattery: Bool,
        activeCategories: Set<MetricCategory> = Set(MetricCategory.allCases)
    ) {
        self._selection = selection
        self.hasBattery = hasBattery
        self.activeCategories = activeCategories
    }

    private var groups: [[SettingsSection]] {
        SettingsSection.groups(hasBattery: hasBattery, activeCategories: activeCategories)
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                SwiftUI.Section {
                    ForEach(group) { section in
                        Label(
                            section.title(hasBattery: hasBattery),
                            systemImage: section.symbolName(hasBattery: hasBattery)
                        )
                        .tag(section)
                        .accessibilityIdentifier("settings.sidebar.\(section.storageKey)")
                    }
                } header: {
                    if index == 1 {
                        Text("Monitors")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Settings sections")
    }
}
