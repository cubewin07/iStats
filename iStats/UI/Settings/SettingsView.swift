import SwiftUI
import iStatsCore

/// Which Settings page is selected, persisted to `PreferencesStore.lastSettingsSection`.
/// Owned by `PreferencesWindowController` so deep links can switch pages while the window is open.
@MainActor
public final class SettingsNavigationModel: ObservableObject {
    @Published public private(set) var selection: SettingsSection
    private let store: PreferencesStore

    /// Restores the saved page; a missing or stale key opens General.
    public init(store: PreferencesStore) {
        self.store = store
        self.selection = SettingsSection.resolved(storageKey: store.lastSettingsSection)
    }

    public func select(_ section: SettingsSection) {
        selection = section
        store.lastSettingsSection = section.storageKey
    }

    /// Selects the page for a storage key; unknown keys open General.
    public func select(storageKey: String?) {
        select(SettingsSection.resolved(storageKey: storageKey))
    }
}

/// The Settings window content: sidebar on the left, one native grouped `Form` page on the right.
public struct SettingsView: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var navigation: SettingsNavigationModel

    public init(
        store: PreferencesStore,
        coordinator: MetricsCoordinator,
        navigation: SettingsNavigationModel
    ) {
        self.store = store
        self.coordinator = coordinator
        self.navigation = navigation
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private var selectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { navigation.selection },
            set: { newValue in
                if let newValue { navigation.select(newValue) }
            }
        )
    }

    public var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: selectionBinding, hasBattery: hasBattery)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail(for: navigation.selection)
                .id(navigation.selection)
                .navigationSubtitle(navigation.selection.title(hasBattery: hasBattery))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 560)
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsPage(store: store, coordinator: coordinator)
        case .appearance:
            AppearanceSettingsPage(store: store, hasBattery: hasBattery)
        case .menuBar:
            MenuBarSettingsView(store: store, coordinator: coordinator)
        case .category(let category):
            CategorySettingsView(category: category, store: store, coordinator: coordinator, hasBattery: hasBattery)
        case .notifications:
            NotificationsSettingsPage(store: store, coordinator: coordinator)
        case .about:
            AboutSettingsPage(coordinator: coordinator)
        }
    }
}
