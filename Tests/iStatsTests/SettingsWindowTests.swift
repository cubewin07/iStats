import XCTest
import AppKit
import SwiftUI
@testable import iStatsCore
@testable import iStats

@MainActor
final class SettingsWindowTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, NotificationCenter, String) {
        let suiteName = "test.istats.settings.window.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        let center = NotificationCenter()
        return (defaults, prefs, coord, center, suiteName)
    }

    private func cleanup(controller: PreferencesWindowController? = nil, defaults: UserDefaults, suiteName: String) {
        controller?.close()
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Single Window Path

    func testSingleWindowInstanceAcrossRepeatedShows() {
        let (defaults, prefs, coord, center, suiteName) = makeContext()
        let controller = PreferencesWindowController(
            store: prefs,
            coordinator: coord,
            notificationCenter: center,
            frameAutosaveName: nil
        )
        defer { cleanup(controller: controller, defaults: defaults, suiteName: suiteName) }

        controller.showPreferences()
        let firstWindow = controller.window
        XCTAssertNotNil(firstWindow)
        XCTAssertEqual(firstWindow?.title, "iStats Settings")
        XCTAssertEqual(controller.currentSection, .general)

        controller.show(section: .menuBar)
        XCTAssertTrue(controller.window === firstWindow, "Repeated show(section:) must reuse the same window")
        XCTAssertEqual(controller.currentSection, .menuBar)

        controller.show(section: .category(.cpu))
        XCTAssertTrue(controller.window === firstWindow, "Switching to a category page must reuse the same window")
        XCTAssertEqual(controller.currentSection, .category(.cpu))

        controller.showPreferences()
        XCTAssertTrue(controller.window === firstWindow, "showPreferences() must reuse the same window")
        XCTAssertEqual(controller.currentSection, .category(.cpu), "showPreferences() preserves the current section")
    }

    // MARK: - Persistence & Stale Key Fallback

    func testLastSectionPersistsAcrossControllerInstances() {
        let (defaults, prefs, coord, center, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let first = PreferencesWindowController(
            store: prefs,
            coordinator: coord,
            notificationCenter: center,
            frameAutosaveName: nil
        )
        first.show(section: .category(.memory))
        XCTAssertEqual(prefs.lastSettingsSection, "memory")
        first.close()

        let reloadedPrefs = PreferencesStore(userDefaults: defaults)
        let second = PreferencesWindowController(
            store: reloadedPrefs,
            coordinator: coord,
            notificationCenter: NotificationCenter(),
            frameAutosaveName: nil
        )
        defer { second.close() }
        second.showPreferences()
        XCTAssertEqual(second.currentSection, .category(.memory))
    }

    func testStaleAndLegacyKeysResolveCorrectly() {
        let (defaults, prefs, coord, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        prefs.lastSettingsSection = "nonexistent-tab"
        let staleController = PreferencesWindowController(
            store: prefs,
            coordinator: coord,
            notificationCenter: NotificationCenter(),
            frameAutosaveName: nil
        )
        defer { staleController.close() }
        staleController.showPreferences()
        XCTAssertEqual(staleController.currentSection, .general)

        prefs.lastSettingsSection = "alerts"
        let legacyController = PreferencesWindowController(
            store: prefs,
            coordinator: coord,
            notificationCenter: NotificationCenter(),
            frameAutosaveName: nil
        )
        defer { legacyController.close() }
        legacyController.showPreferences()
        XCTAssertEqual(legacyController.currentSection, .notifications)
    }

    // MARK: - Deep-Link Notification Observer

    func testOpenSettingsSectionNotificationNavigatesAndPersists() {
        let (defaults, prefs, coord, center, suiteName) = makeContext()
        let controller = PreferencesWindowController(
            store: prefs,
            coordinator: coord,
            notificationCenter: center,
            frameAutosaveName: nil
        )
        defer { cleanup(controller: controller, defaults: defaults, suiteName: suiteName) }

        // Deep-link every category
        for category in MetricCategory.allCases {
            center.post(
                name: Notification.Name("iStats.openSettingsSection"),
                object: nil,
                userInfo: ["section": category.rawValue]
            )
            XCTAssertNotNil(controller.window)
            XCTAssertEqual(controller.currentSection, .category(category))
            XCTAssertEqual(prefs.lastSettingsSection, category.rawValue)
        }

        // Deep-link top-level sections and legacy "alerts" alias
        let cases: [(String, SettingsSection)] = [
            ("general", .general),
            ("appearance", .appearance),
            ("menuBar", .menuBar),
            ("notifications", .notifications),
            ("alerts", .notifications),
            ("about", .about),
            ("stale-unknown", .general)
        ]
        for (raw, expected) in cases {
            center.post(
                name: Notification.Name("iStats.openSettingsSection"),
                object: nil,
                userInfo: ["section": raw]
            )
            XCTAssertEqual(controller.currentSection, expected, "Deep link '\(raw)' should resolve to \(expected)")
            XCTAssertEqual(prefs.lastSettingsSection, expected.storageKey)
        }

        // Notification without section key preserves current section
        controller.show(section: .appearance)
        center.post(name: Notification.Name("iStats.openSettingsSection"), object: nil)
        XCTAssertEqual(controller.currentSection, .appearance)
    }

    // MARK: - Layout Smoke Tests for Every Settings Page

    func testAllSettingsPagesLayOutCleanly() {
        let (defaults, prefs, coord, _, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let nav = SettingsNavigationModel(store: prefs)
        for section in SettingsSection.allSections() {
            nav.select(section)
            let view = SettingsView(store: prefs, coordinator: coord, navigation: nav)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 920, height: 620)
            hosting.layoutSubtreeIfNeeded()

            let fit = hosting.fittingSize
            XCTAssertGreaterThan(fit.width, 400, "Section \(section) width")
            XCTAssertGreaterThan(fit.height, 300, "Section \(section) height")
        }
    }

    // MARK: - Alert Titles Contain No Emoji

    func testAlertTitlesContainNoEmoji() {
        let cpu = AlertEvaluator.evaluateCPU(
            sample: CPUSample(totalUsage: 95, perCore: [95], user: 80, system: 15, idle: 5),
            threshold: 90
        )
        let memory = AlertEvaluator.evaluateMemory(
            sample: MemorySample(total: 100, used: 95, free: 5, wired: 20, compressed: 10, cached: 5, swapUsed: 0, pressure: .critical),
            threshold: 85,
            criticalPressureOnly: true
        )
        let lowBattery = AlertEvaluator.evaluateBattery(
            sample: PowerSample(hasBattery: true, charge: 10, state: .discharging),
            lowThreshold: 20,
            lowAlertEnabled: true,
            fullAlertEnabled: false
        )
        let fullBattery = AlertEvaluator.evaluateBattery(
            sample: PowerSample(hasBattery: true, charge: 100, state: .charging),
            lowThreshold: 20,
            lowAlertEnabled: false,
            fullAlertEnabled: true
        )
        let thermal = AlertEvaluator.evaluateThermal(
            sample: ThermalSample(sensors: [SensorReading(name: "CPU", celsius: 98)], pressure: .critical),
            thresholdCelsius: 90,
            unit: .celsius
        )
        let disk = AlertEvaluator.evaluateDisk(
            sample: DiskSample(volumes: [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 100, used: 95, free: 5)]),
            threshold: 90
        )

        let titles = [cpu?.title, memory?.title, lowBattery?.title, fullBattery?.title, thermal?.title, disk?.title]
            .compactMap { $0 }
        XCTAssertEqual(titles.count, 6)
        for title in titles {
            let hasEmoji = title.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
            XCTAssertFalse(hasEmoji, "Alert title must not contain emoji: '\(title)'")
        }
    }
}
