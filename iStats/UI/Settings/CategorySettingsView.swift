import SwiftUI
import iStatsCore

/// Per-category Settings page: monitoring header, widget gallery with light/dark previews,
/// popover defaults, category-specific extras (network interface, disk volume, thermal sensor),
/// and sustained alert rule editor.
public struct CategorySettingsView: View {
    public let category: MetricCategory
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    public let hasBattery: Bool

    public init(
        category: MetricCategory,
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared,
        hasBattery: Bool = true
    ) {
        self.category = category
        self.store = store
        self.coordinator = coordinator
        self.hasBattery = hasBattery
    }

    private var identity: CategoryIdentity {
        category.identity
    }

    private var name: String {
        identity.displayName(hasBattery: hasBattery)
    }

    private var categoryWidgets: [MenuBarItemConfig] {
        store.items(for: category)
    }

    private var isFanless: Bool {
        category == .fan && (coordinator.latestFan?.value.isFanless == true || (coordinator.latestFan != nil && (coordinator.latestFan?.value.fans.isEmpty ?? false)))
    }

    private var statusText: String {
        guard store.isCategoryEnabled(category) else { return "Off" }
        switch coordinator.categoryAvailability[category] {
        case .some(.available): return "Available"
        case .some(.unavailable(let reason)): return "Unavailable: \(reason)"
        case .none: return "Waiting for the first reading"
        }
    }

    private var alertKinds: [AlertKind] {
        switch category {
        case .cpu: return [.cpu]
        case .memory: return [.memory]
        case .thermal: return [.temperature]
        case .disk: return [.disk]
        case .power: return hasBattery ? [.batteryLow, .batteryFull] : []
        case .gpu, .fan, .network: return []
        }
    }

    public var body: some View {
        Form {
            headerSection
            widgetGallerySection
            popoverOptionsSection
            if category == .network {
                networkInterfaceSection
            }
            if !alertKinds.isEmpty {
                alertsSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Header & Monitoring

    private var headerSection: some View {
        SwiftUI.Section {
            HStack(spacing: Instrument.Space.m) {
                Image(systemName: identity.symbol(hasBattery: hasBattery))
                    .font(.title2)
                    .foregroundStyle(CategoryPalette.color(for: category))
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.title3.weight(.semibold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Monitor \(name)", isOn: Binding(
                    get: { store.isCategoryEnabled(category) },
                    set: { store.setCategory(category, isEnabled: $0) }
                ))
                .accessibilityLabel("Monitor \(name)")
            }
            .padding(.vertical, 2)
        } footer: {
            if category == .fan {
                Text("macOS manages fan speed automatically.")
            }
        }
    }

    // MARK: - Widget Gallery

    private var widgetGallerySection: some View {
        SwiftUI.Section {
            if category == .fan && isFanless {
                Label("This Mac has no fans.", systemImage: "fan.slash")
                    .foregroundStyle(.secondary)
            } else {
                if store.isCategoryEnabled(category) && categoryWidgets.isEmpty {
                    HStack(spacing: Instrument.Space.s) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(CategoryPalette.color(for: category))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shown in Overview only")
                                .font(.callout.weight(.medium))
                            Text("Enable a widget below to place \(name) in the menu bar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } else if !store.isCategoryEnabled(category) {
                    Text("Turn on Monitor \(name) above to show widgets in the menu bar and Overview.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                WidgetCatalogView(
                    store: store,
                    category: category,
                    hasBattery: hasBattery,
                    coordinator: coordinator,
                    showAppearanceControl: false
                )
                .padding(.vertical, Instrument.Space.xs)
            }
        } header: {
            Text("Menu Bar Widgets")
        }
    }

    // MARK: - Popover Options

    private var popoverOptionsSection: some View {
        let supportedTabs = PopoverTab.supportedTabs(for: category, hasBattery: hasBattery)
        let defaultTabBinding = Binding<PopoverTab>(
            get: {
                if let firstWidget = categoryWidgets.first {
                    return firstWidget.resolvedPopoverConfig.openingTab
                }
                return store.lastSelectedTab(for: category) ?? .overview
            },
            set: { newTab in
                if categoryWidgets.isEmpty {
                    store.setLastSelectedTab(newTab, for: category)
                } else {
                    var updated = store.menuBarItems
                    for idx in updated.indices where updated[idx].category == category {
                        var pop = updated[idx].resolvedPopoverConfig
                        pop.openingTab = newTab
                        updated[idx].popover = pop
                    }
                    store.menuBarItems = updated
                }
            }
        )

        let historyRangeBinding = Binding<HistoryTimeRange>(
            get: { store.historyRange(for: category) },
            set: { store.setHistoryRange($0, for: category) }
        )

        return SwiftUI.Section {
            Picker("Default initial page", selection: defaultTabBinding) {
                ForEach(supportedTabs) { tab in
                    Text(tabLabel(for: tab)).tag(tab)
                }
            }
            .accessibilityLabel("Default initial page for \(name)")

            Picker("History range", selection: historyRangeBinding) {
                ForEach(HistoryTimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .accessibilityLabel("History range for \(name)")
        } header: {
            Text("Popover")
        } footer: {
            Text("The last page you viewed is always remembered per category, so the default initial page applies before a page has been remembered.")
        }
    }

    private func tabLabel(for tab: PopoverTab) -> String {
        switch tab {
        case .overview: return "Now"
        case .detail, .history: return tab.title(for: category)
        }
    }

    // MARK: - Network Interface Extra

    private var networkInterfaceSection: some View {
        let interfaces = (coordinator.latestNetwork?.value.interfaces ?? [])
            .sorted { $0.interfaceName < $1.interfaceName }
        let saved = store.networkInterfaceSelection

        return SwiftUI.Section {
            Picker("Active interface", selection: $store.networkInterfaceSelection) {
                Text("Automatic").tag(String?.none)
                ForEach(interfaces, id: \.interfaceName) { iface in
                    Text("\(iface.interfaceName) (\(iface.type.displayName))").tag(Optional(iface.interfaceName))
                }
                if let saved, !interfaces.contains(where: { $0.interfaceName == saved }) {
                    Text("\(saved) (Unavailable)").tag(Optional(saved))
                }
            }
            .accessibilityLabel("Active network interface")
        } header: {
            Text("Network Interface")
        } footer: {
            Text("Select a specific interface to track in the Network panel, or keep Automatic to follow macOS routing.")
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        SwiftUI.Section {
            if !store.notificationsEnabled {
                HStack(spacing: Instrument.Space.s) {
                    Image(systemName: "bell.slash")
                        .foregroundStyle(.secondary)
                    Text("Hardware alerts are turned off in Notifications.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Turn On") {
                        store.notificationsEnabled = true
                    }
                    .controlSize(.small)
                }
            }

            ForEach(alertKinds) { kind in
                AlertRuleEditorRow(
                    kind: kind,
                    store: store,
                    coordinator: coordinator,
                    hasBattery: hasBattery,
                    showTargetPicker: true
                )
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text("Alerts trigger only after the condition holds continuously for the selected sustain window.")
        }
    }
}
