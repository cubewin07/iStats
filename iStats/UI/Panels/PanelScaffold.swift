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
        chartHeight: CGFloat = 72,
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

/// The unified Instrument Panel Scaffold (ADR 0009 / Task 8.6).
/// Composes zones ① Eyebrow, ② Glance, ③ Living Chart, ④ Status Ribbon, and ⑤ Page Body.
public struct PanelScaffold<Content: View>: View {
    public let category: MetricCategory
    public let glance: PanelGlance
    public let status: StatusLevel
    public let ribbon: String?
    public var ribbonActionTitle: String? = nil
    public var ribbonAction: (() -> Void)? = nil
    public let pages: [PopoverTab]
    @Binding public var selection: PopoverTab
    public var availability: Availability? = nil
    public var isLoading: Bool = false
    public var isPaused: Bool = false
    public var onTogglePause: (() -> Void)? = nil
    public var onPinToggle: (() -> Void)? = nil
    public var isPinned: Bool = false
    private var externalScrubState: Binding<ChartScrubState?>?
    @ViewBuilder public let content: (PopoverTab) -> Content

    @State private var scrubState: ChartScrubState? = nil
    @State private var activeScrubSourceID: UUID? = nil
    @State private var measuredBodyHeight: CGFloat? = nil
    @State private var scrollVisibleHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.panelScaffoldProbeEnabled) private var probeEnabled
    @ObservedObject private var coordinator = MetricsCoordinator.shared
    @ObservedObject private var panelController = PanelController.shared

    private var effectiveIsPinned: Bool {
        isPinned || panelController.isPinned(for: category)
    }

    private var isWindowVisible: Bool {
        panelController.isPanelOpen(for: category) || (!panelController.isTransientVisible && panelController.pinnedCategories.isEmpty)
    }

    private var activeScrubState: ChartScrubState? {
        guard !isLoading, (availability?.isAvailable ?? true) else { return nil }
        return externalScrubState?.wrappedValue ?? scrubState
    }

    private var shouldShowInsightRow: Bool {
        guard !isLoading else { return false }
        if let avail = availability, !avail.isAvailable { return false }
        return selection != .history
    }

    public init(
        category: MetricCategory,
        glance: PanelGlance,
        status: StatusLevel = .fine,
        ribbon: String? = nil,
        ribbonActionTitle: String? = nil,
        ribbonAction: (() -> Void)? = nil,
        pages: [PopoverTab] = [.overview, .detail, .history],
        selection: Binding<PopoverTab>,
        availability: Availability? = nil,
        isLoading: Bool = false,
        isPaused: Bool = false,
        onTogglePause: (() -> Void)? = nil,
        onPinToggle: (() -> Void)? = nil,
        isPinned: Bool = false,
        scrubState: Binding<ChartScrubState?>? = nil,
        @ViewBuilder content: @escaping (PopoverTab) -> Content
    ) {
        self.category = category
        self.glance = glance
        self.status = status
        self.ribbon = ribbon
        self.ribbonActionTitle = ribbonActionTitle
        self.ribbonAction = ribbonAction
        self.pages = pages
        self._selection = selection
        self.availability = availability
        self.isLoading = isLoading
        self.isPaused = isPaused
        self.onTogglePause = onTogglePause
        self.onPinToggle = onPinToggle
        self.isPinned = isPinned
        self.externalScrubState = scrubState
        self.content = content
    }

    public var body: some View {
        let resolvedPolicy = MotionPolicy.resolve(
            reduceMotion: accessibilityReduceMotion,
            lowPower: coordinator.isLowPowerModeActive,
            paused: isPaused,
            visible: isWindowVisible
        )

        PanelStackLayout(maxHeight: Instrument.Size.maxHeight - (Instrument.Space.xl * 2)) {
            // Child 0: Static-height Chrome (Eyebrow + Glance + Chart + Insight + Status Ribbon)
            VStack(alignment: .leading, spacing: 0) {
                // Zone ①: Eyebrow row (28 pt)
                eyebrowRow
                    .frame(height: 28)
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(category.displayName) Header")

                // Zone ②: Glance (display numeral + headline)
                glanceHeader
                    .padding(.bottom, 6)
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
                    .accessibilityLabel("\(category.displayName) Glance")
                    .accessibilityValue(glanceAccessibilitySummary)

                // Zone ③: Living Chart (full-bleed, 72 pt; collapses cleanly on .history)
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

                // Zone ④: Status Ribbon (shown only at >= .elevated or paused or explicit message)
                if isPaused {
                    StatusRibbon(
                        status: .elevated,
                        message: "Sampling paused",
                        actionTitle: "Resume",
                        action: onTogglePause
                    )
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                } else if let message = ribbon, (!status.isQuiet || status == .fine) {
                    StatusRibbon(
                        status: status,
                        message: message,
                        actionTitle: ribbonActionTitle,
                        action: ribbonAction
                    )
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                }
            }

            // Child 1: Zone ⑤ Page Body
            pageContent(policy: resolvedPolicy)
                .accessibilityElement(children: .contain)
        }
        .padding(Instrument.Space.xl)
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
        .motionPolicy(resolvedPolicy)
        .environment(\.chartScrubAction, ChartScrubAction(scopedHandler: { newState, sourceID in
            updateScrubState(newState, sourceID: sourceID)
        }))
        .onChange(of: selection) { _ in
            updateScrubState(nil, sourceID: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelCommandReceived)) { notification in
            if let targetCategory = notification.userInfo?["category"] as? MetricCategory,
               targetCategory != category {
                return
            }
            if let cmd = notification.object as? PanelCommand {
                handleCommand(cmd)
            }
        }
    }

    // MARK: - Zone ①: Eyebrow Row

    private var eyebrowRow: some View {
        HStack(spacing: 8) {
            // Category Glyph + Tracked Uppercase Name
            HStack(spacing: 5) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CategoryPalette.tint(for: category))

                Text(category.displayName.uppercased())
                    .font(Instrument.Typography.eyebrow)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Page Switcher
            if pages.count > 1 {
                PageSwitcher(
                    pages: pages,
                    selection: $selection,
                    category: category
                )
            }

            // Ellipsis Menu
            Menu {
                if let (title, action) = contextUtilityAction() {
                    Button(title, action: action)
                }

                if let pauseAction = onTogglePause {
                    Button(isPaused ? "Resume Sampling" : "Pause Sampling", action: pauseAction)
                }

                Divider()

                Button("Settings...") {
                    PreferencesWindowController.shared.showPreferences()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20, height: 20)
            .help("More Actions")

            // Pin / Detach Button
            Button {
                if let pinAction = onPinToggle {
                    pinAction()
                } else {
                    panelController.togglePin(for: category)
                }
            } label: {
                Image(systemName: effectiveIsPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: effectiveIsPinned ? .semibold : .regular))
                    .foregroundColor(effectiveIsPinned ? CategoryPalette.tint(for: category) : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(effectiveIsPinned ? "Unpin Window" : "Pin Window")

            // Explicit Close Button on Pinned HUDs
            if effectiveIsPinned {
                Button {
                    panelController.unpin(category: category)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Pinned Window")
            }
        }
    }

    // MARK: - Zone ②: Glance Header

    private var glanceHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                // Value Display
                if isLoading {
                    Text("--")
                        .font(Instrument.Typography.display)
                        .foregroundColor(.secondary.opacity(0.3))
                } else if let avail = availability, case .unavailable = avail {
                    Text("—")
                        .font(Instrument.Typography.display)
                        .foregroundColor(.secondary)
                } else if let scrub = activeScrubState {
                    scrubValueDisplay(scrub)
                } else if let sec = glance.secondaryGlance {
                    // Dual Ticker (e.g. Network Download ↓ / Upload ↑)
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
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

                        HStack(alignment: .firstTextBaseline, spacing: 2) {
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

                Spacer()
            }

            // Headline
            if isLoading {
                Text("Loading...")
                    .font(Instrument.Typography.headline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if let avail = availability, case .unavailable(let reason) = avail {
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
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if let primaryLbl = scrub.primaryLabel, !primaryLbl.isEmpty {
                        Text(primaryLbl)
                            .font(Instrument.Typography.body)
                            .foregroundColor(CategoryPalette.tint(for: category))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
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

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if let secLbl = sec.label, !secLbl.isEmpty {
                        Text(secLbl)
                            .font(Instrument.Typography.body)
                            .foregroundColor(sec.color)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
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
            HStack(alignment: .firstTextBaseline, spacing: 2) {
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
        HStack(spacing: 4) {
            Text(scrub.relativeTimeText)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            if !scrub.clockTimeText.isEmpty {
                Text("· \(scrub.clockTimeText)")
                    .foregroundColor(.secondary)
            }
        }
        .font(Instrument.Typography.headline.monospacedDigit())
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .lineLimit(1)
    }

    private func insightCaptionRow(_ insight: String) -> some View {
        HStack(spacing: 4) {
            Text(insight)
                .font(Instrument.Typography.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName) Insight")
        .accessibilityValue(insight)
    }

    private var glanceAccessibilitySummary: String {
        if isLoading {
            return "Loading"
        }
        if let avail = availability, case .unavailable(let reason) = avail {
            return reason
        }
        if let scrub = activeScrubState {
            let primary = scrub.primaryUnit.isEmpty
                ? scrub.formattedPrimary
                : "\(scrub.formattedPrimary) \(scrub.primaryUnit)"
            if let sec = scrub.secondaryReadout {
                let secText = sec.unit.isEmpty ? sec.text : "\(sec.text) \(sec.unit)"
                return "\(primary), \(secText), \(scrub.headlineText)"
            }
            return "\(primary), \(scrub.headlineText)"
        }
        let primaryText: String
        if let custom = glance.formattedValue {
            primaryText = glance.unit.isEmpty ? custom : "\(custom) \(glance.unit)"
        } else {
            let num = String(format: glance.format, glance.value ?? 0)
            primaryText = glance.unit.isEmpty ? num : "\(num) \(glance.unit)"
        }
        if glance.headline.isEmpty {
            return primaryText
        }
        return "\(primaryText), \(glance.headline)"
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
        if let avail = availability, !avail.isAvailable {
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
            if let avail = availability, !avail.isAvailable {
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
                .opacity(isPaused ? 0.4 : 1.0)
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
        if let avail = availability, case .unavailable(let reason) = avail {
            InsetEmptyState(
                systemImage: category.symbolName,
                title: "\(category.displayName) Unavailable",
                reason: reason
            )
            .padding(.top, 14)
        } else if isLoading {
            VStack(spacing: 8) {
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
            .padding(.top, 8)
        }
    }

    // MARK: - Keyboard Command Handling

    private func handleCommand(_ cmd: PanelCommand) {
        switch cmd {
        case .previousPage:
            if let idx = pages.firstIndex(of: selection), idx > 0 {
                withAnimation(Motion.snappy) {
                    selection = pages[idx - 1]
                }
            }
        case .nextPage:
            if let idx = pages.firstIndex(of: selection), idx < pages.count - 1 {
                withAnimation(Motion.snappy) {
                    selection = pages[idx + 1]
                }
            }
        case .selectPage(let pageNumber):
            let idx = pageNumber - 1
            if idx >= 0 && idx < pages.count {
                withAnimation(Motion.snappy) {
                    selection = pages[idx]
                }
            }
        case .togglePin:
            if let pinAction = onPinToggle {
                pinAction()
            } else {
                panelController.togglePin(for: category)
            }
        case .togglePause:
            onTogglePause?()
        case .openPreferences:
            PreferencesWindowController.shared.showPreferences()
        case .close:
            if effectiveIsPinned {
                panelController.unpin(category: category)
            } else {
                panelController.close()
            }
        }
    }

    private func contextUtilityAction() -> (title: String, action: () -> Void)? {
        switch category {
        case .cpu, .memory, .gpu:
            return ("Open Activity Monitor", {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            })
        case .network:
            return ("Open Network Settings", {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            })
        case .disk:
            return ("Open Storage Settings", {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                    NSWorkspace.shared.open(url)
                }
            })
        case .power:
            return ("Open Battery Settings", {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                    NSWorkspace.shared.open(url)
                }
            })
        case .thermal, .fan:
            return nil
        }
    }
}

// MARK: - Panel Layout & Height Preference Keys

/// Single-pass layout clamping the scroll body to `maxHeight - chromeHeight` without double-building content.
private struct PanelStackLayout: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? Instrument.Size.panelWidth
        guard subviews.count == 2 else { return .zero }
        let chromeSize = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let maxBody = max(80.0, maxHeight - chromeSize.height)
        let bodyIdeal = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let clampedBody = min(bodyIdeal.height, maxBody)
        return CGSize(width: width, height: chromeSize.height + clampedBody)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let width = bounds.width
        let chromeSize = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: chromeSize.height))
        let maxBody = max(80.0, maxHeight - chromeSize.height)
        let bodyIdeal = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let clampedBody = min(bodyIdeal.height, maxBody)
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + chromeSize.height),
            proposal: ProposedViewSize(width: width, height: clampedBody)
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
            .padding(.vertical, 2)
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

// MARK: - Chart Namespace Environment (unused in 8.5.6a; kept nil until 8.5.5 removes HistoryPage reference)

private struct ChartNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    public var chartNamespace: Namespace.ID? {
        get { self[ChartNamespaceKey.self] }
        set { self[ChartNamespaceKey.self] = newValue }
    }

    internal var panelScaffoldProbeEnabled: Bool {
        get { self[PanelScaffoldProbeEnabledKey.self] }
        set { self[PanelScaffoldProbeEnabledKey.self] = newValue }
    }
}

private struct PanelScaffoldProbeEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

internal struct PanelScaffoldProbeSnapshot: Equatable, Sendable {
    var glanceSummary: String?
    var glanceFrame: CGRect?
    var chartFrame: CGRect?
    var insightText: String?
    var insightFrame: CGRect?
}

internal struct PanelScaffoldProbeKey: PreferenceKey {
    static let defaultValue = PanelScaffoldProbeSnapshot()
    static func reduce(value: inout PanelScaffoldProbeSnapshot, nextValue: () -> PanelScaffoldProbeSnapshot) {
        let next = nextValue()
        if let s = next.glanceSummary { value.glanceSummary = s }
        if let f = next.glanceFrame { value.glanceFrame = f }
        if let f = next.chartFrame { value.chartFrame = f }
        if let t = next.insightText { value.insightText = t }
        if let f = next.insightFrame { value.insightFrame = f }
    }
}

