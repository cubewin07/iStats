import SwiftUI
import AppKit
import iStatsCore

/// Shared page section header helper encoding `Instrument.Typography.eyebrow` (Task 9.4).
public struct PanelPageSection<Content: View>: View {
    public let title: String
    public let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Instrument.Space.xs) {
            Text(title.uppercased())
                .font(Instrument.Typography.eyebrow)
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// Overview destination view (ADR 0011 / Task 9.4):
/// 2-column grid of category summary tiles (320 pt content width inside 352×560 panel shell)
/// with live primary values, 24 pt sparklines, status dots, and system uptime summary.
public struct OverviewView: View {
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    public var onSelectCategory: ((MetricCategory) -> Void)?
    public var uptimeProvider: () -> TimeInterval

    @ObservedObject private var panelController = PanelController.shared
    @FocusState private var focusedCategory: MetricCategory?
    @State private var measuredBodyHeight: CGFloat? = nil
    @State private var scrollVisibleHeight: CGFloat = 0

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: Instrument.Space.m),
        GridItem(.flexible(), spacing: Instrument.Space.m)
    ]

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        onSelectCategory: ((MetricCategory) -> Void)? = nil,
        uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.onSelectCategory = onSelectCategory
        self.uptimeProvider = uptimeProvider
    }

    private var hasBattery: Bool {
        coordinator.latestPower?.value.hasBattery ?? true
    }

    private var isPinned: Bool {
        panelController.isPinned(for: .overview)
    }

    private var unitPreferences: OverviewUnitPreferences {
        OverviewUnitPreferences(
            temperatureUnit: preferences.temperatureUnit,
            networkUnit: preferences.networkUnit,
            byteUnitStandard: preferences.byteUnitStandard
        )
    }

    public var tiles: [OverviewTileModel] {
        OverviewTileModel.tiles(
            enabledCategories: preferences.enabledCategories,
            store: coordinator.store,
            availabilityByCategory: coordinator.categoryAvailability,
            hasBattery: hasBattery,
            units: unitPreferences,
            sparkMaxPoints: 30
        )
    }

    public var uptimeSummaryText: String {
        "Uptime \(OverviewTileModel.formattedUptime(uptimeProvider()))"
    }

    public var body: some View {
        let topPadding = Instrument.Space.l
        let bottomPadding = Instrument.Space.m
        let currentTiles = tiles

        OverviewStackLayout(maxHeight: Instrument.Size.maxHeight - topPadding - bottomPadding) {
            // Child 0: Static-height Top Chrome (Header Strip + Overview Title & Uptime + Optional Paused Ribbon)
            VStack(alignment: .leading, spacing: 0) {
                PanelHeaderStrip(
                    destination: .overview,
                    enabledCategories: preferences.enabledCategories,
                    hasBattery: hasBattery,
                    isPinned: isPinned,
                    isPaused: coordinator.isSamplingPaused,
                    onSelectDestination: { target in
                        panelController.swap(to: target, from: .overview)
                    },
                    onTogglePin: {
                        panelController.togglePin(for: .overview)
                    },
                    onClose: {
                        closePanel()
                    },
                    onTogglePause: {
                        coordinator.toggleSamplingPaused()
                    },
                    onOpenSettings: {
                        PanelChromeActions.openSettings(for: .overview, closeTransientIfUnpinned: !isPinned)
                    },
                    onQuit: {
                        PanelChromeActions.quitApp()
                    }
                )
                .padding(.bottom, Instrument.Space.xs)

                overviewTitleRow
                    .padding(.bottom, Instrument.Space.s)

                if coordinator.isSamplingPaused {
                    StatusRibbon(
                        status: .elevated,
                        message: "Sampling paused",
                        actionTitle: "Resume",
                        action: {
                            coordinator.toggleSamplingPaused()
                        }
                    )
                    .padding(.bottom, Instrument.Space.xs)
                }
            }

            // Child 1: Scrollable 2-Column Tile Grid (auto-sizes when <= maxBody)
            tileGridBody(tiles: currentTiles)

            // Child 2: 24 pt Slim Footer
            PanelFooterBar(
                destination: .overview,
                hasBattery: hasBattery,
                isPaused: coordinator.isSamplingPaused,
                isPinned: isPinned,
                refreshInterval: preferences.refreshInterval,
                onTogglePause: {
                    coordinator.toggleSamplingPaused()
                },
                onOpenSettings: {
                    PanelChromeActions.openSettings(for: .overview, closeTransientIfUnpinned: !isPinned)
                }
            )
            .padding(.top, Instrument.Space.s)
        }
        .padding(.horizontal, Instrument.Space.xl)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(width: Instrument.Size.panelWidth)
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
        .onReceive(NotificationCenter.default.publisher(for: .panelCommandReceived)) { notification in
            if let target = notification.userInfo?["destination"] as? PanelDestination, target != .overview {
                return
            }
            guard let cmd = notification.object as? PanelCommand else { return }
            handleCommand(cmd)
        }
    }

    private var overviewTitleRow: some View {
        HStack(alignment: .center, spacing: Instrument.Space.xs) {
            Text("Overview")
                .font(Instrument.Typography.title)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: Instrument.Space.xs) {
                Image(systemName: "clock")
                    .font(Instrument.Typography.icon(Instrument.Icon.small))
                    .foregroundStyle(.secondary)
                Text(uptimeSummaryText)
                    .font(Instrument.Typography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Instrument.Space.s)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Instrument.Surface.module)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(uptimeSummaryText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview Title")
    }

    @ViewBuilder
    private func tileGridBody(tiles: [OverviewTileModel]) -> some View {
        if tiles.isEmpty {
            InsetEmptyState(
                systemImage: "square.grid.2x2",
                title: "No Categories Enabled",
                reason: "Enable at least one category in Settings to monitor system health."
            ) {
                Button("Open Settings…") {
                    PanelChromeActions.openSettings(for: .overview, closeTransientIfUnpinned: !isPinned)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.vertical, Instrument.Space.m)
        } else {
            let bodyFits = (measuredBodyHeight ?? 0) <= scrollVisibleHeight + 0.5
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Self.columns, spacing: Instrument.Space.m) {
                    ForEach(tiles) { model in
                        tileButton(for: model)
                    }
                }
                .padding(.vertical, Instrument.Space.xxs)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: OverviewBodyHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .frame(idealHeight: measuredBodyHeight, maxHeight: measuredBodyHeight)
            .fixedSize(horizontal: false, vertical: measuredBodyHeight == nil)
            .scrollDisabled(bodyFits)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: OverviewScrollVisibleHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(OverviewBodyHeightKey.self) { height in
                if height > 0 && abs((measuredBodyHeight ?? -1) - height) > 0.5 {
                    measuredBodyHeight = height
                }
            }
            .onPreferenceChange(OverviewScrollVisibleHeightKey.self) { height in
                if height > 0 && abs(scrollVisibleHeight - height) > 0.5 {
                    scrollVisibleHeight = height
                }
            }
        }
    }

    @ViewBuilder
    private func tileButton(for model: OverviewTileModel) -> some View {
        let base = OverviewTile(model: model) {
            selectCategory(model.category)
        }
        .focused($focusedCategory, equals: model.category)

        if focusedCategory == model.category {
            base.keyboardShortcut(.defaultAction)
        } else {
            base
        }
    }

    internal func selectCategory(_ category: MetricCategory) {
        if let onSelectCategory {
            onSelectCategory(category)
        } else {
            panelController.swap(to: .category(category), from: .overview)
        }
    }

    private func closePanel() {
        if isPinned {
            panelController.unpin(destination: .overview)
        } else {
            panelController.close()
        }
    }

    private func handleCommand(_ cmd: PanelCommand) {
        switch cmd {
        case .selectDestination(let idx):
            let items = PanelDestination.strip(enabled: preferences.enabledCategories)
            if idx >= 0 && idx < items.count, items[idx] != .overview {
                panelController.swap(to: items[idx], from: .overview)
            }
        case .nextDestination:
            let ordered = PanelDestination.orderedCategories(enabled: preferences.enabledCategories)
            let next = PanelDestination.overview.neighbor(offset: 1, in: ordered)
            if next != .overview {
                panelController.swap(to: next, from: .overview)
            }
        case .previousDestination:
            let ordered = PanelDestination.orderedCategories(enabled: preferences.enabledCategories)
            let prev = PanelDestination.overview.neighbor(offset: -1, in: ordered)
            if prev != .overview {
                panelController.swap(to: prev, from: .overview)
            }
        case .togglePin:
            panelController.togglePin(for: .overview)
        case .openPreferences:
            PanelChromeActions.openSettings(for: .overview, closeTransientIfUnpinned: !isPinned)
        case .quit:
            PanelChromeActions.quitApp()
        case .close:
            closePanel()
        case .previousPage, .nextPage, .showGlossary:
            break
        }
    }
}

