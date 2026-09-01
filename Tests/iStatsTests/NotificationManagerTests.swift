import XCTest
import UserNotifications
@testable import iStatsCore
@testable import iStats

@MainActor
final class NotificationManagerTests: XCTestCase {
    func testNotificationManagerInitialization() {
        let manager = NotificationManager.shared
        XCTAssertNotNil(manager)
        XCTAssertNotNil(manager.authorizationStatus)
    }

    func testNotificationManagerGracefulDegradationInUnbundledEnvironment() async {
        let manager = NotificationManager()
        
        // In CLI test harness, bundle ID is nil, so it activates native fallback mode gracefully
        let status = await manager.refreshAuthorizationStatus()
        XCTAssertEqual(status, .authorized)
        XCTAssertTrue(manager.isAuthorized)
        
        // requestAuthorization succeeds via fallback
        let granted = await manager.requestAuthorization()
        XCTAssertTrue(granted)
        
        // postNotification delivers via fallback without crashing or throwing
        do {
            try await manager.postNotification(title: "iStats Test", body: "Testing unbundled notification fallback")
        } catch {
            XCTFail("Should handle unbundled state gracefully without throwing: \(error)")
        }
    }

    func testNotificationManagerDelegateProtocolConformance() {
        let manager = NotificationManager()
        XCTAssertTrue(manager.conforms(to: UNUserNotificationCenterDelegate.self))
    }
}
