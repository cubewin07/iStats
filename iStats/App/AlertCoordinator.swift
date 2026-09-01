import Foundation
import Combine
import iStatsCore
import os.log

/// A pure rule evaluation engine that checks metric samples against user-defined thresholds.
public struct AlertEvaluator: Sendable {
    /// Evaluates CPU usage against user threshold.
    public static func evaluateCPU(
        sample: CPUSample,
        threshold: Double
    ) -> (triggered: Bool, title: String, body: String)? {
        guard sample.totalUsage >= threshold else { return nil }
        return (
            triggered: true,
            title: "⚠️ High CPU Usage",
            body: String(format: "Total CPU load is at %.1f%% (threshold: %.0f%%).", sample.totalUsage, threshold)
        )
    }

    /// Evaluates Memory usage and pressure against user preferences.
    public static func evaluateMemory(
        sample: MemorySample,
        threshold: Double,
        criticalPressureOnly: Bool
    ) -> (triggered: Bool, title: String, body: String)? {
        let usedPct = sample.total > 0 ? (Double(sample.used) / Double(sample.total)) * 100.0 : 0.0
        let isCritical = (sample.pressure == .critical)
        let isOverUsage = (usedPct >= threshold)
        
        if criticalPressureOnly {
            guard isCritical else { return nil }
        } else {
            guard isCritical || sample.pressure == .warning || isOverUsage else { return nil }
        }

        let pressureDesc = sample.pressure.displayName
        return (
            triggered: true,
            title: "⚠️ Memory Pressure Warning",
            body: String(format: "System memory pressure is %@ (%.1f%% used).", pressureDesc, usedPct)
        )
    }

    /// Evaluates Battery state for low battery and full charge alerts.
    public static func evaluateBattery(
        sample: PowerSample,
        lowThreshold: Int,
        lowAlertEnabled: Bool,
        fullAlertEnabled: Bool
    ) -> (type: AlertCoordinator.AlertType, title: String, body: String)? {
        guard sample.hasBattery, let charge = sample.charge else { return nil }

        // Low battery condition (discharging and SoC <= lowThreshold)
        if lowAlertEnabled && sample.state == .discharging && Int(charge) <= lowThreshold {
            return (
                type: .batteryLow,
                title: "🪫 Low Battery Warning",
                body: String(format: "Battery is at %.0f%% (threshold: %d%%).", charge, lowThreshold)
            )
        }

        // Full charge condition (charging/AC connected/charged and SoC >= 100%)
        if fullAlertEnabled && (sample.state == .charging || sample.state == .charged || sample.state == .acConnected) && charge >= 100.0 {
            return (
                type: .batteryFull,
                title: "🔋 Battery Fully Charged",
                body: "Battery has reached 100% and is ready to unplug."
            )
        }

        return nil
    }

    /// Evaluates Thermal temperature against user threshold.
    public static func evaluateThermal(
        sample: ThermalSample,
        thresholdCelsius: Double,
        unit: Units.TemperatureUnit
    ) -> (triggered: Bool, title: String, body: String)? {
        let peakTemp = sample.sensors.map(\.celsius).max() ?? 0.0
        guard peakTemp >= thresholdCelsius else { return nil }

        let formattedPeak = Units.formatTemperature(peakTemp, unit: unit)
        let formattedThreshold = Units.formatTemperature(thresholdCelsius, unit: unit)

        return (
            triggered: true,
            title: "🔥 High System Temperature",
            body: "Peak hardware sensor reached \(formattedPeak) (threshold: \(formattedThreshold))."
        )
    }

