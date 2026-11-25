import SwiftUI
import iStatsCore

/// Per-category Settings page. Placeholder until 9.10 adds the full contents: it shows whether
/// the category is monitored and what its sampler reports.
struct CategorySettingsPage: View {
    let category: MetricCategory
    @ObservedObject var store: PreferencesStore
    @ObservedObject var coordinator: MetricsCoordinator
    let hasBattery: Bool

    private var name: String { category.displayName(hasBattery: hasBattery) }

    private var statusText: String {
        guard store.isCategoryEnabled(category) else { return "Off" }
        switch coordinator.categoryAvailability[category] {
        case .some(.available): return "Available"
        case .some(.unavailable(let reason)): return "Unavailable: \(reason)"
        case .none: return "Waiting for the first reading"
        }
    }

    var body: some View {
        Form {
            SwiftUI.Section {
                HStack(spacing: 12) {
                    Image(systemName: category.symbolName(hasBattery: hasBattery))
                        .font(.title2)
                        .foregroundStyle(CategoryPalette.color(for: category))
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    Text(name)
                        .font(.title3.weight(.semibold))
                }
                .padding(.vertical, 2)
            }

            SwiftUI.Section {
                Toggle("Monitor \(name)", isOn: Binding(
                    get: { store.isCategoryEnabled(category) },
                    set: { store.setCategory(category, isEnabled: $0) }
                ))
                .accessibilityLabel("Monitor \(name)")

                LabeledContent("Status", value: statusText)
            } header: {
                Text("Monitoring")
            } footer: {
                if category == .fan {
                    Text("Fan speeds are read-only. iStats does not control fans.")
                } else {
                    Text("More \(name) options are coming in a later update.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
