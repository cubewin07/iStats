import Foundation
import Combine
import iStatsCore
import os.log

/// Builds emoji-free notification titles and bodies for metric threshold alerts.
public struct AlertMessageBuilder: Sendable {
    /// Evaluates CPU usage against user threshold.
    public static func evaluateCPU(
        sample: CPUSample,
        threshold: Double
    ) -> (triggered: Bool, title: String, body: String)? {
        guard sample.totalUsage >= threshold else { return nil }
        return (
            triggered: true,
            title: "High CPU Usage",
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
            title: "Memory Pressure Warning",
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
                title: "Low Battery Warning",
                body: String(format: "Battery is at %.0f%% (threshold: %d%%).", charge, lowThreshold)
            )
        }

        // Full charge condition (charging/AC connected/charged and SoC >= 100%)
        if fullAlertEnabled && (sample.state == .charging || sample.state == .charged || sample.state == .acConnected) && charge >= 100.0 {
            return (
                type: .batteryFull,
                title: "Battery Fully Charged",
                body: "Battery has reached 100% and is ready to unplug."
            )
        }

        return nil
    }

    /// Evaluates Thermal temperature against user threshold (optionally scoped to a sensor source).
    public static func evaluateThermal(
        sample: ThermalSample,
        thresholdCelsius: Double,
        unit: Units.TemperatureUnit,
        source: MetricSource = .peak
    ) -> (triggered: Bool, title: String, body: String)? {
        guard let peakTemp = ThermalSensorClassifier.peakCelsius(in: sample, for: source),
              peakTemp >= thresholdCelsius else {
            return nil
        }

        let formattedPeak = Units.formatTemperature(peakTemp, unit: unit)
        let formattedThreshold = Units.formatTemperature(thresholdCelsius, unit: unit)
        let sensorLabel = source == .peak ? "Peak hardware sensor" : "\(source.displayName) sensor"

        return (
            triggered: true,
            title: "High System Temperature",
            body: "\(sensorLabel) reached \(formattedPeak) (threshold: \(formattedThreshold))."
        )
    }

    /// Evaluates Disk capacity usage against user threshold for the target mount point (default "/").
    public static func evaluateDisk(
        sample: DiskSample,
        threshold: Double,
        target: String? = nil
    ) -> (triggered: Bool, title: String, body: String)? {
        let targetVolume: VolumeCapacity?
        if let target {
            targetVolume = sample.volumes.first(where: { $0.mountPoint == target })
        } else {
            targetVolume = sample.volumes.first(where: { $0.mountPoint == "/" }) ?? sample.volumes.first
        }
        guard let volume = targetVolume else {
            return nil
        }
        let usedPct = volume.total > 0 ? (Double(volume.used) / Double(volume.total)) * 100.0 : 0.0
        guard usedPct >= threshold else { return nil }

        let prefix = volume.mountPoint == "/" ? "Primary disk" : "Disk"
        return (
            triggered: true,
            title: "Low Disk Space Warning",
            body: String(format: "%@ '%@' is %.1f%% full (threshold: %.0f%%).", prefix, volume.mountPoint, usedPct, threshold)
        )
    }
}

