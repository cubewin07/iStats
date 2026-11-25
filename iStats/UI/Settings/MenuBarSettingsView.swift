import SwiftUI
import UniformTypeIdentifiers
import iStatsCore

/// Menu Bar Settings page: live preview strip, drag-to-reorder active widget list
/// (synced with `⌘`-drag via `MenuBarOrdering.observedOrder` and `PreferencesStore.menuBarItems`),
/// appearance mode selector, and catalog browser to add/remove widgets.
public struct MenuBarSettingsView: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator

    @State private var selectedCatalogCategory: MetricCategory = .cpu
    @State private var draggingItemID: String?

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.store = store
        self.coordinator = coordinator
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private var widgetOptions: WidgetOptions {
        WidgetOptions(
            temperatureUnit: store.temperatureUnit,
            networkUnit: store.networkUnit,
            byteUnitStandard: store.byteUnitStandard,
            appearance: store.menuBarAppearance
        )
    }

    public var body: some View {
        Form {
            previewSection
            activeWidgetsSection
            addWidgetsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Live Menu Bar Preview

    private var previewSection: some View {
        SwiftUI.Section {
            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                HStack {
                    if store.isSamplingPaused {
                        Label("Sampling Paused (Minimal Icon)", systemImage: "pause.circle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Resume") {
                            coordinator.resumeSampling()
                        }
                        .controlSize(.small)
                    } else {
                        let count = store.activeMenuBarItems.count
                        Text("\(count) \(count == 1 ? "widget" : "widgets") active")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Instrument.Space.s) {
                        if store.isSamplingPaused {
                            HStack(spacing: Instrument.Space.xs) {
                                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                Text("Paused")
                                    .font(.caption)
                            }
                            .padding(.horizontal, Instrument.Space.m)
                            .padding(.vertical, Instrument.Space.xs)
                            .background(Instrument.Surface.inset)
                            .clipShape(RoundedRectangle(cornerRadius: Instrument.Radius.chip))
                        } else if store.activeMenuBarItems.isEmpty {
                            Text("No active menu bar widgets. Add one from the catalog below.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, Instrument.Space.xs)
                        } else {
                            ForEach(store.activeMenuBarItems) { item in
                                WidgetPreview(
                                    config: item,
                                    snapshot: previewSnapshot(for: item),
                                    options: widgetOptions,
                                    scale: 2.0
                                )
                            }
                        }
                    }
                    .padding(.vertical, Instrument.Space.xxs)
                }
                .padding(.horizontal, Instrument.Space.m)
                .padding(.vertical, Instrument.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Instrument.Surface.inset)
                .clipShape(RoundedRectangle(cornerRadius: Instrument.Radius.control))

                Picker("Widget color", selection: $store.menuBarAppearance) {
                    ForEach(MenuBarAppearance.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityLabel("Menu bar widget color")
            }
        } header: {
            Text("Menu Bar Preview")
        } footer: {
            Text("Hold ⌘ and drag icons in the macOS menu bar to reorder, or drag rows below. Both stay in sync.")
        }
    }

    // MARK: - Active Widgets (Drag Reorder + Remove)

    private var activeWidgetsSection: some View {
        SwiftUI.Section {
            if store.menuBarItems.isEmpty {
                Text("No widgets configured.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.menuBarItems) { item in
                    activeWidgetRow(item)
                        .onDrag {
                            draggingItemID = item.id
                            return NSItemProvider(object: item.id as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: WidgetReorderDropDelegate(
                                targetItemID: item.id,
                                draggingItemID: $draggingItemID,
                                onMove: { fromID, toID in
                                    moveItem(id: fromID, beforeItemWithID: toID)
                                }
                            )
                        )
                }
                .onMove(perform: moveItems)
            }
        } header: {
            Text("Active Widgets")
        } footer: {
            Text("Drag rows to change their order. Removing all widgets shows the Overview menu bar icon.")
        }
    }

    private func activeWidgetRow(_ item: MenuBarItemConfig) -> some View {
        let isCategoryEnabled = store.isCategoryEnabled(item.category)
        let title = item.category.identity.displayName(hasBattery: hasBattery)
        let styleName = item.style.displayName(for: item.category, hasBattery: hasBattery)

        return HStack(spacing: Instrument.Space.m) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            WidgetPreview(
                config: item,
                snapshot: previewSnapshot(for: item),
                options: widgetOptions,
                scale: 2.0
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Instrument.Space.s) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(styleName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let source = item.source, item.category == .thermal {
                        MetricSourceBadge(source: source)
                    }
                }

                if !isCategoryEnabled {
                    Text("Hidden in menu bar (\(title) monitoring is off)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Button {
                moveItem(id: item.id, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(store.menuBarItems.first?.id == item.id)
            .accessibilityLabel("Move \(title) \(styleName) left")

            Button {
                moveItem(id: item.id, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(store.menuBarItems.last?.id == item.id)
            .accessibilityLabel("Move \(title) \(styleName) right")

            Button(role: .destructive) {
                removeItem(item)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(title) \(styleName)")
            .help("Remove from menu bar")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Add Widgets via Catalog

    private var addWidgetsSection: some View {
        SwiftUI.Section {
            Picker("Category", selection: $selectedCatalogCategory) {
                ForEach(MetricCategory.allCases) { cat in
                    Label(
                        cat.identity.displayName(hasBattery: hasBattery),
                        systemImage: cat.identity.symbol(hasBattery: hasBattery)
                    )
                    .tag(cat)
                }
            }
            .accessibilityLabel("Catalog category")

            WidgetCatalogView(
                store: store,
                category: selectedCatalogCategory,
                hasBattery: hasBattery,
                coordinator: coordinator,
                showAppearanceControl: false
            )
            .padding(.vertical, Instrument.Space.xs)
        } header: {
            Text("Widget Catalog")
        }
    }

    // MARK: - Actions & Reordering

    /// Moves items in `store.menuBarItems` and syncs active ordering cleanly.
    public func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        var updated = store.menuBarItems
        updated.move(fromOffsets: source, toOffset: destination)
        applyOrderedItems(updated)
    }

    /// Moves a single item before `targetID`.
    public func moveItem(id sourceID: String, beforeItemWithID targetID: String) {
        guard sourceID != targetID,
              let fromIndex = store.menuBarItems.firstIndex(where: { $0.id == sourceID }),
              let toIndex = store.menuBarItems.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        var updated = store.menuBarItems
        let moved = updated.remove(at: fromIndex)
        updated.insert(moved, at: min(toIndex, updated.count))
        applyOrderedItems(updated)
    }

    /// Moves a single item by `offset` (-1 or +1) in the menu bar order.
    public func moveItem(id: String, offset: Int) {
        guard let idx = store.menuBarItems.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + offset
        guard target >= 0 && target < store.menuBarItems.count else { return }
        var updated = store.menuBarItems
        let moved = updated.remove(at: idx)
        updated.insert(moved, at: target)
        applyOrderedItems(updated)
    }

    private func applyOrderedItems(_ updated: [MenuBarItemConfig]) {
        let activeIds = updated.filter { store.isCategoryEnabled($0.category) }.map(\.id)
        if !store.isSamplingPaused, activeIds.count == store.activeMenuBarItems.count {
            store.menuBarItems = updated
            store.setActiveMenuBarOrder(activeIds)
        } else {
            store.menuBarItems = updated
        }
    }

    /// Removes `item` from the menu bar configuration.
    public func removeItem(_ item: MenuBarItemConfig) {
        store.setItemEnabled(
            category: item.category,
            style: item.style,
            source: item.source,
            isEnabled: false
        )
    }

    /// Adds a catalog widget configuration to the menu bar.
    public func addItem(_ config: MenuBarItemConfig) {
        store.setItemEnabled(
            category: config.category,
            style: config.style,
            source: config.source,
            throughputLayout: config.throughputLayout,
            showLabel: config.showLabel,
            isEnabled: true
        )
    }

    private func previewSnapshot(for config: MenuBarItemConfig) -> WidgetSnapshot {
        let hasLive: Bool
        switch config.category {
        case .cpu: hasLive = coordinator.latestCPU != nil
        case .memory: hasLive = coordinator.latestMemory != nil
        case .gpu: hasLive = coordinator.latestGPU != nil
        case .thermal: hasLive = coordinator.latestThermal != nil
        case .fan: hasLive = coordinator.latestFan != nil
        case .network: hasLive = coordinator.latestNetwork != nil
        case .disk: hasLive = coordinator.latestDisk != nil
        case .power: hasLive = coordinator.latestPower != nil
        }
        if hasLive {
            return MenuBarIconRenderer.snapshot(config: config, coordinator: coordinator)
        }
        if let entry = WidgetCatalog.entry(for: config.category, style: config.style, hasBattery: hasBattery) {
            return entry.sampleSnapshot(hasBattery: hasBattery)
        }
        return WidgetCatalog.defaultEntry(for: config.category, hasBattery: hasBattery).sampleSnapshot(hasBattery: hasBattery)
    }
}

private struct WidgetReorderDropDelegate: DropDelegate {
    let targetItemID: String
    @Binding var draggingItemID: String?
    let onMove: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingItemID, draggingItemID != targetItemID else { return }
        onMove(draggingItemID, targetItemID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItemID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
