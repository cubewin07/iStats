import SwiftUI
import AppKit
import iStatsCore

/// Model describing the glance header atop every Instrument panel (Task 8.6 / ADR 0009).
public struct PanelGlance: Sendable {
    public var value: Double?
    public var formattedValue: String?
    public var format: String
    public var unit: String
    public var secondaryGlance: (value: Double, unit: String, color: Color)?
    public var headline: String
    public var insight: String?
    public var chartMode: LiveChartMode?
    public var chartHeight: CGFloat
    public var scrubFormat: (@Sendable (Double) -> String)?

    public init(
        value: Double? = nil,
        formattedValue: String? = nil,
        format: String = "%.0f",
        unit: String = "%",
        secondaryGlance: (value: Double, unit: String, color: Color)? = nil,
        headline: String = "",
        insight: String? = nil,
        chartMode: LiveChartMode? = nil,
        chartHeight: CGFloat = Instrument.Size.chartHeightCompact,
        scrubFormat: (@Sendable (Double) -> String)? = nil
    ) {
        self.value = value
        self.formattedValue = formattedValue
        self.format = format
        self.unit = unit
        self.secondaryGlance = secondaryGlance
        self.headline = headline
        self.insight = insight
        self.chartMode = chartMode
        self.chartHeight = chartHeight
        self.scrubFormat = scrubFormat
    }
}

/// The unified Instrument Panel Scaffold v3 (ADR 0011 / Task 9.3).
/// Composes `PanelHeaderStrip` (28 pt), `PanelTitleRow` (15 pt + `PageSwitcher`),
/// Glance, Living Chart, Status Ribbon, Page Body, and `PanelFooterBar` (24 pt).
public struct PanelScaffold<Content: View>: View {
    public let chrome: PanelChrome
    public let glance: PanelGlance
    public let pages: [PopoverTab]
    @Binding public var selection: PopoverTab
    private var externalScrubState: Binding<ChartScrubState?>?
    @ViewBuilder public let content: (PopoverTab) -> Content

