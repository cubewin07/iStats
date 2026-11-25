import AppKit
import SwiftUI
import iStatsCore

/// Menu bar rendering entry point (task 9.7).
///
/// Pipeline: `MetricsCoordinator` samples -> `WidgetSnapshot` -> pure `WidgetModel` -> per-family
/// renderer in `iStats/UI/MenuBar/`. The model's `visualKey` is both the dirty-check key used by
/// `MenuBarController` and the key of the rendered-image cache.
@MainActor
public struct MenuBarIconRenderer {
    // MARK: - Image Cache

    static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    /// Clears the rendered image cache (useful on low memory or theme change).
    public static func clearImageCache() {
        imageCache.removeAllObjects()
    }

    internal static func hasCachedImage(forKey key: String) -> Bool {
        imageCache.object(forKey: key as NSString) != nil
    }

    /// Returns the cached image for `key`, drawing and caching it on a miss.
    private static func cachedOrDraw(key: String, draw: () -> NSImage) -> NSImage {
        if let cached = imageCache.object(forKey: key as NSString) {
            return cached
        }
        let image = draw()
        imageCache.setObject(image, forKey: key as NSString)
        return image
    }

    public struct RenderResult {
        public let image: NSImage?
        public let title: String
        public let toolTip: String
        public let accessibilityLabel: String
        public let visualKey: String?

        public init(
            image: NSImage? = nil,
            title: String = "",
            toolTip: String = "",
            accessibilityLabel: String = "",
            visualKey: String? = nil
        ) {
            self.image = image
            self.title = title
            self.toolTip = toolTip
            self.accessibilityLabel = accessibilityLabel.isEmpty ? toolTip : accessibilityLabel
            self.visualKey = visualKey
        }
    }

    // MARK: - Snapshot and model

    /// Gathers the samples (and, for graph styles only, history) one widget needs.
    static func snapshot(config: MenuBarItemConfig, coordinator: MetricsCoordinator) -> WidgetSnapshot {
        var snap = WidgetSnapshot(
            cpu: coordinator.latestCPU?.value,
            memory: coordinator.latestMemory?.value,
            gpu: coordinator.latestGPU?.value,
            thermal: coordinator.latestThermal?.value,
            fan: coordinator.latestFan?.value,
            network: coordinator.latestNetwork?.value,
            disk: coordinator.latestDisk?.value,
            power: coordinator.latestPower?.value
        )
        guard config.style == .sparkline else { return snap }

        switch config.category {
        case .cpu:
            snap.series = WidgetSeries.build(coordinator.cpuHistory, primary: { $0.totalUsage }, secondary: { $0.user }, tertiary: { $0.system })
        case .memory:
            snap.series = WidgetSeries.build(coordinator.memoryHistory, primary: {
                $0.total > 0 ? Double($0.used) / Double($0.total) * 100.0 : 0.0
            })
        case .gpu:
            snap.series = WidgetSeries.build(coordinator.gpuHistory, primary: { $0.utilization })
        case .thermal:
            let source = config.source ?? .peak
            snap.series = WidgetSeries.build(coordinator.thermalHistory, primary: {
                ThermalSensorClassifier.peakCelsius(in: $0, for: source)
            })
        case .fan:
            snap.series = WidgetSeries.build(coordinator.fanHistory, scaleFloor: 2000, emptyMax: FanMath.fallbackMaxRPM, primary: {
                Double($0.fans.map(\.rpm).max() ?? 0)
            })
        case .network:
            snap.series = WidgetSeries.build(coordinator.networkHistory, primary: { $0.totalBytesInPerSec }, secondary: { $0.totalBytesOutPerSec })
        case .disk:
            snap.series = WidgetSeries.build(coordinator.diskHistory, primary: { $0.io?.bytesReadPerSec ?? 0 }, secondary: { $0.io?.bytesWrittenPerSec ?? 0 })
        case .power:
            snap.series = WidgetSeries.build(coordinator.powerHistory, scaleFloor: 5, primary: { $0.powerDrawWatts })
        }
        return snap
    }

    static func options(_ preferences: PreferencesStore) -> WidgetOptions {
        WidgetOptions(
            temperatureUnit: preferences.temperatureUnit,
            networkUnit: preferences.networkUnit,
            byteUnitStandard: preferences.byteUnitStandard
        )
    }

    /// Builds the widget model for a configuration from the coordinator's current state.
    public static func model(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator,
        preferences: PreferencesStore
    ) -> WidgetModel {
        WidgetModel.make(config: config, snapshot: snapshot(config: config, coordinator: coordinator), options: options(preferences))
    }

    /// Visual / dirty-check key of the widget (the `WidgetModel` form), computed without drawing.
    public static func computeVisualKey(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator,
        preferences: PreferencesStore
    ) -> String {
        model(config: config, coordinator: coordinator, preferences: preferences).visualKey
    }

    /// Draws (or fetches from cache) the image for a model.
    public static func image(for model: WidgetModel) -> NSImage {
        cachedOrDraw(key: model.visualKey) { WidgetRenderers.draw(model) }
    }

    /// Primary entry point: image, title, tooltip and accessibility label for a menu bar item configuration.
    public static func render(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator,
        preferences: PreferencesStore
    ) -> RenderResult {
        let snap = snapshot(config: config, coordinator: coordinator)
        let opts = options(preferences)
        let model = WidgetModel.make(config: config, snapshot: snap, options: opts)
        let description = WidgetDescription.make(config: config, snapshot: snap, options: opts)
        return RenderResult(
            image: image(for: model),
            toolTip: description.toolTip,
            accessibilityLabel: description.accessibilityLabel,
            visualKey: model.visualKey
        )
    }
}
