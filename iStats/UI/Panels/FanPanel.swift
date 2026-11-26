import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Fans Instrument Panel (Task 8.5.8e / B8, B13, B14 / ADR 0004, ADR 0010).
/// Features the RPM-locked 28×28 pt `TurbineView`, horizontal Min–Max RPM Range Bar,
/// a dedicated Fan Hardware Table on Details, and a calm passive-cooling state on fanless Macs.
public struct FanPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @StateObject private var memoCache = MemoCache()

    private static let supportedTabs: [PopoverTab] = [.overview, .detail, .history]

    private final class MemoCache: ObservableObject {
        struct Key: Equatable {
            let timestamp: Date?
            let sample: FanSample?
            let isFanless: Bool
            let refreshInterval: TimeInterval
        }

        var key: Key?
        var glance: PanelGlance?
    }

    public init(
        initialTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self.initialTab = initialTab
        self.rememberLastTab = rememberLastTab
        self.focusSource = focusSource
        self.coordinator = coordinator
        self.preferences = preferences
        let resolved = Self.supportedTabs.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    private var latestSample: Sample<FanSample>? {
        coordinator.latestFan
    }

    private var sample: FanSample? {
        latestSample?.value
    }

    private var isFanless: Bool {
        sample?.isFanless == true || (sample != nil && sample!.fans.isEmpty)
    }

    public var body: some View {
        let glance = memoizedGlance(for: latestSample)
        let availability = coordinator.categoryAvailability[.fan]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            chrome: PanelChrome(
                category: .fan,
                status: .fine,
                ribbon: nil,
                availability: availability,
                isLoading: isLoading,
                isPaused: coordinator.isSamplingPaused,
                isLowPowerModeActive: coordinator.isLowPowerModeActive,
                isPinned: PanelController.shared.isPinned(for: .fan),
                hasBattery: coordinator.latestPower?.value.hasBattery ?? true,
                refreshInterval: preferences.refreshInterval,
                enabledCategories: preferences.enabledCategories,
                onTogglePause: {
                    coordinator.toggleSamplingPaused()
                },
                onPinToggle: {
                    PanelController.shared.togglePin(for: .fan)
                }
            ),
            glance: glance,
            pages: Self.supportedTabs,
            selection: $selectedTab
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample)
            case .detail:
                detailsPage(sample: sample)
            case .history:
                HistoryPage(category: .fan, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .fan)
            }
        }
    }

    // MARK: - Glance Derivation (B8 + B14)

    private func memoizedGlance(for latest: Sample<FanSample>?) -> PanelGlance {
        let key = MemoCache.Key(
            timestamp: latest?.timestamp,
            sample: latest?.value,
            isFanless: isFanless,
            refreshInterval: preferences.refreshInterval
        )
        if memoCache.key == key, let cached = memoCache.glance {
            return cached
        }
        let derived = deriveGlance(latest: latest)
        memoCache.key = key
        memoCache.glance = derived
        return derived
    }

    internal func deriveGlance(latest: Sample<FanSample>?) -> PanelGlance {
        let currentSample = latest?.value
        let maxRPM = currentSample?.fans.map(\.rpm).max() ?? 0
        let headline = PanelHeadline.fan(sample: currentSample)

        let refDate = latest?.timestamp ?? Date()
        let rpmPoints = coordinator.timedScalarHistory(
            for: .fanMaxRPM,
            duration: 60,
            referenceDate: refDate
        )

        let minFanFloor = currentSample?.fans.compactMap(\.minRPM).min().map(Double.init)
        let minRPMForInsight = minFanFloor ?? 1200.0
        let maxSpecRPM = Double(currentSample?.fans.compactMap(\.maxRPM).max() ?? 6000)

        let insight = isFanless
            ? "Passive silent cooling"
            : InsightEngine.insights(
                series: rpmPoints.map(\.value),
                interval: preferences.refreshInterval,
                unit: .rpm,
                thresholds: .fanRPM(minRPM: minRPMForInsight, maxRPM: maxSpecRPM)
            ).first?.text

        let chartMode: LiveChartMode? = isFanless ? nil : .single(
            points: rpmPoints,
            color: CategoryPalette.tint(for: .fan),
            deepColor: CategoryPalette.tintDeep(for: .fan),
            domainFloor: minFanFloor
        )

        return PanelGlance(
            value: isFanless ? nil : Double(maxRPM),
            formattedValue: isFanless ? "Passive" : nil,
            format: "%.0f",
            unit: isFanless ? "" : "rpm",
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            chartHeight: Instrument.Size.chartHeightStandard,
            scrubFormat: { "\(Int(round($0))) RPM" }
        )
    }

    // MARK: - Now Page (single Fans section)

    @ViewBuilder
    private func nowPage(sample: FanSample?) -> some View {
        if isFanless {
            fanlessModule
        } else if let s = sample, !s.fans.isEmpty {
            Section(FanPanelCopy.nowSectionTitle, glossaryKey: .fanRpmRange) {
                VStack(spacing: Instrument.Space.m) {
                    ForEach(Array(s.fans.enumerated()), id: \.offset) { index, fan in
                        VStack(alignment: .leading, spacing: Instrument.Space.xs) {
                            if s.fans.count > 1 {
                                Text(fanTitle(fan, index: index))
                                    .font(Instrument.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            fanRowBody(fan: fan)
                        }
                        .padding(.bottom, index < s.fans.count - 1 ? Instrument.Space.s : 0)
                        .overlay(alignment: .bottom) {
                            if index < s.fans.count - 1 {
                                Rectangle()
                                    .fill(Instrument.Surface.hairline)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        } else {
            InsetEmptyState(
                systemImage: CategoryIdentity(.fan).liveSymbol(LiveSymbolState(isFanless: true)),
                title: "No Fan Telemetry",
                reason: "Fan speed readings are currently unavailable."
            )
        }
    }

    // MARK: - Details Page (hardware table, control shown once)

    @ViewBuilder
    private func detailsPage(sample: FanSample?) -> some View {
        if isFanless {
            fanlessModule
        } else if let s = sample, !s.fans.isEmpty {
            VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
                Section(FanPanelCopy.detailsSectionTitle) {
                    VStack(spacing: Instrument.Space.m) {
                        ForEach(Array(s.fans.enumerated()), id: \.offset) { index, fan in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(fanTitle(fan, index: index))
                                    .font(Instrument.Typography.body)
                                    .fontWeight(.medium)
                                    .padding(.bottom, Instrument.Space.xs)
                                fanHardwareRows(fan: fan)
                            }
                            .padding(.bottom, index < s.fans.count - 1 ? Instrument.Space.xs : 0)
                            .overlay(alignment: .bottom) {
                                if index < s.fans.count - 1 {
                                    Rectangle()
                                        .fill(Instrument.Surface.hairline)
                                        .frame(height: 0.5)
                                }
                            }
                        }

                        MetricRow(
                            label: "Control",
                            valueText: FanControlPolicy.statusLabel,
                            isCopyable: false,
                            showHairline: false
                        )
                    }
                }

                Text(FanPanelCopy.footnote)
                    .font(Instrument.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Instrument.Space.xs)
            }
        } else {
            InsetEmptyState(
                systemImage: CategoryIdentity(.fan).liveSymbol(LiveSymbolState(isFanless: true)),
                title: "No Cooling Hardware Data",
                reason: "Fan hardware bounds are currently unavailable."
            )
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var fanlessModule: some View {
        Section(FanPanelCopy.fanlessSectionTitle) {
            InsetEmptyState(
                systemImage: CategoryIdentity(.fan).liveSymbol(LiveSymbolState(isFanless: true)),
                title: FanPanelCopy.fanlessTitle,
                reason: FanPanelCopy.fanlessReason
            ) {
                Button("Open Temperature") {
                    PanelController.shared.swapToCategory(.thermal)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func fanRowBody(fan: FanReading) -> some View {
        VStack(alignment: .leading, spacing: Instrument.Space.m) {
            HStack(alignment: .center, spacing: Instrument.Space.m) {
                TurbineView(
                    rpm: fan.rpm,
                    minRPM: fan.minRPM,
                    maxRPM: fan.maxRPM,
                    size: 28,
                    isPaused: coordinator.isSamplingPaused
                )

                LiveNumber(
                    value: Double(fan.rpm),
                    format: { Units.formatRPM(Int(round($0))) },
                    font: Instrument.Typography.displayCompact
                )
                .foregroundColor(.primary)

                Spacer()

                if let minBound = fan.minRPM, let maxBound = fan.maxRPM, maxBound > minBound {
                    let pct = Int(round(FanMath.fraction(rpm: fan.rpm, min: minBound, max: maxBound) * 100.0))
                    Text("\(pct)% range")
                        .font(Instrument.Typography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            FanRPMRangeBar(
                currentRPM: fan.rpm,
                minRPM: fan.minRPM,
                maxRPM: fan.maxRPM,
                targetRPM: nil,
                tint: CategoryPalette.tint(for: .fan)
            )
        }
    }

    @ViewBuilder
    private func fanHardwareRows(fan: FanReading) -> some View {
        VStack(spacing: 0) {
            MetricRow(
                label: "Min RPM",
                valueText: fan.minRPM.map { Units.formatRPM($0) } ?? "Unavailable",
                glossaryKey: .fanRpmRange,
                isCopyable: false,
                showHairline: true
            )
            MetricRow(
                label: "Max RPM",
                valueText: fan.maxRPM.map { Units.formatRPM($0) } ?? "Unavailable",
                isCopyable: false,
                showHairline: false
            )
        }
    }

    private func fanTitle(_ fan: FanReading, index: Int) -> String {
        fan.name.isEmpty ? "Fan \(index + 1)" : fan.name
    }
}

/// User-facing Fans copy. Kept separate so tests can assert there is no internal doc
/// reference (ADR numbers) and no policy essay in the UI.
enum FanPanelCopy {
    static let nowSectionTitle = "Fans"
    static let detailsSectionTitle = "Fan Hardware"
    static let fanlessSectionTitle = "Cooling"
    static let fanlessTitle = "Fanless by design"
    static let fanlessReason = "This Mac cools passively. See Temperature for heat."
    static let footnote = "macOS manages fan speed automatically."
}

// MARK: - Min–Max RPM Range Bar

/// Horizontal range bar showing live fan RPM between hardware `minRPM` and `maxRPM`,
/// with a glowing position pill and optional target RPM tick.
private struct FanRPMRangeBar: View {
    let currentRPM: Int
    let minRPM: Int?
    let maxRPM: Int?
    let targetRPM: Int?
    let tint: Color

    @Environment(\.motionPolicy) private var motionPolicy
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        if let minBound = minRPM, let maxBound = maxRPM, maxBound > minBound {
            let fraction = FanMath.fraction(rpm: currentRPM, min: minBound, max: maxBound)
            let targetFraction: Double? = targetRPM.map { target in
                let span = Double(maxBound - minBound)
                return max(0.0, min(1.0, Double(target - minBound) / span))
            }

            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { proxy in
                    let width = max(1.0, proxy.size.width)
                    let trackHeight: CGFloat = 6.0
                    let fillWidth = max(trackHeight, width * CGFloat(fraction))
                    let markerX = min(max(5.0, width * CGFloat(fraction)), width - 5.0)

                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Instrument.Surface.inset)
                            .frame(height: trackHeight)
                            .overlay {
                                if colorSchemeContrast == .increased {
                                    Capsule(style: .continuous)
                                        .stroke(Color.primary.opacity(0.25), lineWidth: 0.75)
                                }
                            }

                        Capsule(style: .continuous)
                            .fill(tint.opacity(0.45))
                            .frame(width: fillWidth, height: trackHeight)

                        if let tFrac = targetFraction {
                            let tickX = min(max(1.0, width * CGFloat(tFrac)), width - 1.0)
                            RoundedRectangle(cornerRadius: 0.75, style: .continuous)
                                .fill(Color.primary.opacity(0.55))
                                .frame(width: 1.5, height: 10)
                                .position(x: tickX, y: proxy.size.height / 2.0)
                        }

                        Capsule(style: .continuous)
                            .fill(tint)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Instrument.Surface.panel, lineWidth: 1.5)
                            )
                            .shadow(
                                color: currentRPM > 0 ? tint.opacity(0.45) : .clear,
                                radius: 4,
                                x: 0,
                                y: 0
                            )
                            .position(x: markerX, y: proxy.size.height / 2.0)
                    }
                    .animation(motionPolicy.allowsEasing ? Motion.smooth : nil, value: fraction)
                }
                .frame(height: 12)

                HStack {
                    Text(Units.formatRPM(minBound))
                        .font(Instrument.Typography.micro)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let targetRPM {
                        Text("Target \(Units.formatRPM(targetRPM))")
                            .font(Instrument.Typography.micro)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }

                    Text(Units.formatRPM(maxBound))
                        .font(Instrument.Typography.micro)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fan speed range")
            .accessibilityValue("\(Units.formatRPM(currentRPM)), range \(Units.formatRPM(minBound)) to \(Units.formatRPM(maxBound))")
        } else {
            Text("Hardware bounds not exposed by SMC")
                .font(Instrument.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
struct FanPanel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FanPanel(
                initialTab: .overview,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Active Fans — Now")

            FanPanel(
                initialTab: .detail,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Active Fans — Details")

            FanPanel(
                initialTab: .history,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Fan History")
        }
        .frame(width: Instrument.Size.panelWidth)
        .background(Instrument.Surface.panel)
    }
}
#endif
