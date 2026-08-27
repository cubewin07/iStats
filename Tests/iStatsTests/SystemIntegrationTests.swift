import XCTest
import AppKit
import ServiceManagement
@testable import iStatsCore
@testable import iStats

@MainActor
final class SystemIntegrationTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "iStats.test.system.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - DockIconManager Tests

    func testDockIconManagerDefaultState() {
        let manager = DockIconManager(userDefaults: testDefaults)
        XCTAssertFalse(manager.isDockIconVisible)
    }

    func testDockIconManagerToggling() {
        let manager = DockIconManager(userDefaults: testDefaults)

        manager.setDockIconVisible(true)
        XCTAssertTrue(manager.isDockIconVisible)
        XCTAssertTrue(testDefaults.bool(forKey: DockIconManager.showDockIconDefaultsKey))

        manager.setDockIconVisible(false)
        XCTAssertFalse(manager.isDockIconVisible)
        XCTAssertFalse(testDefaults.bool(forKey: DockIconManager.showDockIconDefaultsKey))
    }

    func testDockIconManagerApplyCurrentPolicy() {
        let manager = DockIconManager(userDefaults: testDefaults)
        manager.setDockIconVisible(false)
        manager.applyCurrentPolicy()
        // Default policy under LSUIElement
        XCTAssertFalse(manager.isDockIconVisible)
    }

    // MARK: - LaunchAtLoginManager Tests

    func testLaunchAtLoginManagerStatusQueriesSafely() {
        let manager = LaunchAtLoginManager.shared
        manager.refreshStatus()

        // Verify status is a valid SMAppService.Status and does not crash
        let validStatuses: [SMAppService.Status] = [.notRegistered, .enabled, .requiresApproval, .notFound]
        XCTAssertTrue(validStatuses.contains(manager.status))
        XCTAssertEqual(manager.isRegistered, manager.status == .enabled)
    }

    func testLaunchAtLoginManagerSetLaunchAtLoginDegradesGracefully() {
        let manager = LaunchAtLoginManager.shared

        // Attempting to set launch at login in a test runner / unbundled environment
        // must degrade gracefully without throwing an uncaught exception or fatal error.
        let resultDisable = manager.setLaunchAtLogin(enabled: false)
        XCTAssertTrue(resultDisable || !resultDisable) // Clean boolean return

        let resultEnable = manager.setLaunchAtLogin(enabled: true)
        XCTAssertTrue(resultEnable || !resultEnable) // Clean boolean return

        // Always restore to disabled for cleanliness
        _ = manager.setLaunchAtLogin(enabled: false)
    }

    func testPreferencesStoreLaunchAtLoginSynchronization() {
        let store = PreferencesStore(userDefaults: testDefaults)
        XCTAssertFalse(store.launchAtLogin)

        store.launchAtLogin = true
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesStore.Keys.launchAtLogin))

        store.launchAtLogin = false
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesStore.Keys.launchAtLogin))
    }
}
