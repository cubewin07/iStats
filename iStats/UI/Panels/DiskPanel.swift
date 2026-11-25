import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Disk Instrument Panel (Task 8.5.8g / ADR 0009 / ADR 0010).
/// Features an independent-scale mirrored Read/Write hero chart from timestamped scalar buffers,
/// 14 pt SplitCapsule boot volume storage with 2-column legend, hairline throughput & IOPS table,
/// and compact capacity meters per mounted volume.
public struct DiskPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var hoveredVolumePoint: String? = nil
    @State private var derivedCache = DerivedCache()

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
        let supported = PopoverTab.supportedTabs(for: .disk)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    private var sampleWrapper: Sample<DiskSample>? {
        coordinator.latestDisk
    }

    private var sample: DiskSample? {
        sampleWrapper?.value
    }

    private var bootVolume: VolumeCapacity? {
        Self.resolveBootVolume(in: sample)
    }

    public var body: some View {
        let derived = memoizedDerivedState()
        let availability = coordinator.categoryAvailability[.disk]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            chrome: PanelChrome(
                category: .disk,
                status: derived.status,
                ribbon: derived.ribbon,
                availability: availability,
                isLoading: isLoading,
                isPaused: coordinator.isSamplingPaused,
                isLowPowerModeActive: coordinator.isLowPowerModeActive,
                isPinned: PanelController.shared.isPinned(for: .disk),
                hasBattery: coordinator.latestPower?.value.hasBattery ?? true,
                refreshInterval: preferences.refreshInterval,
                enabledCategories: preferences.enabledCategories,
                onTogglePause: {
                    coordinator.toggleSamplingPaused()
                },
                onPinToggle: {
                    PanelController.shared.togglePin(for: .disk)
                }
            ),
            glance: derived.glance,
            pages: PopoverTab.supportedTabs(for: .disk),
            selection: $selectedTab
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample, derived: derived)
            case .detail:
                volumesPage(sample: sample)
            case .history:
                HistoryPage(category: .disk, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .disk)
            }
        }
    }

    // MARK: - Memoised Derived State (B8 + B14)

    private struct CacheKey: Equatable {
        let timestamp: Date?
        let sample: DiskSample?
        let byteUnitStandard: Units.ByteUnitStandard
        let refreshInterval: TimeInterval
    }

    private struct DerivedState {
        let glance: PanelGlance
        let status: StatusLevel
        let ribbon: String?
    }

    private final class DerivedCache {
        var key: CacheKey?
        var value: DerivedState?
    }

    private func memoizedDerivedState() -> DerivedState {
        let key = CacheKey(
            timestamp: sampleWrapper?.timestamp,
            sample: sample,
            byteUnitStandard: preferences.byteUnitStandard,
            refreshInterval: preferences.refreshInterval
        )
        if let cachedKey = derivedCache.key, cachedKey == key, let cached = derivedCache.value {
            return cached
        }

        let computed = computeDerivedState(sampleWrapper: sampleWrapper)
        derivedCache.key = key
        derivedCache.value = computed
        return computed
    }

    private func computeDerivedState(sampleWrapper: Sample<DiskSample>?) -> DerivedState {
        let currentSample = sampleWrapper?.value
        let std = preferences.byteUnitStandard
        let boot = Self.resolveBootVolume(in: currentSample)

        let freeParts = Units.byteComponents(boot?.free ?? 0, standard: std)
        let headline = deriveHeadline(boot: boot, std: std)

        // B8: Read exclusively from timestamped scalar buffers (never mix diskHistory).
        let refDate = sampleWrapper?.timestamp ?? Date()
        let dualPoints = coordinator.timedDualScalarHistory(
            primary: .diskReadBytesPerSec,
            secondary: .diskWriteBytesPerSec,
            duration: 60.0,
            referenceDate: refDate
        )

        let insight = InsightEngine.best(
            series: dualPoints.map(\.primary),
            interval: preferences.refreshInterval,
            unit: .bytesPerSecond(standard: std),
            thresholds: .throughputBytesPerSec()
        )?.text

        let chartMode = LiveChartMode.mirrored(
            points: dualPoints,
            topColor: CategoryPalette.Series.diskRead,
            bottomColor: CategoryPalette.Series.diskWrite,
            topLabel: "R",
            bottomLabel: "W"
        )

        let glance = PanelGlance(
            value: freeParts.value,
            format: freeParts.format,
            unit: "\(freeParts.unit) free",
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            chartHeight: Instrument.Size.chartHeightStandard,
            scrubFormat: { Units.formatCompactRate($0, standard: std) }
        )

        let (status, ribbon) = deriveStatusAndRibbon(boot: boot)

        return DerivedState(
            glance: glance,
            status: status,
            ribbon: ribbon
        )
    }

    private static func resolveBootVolume(in sample: DiskSample?) -> VolumeCapacity? {
        guard let s = sample else { return nil }
        return s.volumes.first(where: { $0.mountPoint == "/" })
            ?? s.volumes.max(by: { $0.total < $1.total })
    }

    private func deriveHeadline(boot: VolumeCapacity?, std: Units.ByteUnitStandard) -> String {
        guard let boot, boot.total > 0 else { return "No volume information" }
        let totalStr = Units.formatBytes(boot.total, standard: std)
        let usedPct = Int(round(Double(boot.used) / Double(boot.total) * 100.0))
        return "of \(totalStr) · \(usedPct)% used"
    }

    private func deriveStatusAndRibbon(boot: VolumeCapacity?) -> (StatusLevel, String?) {
        guard let boot, boot.total > 0 else { return (.fine, nil) }
        let usedPct = Double(boot.used) / Double(boot.total) * 100.0
        let level = StatusThresholds.disk(usedPercent: usedPct)

        switch level {
        case .critical:
            return (.critical, "Disk space critically low: free up space immediately")
        case .warning:
            return (.warning, "Disk space low: \(Int(round(usedPct)))% used")
        case .elevated:
            return (.elevated, "Disk space running low: \(Int(round(usedPct)))% used")
        case .fine:
            return (.fine, nil)
        }
    }

    // MARK: - Now Page (Max 2 Sections)

    @ViewBuilder
    private func nowPage(sample: DiskSample?, derived: DerivedState) -> some View {
        if let s = sample, let boot = bootVolume {
            let std = preferences.byteUnitStandard

            VStack(alignment: .leading, spacing: Instrument.Space.sectionGap) {
                bootStorageSection(volume: boot, status: derived.status, std: std)
                throughputSection(io: s.io, std: std)
            }
        } else {
            InsetEmptyState(
                systemImage: "internaldrive",
                title: "No Disk Data",
                reason: "Disk storage and I/O metrics are currently unavailable."
            )
        }
    }

    // MARK: - Boot Volume Storage

    private struct StorageLegendItem: Identifiable {
        let id: String
        let label: String
        let bytes: UInt64
        let percent: Double
        let color: Color
    }

    private func buildStorageBreakdown(
        volume: VolumeCapacity,
        std: Units.ByteUnitStandard
    ) -> (segments: [CapsuleSegment], legendItems: [StorageLegendItem]) {
        let total = max(1.0, Double(volume.total))
        let unallocated = volume.total > (volume.used &+ volume.free)
            ? (volume.total - volume.used - volume.free)
            : 0
        let usedPct = (Double(volume.used) / total) * 100.0
        let freePct = (Double(volume.free) / total) * 100.0
        let otherPct = (Double(unallocated) / total) * 100.0

        let freeColor = Color.secondary.opacity(0.24)
        let otherColor = CategoryPalette.color(for: .disk).opacity(0.45)

        var segments: [CapsuleSegment] = [
            CapsuleSegment(
                value: Double(volume.used),
                color: CategoryPalette.color(for: .disk),
                label: "Used",
                formattedValue: "Used · \(Units.formatBytes(volume.used, standard: std)) · \(Int(round(usedPct)))%"
            )
        ]
        var legendItems: [StorageLegendItem] = [
            StorageLegendItem(
                id: "used",
                label: "Used",
                bytes: volume.used,
                percent: usedPct,
                color: CategoryPalette.color(for: .disk)
            )
        ]

        if unallocated > 0 {
            segments.append(
                CapsuleSegment(
                    value: Double(unallocated),
                    color: otherColor,
                    label: "Purgeable",
                    formattedValue: "Purgeable · \(Units.formatBytes(unallocated, standard: std)) · \(Int(round(otherPct)))%"
                )
            )
            legendItems.append(
                StorageLegendItem(
                    id: "purgeable",
                    label: "Purgeable",
                    bytes: unallocated,
                    percent: otherPct,
                    color: otherColor
                )
            )
        }

        segments.append(
            CapsuleSegment(
                value: Double(volume.free),
                color: freeColor,
                label: "Free",
                formattedValue: "Free · \(Units.formatBytes(volume.free, standard: std)) · \(Int(round(freePct)))%"
            )
        )
        legendItems.append(
            StorageLegendItem(
                id: "free",
                label: "Free",
                bytes: volume.free,
                percent: freePct,
                color: freeColor
            )
        )

        return (segments, legendItems)
    }

    @ViewBuilder
    private func bootStorageSection(
        volume: VolumeCapacity,
        status: StatusLevel,
        std: Units.ByteUnitStandard
    ) -> some View {
        let breakdown = buildStorageBreakdown(volume: volume, std: std)

        Section("\(volume.name) Storage") {
            storageHeaderTrailing(volume: volume, status: status, std: std)
        } content: {
            VStack(alignment: .leading, spacing: Instrument.Space.s) {
                SplitCapsule(
                    segments: breakdown.segments,
                    height: 14,
                    minVisibleWidth: 4,
                    gap: 1
                )

                // Structured 2-column legend: swatch · label · formatted bytes · %
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Instrument.Space.l),
                        GridItem(.flexible(), spacing: Instrument.Space.l)
                    ],
                    alignment: .leading,
                    spacing: Instrument.Space.s
                ) {
                    ForEach(breakdown.legendItems) { item in
                        storageLegendCell(item: item, std: std)
                    }
                }
                .padding(.top, Instrument.Space.xxs)
            }
        }
    }

    @ViewBuilder
    private func storageHeaderTrailing(
        volume: VolumeCapacity,
        status: StatusLevel,
        std: Units.ByteUnitStandard
    ) -> some View {
        HStack(spacing: 5) {
            if !status.isQuiet {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
            }
            Text("\(statusHealthLabel(for: status)) · \(Units.formatBytes(volume.total, standard: std))")
                .font(Instrument.Typography.caption.monospacedDigit())
                .foregroundStyle(status.isQuiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(status.color))
        }
    }

    private func statusHealthLabel(for status: StatusLevel) -> String {
        switch status {
        case .fine: return "Healthy"
        case .elevated: return "Running Low"
        case .warning: return "Low Space"
        case .critical: return "Critical"
        }
    }

    private func storageLegendCell(item: StorageLegendItem, std: Units.ByteUnitStandard) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.color)
                .frame(width: 7, height: 7)

            Text(item.label)
                .font(Instrument.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 2)

            Text(Units.formatBytes(item.bytes, standard: std, fractionDigits: 1))
                .font(Instrument.Typography.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("\(Int(round(item.percent)))%")
                .font(Instrument.Typography.micro)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Throughput

    @ViewBuilder
    private func throughputSection(
        io: DiskIO?,
        std: Units.ByteUnitStandard
    ) -> some View {
        Section("Throughput") {
            if let io {
                VStack(spacing: 0) {
                    MetricRow(
                        label: "Read",
                        valueText: Self.throughputText(bytesPerSec: io.bytesReadPerSec, opsPerSec: io.readOpsPerSec, standard: std),
                        showHairline: true
                    )
                    MetricRow(
                        label: "Write",
                        valueText: Self.throughputText(bytesPerSec: io.bytesWrittenPerSec, opsPerSec: io.writeOpsPerSec, standard: std),
                        showHairline: false
                    )
                }
            } else {
                MetricRow(
                    label: "Disk I/O Counters",
                    valueText: "Unavailable",
                    showHairline: false
                )
            }
        }
    }

    /// "14.5 MB/s · 240 IOPS": rate and operations together, the chart owns the history.
    static func throughputText(bytesPerSec: Double, opsPerSec: Double, standard: Units.ByteUnitStandard) -> String {
        "\(Units.formatCompactRate(bytesPerSec, standard: standard)) · \(formatIOPS(opsPerSec)) IOPS"
    }

    private static func formatIOPS(_ value: Double) -> String {
        let count = max(0, Int(round(value)))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    // MARK: - Details Page (Mounted Volumes)

    @ViewBuilder
    private func volumesPage(sample: DiskSample?) -> some View {
        if let s = sample, !s.volumes.isEmpty {
            let std = preferences.byteUnitStandard
            let boot = bootVolume
            let others = s.volumes.filter { $0.mountPoint != boot?.mountPoint }

            Section("Volumes") {
                Text("\(s.volumes.count)")
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } content: {
                VStack(spacing: 0) {
                    if let boot {
                        bootCompactRow(vol: boot, std: std)
                            .padding(.bottom, others.isEmpty ? 0 : Instrument.Space.m)
                        if !others.isEmpty {
                            Rectangle()
                                .fill(Instrument.Surface.hairline)
                                .frame(height: 0.5)
                        }
                    }
                    if others.count > Self.maxVisibleVolumeRows {
                        ScrollView {
                            otherVolumesList(others, std: std)
                        }
                        .frame(maxHeight: Self.volumeListMaxHeight)
                    } else {
                        otherVolumesList(others, std: std)
                    }
                }
            }
        } else {
            InsetEmptyState(
                systemImage: "internaldrive",
                title: "No Volumes Mounted",
                reason: "No mounted file system volumes detected."
            )
        }
    }

    private static let maxVisibleVolumeRows = 4
    private static let volumeListMaxHeight: CGFloat = 4 * 80

    @ViewBuilder
    private func otherVolumesList(_ volumes: [VolumeCapacity], std: Units.ByteUnitStandard) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(volumes.enumerated()), id: \.element.mountPoint) { index, vol in
                volumeRow(vol: vol, std: std)
                    .padding(.vertical, Instrument.Space.m)

                if index < volumes.count - 1 {
                    Rectangle()
                        .fill(Instrument.Surface.hairline)
                        .frame(height: 0.5)
                }
            }
        }
    }

    /// Boot volume as one compact row: capacity already has its card on Now.
    @ViewBuilder
    private func bootCompactRow(vol: VolumeCapacity, std: Units.ByteUnitStandard) -> some View {
        HStack(spacing: Instrument.Space.s) {
            Image(systemName: CategoryIdentity(.disk).liveSymbol(LiveSymbolState(isExternalVolume: false)))
                .font(Instrument.Typography.icon(Instrument.Icon.regular, weight: .medium))
                .foregroundColor(CategoryPalette.color(for: .disk))
            Text(vol.name)
                .font(Instrument.Typography.body.weight(.medium))
                .lineLimit(1)
            Text("Boot")
                .font(Instrument.Typography.micro)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Instrument.Space.s)
                .padding(.vertical, Instrument.Space.xxs)
                .background(Capsule(style: .continuous).fill(Instrument.Surface.inset))
            Spacer(minLength: Instrument.Space.xs)
            Text(Units.formatBytes(vol.total, standard: std, fractionDigits: 1))
                .font(Instrument.Typography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func volumeRow(vol: VolumeCapacity, std: Units.ByteUnitStandard) -> some View {
        let isHovered = (hoveredVolumePoint == vol.mountPoint)
        let isBoot = (vol.mountPoint == "/")
        let total = max(1.0, Double(vol.total))
        let usedFraction = min(1.0, max(0.0, Double(vol.used) / total))
        let usedPct = usedFraction * 100.0
        let volStatus = StatusThresholds.disk(usedPercent: usedPct)
        let meterTint = volStatus.isQuiet ? CategoryPalette.color(for: .disk) : volStatus.color

        VStack(alignment: .leading, spacing: Instrument.Space.s) {
            // Header: icon + mount name + role badge + Finder button / % used
            HStack(spacing: Instrument.Space.s) {
                Image(systemName: isBoot ? "internaldrive.fill" : "externaldrive.fill")
                    .font(Instrument.Typography.icon(Instrument.Icon.regular, weight: .medium))
                    .foregroundColor(CategoryPalette.color(for: .disk))

                Text(vol.name)
                    .font(Instrument.Typography.body.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(isBoot ? "Boot" : "External")
                    .font(Instrument.Typography.micro)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Instrument.Surface.inset)
                    )

                Spacer(minLength: 4)

                if !isBoot && isHovered {
                    Button {
                        let url = URL(fileURLWithPath: vol.mountPoint)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(Instrument.Typography.icon(Instrument.Icon.regular))
                            .foregroundColor(CategoryPalette.color(for: .disk))
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }

                Text("\(Int(round(usedPct)))% used")
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Thin 6 pt capacity Meter
            Meter(
                progress: usedFraction,
                height: .small,
                tint: meterTint
            )

            // Tabular Used / Available / Total summary
            HStack(spacing: Instrument.Space.m) {
                volumeCapacityStat(label: "Used", value: Units.formatBytes(vol.used, standard: std, fractionDigits: 1))
                Spacer(minLength: 4)
                volumeCapacityStat(label: "Available", value: Units.formatBytes(vol.free, standard: std, fractionDigits: 1))
                Spacer(minLength: 4)
                volumeCapacityStat(label: "Total", value: Units.formatBytes(vol.total, standard: std, fractionDigits: 1))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredVolumePoint = hovering ? vol.mountPoint : nil
        }
    }

    private func volumeCapacityStat(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Instrument.Typography.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(Instrument.Typography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

// MARK: - Previews

#if DEBUG
struct DiskPanel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Single Volume
            DiskPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: DiskSample(
                        volumes: [
                            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 494_000_000_000, used: 280_000_000_000, free: 214_000_000_000)
                        ],
                        io: DiskIO(bytesReadPerSec: 14_500_000, bytesWrittenPerSec: 2_100_000, readOpsPerSec: 240, writeOpsPerSec: 85)
                    )
                )
            )
            .previewDisplayName("Single Volume")

            // Multiple Volumes incl. External
            DiskPanel(
                initialTab: .detail,
                coordinator: makeMockCoordinator(
                    sample: DiskSample(
                        volumes: [
                            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 494_000_000_000, used: 280_000_000_000, free: 214_000_000_000),
                            VolumeCapacity(name: "SanDisk SSD", mountPoint: "/Volumes/SanDisk SSD", total: 1_000_000_000_000, used: 450_000_000_000, free: 550_000_000_000)
                        ],
                        io: DiskIO(bytesReadPerSec: 80_000_000, bytesWrittenPerSec: 45_000_000, readOpsPerSec: 1200, writeOpsPerSec: 650)
                    )
                )
            )
            .previewDisplayName("Multiple Volumes")

            // Low Free Space
            DiskPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: DiskSample(
                        volumes: [
                            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 475_000_000_000, free: 25_000_000_000)
                        ],
                        io: DiskIO(bytesReadPerSec: 1_000_000, bytesWrittenPerSec: 500_000, readOpsPerSec: 10, writeOpsPerSec: 5)
                    )
                )
            )
            .previewDisplayName("Low Free Space")

            // No I/O Data
            DiskPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: DiskSample(
                        volumes: [
                            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 200_000_000_000, free: 300_000_000_000)
                        ],
                        io: nil
                    )
                )
            )
            .previewDisplayName("No I/O Data")
        }
        .padding()
        .background(Color.black)
    }

    private static func makeMockCoordinator(sample: DiskSample) -> MetricsCoordinator {
        let suiteName = "iStats.Preview.Disk.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let prefs = PreferencesStore(userDefaults: defaults)
        let coordinator = MetricsCoordinator(preferencesStore: prefs)
        coordinator.handleReading(.disk(Sample(value: sample)))
        return coordinator
    }
}
#endif
