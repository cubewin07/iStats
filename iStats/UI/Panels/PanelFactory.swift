import SwiftUI
import AppKit
import iStatsCore

/// Factory for instantiating Instrument Panels (ADR 0009 / Task 8.6).
@MainActor
public enum PanelFactory {

    /// Instantiates the panel view for a given menu bar item configuration.
    @ViewBuilder
    public static func makePanelView(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        let popConfig = config.resolvedPopoverConfig
        let openingTab = (popConfig.rememberLastTab ? preferences.lastSelectedTab(for: config.category) : nil) ?? popConfig.openingTab
        let focusSource = config.source ?? popConfig.focusSource

        makeCategoryPanelView(
            category: config.category,
            initialTab: openingTab,
            rememberLastTab: popConfig.rememberLastTab,
            focusSource: focusSource,
            coordinator: coordinator,
            preferences: preferences
        )
    }

    /// Instantiates the panel view for a specific metric category.
    @ViewBuilder
    public static func makeCategoryPanelView(
        category: MetricCategory,
        initialTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        switch category {
        case .cpu:
            CPUPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .memory:
            MemoryPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .gpu:
            GPUPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .thermal:
            TemperaturePanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .fan:
            FanPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .network:
            NetworkPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .disk:
            DiskPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .power:
            PowerPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        }
    }
}

/// The fallback panel view shown when no widgets are currently active in the menu bar.
public struct NoWidgetsActiveView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: Instrument.Space.l) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            VStack(spacing: Instrument.Space.xs) {
                Text("No Widgets Active")
                    .font(Instrument.Typography.title)
                Text("Enable metrics to display them in your menu bar.")
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Open Preferences...") {
                PreferencesWindowController.shared.showPreferences()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(Instrument.Space.xxl)
        .frame(width: Instrument.Size.panelWidth)
    }
}