/// A central `@MainActor` coordinator that evaluates incoming telemetry against user alert rules
/// via core `AlertEvaluator` (sustain, cooldown, hysteresis) and dispatches notifications via `NotificationManager`.
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

        public var kind: AlertKind {
            switch self {
            case .cpuHigh: return .cpu
            case .memoryPressure: return .memory
            case .batteryLow: return .batteryLow
            case .batteryFull: return .batteryFull
            case .thermalHigh: return .temperature
            case .diskLow: return .disk
            }
        }
    }

    private let logger = Logger(subsystem: "com.istats.app", category: "AlertCoordinator")
    private let preferencesStore: PreferencesStore
    private let metricsCoordinator: MetricsCoordinator
    private let notificationManager: NotificationManager
    private let notificationHandler: ((AlertType, String, String) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var evaluator = AlertEvaluator()
    private var isStarted = false

    public init(
        preferencesStore: PreferencesStore = .shared,
        metricsCoordinator: MetricsCoordinator = .shared,
        notificationManager: NotificationManager = .shared,
        notificationHandler: ((AlertType, String, String) -> Void)? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.metricsCoordinator = metricsCoordinator
        self.notificationManager = notificationManager
        self.notificationHandler = notificationHandler
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

    private var canDeliverAlerts: Bool {
        guard preferencesStore.notificationsEnabled else { return false }
        return notificationHandler != nil || notificationManager.isAuthorized
    }

    public func handleCPUSample(_ sample: CPUSample, now: Date = Date()) {
        guard canDeliverAlerts else { return }
        let rule = preferencesStore.alertRule(for: .cpu)
        guard evaluator.evaluate(rule: rule, value: sample.totalUsage, now: now) == .fire else { return }

        if let alert = AlertMessageBuilder.evaluateCPU(sample: sample, threshold: rule.threshold) {
            dispatchAlert(type: .cpuHigh, title: alert.title, body: alert.body)
        }
    }

    public func handleMemorySample(_ sample: MemorySample, now: Date = Date()) {
        guard canDeliverAlerts else { return }
        let rule = preferencesStore.alertRule(for: .memory)
        let criticalOnly = preferencesStore.memoryAlertCriticalPressureOnly
        let usedPct = sample.total > 0 ? (Double(sample.used) / Double(sample.total)) * 100.0 : 0.0
        let evaluatedValue: Double
        if criticalOnly {
            evaluatedValue = (sample.pressure == .critical) ? 100.0 : 0.0
        } else if sample.pressure == .critical || sample.pressure == .warning {
            evaluatedValue = max(usedPct, rule.threshold)
        } else {
            evaluatedValue = usedPct
        }

        guard evaluator.evaluate(rule: rule, value: evaluatedValue, now: now) == .fire else { return }

        if let alert = AlertMessageBuilder.evaluateMemory(
            sample: sample,
            threshold: rule.threshold,
            criticalPressureOnly: criticalOnly
        ) {
            dispatchAlert(type: .memoryPressure, title: alert.title, body: alert.body)
        }
    }

    public func handlePowerSample(_ sample: PowerSample, now: Date = Date()) {
        guard canDeliverAlerts else { return }
        let lowRule = preferencesStore.alertRule(for: .batteryLow)
        let fullRule = preferencesStore.alertRule(for: .batteryFull)

        guard sample.hasBattery, let charge = sample.charge else {
            _ = evaluator.evaluate(rule: lowRule, value: nil, now: now)
            _ = evaluator.evaluate(rule: fullRule, value: nil, now: now)
            return
        }

        let lowVal = (sample.state == .discharging) ? charge : 100.0
        if evaluator.evaluate(rule: lowRule, value: lowVal, now: now) == .fire,
           let alert = AlertMessageBuilder.evaluateBattery(
               sample: sample,
               lowThreshold: Int(lowRule.threshold.rounded()),
               lowAlertEnabled: true,
               fullAlertEnabled: false
           ) {
            dispatchAlert(type: .batteryLow, title: alert.title, body: alert.body)
        }

        let isPlugged = (sample.state == .charging || sample.state == .charged || sample.state == .acConnected)
        let fullVal = isPlugged ? charge : min(charge, 99.0)
        if evaluator.evaluate(rule: fullRule, value: fullVal, now: now) == .fire,
           let alert = AlertMessageBuilder.evaluateBattery(
               sample: sample,
               lowThreshold: Int(lowRule.threshold.rounded()),
               lowAlertEnabled: false,
               fullAlertEnabled: true
           ) {
            dispatchAlert(type: .batteryFull, title: alert.title, body: alert.body)
        }
    }

    public func handleThermalSample(_ sample: ThermalSample, now: Date = Date()) {
        guard canDeliverAlerts else { return }
        let rule = preferencesStore.alertRule(for: .temperature)
        let source = rule.target.flatMap(MetricSource.init(rawValue:)) ?? .peak
        let temp = ThermalSensorClassifier.peakCelsius(in: sample, for: source)
        guard evaluator.evaluate(rule: rule, value: temp, now: now) == .fire else { return }

        if let alert = AlertMessageBuilder.evaluateThermal(
            sample: sample,
            thresholdCelsius: rule.threshold,
            unit: preferencesStore.temperatureUnit,
            source: source
        ) {
            dispatchAlert(type: .thermalHigh, title: alert.title, body: alert.body)
        }
    }

    public func handleDiskSample(_ sample: DiskSample, now: Date = Date()) {
        guard canDeliverAlerts else { return }
        let rule = preferencesStore.alertRule(for: .disk)
        let targetVolume: VolumeCapacity?
        if let target = rule.target {
            targetVolume = sample.volumes.first(where: { $0.mountPoint == target })
        } else {
            targetVolume = sample.volumes.first(where: { $0.mountPoint == "/" }) ?? sample.volumes.first
        }
        let usedPct: Double? = targetVolume.flatMap { vol in
            vol.total > 0 ? (Double(vol.used) / Double(vol.total)) * 100.0 : nil
        }

        guard evaluator.evaluate(rule: rule, value: usedPct, now: now) == .fire else { return }

        if let alert = AlertMessageBuilder.evaluateDisk(sample: sample, threshold: rule.threshold, target: rule.target) {
            dispatchAlert(type: .diskLow, title: alert.title, body: alert.body)
        }
    }

    // MARK: - Cooldown & Dispatching

    /// Verifies if enough time has passed since the last alert of this type.
    public func canTrigger(type: AlertType, now: Date = Date()) -> Bool {
        guard let lastTime = evaluator.state(for: type.kind).lastFired else { return true }
        if now < lastTime { return false }
        let cooldown = preferencesStore.alertRule(for: type.kind).cooldownSeconds
        return now.timeIntervalSince(lastTime) >= cooldown
    }

    /// Records the trigger timestamp for anti-spam debounce.
    public func recordAlertTrigger(type: AlertType, now: Date = Date()) {
        evaluator.recordFired(kind: type.kind, now: now)
    }

    /// Clears cooldown history for all alert types.
    public func resetCooldowns() {
        evaluator.resetCooldowns()
    }

    private func dispatchAlert(type: AlertType, title: String, body: String) {
        if let notificationHandler {
            notificationHandler(type, title, body)
            return
        }
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
                title: "iStats Test Notification",
                subtitle: "System Monitor",
                body: "Notification permissions and alert channels are working properly!"
            )
        } catch {
            logger.warning("Failed to post test notification: \(error.localizedDescription)")
        }
    }
}
