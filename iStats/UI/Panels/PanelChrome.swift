import SwiftUI
import AppKit
import iStatsCore

extension Notification.Name {
    /// Posted right after `PreferencesWindowController.shared.showPreferences()` so Settings
    /// navigates to the matching section (contract with Task 9.9).
    public static let openSettingsSection = Notification.Name(PanelSettingsLink.notificationName)
}

/// Shared AppKit actions triggered by panel chrome buttons, menu items, ribbons, and shortcuts.
@MainActor
public enum PanelChromeActions {
    /// Opens Settings and notifies it which section matches `destination` (`category.rawValue` or `"general"`).
    public static func openSettings(
        for destination: PanelDestination,
        closeTransientIfUnpinned: Bool = true,
        showPreferences: () -> Void = { PreferencesWindowController.shared.showPreferences() }
    ) {
        if closeTransientIfUnpinned && !PanelController.shared.isPinned(for: destination) {
            PanelController.shared.close()
        }
        showPreferences()
        NotificationCenter.default.post(
            name: .openSettingsSection,
            object: nil,
            userInfo: [PanelSettingsLink.sectionKey: PanelSettingsLink.section(for: destination)]
        )
    }

    public static func perform(
        _ quickAction: PanelQuickAction,
        closeTransientIfUnpinned: Bool = true,
        destination: PanelDestination
    ) {
        if closeTransientIfUnpinned && !PanelController.shared.isPinned(for: destination) {
            PanelController.shared.close()
        }
        switch quickAction.target {
        case .activityMonitor:
            NSWorkspace.shared.open(URL(fileURLWithPath: PanelQuickAction.activityMonitorPath))
        case .systemSettings(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    public static func quitApp() {
        NSApp.terminate(nil)
    }
}

/// Configuration for the v3 panel chrome (ADR 0011 / Task 9.3).
/// Replaces the 16 loose parameters formerly passed directly to `PanelScaffold`.
public struct PanelChrome {
    public var destination: PanelDestination
    public var status: StatusLevel
    public var ribbon: String?
    public var ribbonActionTitle: String?
    public var ribbonAction: (() -> Void)?
    public var availability: Availability?
    public var isLoading: Bool
    public var isPaused: Bool
    public var isLowPowerModeActive: Bool
    public var isPinned: Bool
    public var hasBattery: Bool
    public var refreshInterval: TimeInterval
    public var enabledCategories: Set<MetricCategory>
    public var onSelectDestination: ((PanelDestination) -> Void)?
    public var onTogglePause: (() -> Void)?
    public var onPinToggle: (() -> Void)?
    public var onClosePinned: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onShowGlossary: (() -> Void)?

    public init(
        destination: PanelDestination,
        status: StatusLevel = .fine,
        ribbon: String? = nil,
        ribbonActionTitle: String? = nil,
        ribbonAction: (() -> Void)? = nil,
        availability: Availability? = nil,
        isLoading: Bool = false,
        isPaused: Bool = false,
        isLowPowerModeActive: Bool = false,
        isPinned: Bool = false,
        hasBattery: Bool = true,
        refreshInterval: TimeInterval = 2.0,
        enabledCategories: Set<MetricCategory> = Set(MetricCategory.allCases),
        onSelectDestination: ((PanelDestination) -> Void)? = nil,
        onTogglePause: (() -> Void)? = nil,
        onPinToggle: (() -> Void)? = nil,
        onClosePinned: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        onShowGlossary: (() -> Void)? = nil
    ) {
        self.destination = destination
        self.status = status
        self.ribbon = ribbon
        self.ribbonActionTitle = ribbonActionTitle
        self.ribbonAction = ribbonAction
        self.availability = availability
        self.isLoading = isLoading
        self.isPaused = isPaused
        self.isLowPowerModeActive = isLowPowerModeActive
        self.isPinned = isPinned
        self.hasBattery = hasBattery
        self.refreshInterval = refreshInterval
        self.enabledCategories = enabledCategories
        self.onSelectDestination = onSelectDestination
        self.onTogglePause = onTogglePause
        self.onPinToggle = onPinToggle
        self.onClosePinned = onClosePinned
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onShowGlossary = onShowGlossary
    }

    public init(
        category: MetricCategory,
        status: StatusLevel = .fine,
        ribbon: String? = nil,
        ribbonActionTitle: String? = nil,
        ribbonAction: (() -> Void)? = nil,
        availability: Availability? = nil,
        isLoading: Bool = false,
        isPaused: Bool = false,
        isLowPowerModeActive: Bool = false,
        isPinned: Bool = false,
        hasBattery: Bool = true,
        refreshInterval: TimeInterval = 2.0,
        enabledCategories: Set<MetricCategory> = Set(MetricCategory.allCases),
        onSelectDestination: ((PanelDestination) -> Void)? = nil,
        onTogglePause: (() -> Void)? = nil,
        onPinToggle: (() -> Void)? = nil,
        onClosePinned: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        onShowGlossary: (() -> Void)? = nil
    ) {
        self.init(
            destination: .category(category),
            status: status,
            ribbon: ribbon,
            ribbonActionTitle: ribbonActionTitle,
            ribbonAction: ribbonAction,
            availability: availability,
            isLoading: isLoading,
            isPaused: isPaused,
            isLowPowerModeActive: isLowPowerModeActive,
            isPinned: isPinned,
            hasBattery: hasBattery,
            refreshInterval: refreshInterval,
            enabledCategories: enabledCategories,
            onSelectDestination: onSelectDestination,
            onTogglePause: onTogglePause,
            onPinToggle: onPinToggle,
            onClosePinned: onClosePinned,
            onOpenSettings: onOpenSettings,
            onQuit: onQuit,
            onShowGlossary: onShowGlossary
        )
    }

    public var displayTitle: String {
        switch destination {
        case .overview:
            return "Overview"
        case .category(let category):
            return category.identity.displayName(hasBattery: hasBattery)
        }
    }

    public var identitySymbol: String {
        switch destination {
        case .overview:
            return "square.grid.2x2"
        case .category(let category):
            return category.identity.symbol(hasBattery: hasBattery)
        }
    }

    public var stripDestinations: [PanelDestination] {
        PanelDestination.strip(enabled: enabledCategories)
    }
}

// MARK: - 28 pt Header Strip

/// 28 pt destination navigation strip with Overview + enabled category buttons (24 pt each),
/// pin button, `⋯` action menu (with shortcut hints and Quit iStats ⌘Q), and close button when pinned.
public struct PanelHeaderStrip: View {
    public let destination: PanelDestination
    public let enabledCategories: Set<MetricCategory>
    public let hasBattery: Bool
    public let isPinned: Bool
    public let isPaused: Bool
    public let onSelectDestination: (PanelDestination) -> Void
    public let onTogglePin: () -> Void
    public let onClose: () -> Void
    public let onTogglePause: (() -> Void)?
    public let onOpenSettings: () -> Void
    public let onShowGlossary: (() -> Void)?
    public let onQuit: () -> Void

    @State private var hoveredDestination: PanelDestination? = nil
    @State private var isPinHovered: Bool = false
    @State private var isMenuHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public static let stripButtonSize: CGFloat = 24

    public init(
        destination: PanelDestination,
        enabledCategories: Set<MetricCategory>,
        hasBattery: Bool,
        isPinned: Bool,
        isPaused: Bool,
        onSelectDestination: @escaping (PanelDestination) -> Void,
        onTogglePin: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onTogglePause: (() -> Void)? = nil,
        onOpenSettings: @escaping () -> Void,
        onShowGlossary: (() -> Void)? = nil,
        onQuit: @escaping () -> Void
    ) {
        self.destination = destination
        self.enabledCategories = enabledCategories
        self.hasBattery = hasBattery
        self.isPinned = isPinned
        self.isPaused = isPaused
        self.onSelectDestination = onSelectDestination
        self.onTogglePin = onTogglePin
        self.onClose = onClose
        self.onTogglePause = onTogglePause
        self.onOpenSettings = onOpenSettings
        self.onShowGlossary = onShowGlossary
        self.onQuit = onQuit
    }

    private var stripItems: [PanelDestination] {
        PanelDestination.strip(enabled: enabledCategories)
    }

    private var activeTint: Color {
        switch destination {
        case .overview:
            return .accentColor
        case .category(let category):
            return CategoryPalette.tint(for: category)
        }
    }

    public var body: some View {
        HStack(spacing: Instrument.Space.xxs) {
            // Leading: Overview + enabled categories (24 pt buttons)
            HStack(spacing: Instrument.Space.xxs) {
                ForEach(Array(stripItems.enumerated()), id: \.element) { index, item in
                    stripButton(for: item, shortcutIndex: index + 1)
                }
            }

            Spacer(minLength: 2)

            // Trailing: Pin, ⋯ Menu, and Close (when pinned)
            HStack(spacing: Instrument.Space.xxs) {
                pinButton
                ellipsisMenu
                if isPinned {
                    closePinnedButton
                }
            }
        }
        .frame(height: Instrument.Size.headerStripHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel Navigation")
    }

    private func tint(for item: PanelDestination) -> Color {
        switch item {
        case .overview:
            return .accentColor
        case .category(let category):
            return CategoryPalette.tint(for: category)
        }
    }

    private func symbol(for item: PanelDestination) -> String {
        switch item {
        case .overview:
            return "square.grid.2x2"
        case .category(let category):
            return category.identity.symbol(hasBattery: hasBattery)
        }
    }

    private func label(for item: PanelDestination) -> String {
        switch item {
        case .overview:
            return "Overview"
        case .category(let category):
            return category.identity.displayName(hasBattery: hasBattery)
        }
    }

    private func stripButton(for item: PanelDestination, shortcutIndex: Int) -> some View {
        let isActive = (item == destination)
        let isHovered = (hoveredDestination == item)
        let itemTint = tint(for: item)
        let title = label(for: item)
        let highContrast = (colorSchemeContrast == .increased)

        return Button {
            if !isActive {
                onSelectDestination(item)
            }
        } label: {
            Image(systemName: symbol(for: item))
                .font(Instrument.Typography.icon(Instrument.Icon.regular, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? itemTint : (isHovered ? .primary : .secondary))
                .frame(width: Self.stripButtonSize, height: Self.stripButtonSize)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isActive
                                ? itemTint.opacity(highContrast ? 0.24 : 0.16)
                                : (isHovered ? Color.primary.opacity(0.08) : .clear)
                        )
                        .overlay {
                            if isActive && highContrast {
                                Capsule(style: .continuous)
                                    .strokeBorder(itemTint.opacity(0.65), lineWidth: 0.75)
                            }
                        }
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.snappy) {
                hoveredDestination = hovering ? item : (hoveredDestination == item ? nil : hoveredDestination)
            }
        }
        .help("\(title) (⌘\(shortcutIndex))")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var pinButton: some View {
        let pillFill: Color = isPinned
            ? activeTint.opacity(isPinHovered ? 0.22 : 0.14)
            : (isPinHovered ? Color.primary.opacity(0.09) : .clear)

        return Button(action: onTogglePin) {
            chromeIconLabel(
                systemName: isPinned ? "pin.fill" : "pin",
                size: Instrument.Icon.regular,
                weight: isPinned ? .semibold : .regular,
                foreground: isPinned ? activeTint : (isPinHovered ? .primary : .secondary),
                pillFill: pillFill,
                dimension: 22
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.snappy) {
                isPinHovered = hovering
            }
        }
        .help(isPinned ? "Unpin Window (⌘P)" : "Pin Window (⌘P)")
        .accessibilityLabel(isPinned ? "Unpin Window" : "Pin Window")
    }

    private var ellipsisMenu: some View {
        let quickAction = PanelQuickAction.menu(for: destination, hasBattery: hasBattery)

        return Menu {
            Button {
                PanelChromeActions.perform(
                    quickAction,
                    closeTransientIfUnpinned: !isPinned,
                    destination: destination
                )
            } label: {
                Label(quickAction.title, systemImage: quickAction.systemImage)
            }

            if let pauseAction = onTogglePause {
                Button(action: pauseAction) {
                    Label(
                        isPaused ? "Resume Sampling" : "Pause Sampling",
                        systemImage: isPaused ? "play.circle" : "pause.circle"
                    )
                }
            }

            Button(action: onTogglePin) {
                Label(
                    isPinned ? "Unpin Window  ⌘P" : "Pin Window  ⌘P",
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }

            Button(action: onClose) {
                Label(
                    isPinned ? "Close Pinned Window  ⌘W" : "Close Panel  ⌘W",
                    systemImage: "xmark"
                )
            }

            Divider()

            if let showGlossary = onShowGlossary {
                Button(action: showGlossary) {
                    Label("Metric Glossary  ?", systemImage: "questionmark.circle")
                }
            }

            Button(action: onOpenSettings) {
                Label("Settings…  ⌘,", systemImage: "gearshape")
            }

            Divider()

            Button(action: onQuit) {
                Label("Quit iStats  ⌘Q", systemImage: "power")
            }
        } label: {
            chromeIconLabel(
                systemName: "ellipsis",
                size: Instrument.Icon.regular,
                weight: .semibold,
                foreground: isMenuHovered ? .primary : .secondary,
                pillFill: isMenuHovered ? Color.primary.opacity(0.09) : .clear,
                dimension: 22
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(Motion.snappy) {
                isMenuHovered = hovering
            }
        }
        .help("More Actions")
        .accessibilityLabel("More Actions")
    }

    private var closePinnedButton: some View {
        Button(action: onClose) {
            chromeIconLabel(
                systemName: "xmark",
                size: Instrument.Icon.small,
                weight: .semibold,
                foreground: isCloseHovered ? .primary : .secondary,
                pillFill: isCloseHovered ? Color.primary.opacity(0.09) : .clear,
                dimension: 21
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.snappy) {
                isCloseHovered = hovering
            }
        }
        .help("Close Pinned Window (⌘W)")
        .accessibilityLabel("Close Pinned Window")
    }

    private func chromeIconLabel(
        systemName: String,
        size: CGFloat,
        weight: Font.Weight,
        foreground: Color,
        pillFill: Color,
        dimension: CGFloat
    ) -> some View {
        Image(systemName: systemName)
            .font(Instrument.Typography.icon(size, weight: weight))
            .foregroundColor(foreground)
            .frame(width: dimension, height: dimension)
            .background(
                RoundedRectangle(cornerRadius: Instrument.Radius.chip, style: .continuous)
                    .fill(pillFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Instrument.Radius.chip, style: .continuous))
    }
}

// MARK: - Title Row (15 pt Semibold Title + PageSwitcher)

/// Title row below the header strip: 15 pt semibold destination title paired with `PageSwitcher`.
public struct PanelTitleRow: View {
    public let title: String
    public let category: MetricCategory?
    public let pages: [PopoverTab]
    @Binding public var selection: PopoverTab

    public init(
        title: String,
        category: MetricCategory?,
        pages: [PopoverTab],
        selection: Binding<PopoverTab>
    ) {
        self.title = title
        self.category = category
        self.pages = pages
        self._selection = selection
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Instrument.Space.xs) {
            Text(title)
                .font(Instrument.Typography.title)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 4)

            if let category, pages.count > 1 {
                PageSwitcher(
                    pages: pages,
                    selection: $selection,
                    category: category
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) Title")
    }
}

// MARK: - 24 pt Slim Footer

/// 24 pt footer: contextual quick action leading, update cadence or Paused center, pause & Settings trailing.
public struct PanelFooterBar: View {
    public let destination: PanelDestination
    public let hasBattery: Bool
    public let isPaused: Bool
    public let isPinned: Bool
    public let refreshInterval: TimeInterval
    public let onTogglePause: (() -> Void)?
    public let onOpenSettings: () -> Void

    @State private var isActionHovered: Bool = false
    @State private var isPauseHovered: Bool = false
    @State private var isSettingsHovered: Bool = false

    public init(
        destination: PanelDestination,
        hasBattery: Bool,
        isPaused: Bool,
        isPinned: Bool,
        refreshInterval: TimeInterval,
        onTogglePause: (() -> Void)?,
        onOpenSettings: @escaping () -> Void
    ) {
        self.destination = destination
        self.hasBattery = hasBattery
        self.isPaused = isPaused
        self.isPinned = isPinned
        self.refreshInterval = refreshInterval
        self.onTogglePause = onTogglePause
        self.onOpenSettings = onOpenSettings
    }

    public var statusCaption: String {
        PanelFooterCaption.text(isPaused: isPaused, refreshInterval: refreshInterval)
    }

    public var body: some View {
        let quickAction = PanelQuickAction.footer(for: destination, hasBattery: hasBattery)

        VStack(spacing: 0) {
            Divider()
                .opacity(0.4)
                .padding(.bottom, Instrument.Space.xs)

            HStack(spacing: Instrument.Space.xs) {
                Button {
                    PanelChromeActions.perform(
                        quickAction,
                        closeTransientIfUnpinned: !isPinned,
                        destination: destination
                    )
                } label: {
                    Text(quickAction.title)
                        .font(Instrument.Typography.caption)
                        .foregroundColor(isActionHovered ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(Motion.snappy) {
                        isActionHovered = hovering
                    }
                }
                .help(quickAction.title)
                .accessibilityLabel(quickAction.title)

                Spacer(minLength: 4)

                Text(statusCaption)
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                HStack(spacing: Instrument.Space.xxs) {
                    if let pauseAction = onTogglePause {
                        Button(action: pauseAction) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(Instrument.Typography.icon(Instrument.Icon.small, weight: .semibold))
                                .foregroundColor(isPauseHovered ? .primary : .secondary)
                                .frame(width: 20, height: 20)
                                .background(
                                    RoundedRectangle(cornerRadius: Instrument.Radius.inline, style: .continuous)
                                        .fill(isPauseHovered ? Color.primary.opacity(0.09) : .clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: Instrument.Radius.inline, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(Motion.snappy) {
                                isPauseHovered = hovering
                            }
                        }
                        .help(isPaused ? "Resume Sampling" : "Pause Sampling")
                        .accessibilityLabel(isPaused ? "Resume Sampling" : "Pause Sampling")
                    }

                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(Instrument.Typography.icon(Instrument.Icon.regular, weight: .regular))
                            .foregroundColor(isSettingsHovered ? .primary : .secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: Instrument.Radius.inline, style: .continuous)
                                    .fill(isSettingsHovered ? Color.primary.opacity(0.09) : .clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: Instrument.Radius.inline, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(Motion.snappy) {
                            isSettingsHovered = hovering
                        }
                    }
                    .help("Settings… (⌘,)")
                    .accessibilityLabel("Settings")
                }
            }
            .frame(height: Instrument.Size.footerHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel Footer")
    }
}
