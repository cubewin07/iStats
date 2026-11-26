import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class WidgetPreviewTests: XCTestCase {
    private func hasNonTransparentPixels(_ image: NSImage) -> Bool {
        guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              rep.pixelsWide > 0,
              rep.pixelsHigh > 0 else {
            return false
        }
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.01 {
                    return true
                }
            }
        }
        return false
    }

    func testEveryCatalogEntryRendersNonEmptyImageInLightAndDark() {
        for hasBattery in [true, false] {
            for entry in WidgetCatalog.allEntries(hasBattery: hasBattery) {
                for scheme in [ColorScheme.light, .dark] {
                    for appearance in MenuBarAppearance.allCases {
                        let image = WidgetPreviewRenderer.renderEntry(
                            entry,
                            appearance: appearance,
                            scale: 2.0,
                            colorScheme: scheme,
                            hasBattery: hasBattery
                        )
                        XCTAssertGreaterThan(image.size.width, 0, "Width must be > 0 for \(entry.id) \(appearance) \(scheme)")
                        XCTAssertGreaterThan(image.size.height, 0, "Height must be > 0 for \(entry.id) \(appearance) \(scheme)")
                        XCTAssertTrue(
                            hasNonTransparentPixels(image),
                            "Rendered preview must have visible pixels for \(entry.id) (hasBattery=\(hasBattery), \(appearance), \(scheme))"
                        )
                    }
                }
            }
        }
    }

    func testPreviewRendererHonors1xAnd2xScales() {
        let entry = WidgetCatalog.defaultEntry(for: .cpu)
        let img1x = WidgetPreviewRenderer.renderEntry(entry, appearance: .categoryColor, scale: 1.0, colorScheme: .dark)
        let img2x = WidgetPreviewRenderer.renderEntry(entry, appearance: .categoryColor, scale: 2.0, colorScheme: .dark)

        XCTAssertEqual(img1x.size, img2x.size, "Logical point size must match across 1x and 2x")

        let rep1x = img1x.representations.compactMap { $0 as? NSBitmapImageRep }.first
        let rep2x = img2x.representations.compactMap { $0 as? NSBitmapImageRep }.first
        XCTAssertNotNil(rep1x)
        XCTAssertNotNil(rep2x)
        XCTAssertEqual(rep2x?.pixelsWide, (rep1x?.pixelsWide ?? 0) * 2)
        XCTAssertEqual(rep2x?.pixelsHigh, (rep1x?.pixelsHigh ?? 0) * 2)
    }

    func testAppearanceModesControlTemplateRenderingAcrossRenderers() {
        let normalSnap = WidgetSnapshot(
            cpu: CPUSample(totalUsage: 25, perCore: [25, 25], user: 15, system: 10, idle: 75),
            memory: MemorySample(total: 1000, used: 400, free: 600, wired: 100, compressed: 50, cached: 50, swapUsed: 0, pressure: .normal, appMemory: 250),
            gpu: GPUSample(utilization: 20),
            thermal: ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 45)], pressure: .nominal),
            fan: FanSample(fans: [FanReading(name: "Fan", rpm: 2000, minRPM: 1200, maxRPM: 5800)]),
            network: NetworkSample(interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 50_000, bytesOutPerSec: 10_000, totalBytesIn: 0, totalBytesOut: 0)]),
            disk: DiskSample(volumes: [VolumeCapacity(name: "HD", mountPoint: "/", total: 1000, used: 400, free: 600)], io: DiskIO(bytesReadPerSec: 50_000, bytesWrittenPerSec: 10_000, readOpsPerSec: 10, writeOpsPerSec: 5)),
            power: PowerSample(hasBattery: true, charge: 80, state: .discharging),
            series: WidgetSeries(primary: [10, 20, 30, 40], secondary: [5, 10, 15, 20], tertiary: [5, 10, 15, 20], stamp: 4)
        )

        for entry in WidgetCatalog.allEntries(hasBattery: true) {
            let config = entry.makeConfig()
            let monoImg = MenuBarIconRenderer.image(for: WidgetModel.make(config: config, snapshot: normalSnap, options: WidgetOptions(appearance: .monochrome)))
            let tintImg = MenuBarIconRenderer.image(for: WidgetModel.make(config: config, snapshot: normalSnap, options: WidgetOptions(appearance: .statusTint)))
            let catImg = MenuBarIconRenderer.image(for: WidgetModel.make(config: config, snapshot: normalSnap, options: WidgetOptions(appearance: .categoryColor)))

            XCTAssertTrue(monoImg.isTemplate, "\(entry.id) must be template in .monochrome")
            XCTAssertTrue(tintImg.isTemplate, "\(entry.id) must be template in .statusTint when status < .warning")
            XCTAssertFalse(catImg.isTemplate, "\(entry.id) must be non-template in .categoryColor")
        }

        // Warning/critical sample: .monochrome stays template, .statusTint tints (non-template)
        let criticalCPU = WidgetSnapshot(cpu: CPUSample(totalUsage: 96, perCore: [96, 96], user: 70, system: 26, idle: 4))
        let cpuBar = MenuBarItemConfig(category: .cpu, style: .bar)
        XCTAssertTrue(MenuBarIconRenderer.image(for: WidgetModel.make(config: cpuBar, snapshot: criticalCPU, options: WidgetOptions(appearance: .monochrome))).isTemplate)
        XCTAssertFalse(MenuBarIconRenderer.image(for: WidgetModel.make(config: cpuBar, snapshot: criticalCPU, options: WidgetOptions(appearance: .statusTint))).isTemplate)
    }

    func testWidgetCatalogViewHostsAndPerformsAddReplace() {
        let suiteName = "test.istats.catalogview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: store)
        let view = WidgetCatalogView(store: store, category: .cpu, hasBattery: true, coordinator: coord)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 520, height: 420)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.width, 100)
        XCTAssertGreaterThan(hosting.fittingSize.height, 100)

        // Replace CPU widgets preserves slot 0 and swaps .bar -> .gauge
        let replacement = MenuBarItemConfig(category: .cpu, style: .gauge)
        view.replaceCategoryWidgets(with: replacement)
        XCTAssertEqual(store.menuBarItems.first, replacement)
        XCTAssertEqual(store.items(for: .cpu), [replacement])
    }
}
