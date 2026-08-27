import Foundation
import ServiceManagement
import os.log

/// Manages macOS system login item registration via ServiceManagement `SMAppService` (Requirements 11.4, 11.5).
///
/// In macOS 13+, `SMAppService.mainApp` provides a native, modern, sandboxed-compatible
/// and non-sandboxed API for registering the main application bundle to launch automatically at user login.
/// Any errors (such as when running in an unbundled test environment) are caught and logged gracefully.
@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    private let logger = Logger(subsystem: "com.istats.app", category: "LaunchAtLogin")

    @Published public private(set) var status: SMAppService.Status = .notRegistered
    @Published public private(set) var isRegistered: Bool = false

    public init() {
        refreshStatus()
    }

    /// Queries the current `SMAppService` status for the main application bundle.
    public func refreshStatus() {
        let currentStatus = SMAppService.mainApp.status
        self.status = currentStatus
        self.isRegistered = (currentStatus == .enabled)
    }

    /// Configures the application to launch automatically at user login.
    /// - Parameter enabled: `true` to register with `SMAppService`, `false` to unregister.
    /// - Returns: `true` if the operation succeeded or matched desired state, `false` if an error occurred.
    @discardableResult
    public func setLaunchAtLogin(enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    logger.info("Successfully registered iStats as login item with SMAppService.")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    logger.info("Successfully unregistered iStats from SMAppService.")
                }
            }
            refreshStatus()
            return true
        } catch {
            logger.warning("SMAppService launch-at-login update failed gracefully (e.g. unbundled test environment): \(error.localizedDescription)")
            refreshStatus()
            return false
        }
    }
}
