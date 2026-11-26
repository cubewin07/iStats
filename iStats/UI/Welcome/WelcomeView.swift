import SwiftUI
import AppKit
import UserNotifications
import iStatsCore

/// Observable state and actions for the 3-step Welcome onboarding flow (Task 9.11).
@MainActor
public final class WelcomeFlowModel: ObservableObject {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome = 0
        case preset = 1
        case setup = 2

        public var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .preset: return "Menu Bar"
            case .setup: return "Setup"
            }
        }
    }

    @Published public var step: Step = .welcome
    @Published public var selectedPreset: MenuBarPreset = .balanced
    @Published public var selectedAppearance: MenuBarAppearance
    @Published public var launchAtLogin: Bool
    @Published public var notificationsStatus: UNAuthorizationStatus
    @Published public private(set) var didUserToggleLaunchAtLogin: Bool = false

    public let store: PreferencesStore
    public let coordinator: MetricsCoordinator
    private let explicitHasBattery: Bool?
    private let explicitHasFans: Bool?
    private let applyLaunchAtLogin: (Bool) -> Bool
    private let requestNotifications: () async -> Bool
    public var onComplete: (() -> Void)?

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared,
        hasBattery: Bool? = nil,
        hasFans: Bool? = nil,
        initialNotificationStatus: UNAuthorizationStatus = NotificationManager.shared.authorizationStatus,
        applyLaunchAtLogin: @escaping (Bool) -> Bool = { LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: $0) },
        requestNotifications: @escaping () async -> Bool = { await NotificationManager.shared.requestAuthorization() },
        onComplete: (() -> Void)? = nil
    ) {
        self.store = store
        self.coordinator = coordinator
        self.explicitHasBattery = hasBattery
        self.explicitHasFans = hasFans
        self.selectedAppearance = store.menuBarAppearance
        // Reflect existing preference without ever enabling launch-at-login silently.
        self.launchAtLogin = store.launchAtLogin
        self.notificationsStatus = initialNotificationStatus
        self.applyLaunchAtLogin = applyLaunchAtLogin
        self.requestNotifications = requestNotifications
        self.onComplete = onComplete
    }

    public var hasBattery: Bool {
        explicitHasBattery ?? (coordinator.latestPower?.value.hasBattery ?? true)
    }

    public var hasFans: Bool {
        if let explicitHasFans { return explicitHasFans }
        guard let fan = coordinator.latestFan?.value else { return true }
        return !fan.isFanless && !fan.fans.isEmpty
    }

    public var previewConfigs: [MenuBarItemConfig] {
        selectedPreset.configs(hasBattery: hasBattery, hasFans: hasFans)
    }

    public func nextStep() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    public func previousStep() {
        if let prev = Step(rawValue: step.rawValue - 1) {
            step = prev
        }
    }

    /// Applies an explicit user toggle for launch-at-login via `SMAppService`.
    public func setLaunchAtLoginByUser(_ enabled: Bool) {
        didUserToggleLaunchAtLogin = true
        launchAtLogin = enabled
        store.launchAtLogin = enabled
        _ = applyLaunchAtLogin(enabled)
    }

    @discardableResult
    public func requestNotificationPermission() async -> Bool {
        let granted = await requestNotifications()
        notificationsStatus = granted ? .authorized : .denied
        if granted {
            store.notificationsEnabled = true
        }
        return granted
    }

    /// Writes the chosen preset, appearance, and `hasCompletedOnboarding = true`.
    public func applyAndFinish() {
        store.applyOnboarding(
            preset: selectedPreset,
            appearance: selectedAppearance,
            hasBattery: hasBattery,
            hasFans: hasFans
        )
        onComplete?()
    }

    /// Skips onboarding, applying the `.balanced` preset and setting `hasCompletedOnboarding = true`.
    public func skip() {
        store.skipOnboarding(hasBattery: hasBattery, hasFans: hasFans)
        onComplete?()
    }
}

/// 3-step first-run Welcome onboarding view (Task 9.11 / ADR 0006 / ADR 0011).
public struct WelcomeView: View {
    @ObservedObject public var model: WelcomeFlowModel
    @ObservedObject private var coordinator: MetricsCoordinator
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    @Environment(\.colorScheme) private var colorScheme

    public init(model: WelcomeFlowModel) {
        self.model = model
        self._coordinator = ObservedObject(wrappedValue: model.coordinator)
    }

