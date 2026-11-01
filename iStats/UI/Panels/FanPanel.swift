import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Fans Instrument Panel (Task 8.8e / ADR 0009 / Blueprint §6.5).
/// Features the signature rotating TurbineView, ArcGauge dials per fan,
/// read-only telemetry per ADR 0004, and a dedicated InsetEmptyState for fanless Macs.
public struct FanPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab

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
        let supported = PopoverTab.supportedTabs(for: .fan)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    private var sample: FanSample? {
        coordinator.latestFan?.value
    }

    private var isFanless: Bool {
        sample?.isFanless == true || (sample != nil && sample!.fans.isEmpty)
    }

    public var body: some View {
        let glance = deriveGlance(sample: sample)
        let availability = coordinator.categoryAvailability[.fan]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            category: .fan,
            glance: glance,
            status: .fine,
            ribbon: nil,
            pages: PopoverTab.supportedTabs(for: .fan),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin()
            },
            isPinned: PanelController.shared.activePanel?.isPinned ?? false
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample)
            case .detail:
                nowPage(sample: sample)
            case .history:
                historyPage(sample: sample)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .fan)
            }
        }
    }

    // MARK: - Glance Derivation

    private func deriveGlance(sample: FanSample?) -> PanelGlance {
        let maxRPM = sample?.fans.map(\.rpm).max() ?? 0
        let headline = PanelHeadline.fan(sample: sample)

        let rpmHistory = coordinator.scalarHistory(for: .fanMaxRPM, duration: 60)
        let insight = isFanless ? "Passive silent cooling" : InsightEngine.insights(series: rpmHistory, interval: 1.0, unit: .rpm).first?.text

        let chartMode: LiveChartMode? = isFanless ? nil : .single(
            values: rpmHistory,
            color: CategoryPalette.tint(for: .fan),
            deepColor: CategoryPalette.tintDeep(for: .fan)
        )

        return PanelGlance(
            value: isFanless ? 0.0 : Double(maxRPM),
            format: "%.0f",
            unit: isFanless ? "—" : "rpm",
            headline: headline,
            insight: insight,
            chartMode: chartMode
        )
    }

    // MARK: - Now Page (Turbine & Fanless State)

    @ViewBuilder
    private func nowPage(sample: FanSample?) -> some View {
        if isFanless {
            fanlessModule
        } else if let s = sample, !s.fans.isEmpty {
            VStack(alignment: .leading, spacing: Instrument.Space.l) {
                ForEach(Array(s.fans.enumerated()), id: \.element.name) { index, fan in
                    fanRowModule(fan: fan, index: index)
                }

                Module(eyebrow: "Acoustics & Control") {
                    MetricRow(
                        label: "Safety Policy",
                        valueText: "Read-only (ADR 0004)"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var fanlessModule: some View {
        Module(eyebrow: "Cooling Architecture") {
            InsetEmptyState(
                systemImage: "wind",
                title: "Fanless by design",
                reason: "This Mac cools passively. See Temperature for heat."
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
    private func fanRowModule(fan: FanReading, index: Int) -> some View {
        let title = fan.name.isEmpty ? "Fan \(index + 1)" : fan.name

        Module(eyebrow: title.uppercased()) {
            HStack(spacing: Instrument.Space.l) {
                // Signature: Rotating Turbine
                TurbineView(
                    rpm: fan.rpm,
                    minRPM: fan.minRPM,
                    maxRPM: fan.maxRPM,
                    size: 64,
                    isPaused: coordinator.isSamplingPaused
                )

                // Dial and telemetry details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        LiveNumber(
                            value: Double(fan.rpm),
                            format: { Units.formatRPM(Int($0)) }
                        )
                        .font(Instrument.Typography.displayCompact)
                        .foregroundColor(Color.primary)

                        Spacer()

                        if let minBound = fan.minRPM, let maxBound = fan.maxRPM, maxBound > minBound {
                            ArcGauge(
                                value: Double(fan.rpm),
                                range: Double(minBound)...Double(maxBound),
                                sweep: 180,
                                startAngle: 180,
                                tint: CategoryPalette.tint(for: .fan),
                                size: 54
                            )
                        }
                    }

                    if let minBound = fan.minRPM, let maxBound = fan.maxRPM {
                        Text("Bounds: \(Units.formatRPM(minBound)) – \(Units.formatRPM(maxBound))")
                            .font(Instrument.Typography.caption)
                            .foregroundColor(Color.secondary)
                    } else {
                        Text("Hardware limits not exposed by SMC")
                            .font(Instrument.Typography.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
            }
        }
    }

    // MARK: - History Page

    @ViewBuilder
    private func historyPage(sample: FanSample?) -> some View {
        Module(eyebrow: "Extended Fan Trends") {
            VStack(alignment: .leading, spacing: 8) {
                MetricRow(
                    label: "Sampling Window",
                    valueText: "Active 60s Buffer"
                )
                if let peak = coordinator.scalarHistory(for: .fanMaxRPM, duration: 60).max() {
                    MetricRow(
                        label: "Peak Fan Speed",
                        valueText: Units.formatRPM(Int(peak))
                    )
                }
            }
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
            .previewDisplayName("Active Fans")

            FanPanel(
                initialTab: .history,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Fan History")
        }
        .frame(width: 352)
        .background(Instrument.Surface.panel)
    }
}
#endif
