import SwiftUI
import iStatsCore

/// Reusable `AlertRule` editor used by both `NotificationsSettingsPage` (all rules)
/// and `CategorySettingsView` (category-scoped rules).
public struct AlertRuleEditorRow: View {
    public let kind: AlertKind
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    public let hasBattery: Bool
    public let showTargetPicker: Bool

    @ObservedObject private var notificationManager = NotificationManager.shared

    public static let sustainOptions: [(label: String, seconds: TimeInterval)] = [
        ("Immediately (0 s)", 0),
        ("for at least 5 s", 5),
        ("for at least 10 s", 10),
        ("for at least 15 s", 15),
        ("for at least 30 s", 30),
        ("for at least 60 s", 60)
    ]

    public static let cooldownOptions: [(label: String, seconds: TimeInterval)] = [
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600)
    ]

    public init(
        kind: AlertKind,
        store: PreferencesStore,
        coordinator: MetricsCoordinator,
        hasBattery: Bool = true,
        showTargetPicker: Bool = true
    ) {
        self.kind = kind
        self.store = store
        self.coordinator = coordinator
        self.hasBattery = hasBattery
        self.showTargetPicker = showTargetPicker
    }

    private var rule: AlertRule {
        store.alertRule(for: kind)
    }

    private var category: MetricCategory {
        switch kind {
        case .cpu: return .cpu
        case .memory: return .memory
        case .temperature: return .thermal
        case .disk: return .disk
        case .batteryLow, .batteryFull: return .power
        }
    }

    private var title: String {
        switch kind {
        case .cpu: return "High CPU Usage"
        case .memory: return "Memory Pressure"
        case .temperature: return "High Temperature"
        case .disk: return "Low Disk Space"
        case .batteryLow: return "Low Battery"
        case .batteryFull: return "Battery Fully Charged"
        }
    }

    private var badgeSymbol: String {
        switch kind {
        case .cpu, .memory, .temperature, .disk:
            return category.identity.symbol(hasBattery: hasBattery)
        case .batteryLow:
            return category.identity.liveSymbol(LiveSymbolState(batteryChargePercent: 25), hasBattery: hasBattery)
        case .batteryFull:
            return category.identity.liveSymbol(LiveSymbolState(batteryChargePercent: 100, isCharging: true), hasBattery: hasBattery)
        }
    }

    private var liveContextText: String? {
        switch kind {
        case .cpu:
            guard let cpu = coordinator.latestCPU?.value else { return nil }
            return "\(Int(round(cpu.totalUsage)))% now"
        case .memory:
            guard let mem = coordinator.latestMemory?.value, mem.total > 0 else { return nil }
            let pct = (Double(mem.used) / Double(mem.total)) * 100.0
            return "\(Int(round(pct)))% now"
        case .temperature:
            guard let th = coordinator.latestThermal?.value else { return nil }
            let source = rule.target.flatMap(MetricSource.init(rawValue:)) ?? .peak
            guard let peak = ThermalSensorClassifier.peakCelsius(in: th, for: source) else { return nil }
            return "\(Units.formatTemperature(peak, unit: store.temperatureUnit, fractionDigits: 0)) now"
        case .disk:
            guard let disk = coordinator.latestDisk?.value else { return nil }
            let vol = rule.target.flatMap { t in disk.volumes.first(where: { $0.mountPoint == t }) }
                ?? disk.volumes.first(where: { $0.mountPoint == "/" })
                ?? disk.volumes.first
            guard let vol, vol.total > 0 else { return nil }
            let pct = (Double(vol.used) / Double(vol.total)) * 100.0
            return "\(Int(round(pct)))% used now"
        case .batteryLow, .batteryFull:
            guard let pwr = coordinator.latestPower?.value, let charge = pwr.charge else { return nil }
            return "\(Int(round(charge)))% now"
        }
    }

    private var sustainChoices: [(label: String, seconds: TimeInterval)] {
        var choices = Self.sustainOptions
        if !choices.contains(where: { $0.seconds == rule.sustainSeconds }) {
            choices.append(("for at least \(Int(rule.sustainSeconds)) s", rule.sustainSeconds))
            choices.sort { $0.seconds < $1.seconds }
        }
        return choices
    }

    private var cooldownChoices: [(label: String, seconds: TimeInterval)] {
        var choices = Self.cooldownOptions
        if !choices.contains(where: { $0.seconds == rule.cooldownSeconds }) {
            let secs = Int(rule.cooldownSeconds)
            let label = secs < 60 ? "\(secs) seconds" : "\(secs / 60) minutes"
            choices.append((label, rule.cooldownSeconds))
            choices.sort { $0.seconds < $1.seconds }
        }
        return choices
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { newValue in
                store.updateAlertRule(kind) { $0.enabled = newValue }
                if newValue && notificationManager.authorizationStatus == .notDetermined {
                    Task { await notificationManager.requestAuthorization() }
                }
            }
        )
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: {
                if kind == .temperature {
                    return TemperatureThresholdScale.displayValue(celsius: rule.threshold, unit: store.temperatureUnit)
                }
                return rule.threshold
            },
            set: { newVal in
                store.updateAlertRule(kind) { r in
                    if kind == .temperature {
                        r.threshold = TemperatureThresholdScale.celsius(fromDisplay: newVal, unit: store.temperatureUnit)
                    } else {
                        r.threshold = newVal
                    }
                }
            }
        )
    }

    private var thresholdRange: ClosedRange<Double> {
        kind == .temperature
            ? TemperatureThresholdScale.range(unit: store.temperatureUnit)
            : kind.thresholdRange
    }

    private var thresholdStep: Double {
        switch kind {
        case .temperature: return TemperatureThresholdScale.step(unit: store.temperatureUnit)
        case .disk: return 2.0
        default: return 5.0
        }
    }

    private var formattedThreshold: String {
        switch kind {
        case .temperature:
            return Units.formatTemperature(rule.threshold, unit: store.temperatureUnit)
        default:
            return "\(Int(rule.threshold.rounded()))%"
        }
    }

    private var sustainBinding: Binding<TimeInterval> {
        Binding(
            get: { rule.sustainSeconds },
            set: { newVal in store.updateAlertRule(kind) { $0.sustainSeconds = newVal } }
        )
    }

    private var cooldownBinding: Binding<TimeInterval> {
        Binding(
            get: { rule.cooldownSeconds },
            set: { newVal in store.updateAlertRule(kind) { $0.cooldownSeconds = newVal } }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Instrument.Space.m) {
            HStack(spacing: Instrument.Space.m) {
                SettingsBadge(category: category, symbol: badgeSymbol)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let liveContextText {
                        Text(liveContextText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("\(title) alert")
            }

            if rule.enabled {
                VStack(alignment: .leading, spacing: Instrument.Space.s) {
                    if kind == .memory {
                        Toggle("Critical memory pressure only", isOn: $store.memoryAlertCriticalPressureOnly)
                            .accessibilityLabel("Notify on critical memory pressure only")
                    }

                    if kind != .batteryFull && !(kind == .memory && store.memoryAlertCriticalPressureOnly) {
                        HStack(spacing: Instrument.Space.m) {
                            Text(kind == .batteryLow ? "At or below" : "Threshold")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 84, alignment: .leading)
                            Slider(value: thresholdBinding, in: thresholdRange, step: thresholdStep)
                                .accessibilityLabel("\(title) threshold")
                            Text(formattedThreshold)
                                .font(.body.monospacedDigit().weight(.semibold))
                                .frame(width: 56, alignment: .trailing)
                        }
                    }

                    if showTargetPicker && kind == .disk {
                        diskVolumePicker
                    }

                    if showTargetPicker && kind == .temperature {
                        thermalSourcePicker
                    }

                    HStack(spacing: Instrument.Space.l) {
                        Picker("Sustained", selection: sustainBinding) {
                            ForEach(sustainChoices, id: \.seconds) { option in
                                Text(option.label).tag(option.seconds)
                            }
                        }
                        .accessibilityLabel("\(title) sustain duration")

                        Picker("Cooldown", selection: cooldownBinding) {
                            ForEach(cooldownChoices, id: \.seconds) { option in
                                Text(option.label).tag(option.seconds)
                            }
                        }
                        .accessibilityLabel("\(title) cooldown")
                    }
                }
                .padding(.leading, 38)
            }

            if !store.isCategoryEnabled(category) {
                HStack(spacing: Instrument.Space.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("\(category.identity.displayName(hasBattery: hasBattery)) monitoring is off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Enable") {
                        store.setCategory(category, isEnabled: true)
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 2)
    }

    private var diskVolumePicker: some View {
        let volumes = coordinator.latestDisk?.value.volumes ?? []
        let savedTarget = rule.target

        return Picker("Target volume", selection: Binding<String?>(
            get: { rule.target },
            set: { newTarget in store.updateAlertRule(.disk) { $0.target = newTarget } }
        )) {
            Text("Primary (/)").tag(String?.none)
            ForEach(volumes, id: \.mountPoint) { vol in
                if vol.mountPoint != "/" {
                    Text("\(vol.name) (\(vol.mountPoint))").tag(Optional(vol.mountPoint))
                }
            }
            if let savedTarget,
               savedTarget != "/",
               !volumes.contains(where: { $0.mountPoint == savedTarget }) {
                Text("\(savedTarget) (Unmounted)").tag(Optional(savedTarget))
            }
        }
        .accessibilityLabel("Disk alert volume")
    }

    private var thermalSourcePicker: some View {
        let sources = MetricSource.allCases.filter { $0 != .battery || hasBattery }
        return Picker("Sensor source", selection: Binding<String?>(
            get: { rule.target },
            set: { newTarget in store.updateAlertRule(.temperature) { $0.target = newTarget } }
        )) {
            Text("Peak System").tag(String?.none)
            ForEach(sources.filter { $0 != .peak }) { source in
                Text(source.displayName).tag(Optional(source.rawValue))
            }
        }
        .accessibilityLabel("Temperature alert sensor source")
    }
}

/// Lists all configurable `AlertRule`s cleanly. Embedded in `NotificationsSettingsPage`,
/// or usable standalone in a `Form`.
public struct AlertsSettingsView: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    public let embedded: Bool

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared,
        embedded: Bool = true
    ) {
        self.store = store
        self.coordinator = coordinator
        self.embedded = embedded
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private var visibleKinds: [AlertKind] {
        AlertKind.allCases.filter { kind in
            if !hasBattery && (kind == .batteryLow || kind == .batteryFull) {
                return false
            }
            return true
        }
    }

    public var body: some View {
        if embedded {
            rows
                .disabled(!store.notificationsEnabled)
                .opacity(store.notificationsEnabled ? 1.0 : 0.5)
        } else {
            Form {
                SwiftUI.Section("Alert Rules") {
                    rows
                }
                .disabled(!store.notificationsEnabled)
                .opacity(store.notificationsEnabled ? 1.0 : 0.5)
            }
            .formStyle(.grouped)
        }
    }

    private var rows: some View {
        ForEach(visibleKinds) { kind in
            AlertRuleEditorRow(
                kind: kind,
                store: store,
                coordinator: coordinator,
                hasBattery: hasBattery,
                showTargetPicker: true
            )
        }
    }
}