    /// Evaluates Disk capacity usage against user threshold.
    public static func evaluateDisk(
        sample: DiskSample,
        threshold: Double
    ) -> (triggered: Bool, title: String, body: String)? {
        // Evaluate primary / root volume or highest usage volume
        guard let primaryVolume = sample.volumes.first(where: { $0.mountPoint == "/" }) ?? sample.volumes.first else {
            return nil
        }
        let usedPct = primaryVolume.total > 0 ? (Double(primaryVolume.used) / Double(primaryVolume.total)) * 100.0 : 0.0
        guard usedPct >= threshold else { return nil }

        return (
            triggered: true,
            title: "💾 Low Disk Space Warning",
            body: String(format: "Primary disk '%@' is %.1f%% full (threshold: %.0f%%).", primaryVolume.mountPoint, usedPct, threshold)
        )
    }
}

/// A central `@MainActor` coordinator that evaluates incoming telemetry against user alert thresholds
/// and dispatches notifications via `NotificationManager` with anti-spam cooldown debouncing.
@MainActor
public final class AlertCoordinator: ObservableObject {
    public static let shared = AlertCoordinator()

    public enum AlertType: String, CaseIterable, Sendable {
        case cpuHigh = "cpuHigh"
        case memoryPressure = "memoryPressure"
        case batteryLow = "batteryLow"
        case batteryFull = "batteryFull"
        case thermalHigh = "thermalHigh"
        case diskLow = "diskLow"
    }

    private let logger = Logger(subsystem: "com.istats.app", category: "AlertCoordinator")
    private let preferencesStore: PreferencesStore
    private let metricsCoordinator: MetricsCoordinator
    private let notificationManager: NotificationManager

    private var cancellables = Set<AnyCancellable>()
    private var lastAlertTimes: [AlertType: Date] = [:]
    private var isStarted = false

    public init(
        preferencesStore: PreferencesStore = .shared,
        metricsCoordinator: MetricsCoordinator = .shared,
        notificationManager: NotificationManager = .shared
    ) {
        self.preferencesStore = preferencesStore
        self.metricsCoordinator = metricsCoordinator
        self.notificationManager = notificationManager
    }

    /// Starts observing live telemetry metrics for threshold alerting.
    public func start() {
        guard !isStarted else { return }
        isStarted = true

        // 1. CPU Observation
        metricsCoordinator.$latestCPU
            .compactMap { $0?.value }
            .sink { [weak self] sample in
                self?.handleCPUSample(sample)
            }
            .store(in: &cancellables)

        // 2. Memory Observation
        metricsCoordinator.$latestMemory
            .compactMap { $0?.value }
            .sink { [weak self] sample in
                self?.handleMemorySample(sample)
            }
            .store(in: &cancellables)

        // 3. Battery Observation
        metricsCoordinator.$latestPower
            .compactMap { $0?.value }
            .sink { [weak self] sample in
                self?.handlePowerSample(sample)
            }
            .store(in: &cancellables)

        // 4. Thermal Observation
        metricsCoordinator.$latestThermal
            .compactMap { $0?.value }
            .sink { [weak self] sample in
                self?.handleThermalSample(sample)
            }
            .store(in: &cancellables)

        // 5. Disk Observation
        metricsCoordinator.$latestDisk
            .compactMap { $0?.value }
            .sink { [weak self] sample in
                self?.handleDiskSample(sample)
            }
            .store(in: &cancellables)

        logger.info("AlertCoordinator started metric threshold observations.")
    }

    // MARK: - Metric Evaluator Handlers

    public func handleCPUSample(_ sample: CPUSample) {
        guard notificationManager.isAuthorized, preferencesStore.notificationsEnabled, preferencesStore.cpuAlertEnabled else { return }
        guard canTrigger(type: .cpuHigh) else { return }

        if let alert = AlertEvaluator.evaluateCPU(sample: sample, threshold: preferencesStore.cpuAlertThreshold) {
            recordAlertTrigger(type: .cpuHigh)
            dispatchAlert(type: .cpuHigh, title: alert.title, body: alert.body)
        }
    }

