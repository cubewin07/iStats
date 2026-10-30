import SwiftUI
import AppKit
import iStatsCore

/// Modern, intuitive Menu Bar studio pane.
/// Features a live interactive menu bar preview strip with reordering,
/// category-specific widget cards with live icons, and a unified Popover Stage.
public struct PreferencesMenuBarPane: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator

    @State private var selectedCategory: MetricCategory = .cpu
    @State private var selectedWidgetStyle: MetricDisplayStyle = .bar
    @State private var selectedPopoverStyle: PopoverStyle = .cpuCluster

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

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. Live Menu Bar Strip & Controls
            menuBarPreviewHeader
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // MARK: - 2. Split Workspace (Category & Widgets on Left, Popover Stage on Right)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Left Column: Category Rail & Widget Cards
                    VStack(spacing: 0) {
                        // Category Horizontal Bar
                        categoryPillsBar
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

                        Divider()

                        // Category Master & Widget Style Cards
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                categoryHeaderBanner

                                widgetCardsGrid
                            }
                            .padding(16)
                        }
                    }
                    .frame(width: max(380, geo.size.width * 0.52))

                    Divider()

                    // Right Column: Live Popover Preview Stage
                    popoverPreviewStage
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            syncSelectedStyles()
        }
        .onChange(of: selectedCategory) { _ in
            syncSelectedStyles()
        }
        .onChange(of: store.widgetPopoverStyles) { _ in
            syncSelectedStyles()
        }
        .onChange(of: store.menuBarItems) { _ in
            syncSelectedStyles()
        }
    }

    private func syncSelectedStyles() {
        let recommended = MetricDisplayStyle.recommendedStyles(for: selectedCategory, hasBattery: hasBattery)
        let legacy = store.menuBarItems.filter { $0.category == selectedCategory && !recommended.contains($0.style) }.map(\.style)
        let styles = recommended + legacy
        if !styles.contains(selectedWidgetStyle) {
            selectedWidgetStyle = styles.first ?? .text
        }
        selectedPopoverStyle = store.resolvedPopoverStyle(for: selectedCategory, widgetStyle: selectedWidgetStyle, hasBattery: hasBattery)
    }

    // MARK: - Live Menu Bar Strip Header

    private var menuBarPreviewHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Menu Bar Preview")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Click an item to configure it, or use the arrows to reorder items in your menu bar.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Footprint & Pause Status
                if store.isSamplingPaused {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                        Text("Sampling Paused (Minimal Icon)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)

                        Button("Resume") {
                            coordinator.resumeSampling()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    let activeCount = store.activeMenuBarItems.count
                    HStack(spacing: 6) {
                        Text("\(activeCount) \(activeCount == 1 ? "widget" : "widgets") active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
                }
            }

            // Realistic Simulated Menu Bar
            HStack(spacing: 0) {
                Spacer()

                if store.isSamplingPaused {
                    // Minimal iStats Icon When Paused
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if store.activeMenuBarItems.isEmpty {
                    Text("No widgets active. Enable items below to display them.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    // Active Widgets Rendered Live in Order
                    HStack(spacing: 6) {
                        ForEach(Array(store.activeMenuBarItems.enumerated()), id: \.element.id) { index, item in
                            menuBarChip(item: item, index: index)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                    )
            )
        }
    }

    private func menuBarChip(item: MenuBarItemConfig, index: Int) -> some View {
        let isSelected = (selectedCategory == item.category && selectedWidgetStyle == item.style)
        let renderResult = MenuBarIconRenderer.render(
            config: item,
            coordinator: coordinator,
            preferences: store
        )
        let canMoveLeft = index > 0
        let canMoveRight = index < store.activeMenuBarItems.count - 1

        return HStack(spacing: 4) {
            // Live Visual Output
            if let img = renderResult.image {
                Image(nsImage: img)
                    .renderingMode(img.isTemplate ? .template : .original)
            }
            if !renderResult.title.isEmpty {
                Text(renderResult.title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }

            // Selection Controls (Reorder & Remove)
            if isSelected {
                HStack(spacing: 2) {
                    Button(action: {
                        store.moveActiveMenuBarItem(id: item.id, direction: -1)
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveLeft)
                    .opacity(canMoveLeft ? 0.9 : 0.3)
                    .help("Move widget left")

                    Button(action: {
                        store.moveActiveMenuBarItem(id: item.id, direction: 1)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveRight)
                    .opacity(canMoveRight ? 0.9 : 0.3)
                    .help("Move widget right")

                    Button(action: {
                        store.setItemEnabled(category: item.category, style: item.style, isEnabled: false)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Remove from menu bar")
                }
                .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.25 : 0.75)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCategory = item.category
            selectedWidgetStyle = item.style
            selectedPopoverStyle = store.resolvedPopoverStyle(for: item.category, widgetStyle: item.style)
        }
    }

    // MARK: - Category Pills Bar

    private var categoryPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MetricCategory.allCases, id: \.self) { category in
                    let isSelected = (selectedCategory == category)
                    let activeCount = store.items(for: category).count
                    let isEnabled = store.isCategoryEnabled(category)
                    let catColor = preferenceCategoryColor(for: category)

                    Button(action: {
                        selectedCategory = category
                        syncSelectedStyles()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: preferenceCategoryIcon(for: category))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(isSelected ? .white : (isEnabled ? catColor : .secondary))

                            Text(category.displayName)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? .white : .primary)

                            if !isEnabled {
                                Text("Off")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundColor(.secondary)
                            } else if activeCount > 0 {
                                Text("\(activeCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(isSelected ? Color.white.opacity(0.25) : catColor.opacity(0.18))
                                    .clipShape(Capsule())
                                    .foregroundColor(isSelected ? .white : catColor)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? catColor : Color.primary.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Category Master Banner

    private var categoryHeaderBanner: some View {
        HStack(spacing: 12) {
            SettingsBadge(
                icon: preferenceCategoryIcon(for: selectedCategory),
                color: preferenceCategoryColor(for: selectedCategory),
                size: 32
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCategory.displayName)
                    .font(.system(size: 14, weight: .bold))
                Text(categoryDescription(for: selectedCategory))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { store.isCategoryEnabled(selectedCategory) },
                set: { store.setCategory(selectedCategory, isEnabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help("Enable or disable background telemetry sampling for \(selectedCategory.displayName)")
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - Widget Style Cards Grid

    private var widgetCardsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Widgets for \(selectedCategory.displayName)")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.secondary)

            if !store.isCategoryEnabled(selectedCategory) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle")
                        .foregroundColor(.secondary)
                    Text("\(selectedCategory.displayName) sampling is turned off. Toggle it above to display and preview widgets.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)
            } else {
                let recommended = MetricDisplayStyle.recommendedStyles(for: selectedCategory, hasBattery: hasBattery)
                let legacy = store.menuBarItems.filter { $0.category == selectedCategory && !recommended.contains($0.style) }.map(\.style)
                ForEach(recommended + legacy) { style in
                    widgetStyleCard(style: style)
                }
            }
        }
    }

    private func widgetStyleCard(style: MetricDisplayStyle) -> some View {
        let isSelected = (selectedWidgetStyle == style)
        let isItemEnabled = store.isItemEnabled(category: selectedCategory, style: style)
        let customPopover = store.popoverStyle(for: selectedCategory, widgetStyle: style)
        let resolvedPopover = store.resolvedPopoverStyle(for: selectedCategory, widgetStyle: style).purposefulStyle(for: selectedCategory)

        let renderResult = MenuBarIconRenderer.render(
            config: MenuBarItemConfig(category: selectedCategory, style: style),
            coordinator: coordinator,
            preferences: store
        )

        return HStack(spacing: 12) {
            // Live Menu Bar Output Badge
            HStack(spacing: 4) {
                if let img = renderResult.image {
                    Image(nsImage: img)
                        .renderingMode(img.isTemplate ? .template : .original)
                }
                if !renderResult.title.isEmpty {
                    Text(renderResult.title)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minWidth: 46, minHeight: 24)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Widget Information
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(style.displayName(for: selectedCategory))
                        .font(.system(size: 12.5, weight: .semibold))

                    if customPopover != nil {
                        Text("Custom Popover")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text("Opens: \(resolvedPopover.displayName(for: selectedCategory))")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Selection Preview Button
            Button(action: {
                selectedWidgetStyle = style
                selectedPopoverStyle = resolvedPopover
            }) {
                Image(systemName: isSelected ? "eye.fill" : "eye")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Preview and configure popover in the stage")

            // Show in Menu Bar Toggle
            Toggle("", isOn: Binding(
                get: { isItemEnabled },
                set: { store.setItemEnabled(category: selectedCategory, style: style, isEnabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help("Toggle visibility in macOS menu bar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedWidgetStyle = style
            selectedPopoverStyle = resolvedPopover
        }
    }

    // MARK: - Popover Preview Stage

    private var popoverPreviewStage: some View {
        VStack(spacing: 0) {
            // Stage Header Bar with Single Unified Popover Picker
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedCategory.displayName) • \(selectedWidgetStyle.displayName(for: selectedCategory))")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Select the popover opened by clicking this widget.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                let supportedPopovers = PopoverStyle.purposefulPopovers(for: selectedCategory, hasBattery: hasBattery)
                let defaultStyle = PopoverStyle.defaultStyle(for: selectedCategory, widgetStyle: selectedWidgetStyle, hasBattery: hasBattery).purposefulStyle(for: selectedCategory)

                Picker("", selection: Binding<PopoverStyle>(
                    get: { selectedPopoverStyle.purposefulStyle(for: selectedCategory) },
                    set: { newStyle in
                        selectedPopoverStyle = newStyle
                        store.setPopoverStyle(newStyle, for: selectedCategory, widgetStyle: selectedWidgetStyle, hasBattery: hasBattery)
                    }
                )) {
                    ForEach(supportedPopovers) { pStyle in
                        let suffix = (pStyle == defaultStyle) ? " (Default)" : ""
                        Text("\(pStyle.displayName(for: selectedCategory))\(suffix)").tag(pStyle)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 155)

                if store.popoverStyle(for: selectedCategory, widgetStyle: selectedWidgetStyle) != nil {
                    Button("Reset") {
                        store.setPopoverStyle(nil, for: selectedCategory, widgetStyle: selectedWidgetStyle, hasBattery: hasBattery)
                        selectedPopoverStyle = defaultStyle
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reset to natural default popover")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Interactive Popover View Canvas
            ScrollView {
                VStack(spacing: 0) {
                    ConfigPopoverFactory.makePopoverView(
                        category: selectedCategory,
                        popoverStyle: selectedPopoverStyle,
                        coordinator: coordinator,
                        preferences: store
                    )
                    .frame(width: 330)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
        }
    }

    private func categoryDescription(for category: MetricCategory) -> String {
        switch category {
        case .cpu: return "Processor utilization, load averages, and core usage."
        case .memory: return "RAM breakdown (active, wired, compressed) and pressure."
        case .thermal: return "SoC temperatures and thermal pressure level."
        case .fan: return "Fan speeds and cooling system status."
        case .gpu: return "GPU core utilization and renderer metrics."
        case .network: return "Real-time interface throughput and bandwidth."
        case .disk: return "Disk I/O operations and volume space capacity."
        case .power: return "Battery status, health, and power consumption."
        }
    }
}
