import SwiftUI
import AppKit
import iStatsCore

/// Dedicated GPU Instrument Panel (Task 8.8c / ADR 0009 / Blueprint §6.3).
/// Features the signature Engine Rings, VRAM working set meter, driver recovery status, and hardware facts.
public struct GPUPanel: View {
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
        let supported = PopoverTab.supportedTabs(for: .gpu)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    private var hasDetailedEngines: Bool {
        let sample = coordinator.latestGPU?.value
        return sample?.rendererUtilization != nil || sample?.tilerUtilization != nil
    }

    public var body: some View {
        let sample = coordinator.latestGPU?.value
        let glance = deriveGlance(sample: sample)
        let availability = coordinator.categoryAvailability[.gpu]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)
        let status = deriveStatus(sample: sample)
        let ribbon = deriveRibbon(sample: sample)

        PanelScaffold(
            category: .gpu,
            glance: glance,
            status: status,
            ribbon: ribbon,
            pages: PopoverTab.supportedTabs(for: .gpu),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: .gpu)
            },
            isPinned: PanelController.shared.isPinned(for: .gpu)
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample)
            case .detail:
                detailPage(sample: sample)
            case .history:
                HistoryPage(category: .gpu, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .gpu)
            }
        }
    }

    // MARK: - Glance Derivation

    private func deriveGlance(sample: GPUSample?) -> PanelGlance {
        let util = sample?.utilization ?? 0.0
        let headline = PanelHeadline.gpu(sample: sample)
        let utilHistory = coordinator.scalarHistory(for: .gpuUtilization, duration: 60)
        let insight = InsightEngine.insights(series: utilHistory, interval: 1.0, unit: .percent).first?.text
        let chartMode = LiveChartMode.single(
            values: utilHistory,
            color: CategoryPalette.tint(for: .gpu),
            deepColor: CategoryPalette.tintDeep(for: .gpu),
            fixedMax: 100.0
        )
        return PanelGlance(
            value: util,
            format: "%.0f",
            unit: "%",
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            scrubFormat: { String(format: "%.0f%%", $0) }
        )
    }

    private func deriveStatus(sample: GPUSample?) -> StatusLevel {
        if let recoveries = sample?.recoveryCount, recoveries > 0 {
            return .warning
        }
        let util = sample?.utilization ?? 0.0
        if util >= 95.0 {
            return .critical
        } else if util >= 80.0 {
            return .elevated
        }
        return .fine
    }

    private func deriveRibbon(sample: GPUSample?) -> String? {
        if let recoveries = sample?.recoveryCount, recoveries > 0 {
            return "Driver recovery event: \(recoveries) GPU reset\(recoveries > 1 ? "s" : "") detected."
        }
        return nil
    }

    // MARK: - Now Page (Overview)

    @ViewBuilder
    private func nowPage(sample: GPUSample?) -> some View {
        if let s = sample {
            VStack(alignment: .leading, spacing: Instrument.Space.l) {
                engineActivityModule(sample: s)

                if let allocated = s.allocatedMemory, let maxMem = s.recommendedMaxMemory, maxMem > 0 {
                    vramWorkingSetModule(allocated: allocated, maxMem: maxMem)
                } else if let memUsed = s.memoryUsed {
                    graphicsWorkingSetModule(memUsed: memUsed)
                }

                if s.powerWatts != nil || s.tempCelsius != nil {
                    subsystemTelemetryModule(sample: s)
                }
            }
        }
    }

    @ViewBuilder
    private func engineActivityModule(sample: GPUSample) -> some View {
        let util = sample.utilization ?? 0.0
        let rings = buildRings(sample: sample)

        Module(eyebrow: "Engine Activity") {
            HStack(spacing: Instrument.Space.l) {
                RingStack(
                    rings: rings,
                    size: 76,
                    ringWidth: 6,
                    ringGap: 3.5
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(CategoryPalette.tint(for: .gpu))
                            .frame(width: 8, height: 8)
                        Text("Device")
                            .font(Instrument.Typography.caption)
                            .foregroundColor(Color.secondary)
                        Spacer()
                        LiveNumber(value: util, format: { String(format: "%.0f%%", $0) })
                            .font(Instrument.Typography.value)
                            .foregroundColor(Color.primary)
                    }

                    if let renderer = sample.rendererUtilization {
                        HStack {
                            Circle()
                                .fill(CategoryPalette.tint(for: .gpu).opacity(0.8))
                                .frame(width: 8, height: 8)
                            Text("Renderer")
                                .font(Instrument.Typography.caption)
                                .foregroundColor(Color.secondary)
                            Spacer()
                            LiveNumber(value: renderer, format: { String(format: "%.0f%%", $0) })
                                .font(Instrument.Typography.value)
                                .foregroundColor(Color.primary)
                        }
                    }

                    if let tiler = sample.tilerUtilization {
                        HStack {
                            Circle()
                                .fill(CategoryPalette.tint(for: .gpu).opacity(0.55))
                                .frame(width: 8, height: 8)
                            Text("Tiler")
                                .font(Instrument.Typography.caption)
                                .foregroundColor(Color.secondary)
                            Spacer()
                            LiveNumber(value: tiler, format: { String(format: "%.0f%%", $0) })
                                .font(Instrument.Typography.value)
                                .foregroundColor(Color.primary)
                        }
                    }

                    if !hasDetailedEngines {
                        Text("Engine breakdown not exposed by this GPU")
                            .font(Instrument.Typography.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
            }
        }
    }

    private func vramWorkingSetModule(allocated: UInt64, maxMem: UInt64) -> some View {
        let ratio = maxMem > 0 ? (Double(allocated) / Double(maxMem)) : 0.0
        let formattedAlloc = Units.formatBytes(allocated, standard: preferences.byteUnitStandard)
        let formattedMax = Units.formatBytes(maxMem, standard: preferences.byteUnitStandard)

        let vramTint = ratio > 0.90 ? CategoryPalette.statusColor(for: .critical) : (ratio > 0.75 ? CategoryPalette.statusColor(for: .elevated) : CategoryPalette.tint(for: .gpu))

        return Module(eyebrow: "VRAM Working Set") {
            HStack {
                Text("\(formattedAlloc) / \(formattedMax)")
                    .font(Instrument.Typography.caption)
                    .foregroundColor(Color.secondary)
                Spacer()
            }
            Meter(
                progress: ratio,
                height: .medium,
                tint: vramTint,
                deepTint: ratio > 0.75 ? nil : CategoryPalette.tintDeep(for: .gpu)
            )
        }
    }

    @ViewBuilder
    private func graphicsWorkingSetModule(memUsed: UInt64) -> some View {
        Module(eyebrow: "Graphics Working Set") {
            MetricRow(
                label: "Allocated Memory",
                valueText: Units.formatBytes(memUsed, standard: preferences.byteUnitStandard)
            )
        }
    }

    @ViewBuilder
    private func subsystemTelemetryModule(sample: GPUSample) -> some View {
        Module(eyebrow: "Subsystem Telemetry") {
            VStack(spacing: 8) {
                if let watts = sample.powerWatts {
                    MetricRow(
                        label: "Power Consumption",
                        valueText: String(format: "%.1f W", watts)
                    )
                }
                if let temp = sample.tempCelsius {
                    MetricRow(
                        label: "Die Temperature",
                        valueText: Units.formatTemperature(temp, unit: preferences.temperatureUnit, fractionDigits: 1)
                    )
                }
            }
        }
    }

    private func buildRings(sample: GPUSample) -> [RingData] {
        let utilFraction = (sample.utilization ?? 0.0) / 100.0
        var rings: [RingData] = [
            RingData(
                id: "gpu.device",
                fraction: utilFraction,
                color: CategoryPalette.tint(for: .gpu),
                label: "Device"
            )
        ]

        if let renderer = sample.rendererUtilization {
            rings.append(
                RingData(
                    id: "gpu.renderer",
                    fraction: renderer / 100.0,
                    color: CategoryPalette.tint(for: .gpu).opacity(0.8),
                    label: "Renderer"
                )
            )
        }

        if let tiler = sample.tilerUtilization {
            rings.append(
                RingData(
                    id: "gpu.tiler",
                    fraction: tiler / 100.0,
                    color: CategoryPalette.tint(for: .gpu).opacity(0.55),
                    label: "Tiler"
                )
            )
        }

        return rings
    }

    // MARK: - Detail Page (Engines / Device)

    @ViewBuilder
    private func detailPage(sample: GPUSample?) -> some View {
        if let s = sample {
            VStack(alignment: .leading, spacing: Instrument.Space.l) {
                engineBreakdownModule(sample: s)
                hardwareArchitectureModule(sample: s)
            }
        }
    }

    @ViewBuilder
    private func engineBreakdownModule(sample: GPUSample) -> some View {
        let util = sample.utilization ?? 0.0
        let enginesTitle = PopoverTab.detail.title(for: .gpu, hasDetailedGPUEngines: hasDetailedEngines)

        Module(eyebrow: "\(enginesTitle) Breakdown") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    MetricRow(label: "Device Utilization", valueText: String(format: "%.0f", util), unit: "%")
                    Meter(
                        progress: util / 100.0,
                        height: .medium,
                        tint: CategoryPalette.tint(for: .gpu)
                    )
                }

                if let renderer = sample.rendererUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        MetricRow(label: "3D Renderer Engine", valueText: String(format: "%.0f", renderer), unit: "%")
                        Meter(
                            progress: renderer / 100.0,
                            height: .medium,
                            tint: CategoryPalette.tint(for: .gpu).opacity(0.85)
                        )
                    }
                }

                if let tiler = sample.tilerUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        MetricRow(label: "Geometry / Tiler Engine", valueText: String(format: "%.0f", tiler), unit: "%")
                        Meter(
                            progress: tiler / 100.0,
                            height: .medium,
                            tint: CategoryPalette.tint(for: .gpu).opacity(0.65)
                        )
                    }
                }

                if !hasDetailedEngines {
                    Text("Per-engine hardware telemetry is synthesized via IOKit on this architecture.")
                        .font(Instrument.Typography.caption)
                        .foregroundColor(Color.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func hardwareArchitectureModule(sample: GPUSample) -> some View {
        Module(eyebrow: "Device Architecture") {
            VStack(spacing: 8) {
                if let deviceName = sample.deviceName, !deviceName.isEmpty {
                    MetricRow(label: "Metal Device", valueText: deviceName)
                }
                if let coreCount = sample.coreCount {
                    MetricRow(label: "GPU Cores", valueText: "\(coreCount) Cores")
                }
                if let unified = sample.isUnifiedMemory {
                    MetricRow(label: "Memory Architecture", valueText: unified ? "Unified Memory" : "Discrete VRAM")
                }
                if let metal = sample.metalFeatureSet, !metal.isEmpty {
                    MetricRow(label: "Metal Architecture", valueText: metal)
                }
                if let ray = sample.supportsRaytracing {
                    MetricRow(label: "Hardware Ray Tracing", valueText: ray ? "Supported" : "Not Supported")
                }
                if let displays = sample.displayDescriptions, !displays.isEmpty {
                    MetricRow(label: "Connected Displays", valueText: displays.joined(separator: ", "))
                }
            }
        }
    }


}

#if DEBUG
struct GPUPanel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Full engines preview
            GPUPanel(
                initialTab: .overview,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Full Engines")

            // Device only preview
            GPUPanel(
                initialTab: .detail,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Device Only")
        }
        .frame(width: 320)
        .background(Instrument.Surface.panel)
    }
}
#endif