    private var appIcon: NSImage {
        NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    public var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()

            Group {
                switch model.step {
                case .welcome:
                    welcomeStep
                case .preset:
                    presetStep
                case .setup:
                    setupStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            Divider()
            footerBar
        }
        .frame(width: 580, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var stepHeader: some View {
        HStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("iStats Setup")
                    .font(.headline)
                Text("Step \(model.step.rawValue + 1) of \(WelcomeFlowModel.Step.allCases.count) · \(model.step.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(WelcomeFlowModel.Step.allCases, id: \.rawValue) { step in
                    Capsule(style: .continuous)
                        .fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: step == model.step ? 22 : 8, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Step 1: Welcome + In-Memory Privacy Promise

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to iStats")
                    .font(.title.weight(.bold))
                Text("Live system telemetry in your macOS menu bar — CPU, memory, GPU, thermals, fans, network, disk, and power.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                featureCard(
                    symbol: "lock.shield",
                    tint: .green,
                    title: "Private by Design (In-Memory Only)",
                    detail: "Metrics stay in memory while iStats runs. Nothing is written to disk or sent over the network. Only your preferences are saved."
                )

                featureCard(
                    symbol: "menubar.rectangle",
                    tint: .accentColor,
                    title: "At-a-Glance Menu Bar & Panels",
                    detail: "Pick the exact sensors you care about in the menu bar, or open Overview anytime to inspect every subsystem."
                )

                featureCard(
                    symbol: "info.circle",
                    tint: .orange,
                    title: "Explained in Context",
                    detail: "Click any info button or press ? inside a panel to read plain-English explanations and typical ranges."
                )
            }
        }
    }

    private func featureCard(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Step 2: Preset + Live Menu Bar Preview

    private var presetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose Your Menu Bar")
                    .font(.title2.weight(.bold))
                Text("Start with a preset tailored to your Mac's hardware. You can customize widgets anytime in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Live Menu Bar Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE MENU BAR PREVIEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                menuBarPreviewStrip
            }

            // Hardware-aware presets
            VStack(spacing: 8) {
                ForEach(MenuBarPreset.allCases) { preset in
                    presetOptionRow(preset)
                }
            }

            // Appearance selector
            HStack {
                Text("Widget color")
                    .font(.callout.weight(.medium))
                Spacer()
                Picker("Widget color", selection: $model.selectedAppearance) {
                    ForEach(MenuBarAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 310)
            }
            .padding(.top, 2)
        }
    }

    private var menuBarPreviewStrip: some View {
        let configs = model.previewConfigs
        var opts = WidgetOptions()
        opts.appearance = model.selectedAppearance
        opts.temperatureUnit = model.store.temperatureUnit
        opts.networkUnit = model.store.networkUnit
        opts.byteUnitStandard = model.store.byteUnitStandard

        return HStack(spacing: 10) {
            Spacer(minLength: 0)
            ForEach(configs) { config in
                if let entry = WidgetCatalog.entry(for: config.category, style: config.style, hasBattery: model.hasBattery)
                    ?? WidgetCatalog.entries(for: config.category, hasBattery: model.hasBattery).first {
                    WidgetPreview(
                        config: config,
                        snapshot: entry.sampleSnapshot(hasBattery: model.hasBattery),
                        options: opts,
                        scale: 2.0,
                        colorScheme: colorScheme,
                        showBackdrop: false
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live menu bar preview with \(configs.count) widgets")
    }

    private func presetOptionRow(_ preset: MenuBarPreset) -> some View {
        let isSelected = (model.selectedPreset == preset)
        let configs = preset.configs(hasBattery: model.hasBattery, hasFans: model.hasFans)

        return Button {
            model.selectedPreset = preset
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(preset.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(configs.count) \(configs.count == 1 ? "widget" : "widgets")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.25)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Step 3: Optional Notifications & Launch at Login

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Optional Setup")
                    .font(.title2.weight(.bold))
                Text("Both options are completely optional and can be changed anytime in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Notification permission card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Metric Alerts")
                            .font(.headline)
                        Text("Receive macOS notifications when sustained CPU, memory pressure, temperature, disk, or battery thresholds trigger.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Text(notificationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.notificationsStatus == .notDetermined {
                        Button("Allow Notifications") {
                            Task {
                                await model.requestNotificationPermission()
                            }
                        }
                    } else if model.notificationsStatus == .denied {
                        Button("Open Notification Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            // Launch at login card (never enabled silently)
            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "Open iStats at login",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLoginByUser($0) }
                    )
                )
                .font(.headline)
                .accessibilityLabel("Open iStats at login")

                Text("Off by default. When enabled, macOS registers iStats as a login item via System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if launchManager.status == .requiresApproval {
                    HStack {
                        Text("macOS needs your approval in Login Items.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Approve in System Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    private var notificationStatusText: String {
        switch model.notificationsStatus {
        case .authorized, .provisional, .ephemeral:
            return "Notifications are allowed."
        case .denied:
            return "Notifications are currently denied in System Settings."
        case .notDetermined:
            return "Permission not requested yet."
        @unknown default:
            return "Permission status unknown."
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Button("Skip") {
                model.skip()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Skip onboarding")

            Spacer()

            if model.step != .welcome {
                Button("Back") {
                    model.previousStep()
                }
            }

            if model.step == .setup {
                Button("Get Started") {
                    model.applyAndFinish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") {
                    model.nextStep()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
