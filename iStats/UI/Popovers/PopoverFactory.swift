import SwiftUI
import AppKit
import iStatsCore

/// Fallback popover view displayed when zero widgets are active in the menu bar.
public struct NoWidgetsActiveView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("No Widgets Active")
                    .font(.system(size: 13, weight: .semibold))
                Text("Enable metrics to display them in your menu bar.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Open Preferences...") {
                PreferencesWindowController.shared.showPreferences()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: Tokens.popoverWidth)
        .background(PopoverVisualEffectView())
    }
}

/// The unified PopoverFactory for iStats (ADR 0008).
/// Responsible for instantiating purpose-driven category popovers
/// with resolved opening tabs, focus subcomponents, and fixed 330 pt width.
@MainActor
public enum PopoverFactory {

    /// Instantiates the tabbed popover view for a given menu bar item configuration.
    @ViewBuilder
    public static func makePopoverView(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        let popConfig = config.resolvedPopoverConfig
        let openingTab = (popConfig.rememberLastTab ? preferences.lastSelectedTab(for: config.category) : nil) ?? popConfig.openingTab
        let focusSource = config.source ?? popConfig.focusSource

        makeCategoryPopoverView(
            category: config.category,
            initialTab: openingTab,
            focusSource: focusSource,
            coordinator: coordinator,
            preferences: preferences
        )
    }

    /// Instantiates the tabbed popover view for a specific category.
    @ViewBuilder
    public static func makeCategoryPopoverView(
        category: MetricCategory,
        initialTab: PopoverTab = .overview,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        switch category {
        case .cpu:
            CPUPopover(
                initialTab: initialTab,
                coordinator: coordinator,
                preferences: preferences
            )
        case .memory:
            MemoryPopover(
                initialTab: initialTab,
                coordinator: coordinator,
                preferences: preferences
            )
        case .gpu:
            GPUPopover(
                initialTab: initialTab,
                coordinator: coordinator,
                preferences: preferences
            )
        case .thermal:
            TemperaturePopover(
                initialTab: initialTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .fan:
            FanPopover(
                initialTab: initialTab,
                coordinator: coordinator,
                preferences: preferences
            )
        case .network:
            NetworkPopover(
                initialTab: initialTab,
                coordinator: coordinator,
                preferences: preferences
            )
        case .disk:
            DiskPopover(
                initialTab: initialTab,
                coordinator: coordinator,
                preferences: preferences
            )
        case .power:
            PowerPopover(
                initialTab: initialTab,
                coordinator: coordinator,
                preferences: preferences
            )
        }
    }

    /// Creates a dedicated NSHostingController wrapping the concrete tabbed popover for MenuBarController.
    public static func makeHostingController(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> NSViewController {
        let popConfig = config.resolvedPopoverConfig
        let openingTab = (popConfig.rememberLastTab ? preferences.lastSelectedTab(for: config.category) : nil) ?? popConfig.openingTab
        let focusSource = config.source ?? popConfig.focusSource

        switch config.category {
        case .cpu:
            let view = CPUPopover(initialTab: openingTab, coordinator: coordinator, preferences: preferences)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            return controller
        case .memory:
            let view = MemoryPopover(initialTab: openingTab, coordinator: coordinator, preferences: preferences)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            return controller
        case .gpu:
            let view = GPUPopover(initialTab: openingTab, coordinator: coordinator, preferences: preferences)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            return controller
        case .thermal:
            let view = TemperaturePopover(initialTab: openingTab, focusSource: focusSource, coordinator: coordinator, preferences: preferences)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            return controller
        case .fan:
            let view = FanPopover(initialTab: openingTab, coordinator: coordinator, preferences: preferences)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            return controller
        case .network:
            let view = NetworkPopover(initialTab: openingTab, coordinator: coordinator, preferences: preferences)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            return controller
        case .disk:
            let view = DiskPopover(initialTab: openingTab, coordinator: coordinator, preferences: preferences)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            return controller
        case .power:
            let view = PowerPopover(initialTab: openingTab, coordinator: coordinator, preferences: preferences)
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            return controller
        }
    }

    /// Creates a fallback NSHostingController when no widgets are active.
    public static func makeFallbackHostingController() -> NSHostingController<NoWidgetsActiveView> {
        let controller = NSHostingController(rootView: NoWidgetsActiveView())
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }
}
