import SwiftUI
import AppKit
import iStatsCore

/// Visual catalog of menu bar widgets for a single `MetricCategory`, with Add / Replace actions
/// and an appearance segmented control bound to `PreferencesStore.menuBarAppearance` (Task 9.8).
///
/// Designed to be hosted inside Settings category pages by Task 9.10.
public struct WidgetCatalogView: View {
    @ObservedObject public var store: PreferencesStore
    public let category: MetricCategory
    public var hasBattery: Bool
    public var coordinator: MetricsCoordinator?
    public var showAppearanceControl: Bool
    public var onSelect: ((MenuBarItemConfig) -> Void)?

    @State private var selectedThermalSource: MetricSource = .peak
    @State private var selectedThroughputLayout: ThroughputLayout = .stacked

    public init(
        store: PreferencesStore = .shared,
        category: MetricCategory,
        hasBattery: Bool = true,
        coordinator: MetricsCoordinator? = nil,
        showAppearanceControl: Bool = true,
        onSelect: ((MenuBarItemConfig) -> Void)? = nil
    ) {
        self.store = store
        self.category = category
        self.hasBattery = hasBattery
        self.coordinator = coordinator
        self.showAppearanceControl = showAppearanceControl
        self.onSelect = onSelect
    }

    private var entries: [WidgetCatalogEntry] {
        WidgetCatalog.entries(for: category, hasBattery: hasBattery)
    }

    private var availableThermalSources: [MetricSource] {
        MetricSource.allCases.filter { $0 != .battery || hasBattery }
    }