/// Individual category summary tile rendered in `OverviewView`'s 2-column grid.
public struct OverviewTile: View {
    public let model: OverviewTileModel
    public let action: () -> Void

    @State private var isHovered: Bool = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(model: OverviewTileModel, action: @escaping () -> Void) {
        self.model = model
        self.action = action
    }

    private var accentColor: Color {
        CategoryPalette.tint(for: model.category)
    }

    private var isUnavailable: Bool {
        if case .unavailable = model.availability { return true }
        return false
    }

    private var unavailableReason: String? {
        model.availability?.unavailableReason
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Instrument.Space.xs) {
                headerRow
                valueRow
                bottomZone
            }
            .padding(.horizontal, Instrument.Space.m)
            .padding(.vertical, Instrument.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                    .fill(isHovered ? Instrument.Surface.moduleHover : Instrument.Surface.module)
            )
            .overlay {
                if colorSchemeContrast == .increased {
                    RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                        .stroke(Color.primary.opacity(0.35), lineWidth: 1.0)
                } else {
                    RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Instrument.Surface.edgeHighlight, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Opens \(model.displayName) details")
    }

    private var headerRow: some View {
        HStack(spacing: Instrument.Space.xs) {
            Image(systemName: model.symbolName)
                .font(Instrument.Typography.icon(Instrument.Icon.regular, weight: .medium))
                .foregroundColor(isUnavailable ? .secondary : accentColor)
                .frame(width: 14, alignment: .center)

            Text(model.displayName)
                .font(Instrument.Typography.captionStrong)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if isUnavailable {
                Image(systemName: "info.circle")
                    .font(Instrument.Typography.icon(Instrument.Icon.small))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(CategoryPalette.statusColor(for: model.status))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var valueRow: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: Instrument.Space.xxs) {
                Text(model.headline)
                    .font(Instrument.Typography.tileValue)
                    .foregroundColor(model.hasData ? .primary : .secondary.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if !model.unit.isEmpty {
                    Text(model.unit)
                        .font(Instrument.Typography.captionMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if let secondary = model.secondaryText, !secondary.isEmpty {
                Text(secondary)
                    .font(Instrument.Typography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var bottomZone: some View {
        if let reason = unavailableReason {
            HStack(spacing: Instrument.Space.xxs) {
                Text(reason)
                    .font(Instrument.Typography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(height: 24, alignment: .leading)
        } else {
            OverviewSparkline(values: model.spark, color: accentColor)
                .frame(height: 24)
        }
    }

    private var accessibilityLabelText: String {
        if let reason = unavailableReason {
            return "\(model.displayName), unavailable: \(reason)"
        }
        if !model.hasData {
            return "\(model.displayName), awaiting sample"
        }
        let main = model.unit.isEmpty ? model.headline : "\(model.headline) \(model.unit)"
        if let secondary = model.secondaryText {
            return "\(model.displayName), \(main), \(secondary)"
        }
        return "\(model.displayName), \(main)"
    }
}

/// 24 pt smoothed sparkline drawn with `LiveChartMath` for Overview tiles.
private struct OverviewSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard w > 1, h > 1 else { return }

            let finite = values.filter(\.isFinite)
            guard finite.count >= 2 else {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: h - 2))
                baseline.addLine(to: CGPoint(x: w, y: h - 2))
                context.stroke(baseline, with: .color(color.opacity(0.2)), lineWidth: 1.0)
                return
            }

            let minVal = finite.min() ?? 0
            let maxVal = finite.max() ?? 1
            let span = max(1e-6, maxVal - minVal)
            let isFlat = (maxVal - minVal) < 1e-6

            let dx = w / CGFloat(finite.count - 1)
            let topInset: CGFloat = 2
            let bottomInset: CGFloat = 2
            let usableHeight = max(1, h - topInset - bottomInset)

            let points = finite.enumerated().map { idx, val in
                let normalized = isFlat ? 0.5 : (val - minVal) / span
                let y = h - bottomInset - (usableHeight * CGFloat(normalized))
                return LiveChartMath.Point2D(x: Double(CGFloat(idx) * dx), y: Double(y))
            }

            let segments = LiveChartMath.smoothSegments(points: points)
            var strokePath = Path()
            if let first = segments.first {
                strokePath.move(to: CGPoint(x: first.start.x, y: first.start.y))
                for seg in segments {
                    strokePath.addCurve(
                        to: CGPoint(x: seg.end.x, y: seg.end.y),
                        control1: CGPoint(x: seg.control1.x, y: seg.control1.y),
                        control2: CGPoint(x: seg.control2.x, y: seg.control2.y)
                    )
                }
            }

            var fillPath = strokePath
            if let last = points.last, let first = points.first {
                fillPath.addLine(to: CGPoint(x: last.x, y: h))
                fillPath.addLine(to: CGPoint(x: first.x, y: h))
                fillPath.closeSubpath()
                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0.22), color.opacity(0.02)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: h)
                    )
                )
            }

            context.stroke(
                strokePath,
                with: .color(color.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Bounded 3-Child Stack Layout (Header, Scrollable Grid, Pinned Footer)

private struct OverviewStackLayout: Layout {
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

private struct OverviewBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct OverviewScrollVisibleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
