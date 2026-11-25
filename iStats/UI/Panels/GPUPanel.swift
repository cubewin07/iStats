import SwiftUI
import AppKit
import iStatsCore

/// Dedicated GPU Instrument Panel (Task 8.5.8c / ADR 0009 / ADR 0010).
/// Features the Engine Activity RingStack + tabular bars, consolidated Memory & Telemetry,
/// Engine Breakdown, and Device Architecture spec sheet.
public struct GPUPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var derivedMemo = DerivedMemo()

    private struct MemoKey: Equatable {
        let sampleTimestamp: Date?
        let hasSample: Bool
        let refreshInterval: Double
    }

    private struct DerivedState {
        let glance: PanelGlance
        let status: StatusLevel
        let ribbon: String?
        let rings: [RingData]
    }

    private final class DerivedMemo {
        var key: MemoKey?
        var state: DerivedState?
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
        let supported = PopoverTab.supportedTabs(for: .gpu)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    private var hasDetailedEngines: Bool {
        let sample = coordinator.latestGPU?.value
        return sample?.rendererUtilization != nil || sample?.tilerUtilization != nil
    }

    public var body: some View {
        let sampleWrapper = coordinator.latestGPU
        let sample = sampleWrapper?.value
        let derived = resolveDerivedState(sampleWrapper: sampleWrapper)
        let availability = coordinator.categoryAvailability[.gpu]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            chrome: PanelChrome(
                category: .gpu,
                status: derived.status,
                ribbon: derived.ribbon,
                availability: availability,
                isLoading: isLoading,
                isPaused: coordinator.isSamplingPaused,
                isLowPowerModeActive: coordinator.isLowPowerModeActive,
                isPinned: PanelController.shared.isPinned(for: .gpu),
                hasBattery: coordinator.latestPower?.value.hasBattery ?? true,
                refreshInterval: preferences.refreshInterval,
                enabledCategories: preferences.enabledCategories,
                onTogglePause: {
                    coordinator.toggleSamplingPaused()
                },
                onPinToggle: {
                    PanelController.shared.togglePin(for: .gpu)
                }
            ),
            glance: derived.glance,
            pages: PopoverTab.supportedTabs(for: .gpu),
            selection: $selectedTab
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample, rings: derived.rings)
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

    // MARK: - Memoised Glance & State Derivation (B8 + B14)

    private func resolveDerivedState(sampleWrapper: Sample<GPUSample>?) -> DerivedState {
        let key = MemoKey(
            sampleTimestamp: sampleWrapper?.timestamp,
            hasSample: sampleWrapper != nil,
            refreshInterval: preferences.refreshInterval
        )
        if derivedMemo.key == key, let cached = derivedMemo.state {
            return cached
        }

        let sample = sampleWrapper?.value
        let referenceDate = sampleWrapper?.timestamp ?? Date()
        let glance = deriveGlance(sample: sample, referenceDate: referenceDate)
        let status = deriveStatus(sample: sample)
        let ribbon = deriveRibbon(sample: sample)
        let rings = sample.map(buildRings(sample:)) ?? []

        let state = DerivedState(
            glance: glance,
            status: status,
            ribbon: ribbon,
            rings: rings
        )
        derivedMemo.key = key
        derivedMemo.state = state
        return state
    }

    private func deriveGlance(sample: GPUSample?, referenceDate: Date) -> PanelGlance {
        let util = sample?.utilization ?? 0.0
        let headline = GPUPageContent.headline(sample: sample)
        let utilPoints = coordinator.timedScalarHistory(
            for: .gpuUtilization,
            duration: 60,
            referenceDate: referenceDate
        )
        let insight = InsightEngine.insights(
            series: utilPoints.map(\.value),
            interval: preferences.refreshInterval,
            unit: .percent
        ).first?.text
        let chartMode = LiveChartMode.single(
            points: utilPoints,
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
        StatusThresholds.gpuPanel(
            utilizationPercent: sample?.utilization ?? 0.0,
            recoveryCount: sample?.recoveryCount ?? 0
        )
    }

    private func deriveRibbon(sample: GPUSample?) -> String? {
        if let recoveries = sample?.recoveryCount, recoveries > 0 {
            return "Driver recovery event: \(recoveries) GPU reset\(recoveries > 1 ? "s" : "") detected."
        }
        return nil
    }

    // MARK: - Now Page (Engine Activity only; telemetry lives on Details)

    @ViewBuilder
    private func nowPage(sample: GPUSample?, rings: [RingData]) -> some View {
        if let s = sample {
            VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
                engineActivitySection(sample: s, rings: rings)
            }
        }
    }

    private func hasMemoryTelemetrySection(sample: GPUSample) -> Bool {
        let hasVRAM = (sample.allocatedMemory != nil && (sample.recommendedMaxMemory ?? 0) > 0)
        return hasVRAM || sample.memoryUsed != nil || sample.powerWatts != nil || sample.tempCelsius != nil
    }

    private func engineActivitySection(sample: GPUSample, rings: [RingData]) -> some View {
        let util = sample.utilization ?? 0.0

        return Section(
            "Engine Activity",
            trailing: {
                if let coreCount = sample.coreCount, coreCount > 0 {
                    Text("\(coreCount) cores")
                        .font(Instrument.Typography.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        ) {
            HStack(alignment: .center, spacing: Instrument.Space.l) {
                RingStack(
                    rings: rings,
                    size: 92,
                    ringWidth: 7,
                    ringGap: 4
                )

                VStack(alignment: .leading, spacing: Instrument.Space.m) {
                    engineLegendRow(
                        label: "Device",
                        value: util,
                        color: CategoryPalette.tint(for: .gpu)
                    )

                    if let renderer = sample.rendererUtilization {
                        engineLegendRow(
                            label: "Renderer",
                            value: renderer,
                            color: CategoryPalette.tintDeep(for: .gpu)
                        )
                    }

                    if let tiler = sample.tilerUtilization {
                        engineLegendRow(
                            label: "Tiler",
                            value: tiler,
                            color: CategoryPalette.tint(for: .gpu).opacity(0.55)
                        )
                    }

                    if !hasDetailedEngines {
                        Text("Engine breakdown not exposed by this GPU")
                            .font(Instrument.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func engineLegendRow(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: Instrument.Space.s) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(label)
                .font(Instrument.Typography.body)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
                .lineLimit(1)

            Meter(
                progress: value / 100.0,
                height: .small,
                tint: color,
                interval: preferences.refreshInterval
            )

            LiveNumber(
                value: value,
                format: { String(format: "%.0f%%", $0) },
                font: Instrument.Typography.value
            )
            .foregroundStyle(.primary)
            .frame(width: 36, alignment: .trailing)
        }
    }

    private func memoryAndTelemetrySection(sample: GPUSample) -> some View {
        let hasPower = sample.powerWatts != nil
        let hasTemp = sample.tempCelsius != nil
        let hasTelemetry = hasPower || hasTemp

        return Section("Memory & Telemetry") {
            VStack(spacing: 0) {
                if let allocated = sample.allocatedMemory, let maxMem = sample.recommendedMaxMemory, maxMem > 0 {
                    let ratio = Double(allocated) / Double(maxMem)
                    let formattedAlloc = Units.formatBytes(allocated, standard: preferences.byteUnitStandard)
                    let formattedMax = Units.formatBytes(maxMem, standard: preferences.byteUnitStandard)
                    let vramLevel = StatusThresholds.gpuMemory(allocatedRatio: ratio)
                    let vramTint = vramLevel == .fine
                        ? CategoryPalette.tint(for: .gpu)
                        : CategoryPalette.statusColor(for: vramLevel)

                    VStack(alignment: .leading, spacing: Instrument.Space.s) {
                        HStack {
                            Text("VRAM Working Set")
                                .font(Instrument.Typography.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(formattedAlloc) / \(formattedMax)")
                                .font(Instrument.Typography.value)
                                .foregroundStyle(.primary)
                        }
                        Meter(
                            progress: ratio,
                            height: .medium,
                            tint: vramTint,
                            deepTint: ratio > 0.75 ? nil : CategoryPalette.tintDeep(for: .gpu),
                            interval: preferences.refreshInterval
                        )
                    }
                    .padding(.horizontal, Instrument.Space.xs)
                    .padding(.vertical, Instrument.Space.s)
                    .overlay(alignment: .bottom) {
                        if hasTelemetry {
                            Rectangle()
                                .fill(Instrument.Surface.hairline)
                                .frame(height: 0.5)
                        }
                    }
                } else if let memUsed = sample.memoryUsed {
                    MetricRow(
                        label: "Allocated Memory",
                        valueText: Units.formatBytes(memUsed, standard: preferences.byteUnitStandard),
                        showHairline: hasTelemetry
                    )
                }

                if let watts = sample.powerWatts {
                    MetricRow(
                        label: "Power Consumption",
                        valueText: String(format: "%.1f", watts),
                        unit: "W",
                        showHairline: hasTemp
                    )
                }

                if let temp = sample.tempCelsius {
                    MetricRow(
                        label: "Die Temperature",
                        valueText: Units.formatTemperature(temp, unit: preferences.temperatureUnit, fractionDigits: 1),
                        showHairline: false
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
                    color: CategoryPalette.tintDeep(for: .gpu),
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

    // MARK: - Detail Page (Telemetry + Device Architecture)

    @ViewBuilder
    private func detailPage(sample: GPUSample?) -> some View {
        if let s = sample {
            let specs = architectureSpecRows(sample: s)

            VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
                if hasMemoryTelemetrySection(sample: s) {
                    memoryAndTelemetrySection(sample: s)
                }

                if !specs.isEmpty {
                    deviceArchitectureSection(rows: specs)
                }
            }
        }
    }

    private struct ArchitectureSpecRow: Identifiable {
        let id: String
        let label: String
        let value: String
        let isCopyable: Bool
    }

    private func architectureSpecRows(sample: GPUSample) -> [ArchitectureSpecRow] {
        var rows: [ArchitectureSpecRow] = []

        if let deviceName = sample.deviceName, !deviceName.isEmpty {
            rows.append(ArchitectureSpecRow(
                id: "metalDevice",
                label: "Metal Device",
                value: deviceName,
                isCopyable: true
            ))
        }
        if let coreCount = sample.coreCount {
            rows.append(ArchitectureSpecRow(
                id: "gpuCores",
                label: "GPU Cores",
                value: "\(coreCount) Cores",
                isCopyable: false
            ))
        }
        if let unified = sample.isUnifiedMemory {
            rows.append(ArchitectureSpecRow(
                id: "memoryArch",
                label: "Memory Architecture",
                value: unified ? "Unified Memory" : "Discrete VRAM",
                isCopyable: false
            ))
        }
        if let metal = sample.metalFeatureSet, !metal.isEmpty {
            rows.append(ArchitectureSpecRow(
                id: "metalFamily",
                label: "Metal Family",
                value: metal,
                isCopyable: false
            ))
        }
        if let ray = sample.supportsRaytracing {
            rows.append(ArchitectureSpecRow(
                id: "rayTracing",
                label: "Hardware Ray Tracing",
                value: ray ? "Supported" : "Not Supported",
                isCopyable: false
            ))
        }
        if let displays = sample.displayDescriptions, !displays.isEmpty {
            rows.append(ArchitectureSpecRow(
                id: "displays",
                label: "Connected Displays",
                value: displays.joined(separator: ", "),
                isCopyable: true
            ))
        }

        return rows
    }

    private func deviceArchitectureSection(rows: [ArchitectureSpecRow]) -> some View {
        Section("Device Architecture") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    MetricRow(
                        label: row.label,
                        valueText: row.value,
                        isCopyable: row.isCopyable,
                        showHairline: index < rows.count - 1
                    )
                }
            }
        }
    }
}

/// Pure content rules for the GPU panel (Task 9.5), kept testable without rendering.
enum GPUPageContent {
    /// State word only: utilization is the hero and die temperature sits on Details.
    static func headline(sample: GPUSample?) -> String {
        guard let sample else { return "GPU telemetry unavailable" }
        let util = sample.utilization ?? 0.0
        if util >= 80.0 { return "Heavy GPU load" }
        if util >= 25.0 { return "Active" }
        return "Idle"
    }
}

#if DEBUG
struct GPUPanel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GPUPanel(
                initialTab: .overview,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Full Engines")

            GPUPanel(
                initialTab: .detail,
                coordinator: .shared,
                preferences: .shared
            )
            .previewDisplayName("Device Only")
        }
        .frame(width: 352)
        .background(Instrument.Surface.panel)
    }
}
#endif