    public func handleMemorySample(_ sample: MemorySample) {
        guard notificationManager.isAuthorized, preferencesStore.notificationsEnabled, preferencesStore.memoryAlertEnabled else { return }
        guard canTrigger(type: .memoryPressure) else { return }

        if let alert = AlertEvaluator.evaluateMemory(
            sample: sample,
            threshold: preferencesStore.memoryAlertThreshold,
            criticalPressureOnly: preferencesStore.memoryAlertCriticalPressureOnly
        ) {
            recordAlertTrigger(type: .memoryPressure)
            dispatchAlert(type: .memoryPressure, title: alert.title, body: alert.body)
        }
    }

    public func handlePowerSample(_ sample: PowerSample) {
        guard notificationManager.isAuthorized, preferencesStore.notificationsEnabled else { return }

        if let alert = AlertEvaluator.evaluateBattery(
            sample: sample,
            lowThreshold: preferencesStore.batteryLowThreshold,
            lowAlertEnabled: preferencesStore.batteryLowAlertEnabled,
            fullAlertEnabled: preferencesStore.batteryFullAlertEnabled
        ) {
            guard canTrigger(type: alert.type) else { return }
            recordAlertTrigger(type: alert.type)
            dispatchAlert(type: alert.type, title: alert.title, body: alert.body)
        }
    }

    public func handleThermalSample(_ sample: ThermalSample) {
        guard notificationManager.isAuthorized, preferencesStore.notificationsEnabled, preferencesStore.thermalAlertEnabled else { return }
        guard canTrigger(type: .thermalHigh) else { return }

        if let alert = AlertEvaluator.evaluateThermal(
            sample: sample,
            thresholdCelsius: preferencesStore.thermalAlertThreshold,
            unit: preferencesStore.temperatureUnit
        ) {
            recordAlertTrigger(type: .thermalHigh)
            dispatchAlert(type: .thermalHigh, title: alert.title, body: alert.body)
        }
    }

    public func handleDiskSample(_ sample: DiskSample) {
        guard notificationManager.isAuthorized, preferencesStore.notificationsEnabled, preferencesStore.diskAlertEnabled else { return }
        guard canTrigger(type: .diskLow) else { return }

        if let alert = AlertEvaluator.evaluateDisk(sample: sample, threshold: preferencesStore.diskAlertThreshold) {
            recordAlertTrigger(type: .diskLow)
            dispatchAlert(type: .diskLow, title: alert.title, body: alert.body)
        }
    }

    // MARK: - Cooldown & Dispatching

    /// Verifies if enough time has passed since the last alert of this type.
    public func canTrigger(type: AlertType, now: Date = Date()) -> Bool {
        guard let lastTime = lastAlertTimes[type] else { return true }
        return now.timeIntervalSince(lastTime) >= preferencesStore.alertCooldownInterval
    }

    /// Records the trigger timestamp for anti-spam debounce.
    public func recordAlertTrigger(type: AlertType, now: Date = Date()) {
        lastAlertTimes[type] = now
    }

    /// Clears cooldown history for a specific alert type or all types.
    public func resetCooldowns() {
        lastAlertTimes.removeAll()
    }

    private func dispatchAlert(type: AlertType, title: String, body: String) {
        guard notificationManager.isAuthorized else {
            logger.debug("Notification permission not authorized. Suppressing alert [\(type.rawValue)].")
            return
        }
        Task {
            do {
                try await notificationManager.postNotification(
                    identifier: "iStats.alert.\(type.rawValue)",
                    title: title,
                    subtitle: "iStats Alert",
                    body: body
                )
                logger.info("Dispatched alert notification [\(type.rawValue)]: \(title)")
            } catch {
                logger.warning("Failed to post alert notification: \(error.localizedDescription)")
            }
        }
    }

    /// Sends an immediate test notification to verify system notification delivery.
    public func sendTestNotification() async {
        do {
            try await notificationManager.postNotification(
                identifier: "iStats.alert.test",
                title: "🔔 iStats Test Notification",
                subtitle: "System Monitor",
                body: "Notification permissions and alert channels are working properly!"
            )
        } catch {
            logger.warning("Failed to post test notification: \(error.localizedDescription)")
        }
    }
}