    private var widgetOptions: WidgetOptions {
        WidgetOptions(
            temperatureUnit: store.temperatureUnit,
            networkUnit: store.networkUnit,
            byteUnitStandard: store.byteUnitStandard,
            appearance: store.menuBarAppearance
        )
    }

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: Instrument.Space.l)
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: Instrument.Space.l) {
            if showAppearanceControl {
                appearanceControl
            }

            if category == .thermal {
                thermalSourcePicker
            }

            if category == .network || category == .disk {
                throughputLayoutPicker
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: Instrument.Space.l) {
                ForEach(entries) { entry in
                    catalogCard(for: entry)
                }
            }
        }
    }

    // MARK: - Controls

    private var appearanceControl: some View {
        VStack(alignment: .leading, spacing: Instrument.Space.xs) {
            HStack {
                Text("Menu Bar Appearance")
                    .font(Instrument.Typography.captionStrong)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Menu Bar Appearance", selection: $store.menuBarAppearance) {
                    ForEach(MenuBarAppearance.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 320)
            }
            Text(store.menuBarAppearance.summary)
                .font(Instrument.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var thermalSourcePicker: some View {
        HStack(spacing: Instrument.Space.m) {
            Text("Sensor Source")
                .font(Instrument.Typography.captionMedium)
                .foregroundStyle(.secondary)
            Picker("Sensor Source", selection: $selectedThermalSource) {
                ForEach(availableThermalSources, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 180)
            Spacer()
        }
    }

    private var throughputLayoutBinding: Binding<ThroughputLayout> {
        Binding(
            get: {
                store.item(category: category, style: .throughput)?.throughputLayout ?? selectedThroughputLayout
            },
            set: { newLayout in
                selectedThroughputLayout = newLayout
                if let existing = store.item(category: category, style: .throughput) {
                    store.setItemEnabled(
                        category: category,
                        style: .throughput,
                        source: existing.source,
                        throughputLayout: newLayout,
                        showLabel: existing.showLabel,
                        isEnabled: true
                    )
                }
            }
        )
    }

    private var throughputLayoutPicker: some View {
        HStack(spacing: Instrument.Space.m) {
            Text("Dual Layout")
                .font(Instrument.Typography.captionMedium)
                .foregroundStyle(.secondary)
            Picker("Dual Layout", selection: throughputLayoutBinding) {
                ForEach(ThroughputLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(maxWidth: 220)
            Spacer()
        }
    }

    // MARK: - Catalog Card

    private func catalogCard(for entry: WidgetCatalogEntry) -> some View {
        let source = effectiveSource(for: entry)
        let layout = effectiveLayout(for: entry)
        let existing = store.item(category: category, style: entry.style, source: source)
        let isActive = store.isExactItemEnabled(category: category, style: entry.style, source: source)
        let hasOtherCategoryItems = !store.items(for: category).isEmpty
        let config = entry.makeConfig(
            source: source,
            throughputLayout: existing?.throughputLayout ?? layout,
            showLabel: existing?.showLabel ?? false
        )
        let snapshot = previewSnapshot(for: entry, config: config)
        let accent = CategoryPalette.color(for: category)

        return VStack(alignment: .leading, spacing: Instrument.Space.m) {
            HStack(alignment: .center, spacing: Instrument.Space.m) {
                HStack(spacing: Instrument.Space.xs) {
                    WidgetPreview(
                        config: config,
                        snapshot: snapshot,
                        options: widgetOptions,
                        scale: 2.0,
                        colorScheme: .light
                    )
                    WidgetPreview(
                        config: config,
                        snapshot: snapshot,
                        options: widgetOptions,
                        scale: 2.0,
                        colorScheme: .dark
                    )
                }

                Spacer(minLength: Instrument.Space.xs)

                Text(entry.vocabularyName)
                    .font(Instrument.Typography.eyebrow)
                    .foregroundStyle(isActive ? accent : .secondary)
                    .padding(.horizontal, Instrument.Space.s)
                    .padding(.vertical, Instrument.Space.xxs)
                    .background(
                        Capsule().fill(isActive ? accent.opacity(0.14) : Instrument.Surface.inset)
                    )
            }

            VStack(alignment: .leading, spacing: Instrument.Space.xxs) {
                Text(entry.title)
                    .font(Instrument.Typography.headlineStrong)
                Text(entry.summary)
                    .font(Instrument.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if (entry.style == .gauge || entry.style == .sparkline) && isActive {
                Toggle("Show label (\(category.identity.shortLabel(hasBattery: hasBattery)))", isOn: Binding(
                    get: { existing?.showLabel ?? false },
                    set: { newValue in
                        store.setItemEnabled(
                            category: category,
                            style: entry.style,
                            source: source,
                            throughputLayout: existing?.throughputLayout ?? layout,
                            showLabel: newValue,
                            isEnabled: true
                        )
                    }
                ))
                .font(Instrument.Typography.caption)
                .controlSize(.small)
            }

            Spacer(minLength: 0)

            HStack(spacing: Instrument.Space.s) {
                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(Instrument.Typography.captionStrong)
                        .foregroundStyle(accent)

                    Spacer()

                    Button("Remove") {
                        store.setItemEnabled(
                            category: category,
                            style: entry.style,
                            source: source,
                            isEnabled: false
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Add") {
                        addWidget(config)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if hasOtherCategoryItems {
                        Button("Replace") {
                            replaceCategoryWidgets(with: config)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()
                }
            }
        }
        .padding(Instrument.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.module)
                .fill(isActive ? accent.opacity(0.06) : Instrument.Surface.module)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Instrument.Radius.module)
                .strokeBorder(
                    isActive ? accent.opacity(0.45) : Instrument.Surface.hairline,
                    lineWidth: isActive ? 1.25 : 0.75
                )
        )
    }

    // MARK: - Actions & Helpers

    private func effectiveSource(for entry: WidgetCatalogEntry) -> MetricSource? {
        guard entry.category == .thermal && (entry.style == .text || entry.style == .glyph) else {
            return nil
        }
        return selectedThermalSource
    }

    private func effectiveLayout(for entry: WidgetCatalogEntry) -> ThroughputLayout? {
        guard (entry.category == .network || entry.category == .disk) && entry.style == .throughput else {
            return nil
        }
        return selectedThroughputLayout
    }

    private func previewSnapshot(for entry: WidgetCatalogEntry, config: MenuBarItemConfig) -> WidgetSnapshot {
        if let coordinator, hasLiveSample(for: category, coordinator: coordinator) {
            return MenuBarIconRenderer.snapshot(config: config, coordinator: coordinator)
        }
        return entry.sampleSnapshot(hasBattery: hasBattery)
    }

    private func hasLiveSample(for category: MetricCategory, coordinator: MetricsCoordinator) -> Bool {
        switch category {
        case .cpu: return coordinator.latestCPU != nil
        case .memory: return coordinator.latestMemory != nil
        case .gpu: return coordinator.latestGPU != nil
        case .thermal: return coordinator.latestThermal != nil
        case .fan: return coordinator.latestFan != nil
        case .network: return coordinator.latestNetwork != nil
        case .disk: return coordinator.latestDisk != nil
        case .power: return coordinator.latestPower != nil
        }
    }

    private func addWidget(_ config: MenuBarItemConfig) {
        store.setItemEnabled(
            category: config.category,
            style: config.style,
            source: config.source,
            throughputLayout: config.throughputLayout,
            showLabel: config.showLabel,
            isEnabled: true
        )
        onSelect?(config)
    }

    /// Replaces all existing widgets for `category` with `config`, preserving the first slot position.
    public func replaceCategoryWidgets(with config: MenuBarItemConfig) {
        var updated = store.menuBarItems
        if let firstIndex = updated.firstIndex(where: { $0.category == category }) {
            updated.removeAll { $0.category == category }
            updated.insert(config, at: min(firstIndex, updated.count))
        } else {
            updated.append(config)
        }
        store.menuBarItems = MenuBarItemConfig.deduplicated(updated)
        onSelect?(config)
    }
}