    @State private var scrubState: ChartScrubState? = nil
    @State private var activeScrubSourceID: UUID? = nil
    @State private var measuredBodyHeight: CGFloat? = nil
    @State private var scrollVisibleHeight: CGFloat = 0
    @State private var isShowingGlossary: Bool = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.explicitMotionPolicy) private var explicitMotionPolicy
    @Environment(\.isManagedByPanelController) private var isManagedByPanelController
    @Environment(\.panelScaffoldProbeEnabled) private var probeEnabled
    @ObservedObject private var panelController = PanelController.shared

    /// Convenience accessor for the active category (category panels always pass `.category(...)`).
    public var category: MetricCategory {
        chrome.destination.category ?? .cpu
    }

    private var destination: PanelDestination {
        chrome.destination
    }

    private var effectiveIsPinned: Bool {
        chrome.isPinned || panelController.isPinned(for: destination)
    }

    private var isWindowVisible: Bool {
        isManagedByPanelController ? panelController.isPanelOpen(for: destination) : true
    }

    private var activeScrubState: ChartScrubState? {
        guard !chrome.isLoading, (chrome.availability?.isAvailable ?? true) else { return nil }
        return externalScrubState?.wrappedValue ?? scrubState
    }

    private var shouldShowInsightRow: Bool {
        guard !chrome.isLoading else { return false }
        if let avail = chrome.availability, !avail.isAvailable { return false }
        return selection != .history
    }

    internal var shouldShowInlineStatusChip: Bool {
        !chrome.isLoading && (chrome.availability?.isAvailable ?? true) && chrome.status >= .elevated
    }

    internal struct ResolvedRibbon {
        let status: StatusLevel
        let message: String
        let actionTitle: String
        let action: (() -> Void)?
    }

    /// Single source of truth for StatusRibbon visibility:
    /// - Paused sampling always shows a Resume ribbon.
    /// - Explicit ribbon action always shows.
    /// - Any message at `.warning` or above always shows with a real category action.
    internal var resolvedRibbon: ResolvedRibbon? {
        if chrome.isPaused {
            return ResolvedRibbon(
                status: .elevated,
                message: "Sampling paused",
                actionTitle: "Resume",
                action: chrome.onTogglePause
            )
        }
        guard let message = chrome.ribbon, !message.isEmpty else { return nil }

        if let title = chrome.ribbonActionTitle, !title.isEmpty, let action = chrome.ribbonAction {
            return ResolvedRibbon(
                status: chrome.status,
                message: message,
                actionTitle: title,
                action: action
            )
        }

        guard !chrome.isLoading, (chrome.availability?.isAvailable ?? true), chrome.status >= .warning else {
            return nil
        }

        let quickAction = PanelQuickAction.ribbon(for: category)
        let isPinnedSnapshot = effectiveIsPinned
        let dest = destination
        return ResolvedRibbon(
            status: chrome.status,
            message: message,
            actionTitle: quickAction.title,
            action: {
                PanelChromeActions.perform(
                    quickAction,
                    closeTransientIfUnpinned: !isPinnedSnapshot,
                    destination: dest
                )
            }
        )
    }

    internal var shouldShowActionableRibbon: Bool {
        resolvedRibbon != nil
    }

    public init(
        chrome: PanelChrome,
        glance: PanelGlance,
        pages: [PopoverTab] = [.overview, .detail, .history],
        selection: Binding<PopoverTab>,
        scrubState: Binding<ChartScrubState?>? = nil,
        @ViewBuilder content: @escaping (PopoverTab) -> Content
    ) {
        self.chrome = chrome
        self.glance = glance
        self.pages = pages
        self._selection = selection
        self.externalScrubState = scrubState
        self.content = content
    }

    public var body: some View {
        let resolvedPolicy = explicitMotionPolicy ?? MotionPolicy.resolve(
            reduceMotion: accessibilityReduceMotion,
            lowPower: chrome.isLowPowerModeActive,
            paused: chrome.isPaused,
            visible: isWindowVisible
        )
        let activeRibbon = resolvedRibbon
        let topPadding = Instrument.Space.l
        let bottomPadding = Instrument.Space.m

        PanelStackLayout(maxHeight: Instrument.Size.maxHeight - topPadding - bottomPadding) {
            // Child 0: Static-height Top Chrome (Header Strip + Title Row + Glance + Chart + Insight + Status Ribbon)
            VStack(alignment: .leading, spacing: 0) {
                // Zone ①: 28 pt Header Strip (Overview + enabled categories + pin + ⋯ menu)
                PanelHeaderStrip(
                    destination: destination,
                    enabledCategories: chrome.enabledCategories,
                    hasBattery: chrome.hasBattery,
                    isPinned: effectiveIsPinned,
                    isPaused: chrome.isPaused,
                    onSelectDestination: { target in
                        selectDestination(target)
                    },
                    onTogglePin: {
                        togglePin()
                    },
                    onClose: {
                        closePanel()
                    },
                    onTogglePause: chrome.onTogglePause,
                    onOpenSettings: {
                        openSettings()
                    },
                    onShowGlossary: {
                        showGlossary()
                    },
                    onQuit: {
                        quitApp()
                    }
                )
                .background(
                    Group {
                        if probeEnabled {
                            GeometryReader { proxy in
                                let frame = proxy.frame(in: .named("PanelScaffoldProbe"))
                                Color.clear.preference(
                                    key: PanelScaffoldProbeKey.self,
                                    value: PanelScaffoldProbeSnapshot(
                                        badgeTitle: chrome.displayTitle,
                                        eyebrowFrame: frame,
                                        headerStripFrame: frame,
                                        headerStripButtonCount: chrome.stripDestinations.count,
                                        hasActionRibbon: activeRibbon != nil,
                                        ribbonActionTitle: activeRibbon?.actionTitle
                                    )
                                )
                            }
                        }
                    }
                )
                .padding(.bottom, Instrument.Space.xs)

                // Title row (15 pt semibold) + PageSwitcher
                PanelTitleRow(
                    title: chrome.displayTitle,
                    category: destination.category,
                    pages: pages,
                    selection: $selection
                )
                .background(
                    Group {
                        if probeEnabled {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: PanelScaffoldProbeKey.self,
                                    value: PanelScaffoldProbeSnapshot(
                                        titleRowFrame: proxy.frame(in: .named("PanelScaffoldProbe"))
                                    )
                                )
                            }
                        }
                    }
                )
                .padding(.bottom, Instrument.Space.s)

                // Zone ②: Glance (display numeral + headline)
                glanceHeader
                    .padding(.bottom, Instrument.Space.s)
                    .background(
                        Group {
                            if probeEnabled {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: PanelScaffoldProbeKey.self,
                                        value: PanelScaffoldProbeSnapshot(
                                            glanceSummary: glanceAccessibilitySummary,
                                            glanceFrame: proxy.frame(in: .named("PanelScaffoldProbe"))
                                        )
                                    )
                                }
                            }
                        }
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(chrome.displayTitle) Glance")
                    .accessibilityValue(glanceAccessibilitySummary)

                // Zone ③: Living Chart (full-bleed; collapses cleanly on .history)
                chartZone
                    .padding(.horizontal, -Instrument.Space.xl)
                    .animation(nil, value: selection)
                    .background(
                        Group {
                            if probeEnabled {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: PanelScaffoldProbeKey.self,
                                        value: PanelScaffoldProbeSnapshot(
                                            chartFrame: proxy.frame(in: .named("PanelScaffoldProbe"))
                                        )
                                    )
                                }
                            }
                        }
                    )

                // Dedicated 11 pt insight caption row directly below the hero chart
                if shouldShowInsightRow, let insight = glance.insight, !insight.isEmpty {
                    insightCaptionRow(insight)
                        .background(
                            Group {
                                if probeEnabled {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: PanelScaffoldProbeKey.self,
                                            value: PanelScaffoldProbeSnapshot(
                                                insightText: insight,
                                                insightFrame: proxy.frame(in: .named("PanelScaffoldProbe"))
                                            )
                                        )
                                    }
                                }
                            }
                        )
                }

                // Zone ④: Status Ribbon (paused, explicit action, or >= .warning with real category action)
                if let activeRibbon {
                    StatusRibbon(
                        status: activeRibbon.status,
                        message: activeRibbon.message,
                        actionTitle: activeRibbon.actionTitle,
                        action: activeRibbon.action
                    )
                    .padding(.top, Instrument.Space.s)
                    .accessibilityElement(children: .combine)
                }
            }

            // Child 1: Zone ⑤ Page Body
            pageContent(policy: resolvedPolicy)
                .accessibilityElement(children: .contain)

            // Child 2: 24 pt Slim Footer
            PanelFooterBar(
                destination: destination,
                hasBattery: chrome.hasBattery,
                isPaused: chrome.isPaused,
                isPinned: effectiveIsPinned,
                refreshInterval: chrome.refreshInterval,
                onTogglePause: chrome.onTogglePause,
                onOpenSettings: {
                    openSettings()
                }
            )
            .padding(.top, Instrument.Space.s)
            .background(
                Group {
                    if probeEnabled {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PanelScaffoldProbeKey.self,
                                value: PanelScaffoldProbeSnapshot(
                                    footerFrame: proxy.frame(in: .named("PanelScaffoldProbe")),
                                    footerStatusText: PanelFooterCaption.text(
                                        isPaused: chrome.isPaused,
                                        refreshInterval: chrome.refreshInterval
                                    )
                                )
                            )
                        }
                    }
                }
            )
        }
        .padding(.horizontal, Instrument.Space.xl)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(width: Instrument.Size.panelWidth)
        .coordinateSpace(name: "PanelScaffoldProbe")
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PanelContentHeightKey.self,
                    value: proxy.size.height > 0
                        ? min(max(proxy.size.height, 160.0), Instrument.Size.maxHeight)
                        : 0
                )
            }
        )
        .environment(\.motionPolicy, resolvedPolicy)
        .environment(\.chartScrubAction, ChartScrubAction(scopedHandler: { newState, sourceID in
            updateScrubState(newState, sourceID: sourceID)
        }))
        .onChange(of: selection) { _ in
            updateScrubState(nil, sourceID: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelCommandReceived)) { notification in
            if let targetDestination = notification.userInfo?["destination"] as? PanelDestination {
                guard targetDestination == destination else { return }
            } else if let targetCategory = notification.userInfo?["category"] as? MetricCategory {
                guard targetCategory == destination.category else { return }
            }
            if let cmd = notification.object as? PanelCommand {
                handleCommand(cmd)
            }
        }
        .sheet(isPresented: $isShowingGlossary) {
            GlossarySheetView(
                destination: destination,
                enabledCategories: chrome.enabledCategories,
                hasBattery: chrome.hasBattery,
                onDismiss: { isShowingGlossary = false }
            )
        }
    }

    // MARK: - Zone ②: Glance Header

    private var glanceHeader: some View {
        VStack(alignment: .leading, spacing: Instrument.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                // Value Display
                if chrome.isLoading {
                    Text("--")
                        .font(Instrument.Typography.display)
                        .foregroundColor(.secondary.opacity(0.3))
                } else if let avail = chrome.availability, case .unavailable = avail {
                    Text("—")
                        .font(Instrument.Typography.display)
                        .foregroundColor(.secondary)
                } else if let scrub = activeScrubState {
                    scrubValueDisplay(scrub)
                } else if let sec = glance.secondaryGlance {
                    // Dual Ticker (e.g. Network Download ↓ / Upload ↑)
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.xxs) {
                            Text("↓")
                                .font(Instrument.Typography.body)
                                .foregroundColor(CategoryPalette.tint(for: category))
                            LiveNumber(
                                value: glance.value ?? 0,
                                format: { String(format: glance.format, $0) },
                                font: Instrument.Typography.displayCompact,
                                unit: glance.unit
                            )
                        }

                        HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.xxs) {
                            Text("↑")
                                .font(Instrument.Typography.body)
                                .foregroundColor(sec.color)
                            LiveNumber(
                                value: sec.value,
                                format: { String(format: glance.format, $0) },
                                font: Instrument.Typography.displayCompact,
                                unit: sec.unit
                            )
                        }
                    }
                } else {
                    if let custom = glance.formattedValue {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(custom)
                                .font(Instrument.Typography.display)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if !glance.unit.isEmpty {
                                Text(glance.unit)
                                    .font(Instrument.Typography.unit)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        LiveNumber(
                            value: glance.value ?? 0,
                            format: { String(format: glance.format, $0) },
                            font: Instrument.Typography.display,
                            unit: glance.unit.isEmpty ? nil : glance.unit
                        )
                    }
                }

                Spacer(minLength: 8)

                if shouldShowInlineStatusChip {
                    InlineStatusChip(status: chrome.status, detail: chrome.ribbon)
                        .background(
                            Group {
                                if probeEnabled {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: PanelScaffoldProbeKey.self,
                                            value: PanelScaffoldProbeSnapshot(
                                                inlineStatusText: InlineStatusChip.displayText(for: chrome.status),
                                                inlineStatusFrame: proxy.frame(in: .named("PanelScaffoldProbe"))
                                            )
                                        )
                                    }
                                }
                            }
                        )
                }
            }

            // Headline
            if chrome.isLoading {
                Text("Loading...")
                    .font(Instrument.Typography.headline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if let avail = chrome.availability, case .unavailable(let reason) = avail {
                Text(reason)
                    .font(Instrument.Typography.headline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if let scrub = activeScrubState {
                scrubHeadline(scrub)
            } else if !glance.headline.isEmpty {
                Text(glance.headline)
                    .font(Instrument.Typography.headline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func scrubValueDisplay(_ scrub: ChartScrubState) -> some View {
        if let sec = scrub.secondaryReadout {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.xxs) {
                    if let primaryLbl = scrub.primaryLabel, !primaryLbl.isEmpty {
                        Text(primaryLbl)
                            .font(Instrument.Typography.body)
                            .foregroundColor(CategoryPalette.tint(for: category))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.xxs) {
                        Text(scrub.formattedPrimary)
                            .font(Instrument.Typography.displayCompact)
                            .tracking(-0.6)
                        if !scrub.primaryUnit.isEmpty {
                            Text(scrub.primaryUnit)
                                .font(Instrument.Typography.unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }

                HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.xxs) {
                    if let secLbl = sec.label, !secLbl.isEmpty {
                        Text(secLbl)
                            .font(Instrument.Typography.body)
                            .foregroundColor(sec.color)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.xxs) {
                        Text(sec.text)
                            .font(Instrument.Typography.displayCompact)
                            .tracking(-0.6)
                        if !sec.unit.isEmpty {
                            Text(sec.unit)
                                .font(Instrument.Typography.unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
            .frame(minHeight: glance.secondaryGlance == nil ? 52 : nil, alignment: .bottomLeading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.xxs) {
                Text(scrub.formattedPrimary)
                    .font(Instrument.Typography.display)
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !scrub.primaryUnit.isEmpty {
                    Text(scrub.primaryUnit)
                        .font(Instrument.Typography.unit)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scrubHeadline(_ scrub: ChartScrubState) -> some View {
        HStack(spacing: Instrument.Space.xs) {
            Text(scrub.relativeTimeText)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            if !scrub.clockTimeText.isEmpty {
                Text("· \(scrub.clockTimeText)")
                    .foregroundColor(.secondary)
            }
        }
        .font(Instrument.Typography.headline.monospacedDigit())
        .padding(.horizontal, Instrument.Space.s)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.inline, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .lineLimit(1)
    }

    private func insightCaptionRow(_ insight: String) -> some View {
        HStack(spacing: Instrument.Space.xs) {
            Text(insight)
                .font(Instrument.Typography.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.top, Instrument.Space.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chrome.displayTitle) Insight")
        .accessibilityValue(insight)
    }

    private var glanceAccessibilitySummary: String {
        if chrome.isLoading {
            return "Loading"
        }
        if let avail = chrome.availability, case .unavailable(let reason) = avail {
            return reason
        }
        let statusSuffix = chrome.status >= .elevated ? ", \(InlineStatusChip.title(for: chrome.status))" : ""
        if let scrub = activeScrubState {
            let primary = scrub.primaryUnit.isEmpty
                ? scrub.formattedPrimary
                : "\(scrub.formattedPrimary) \(scrub.primaryUnit)"
            if let sec = scrub.secondaryReadout {
                let secText = sec.unit.isEmpty ? sec.text : "\(sec.text) \(sec.unit)"
                return "\(primary), \(secText), \(scrub.headlineText)\(statusSuffix)"
            }
            return "\(primary), \(scrub.headlineText)\(statusSuffix)"
        }
        let primaryText: String
        if let custom = glance.formattedValue {
            primaryText = glance.unit.isEmpty ? custom : "\(custom) \(glance.unit)"
        } else {
            let num = String(format: glance.format, glance.value ?? 0)
            primaryText = glance.unit.isEmpty ? num : "\(num) \(glance.unit)"
        }
        if glance.headline.isEmpty {
            return "\(primaryText)\(statusSuffix)"
        }
        return "\(primaryText), \(glance.headline)\(statusSuffix)"
    }

    private func updateScrubState(_ newState: ChartScrubState?, sourceID: UUID?) {
        if let newState {
            activeScrubSourceID = sourceID
            if let externalScrubState {
                if externalScrubState.wrappedValue != newState {
                    externalScrubState.wrappedValue = newState
                }
            } else if scrubState != newState {
                scrubState = newState
            }
        } else {
            guard sourceID == nil || activeScrubSourceID == nil || activeScrubSourceID == sourceID else {
                return
            }
            activeScrubSourceID = nil
            if let externalScrubState {
                if externalScrubState.wrappedValue != nil {
                    externalScrubState.wrappedValue = nil
                }
            } else if scrubState != nil {
                scrubState = nil
            }
        }
    }

    private var resolvedScrubFormatter: (@Sendable (Double) -> String)? {
        if let custom = glance.scrubFormat {
            return custom
        }
        let format = glance.format
        let unit = glance.unit
        return { val in
            let num = String(format: format, val)
            if unit.isEmpty {
                return num
            } else if unit == "%" || unit.hasPrefix("°") {
                return "\(num)\(unit)"
            } else {
                return "\(num) \(unit)"
            }
        }
    }

    // MARK: - Zone ③: Living Chart

    private var targetChartHeight: CGFloat {
        if let avail = chrome.availability, !avail.isAvailable {
            return 12
        } else if selection == .history {
            return 0
        } else if glance.chartMode != nil {
            return glance.chartHeight
        } else {
            return 8
        }
    }

    private var chartZone: some View {
        Group {
            if let avail = chrome.availability, !avail.isAvailable {
                Color.clear
                    .frame(height: 12)
            } else if selection == .history {
                Color.clear
                    .frame(height: 0)
            } else if let mode = glance.chartMode {
                LiveChart(
                    category: category,
                    mode: mode,
                    height: glance.chartHeight,
                    valueFormatter: resolvedScrubFormatter
                )
                .opacity(chrome.isPaused ? 0.4 : 1.0)
                .transition(.opacity)
            } else {
                Color.clear
                    .frame(height: 8)
            }
        }
        .frame(height: targetChartHeight)
        .clipped()
    }

    // MARK: - Zone ⑤: Page Content

    @ViewBuilder
    private func pageContent(policy: MotionPolicy) -> some View {
        if let avail = chrome.availability, case .unavailable(let reason) = avail {
            InsetEmptyState(
                systemImage: chrome.identitySymbol,
                title: "\(chrome.displayTitle) Unavailable",
                reason: reason
            )
            .padding(.top, 14)
        } else if chrome.isLoading {
            VStack(spacing: Instrument.Space.m) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Acquiring telemetry...")
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(.top, 10)
        } else {
            let bodyFits = (measuredBodyHeight ?? 0) <= scrollVisibleHeight + 0.5
            let transition: AnyTransition = (selection == .history && policy == .full)
                ? .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)),
                    removal: .opacity
                )
                : .opacity

            ScrollView(.vertical, showsIndicators: false) {
                PageBodySlot(tab: selection, activeTab: selection) {
                    content(selection)
                }
                .id(selection)
                .transition(transition)
            }
            .frame(idealHeight: measuredBodyHeight, maxHeight: measuredBodyHeight)
            .fixedSize(horizontal: false, vertical: measuredBodyHeight == nil)
            .scrollDisabled(bodyFits)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PanelScrollVisibleHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(PanelScrollVisibleHeightKey.self) { height in
                if height > 0 && abs(scrollVisibleHeight - height) > 0.5 {
                    scrollVisibleHeight = height
                }
            }
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [bodyFits ? .black : .clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 6)
                    Rectangle().fill(Color.black)
                    LinearGradient(colors: [.black, bodyFits ? .black : .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                }
            )
            .onPreferenceChange(PanelBodyHeightKey.self) { height in
                guard height > 0, abs((measuredBodyHeight ?? -1) - height) > 0.5 else { return }
                measuredBodyHeight = height
            }
            .padding(.top, Instrument.Space.m)
        }
    }

    // MARK: - Actions & Keyboard Command Handling

    private func selectDestination(_ target: PanelDestination) {
        if let handler = chrome.onSelectDestination {
            handler(target)
        } else {
            panelController.swap(to: target, from: destination)
        }
    }

    private func togglePin() {
        if let pinAction = chrome.onPinToggle {
            pinAction()
        } else {
            panelController.togglePin(for: destination)
        }
    }

    private func closePanel() {
        if effectiveIsPinned {
            if let closeAction = chrome.onClosePinned {
                closeAction()
            } else {
                panelController.unpin(destination: destination)
            }
        } else {
            panelController.close()
        }
    }

    private func openSettings() {
        if let custom = chrome.onOpenSettings {
            custom()
        } else {
            PanelChromeActions.openSettings(for: destination, closeTransientIfUnpinned: !effectiveIsPinned)
        }
    }

    private func quitApp() {
        if let custom = chrome.onQuit {
            custom()
        } else {
            PanelChromeActions.quitApp()
        }
    }

    private func showGlossary() {
        chrome.onShowGlossary?()
        isShowingGlossary = true
    }

    private var pageSwitchAnimation: Animation? {
        let policy = explicitMotionPolicy ?? MotionPolicy.resolve(
            reduceMotion: accessibilityReduceMotion,
            lowPower: chrome.isLowPowerModeActive,
            paused: chrome.isPaused,
            visible: isWindowVisible
        )
        switch policy {
        case .full: return Motion.snappy
        case .reduced: return .easeInOut(duration: 0.15)
        case .frozen: return nil
        }
    }

    private func handleCommand(_ cmd: PanelCommand) {
        switch cmd {
        case .previousPage:
            if let idx = pages.firstIndex(of: selection), idx > 0 {
                withAnimation(pageSwitchAnimation) {
                    selection = pages[idx - 1]
                }
            }
        case .nextPage:
            if let idx = pages.firstIndex(of: selection), idx < pages.count - 1 {
                withAnimation(pageSwitchAnimation) {
                    selection = pages[idx + 1]
                }
            }
        case .selectDestination(let index):
            let items = chrome.stripDestinations
            if index >= 0 && index < items.count {
                let target = items[index]
                if target != destination {
                    selectDestination(target)
                }
            }
        case .nextDestination:
            let ordered = PanelDestination.orderedCategories(enabled: chrome.enabledCategories)
            let next = destination.neighbor(offset: 1, in: ordered)
            if next != destination {
                selectDestination(next)
            }
        case .previousDestination:
            let ordered = PanelDestination.orderedCategories(enabled: chrome.enabledCategories)
            let prev = destination.neighbor(offset: -1, in: ordered)
            if prev != destination {
                selectDestination(prev)
            }
        case .togglePin:
            togglePin()
        case .openPreferences:
            openSettings()
        case .quit:
            quitApp()
        case .showGlossary:
            showGlossary()
        case .close:
            closePanel()
        }
    }
}

// MARK: - Panel Layout & Height Preference Keys

/// Single-pass 3-child layout (top chrome, scrollable body, slim footer) clamping the body
/// to `maxHeight - topHeight - footerHeight` without double-building content.
private struct PanelStackLayout: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? Instrument.Size.panelWidth
        guard subviews.count == 3 else { return .zero }
        let topSize = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let footerSize = subviews[2].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let maxBody = max(60.0, maxHeight - topSize.height - footerSize.height)
        let bodyIdeal = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let clampedBody = min(bodyIdeal.height, maxBody)
        return CGSize(width: width, height: topSize.height + clampedBody + footerSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let width = bounds.width
        let topSize = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let footerSize = subviews[2].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let maxBody = max(60.0, maxHeight - topSize.height - footerSize.height)
        let bodyIdeal = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let clampedBody = min(bodyIdeal.height, maxBody)

        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: width, height: topSize.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + topSize.height),
            proposal: ProposedViewSize(width: width, height: clampedBody)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + topSize.height + clampedBody),
            proposal: ProposedViewSize(width: width, height: footerSize.height)
        )
    }
}

/// Reports the scaffold's target total height to `MetricPanel` and `PanelController`.
public struct PanelContentHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct PanelBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct PanelScrollVisibleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct PageBodySlot<BodyContent: View>: View {
    let tab: PopoverTab
    let activeTab: PopoverTab
    @ViewBuilder let bodyContent: () -> BodyContent

    var body: some View {
        bodyContent()
            .padding(.vertical, Instrument.Space.xxs)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PanelBodyHeightKey.self,
                        value: tab == activeTab ? proxy.size.height : 0
                    )
                }
            )
    }
}
