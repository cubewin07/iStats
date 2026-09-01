import Foundation
import UserNotifications
import Combine
import os.log
import AppKit

/// Manages macOS system notifications via the modern `UserNotifications` framework (`UNUserNotificationCenter`).
///
/// Responsibilities:
/// - Registers as the `UNUserNotificationCenterDelegate` to intercept and present notifications in both foreground and background.
/// - Requests user notification permissions (`.alert`, `.sound`, `.badge`).
/// - Tracks and publishes current authorization status (`UNAuthorizationStatus`).
/// - Provides dispatching mechanisms for posting alert and status notifications.
/// - Gracefully supports both bundled `.app` execution (via `UNUserNotificationCenter`) and unbundled / CLI execution (via native `NSAppleScript` banner fallback) so you can test live notifications in any environment.
@MainActor
public final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()

    private let logger = Logger(subsystem: "com.istats.app", category: "NotificationManager")
    
    /// The underlying notification center, safely `nil` when running in unbundled test / CLI environments.
    private let center: UNUserNotificationCenter?

    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published public private(set) var isAuthorized: Bool = false

    /// Determines whether the process is executing inside a bundled macOS application (.app).
    public static var isRunningInRealAppBundle: Bool {
        guard NSClassFromString("XCTestCase") == nil else {
            return false
        }
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return false
        }
        return Bundle.main.bundleURL.pathExtension == "app" || Bundle.main.bundlePath.contains(".app")
    }

    public init(center: UNUserNotificationCenter? = nil) {
        if let center = center {
            self.center = center
        } else if Self.isRunningInRealAppBundle {
            self.center = UNUserNotificationCenter.current()
        } else {
            self.center = nil
        }
        super.init()
        register()
    }

    /// Initializes and registers the notification center delegate and refreshes authorization status.
    public func register() {
        guard let center = self.center else {
            logger.debug("UNUserNotificationCenter is inactive in unbundled mode; using native display notification fallback.")
            return
        }
        center.delegate = self
        Task {
            await refreshAuthorizationStatus()
        }
    }

    /// Queries the current authorization status from `UNUserNotificationCenter`.
    @discardableResult
    public func refreshAuthorizationStatus() async -> UNAuthorizationStatus {
        guard let center = self.center else {
            // In unbundled mode, permissions are handled by system scripting/terminal
            self.authorizationStatus = .authorized
            self.isAuthorized = true
            return .authorized
        }
        let settings = await center.notificationSettings()
        let status = settings.authorizationStatus
        self.authorizationStatus = status
        self.isAuthorized = (status == .authorized || status == .provisional)
        return status
    }

    /// Requests user authorization to display alert banners, play sounds, and badge the app.
    /// - Parameter options: The requested authorization options (default: `[.alert, .sound, .badge]`).
    /// - Returns: `true` if authorization was granted, `false` otherwise.
    @discardableResult
    public func requestAuthorization(options: UNAuthorizationOptions = [.alert, .sound, .badge]) async -> Bool {
        guard let center = self.center else {
            logger.info("Running in unbundled environment: notifications will post via system banner fallback.")
            self.authorizationStatus = .authorized
            self.isAuthorized = true
            return true
        }
        do {
            let granted = try await center.requestAuthorization(options: options)
            logger.info("Notification authorization granted: \(granted)")
            await refreshAuthorizationStatus()
            return granted
        } catch {
            logger.warning("Failed to request notification authorization: \(error.localizedDescription)")
            await refreshAuthorizationStatus()
            return false
        }
    }

    /// Posts a system banner notification.
    ///
    /// - When running in a registered `.app` bundle, uses Apple's modern `UNUserNotificationCenter`.
    /// - When running unbundled (CLI / development script), seamlessly delivers a native macOS banner notification via system scripting.
    ///
    /// - Parameters:
    ///   - identifier: Unique identifier for the notification request (defaults to UUID string).
    ///   - title: Main title of the notification.
    ///   - subtitle: Optional subtitle for additional context.
    ///   - body: Informational body text.
    ///   - sound: The sound to play when delivering the notification (default: `.default`).
    ///   - userInfo: Optional custom dictionary payload.
    public func postNotification(
        identifier: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        body: String,
        sound: UNNotificationSound? = .default,
        userInfo: [AnyHashable: Any] = [:]
    ) async throws {
        if let center = self.center {
            let content = UNMutableNotificationContent()
            content.title = title
            if let subtitle = subtitle {
                content.subtitle = subtitle
            }
            content.body = body
            if let sound = sound {
                content.sound = sound
            }
            content.userInfo = userInfo

            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try await center.add(request)
            logger.info("Posted UNUserNotification [\(identifier)]: \(title)")
        } else {
            // Unbundled / development CLI fallback: trigger native macOS banner via AppleScript
            postAppleScriptNotification(title: title, subtitle: subtitle, body: body)
        }
    }

    /// Delivers a native macOS banner notification in unbundled / CLI development mode.
    private func postAppleScriptNotification(title: String, subtitle: String?, body: String) {
        let cleanTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let cleanBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        var script = "display notification \"\(cleanBody)\" with title \"\(cleanTitle)\""
        if let subtitle = subtitle, !subtitle.isEmpty {
            let cleanSubtitle = subtitle.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            script += " subtitle \"\(cleanSubtitle)\""
        }
        script += " sound name \"default\""

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                logger.warning("AppleScript banner notification error: \(String(describing: error))")
            } else {
                logger.info("Posted native macOS banner notification via fallback: \(title)")
            }
        }
    }

    /// Removes pending notification requests with the specified identifiers.
    public func removePendingNotifications(identifiers: [String]) {
        center?.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Removes all delivered notifications from Notification Center.
    public func removeAllDeliveredNotifications() {
        center?.removeAllDeliveredNotifications()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Allows notifications to be displayed (as banners and sounds) even when the application is active in the foreground.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner, sound, and list in foreground
        completionHandler([.banner, .sound, .list])
    }

    /// Handles user interaction when clicking or responding to a delivered notification.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
