import SwiftUI
import AppKit
import iStatsCore

/// Appearance: menu bar widget coloring, the page panels start on, and accessibility status.
struct AppearanceSettingsPage: View {
    @ObservedObject var store: PreferencesStore
    let hasBattery: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var destinations: [PanelDestination] {
        [.overview] + MetricCategory.allCases.map { PanelDestination.category($0) }
    }

    private func name(of destination: PanelDestination) -> String {
        switch destination {
        case .overview: return "Overview"
        case .category(let category): return category.displayName(hasBattery: hasBattery)
        }
    }

    private func name(of appearance: MenuBarAppearance) -> String {
        switch appearance {
        case .monochrome: return "Monochrome"
        case .statusTint: return "Status tint"
        case .categoryColor: return "Category color"
        }
    }

    private var appearanceFooter: String {
        switch store.menuBarAppearance {
        case .monochrome: return "Widgets match the menu bar text color."
        case .statusTint: return "Widgets stay monochrome until a value needs attention, then turn amber or red."
        case .categoryColor: return "Each widget uses its category color."
        }
    }

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("Widget color", selection: $store.menuBarAppearance) {
                    ForEach(MenuBarAppearance.allCases) { appearance in
                        Text(name(of: appearance)).tag(appearance)
                    }
                }
                .accessibilityLabel("Menu bar widget color")
            } header: {
                Text("Menu Bar")
            } footer: {
                Text(appearanceFooter)
            }

            SwiftUI.Section {
                Picker("Start page", selection: $store.lastPanelDestination) {
                    ForEach(destinations, id: \.self) { destination in
                        Text(name(of: destination)).tag(destination)
                    }
                }
                .accessibilityLabel("Page a panel opens to")
            } header: {
                Text("Panels")
            } footer: {
                Text("The page a panel opens to. It follows the last page you viewed, so changing pages in a panel updates this.")
            }

            SwiftUI.Section {
                LabeledContent("Reduce Motion", value: reduceMotion ? "On" : "Off")
                LabeledContent("Reduce Transparency", value: reduceTransparency ? "On" : "Off")
                Button("Open Accessibility Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("Accessibility")
            } footer: {
                Text("iStats follows these macOS settings. Charts stop animating and panels use solid backgrounds when they are on.")
            }
        }
        .formStyle(.grouped)
    }
}
