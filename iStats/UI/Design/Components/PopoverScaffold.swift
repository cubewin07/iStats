import SwiftUI
import AppKit
import iStatsCore

/// Standard AppKit translucent visual effect background for popovers.
public struct PopoverVisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Category popover footer bar with system context utility shortcut and quick controls.
public struct PopoverFooter: View {
    public let category: MetricCategory
    @ObservedObject public var preferences: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator

    public init(
        category: MetricCategory,
        preferences: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.category = category
        self.preferences = preferences
        self.coordinator = coordinator
    }

    private var contextAction: (title: String, icon: String, action: () -> Void)? {
        switch category {
        case .cpu, .memory, .gpu:
            return (
                title: "Activity Monitor",
                icon: "chart.line.uptrend.xyaxis",
                action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
            )
        case .network:
            return (
                title: "Network Settings",
                icon: "network",
                action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        case .disk:
            return (
                title: "Storage Settings",
                icon: "internaldrive",
                action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        case .power:
            return (
                title: "Battery Settings",
                icon: "bolt.battery",
                action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        case .thermal, .fan:
            return nil
        }
    }

    public var body: some View {
        HStack(spacing: Tokens.sm) {
            // Left: Context Utility Shortcut
            if let ctx = contextAction {
                Button(action: ctx.action) {
                    HStack(spacing: 4) {
                        Image(systemName: ctx.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(ctx.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help("Open system \(ctx.title)")
            }

            Spacer()

            // Right: Pause / Resume & Settings
            HStack(spacing: 8) {
                Button {
                    preferences.isSamplingPaused.toggle()
                } label: {
                    Image(systemName: preferences.isSamplingPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                        .foregroundColor(preferences.isSamplingPaused ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(preferences.isSamplingPaused ? "Resume background telemetry sampling" : "Pause background sampling")

                Button {
                    PreferencesWindowController.shared.showPreferences()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open iStats Preferences (⌘,)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.08))
    }
}

/// The unified container shell for all 8 purpose-driven category popovers.
/// Enforces fixed 330 pt width, ≤ 480 pt height, popover header, tab bar with ⌘1–⌘3,
/// shared loading/unavailable/paused states, and footer actions.
public struct PopoverScaffold<Content: View>: View {
    public let category: MetricCategory
    public let subtitle: String
    public let statusLevel: StatusLevel
    public let badgeText: String
    public let tabs: [PopoverTab]
    @Binding public var selectedTab: PopoverTab
    public var isLoading: Bool
    public var unavailableReason: String?
    @ObservedObject public var preferences: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator
    @ViewBuilder public let content: () -> Content

    public init(
        category: MetricCategory,
        subtitle: String,
        statusLevel: StatusLevel,
        badgeText: String,
        tabs: [PopoverTab],
        selectedTab: Binding<PopoverTab>,
        isLoading: Bool = false,
        unavailableReason: String? = nil,
        preferences: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.category = category
        self.subtitle = subtitle
        self.statusLevel = statusLevel
        self.badgeText = badgeText
        self.tabs = tabs
        self._selectedTab = selectedTab
        self.isLoading = isLoading
        self.unavailableReason = unavailableReason
        self.preferences = preferences
        self.coordinator = coordinator
        self.content = content
    }

    public init(
        category: MetricCategory,
        verdict: MetricVerdict,
        tabs: [PopoverTab],
        selectedTab: Binding<PopoverTab>,
        isLoading: Bool = false,
        unavailableReason: String? = nil,
        preferences: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            category: category,
            subtitle: verdict.dadSentence,
            statusLevel: verdict.level,
            badgeText: verdict.badgeText,
            tabs: tabs,
            selectedTab: selectedTab,
            isLoading: isLoading,
            unavailableReason: unavailableReason,
            preferences: preferences,
            coordinator: coordinator,
            content: content
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            PopoverHeader(
                category: category,
                subtitle: subtitle,
                statusLevel: statusLevel,
                badgeText: badgeText
            )
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Segmented Navigation Tabs
            TabBar(
                category: category,
                tabs: tabs,
                selectedTab: $selectedTab
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            // Main State / Content Area (bounded height, no nested scroll views)
            VStack(spacing: 0) {
                if preferences.isSamplingPaused {
                    VStack(spacing: 12) {
                        StatusBanner(
                            iconName: "pause.circle.fill",
                            message: "Sampling is paused to conserve battery.",
                            level: .elevated
                        )

                        Button("Resume Sampling") {
                            preferences.isSamplingPaused = false
                            coordinator.resumeSampling()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let reason = unavailableReason {
                    VStack(spacing: 12) {
                        HeroMetric(
                            primaryValue: "—",
                            unit: "",
                            contextLine: "Sensor data unavailable"
                        )

                        StatusBanner(
                            iconName: "exclamationmark.triangle.fill",
                            message: reason,
                            level: .warning
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    VStack(alignment: .leading, spacing: 12) {
                        SkeletonView(width: 130, height: 28)
                        SkeletonView(width: 200, height: 14)
                        SkeletonView(width: Tokens.popoverWidth - 32, height: 70)
                        SkeletonView(width: Tokens.popoverWidth - 32, height: 40)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    content()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .frame(maxWidth: Tokens.popoverWidth, maxHeight: Tokens.maxPopoverContentHeight, alignment: .top)
            .clipped()

            Divider()

            // Footer Bar
            PopoverFooter(
                category: category,
                preferences: preferences,
                coordinator: coordinator
            )
        }
        .frame(width: Tokens.popoverWidth)
        .background(PopoverVisualEffectView())
        .onAppear {
            if let saved = preferences.lastSelectedTab(for: category), tabs.contains(saved) {
                selectedTab = saved
            }
        }
        .onChange(of: selectedTab) { newTab in
            preferences.setLastSelectedTab(newTab, for: category)
        }
    }
}

