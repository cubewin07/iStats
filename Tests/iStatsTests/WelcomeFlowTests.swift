import XCTest
import AppKit
import SwiftUI
import UserNotifications
@testable import iStatsCore
@testable import iStats

@MainActor
final class WelcomeFlowTests: XCTestCase {

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.welcome.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        let coord = MetricsCoordinator(preferencesStore: prefs)
        return (defaults, prefs, coord, suiteName)
    }

    private func cleanup(window: WelcomeWindow? = nil, defaults: UserDefaults, suiteName: String) {
        window?.close()
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Preset Application & Skip

    func testApplyingPresetsWritesMenuBarItemsAppearanceAndOnboardingFlag() {
        for preset in MenuBarPreset.allCases {
            for (hasBattery, hasFans) in [(true, true), (false, true), (true, false), (false, false)] {
                let (defaults, prefs, coord, suiteName) = makeContext()
                defer { cleanup(defaults: defaults, suiteName: suiteName) }

                XCTAssertFalse(prefs.hasCompletedOnboarding)
                var launchCalls: [Bool] = []
                var completed = false

                let model = WelcomeFlowModel(
                    store: prefs,
                    coordinator: coord,
                    hasBattery: hasBattery,
                    hasFans: hasFans,
                    initialNotificationStatus: .notDetermined,
                    applyLaunchAtLogin: { enabled in
                        launchCalls.append(enabled)
                        return true
                    },
                    onComplete: { completed = true }
                )

                model.selectedPreset = preset
                model.selectedAppearance = .categoryColor
                model.applyAndFinish()

                XCTAssertTrue(completed)
                XCTAssertTrue(prefs.hasCompletedOnboarding)
                XCTAssertEqual(prefs.menuBarAppearance, .categoryColor)
                XCTAssertEqual(prefs.menuBarItems, preset.configs(hasBattery: hasBattery, hasFans: hasFans))
                XCTAssertTrue(launchCalls.isEmpty, "Launch at login must never be enabled silently during preset apply")
                XCTAssertFalse(prefs.launchAtLogin)
            }
        }
    }

    func testSkipAppliesBalancedPresetAndMarksOnboardingComplete() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        var launchCalls: [Bool] = []
        var completed = false

        let model = WelcomeFlowModel(
            store: prefs,
            coordinator: coord,
            hasBattery: false,
            hasFans: false,
            applyLaunchAtLogin: { enabled in
                launchCalls.append(enabled)
                return true
            },
            onComplete: { completed = true }
        )

        model.selectedPreset = .everything
        model.skip()

        XCTAssertTrue(completed)
        XCTAssertTrue(prefs.hasCompletedOnboarding)
        XCTAssertEqual(prefs.menuBarItems, MenuBarPreset.balanced.configs(hasBattery: false, hasFans: false))
        XCTAssertTrue(launchCalls.isEmpty, "Skipping onboarding must never touch SMAppService")
        XCTAssertFalse(prefs.launchAtLogin)
    }

    // MARK: - Launch Visibility, Migration & Replay

    func testWelcomeShownOnceForFreshUserAndSkippedForMigratedUser() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        let center = NotificationCenter()
        let welcome = WelcomeWindow(store: prefs, coordinator: coord, notificationCenter: center)
        defer { cleanup(window: welcome, defaults: defaults, suiteName: suiteName) }

        XCTAssertFalse(prefs.hasCompletedOnboarding)
        XCTAssertTrue(WelcomeWindow.shouldShowOnLaunch(store: prefs))

        welcome.showIfNeeded()
        XCTAssertTrue(welcome.isPresented)
        XCTAssertNotNil(welcome.window)

        // Completing onboarding closes the window and prevents showing again on next launch.
        welcome.activeModel?.applyAndFinish()
        XCTAssertFalse(welcome.isPresented)
        XCTAssertTrue(prefs.hasCompletedOnboarding)
        XCTAssertFalse(WelcomeWindow.shouldShowOnLaunch(store: prefs))

        welcome.showIfNeeded()
        XCTAssertFalse(welcome.isPresented, "WelcomeWindow must not reopen automatically once completed")

        // Migrated existing users start with hasCompletedOnboarding == true and never see it unprompted.
        let migratedSuite = "test.istats.migrated.\(UUID().uuidString)"
        let migratedDefaults = UserDefaults(suiteName: migratedSuite)!
        migratedDefaults.removePersistentDomain(forName: migratedSuite)
        defer { migratedDefaults.removePersistentDomain(forName: migratedSuite) }

        migratedDefaults.set(2.0, forKey: PreferencesStore.Keys.refreshInterval)
        let migratedPrefs = PreferencesStore(userDefaults: migratedDefaults)
        XCTAssertTrue(migratedPrefs.hasCompletedOnboarding)

        let migratedWelcome = WelcomeWindow(store: migratedPrefs, coordinator: coord, notificationCenter: NotificationCenter())
        defer { migratedWelcome.close() }
        XCTAssertFalse(WelcomeWindow.shouldShowOnLaunch(store: migratedPrefs))
        migratedWelcome.showIfNeeded()
        XCTAssertFalse(migratedWelcome.isPresented)
    }

    func testShowWelcomeAgainNotificationReopensAndClosePreservesCustomConfig() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        let customItems = [MenuBarItemConfig(category: .gpu, style: .gauge)]
        prefs.menuBarItems = customItems
        prefs.hasCompletedOnboarding = true

        let center = NotificationCenter()
        let welcome = WelcomeWindow(store: prefs, coordinator: coord, notificationCenter: center)
        defer { cleanup(window: welcome, defaults: defaults, suiteName: suiteName) }

        XCTAssertFalse(welcome.isPresented)
        center.post(name: SettingsSection.showWelcomeNotificationName, object: nil)
        XCTAssertTrue(welcome.isPresented, "About Settings 'Show Welcome Again' notification must open WelcomeWindow")

        welcome.close()
        XCTAssertFalse(welcome.isPresented)
        XCTAssertEqual(prefs.menuBarItems, customItems, "Dismissing replayed Welcome without Apply/Skip must preserve user widgets")
    }

    // MARK: - Explicit Launch at Login & Notification Consent

    func testLaunchAtLoginAndNotificationsRequireExplicitUserAction() async {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        var launchCalls: [Bool] = []
        var notificationRequests = 0

        let model = WelcomeFlowModel(
            store: prefs,
            coordinator: coord,
            hasBattery: true,
            hasFans: true,
            initialNotificationStatus: .notDetermined,
            applyLaunchAtLogin: { enabled in
                launchCalls.append(enabled)
                return true
            },
            requestNotifications: {
                notificationRequests += 1
                return true
            }
        )

        XCTAssertFalse(model.launchAtLogin)
        XCTAssertTrue(launchCalls.isEmpty)
        XCTAssertEqual(notificationRequests, 0)

        model.setLaunchAtLoginByUser(true)
        XCTAssertEqual(launchCalls, [true])
        XCTAssertTrue(prefs.launchAtLogin)

        model.setLaunchAtLoginByUser(false)
        XCTAssertEqual(launchCalls, [true, false])
        XCTAssertFalse(prefs.launchAtLogin)

        let granted = await model.requestNotificationPermission()
        XCTAssertTrue(granted)
        XCTAssertEqual(notificationRequests, 1)
        XCTAssertEqual(model.notificationsStatus, .authorized)
        XCTAssertTrue(prefs.notificationsEnabled)
    }

    // MARK: - Debug Scratch Defaults

    func testScratchDefaultsLaunchArgumentDetectionAndIsolation() {
        #if DEBUG
        XCTAssertTrue(PreferencesStore.shouldUseScratchDefaults(arguments: ["iStats", "-iStatsUseScratchDefaults", "YES"]))
        XCTAssertTrue(PreferencesStore.shouldUseScratchDefaults(arguments: ["iStats", "-iStatsUseScratchDefaults", "yes"]))
        XCTAssertTrue(PreferencesStore.shouldUseScratchDefaults(arguments: ["iStats", "-iStatsUseScratchDefaults=YES"]))
        XCTAssertFalse(PreferencesStore.shouldUseScratchDefaults(arguments: ["iStats", "-iStatsUseScratchDefaults", "NO"]))
        XCTAssertFalse(PreferencesStore.shouldUseScratchDefaults(arguments: ["iStats"]))

        let scratchSuite = "test.istats.scratch.arg.\(UUID().uuidString)"
        let scratch = PreferencesStore.makeScratchDefaults(suiteName: scratchSuite)
        defer { scratch.removePersistentDomain(forName: scratchSuite) }
        let scratchStore = PreferencesStore(userDefaults: scratch)
        XCTAssertFalse(scratchStore.hasCompletedOnboarding, "Scratch defaults must start fresh as a non-onboarded user")
        #endif
    }

    // MARK: - Views & Glossary Coverage

    func testWelcomeViewRendersAllThreeSteps() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let model = WelcomeFlowModel(store: prefs, coordinator: coord, hasBattery: true, hasFans: true)
        for step in WelcomeFlowModel.Step.allCases {
            model.step = step
            let hosting = NSHostingView(rootView: WelcomeView(model: model))
            hosting.frame = CGRect(x: 0, y: 0, width: 580, height: 500)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.width, 400)
            XCTAssertGreaterThan(hosting.fittingSize.height, 300)
        }
    }

    func testInfoButtonAndGlossarySheetRenderForAllDestinationsAndTerms() {
        for term in MetricGlossary.requiredKeys {
            let entry = MetricGlossary.entry(for: term)
            let button = InfoButton(term: term)
            XCTAssertEqual(button.entry, entry)
            XCTAssertNotNil(InfoButton(key: term.rawValue))

            let hosting = NSHostingView(rootView: button)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.width, 8)
            XCTAssertGreaterThan(hosting.fittingSize.height, 8)
        }
        XCTAssertNil(InfoButton(key: "missing_term_key"))

        let destinations: [PanelDestination] = [.overview] + MetricCategory.allCases.map { .category($0) }
        for destination in destinations {
            let sheet = GlossarySheetView(destination: destination, onDismiss: {})
            let hosting = NSHostingView(rootView: sheet)
            hosting.frame = CGRect(x: 0, y: 0, width: 336, height: 380)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.width, 200)
            XCTAssertGreaterThan(hosting.fittingSize.height, 200)
        }
    }

    func testPanelScaffoldRoutesShowGlossaryShortcutToCallback() {
        var selected = PopoverTab.overview
        let binding = Binding(get: { selected }, set: { selected = $0 })
        var callbackCount = 0

        let scaffold = PanelScaffold(
            chrome: PanelChrome(
                category: .memory,
                onShowGlossary: { callbackCount += 1 }
            ),
            glance: PanelGlance(value: 50, headline: "of 16 GiB"),
            selection: binding
        ) { _ in
            MetricRow(label: "Swap Used", valueText: "0 B", glossaryKey: .swap)
        }

        let hosting = NSHostingView(rootView: scaffold)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 400)
        hosting.layoutSubtreeIfNeeded()

        NotificationCenter.default.post(
            name: .panelCommandReceived,
            object: PanelCommand.showGlossary,
            userInfo: ["destination": PanelDestination.category(.memory)]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(callbackCount, 1)
    }

    func testAlertsSettingsViewRendersWithGlossaryInfoButtons() {
        let (defaults, prefs, coord, suiteName) = makeContext()
        defer { cleanup(defaults: defaults, suiteName: suiteName) }

        let view = AlertsSettingsView(store: prefs, coordinator: coord, embedded: false)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 620, height: 600)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.width, 200)
        XCTAssertGreaterThan(hosting.fittingSize.height, 100)
    }
}
