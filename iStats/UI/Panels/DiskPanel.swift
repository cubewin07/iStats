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
            category: .disk,
            glance: derived.glance,
            status: derived.status,
            ribbon: derived.ribbon,
            pages: PopoverTab.supportedTabs(for: .disk),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: .disk)
            },
            isPinned: PanelController.shared.isPinned(for: .disk)
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
        let readSeries: [Double]
        let writeSeries: [Double]
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

        let (displayVal, displayUnit, formatStr) = formatFreeSpace(boot?.free ?? 0, standard: std)
        let headline = deriveHeadline(boot: boot, std: std)

        // B8: Read exclusively from timestamped scalar buffers (never mix diskHistory).
        let refDate = sampleWrapper?.timestamp ?? Date()
        let dualPoints = coordinator.timedDualScalarHistory(
            primary: .diskReadBytesPerSec,
            secondary: .diskWriteBytesPerSec,
            duration: 60.0,
            referenceDate: refDate
        )
        let readSeries = dualPoints.map(\.primary)
        let writeSeries = dualPoints.map(\.secondary)

        let insight = InsightEngine.best(
            series: readSeries,
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
            value: displayVal,
            format: formatStr,
            unit: displayUnit,
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            chartHeight: 84,
            scrubFormat: { Units.formatCompactRate($0, standard: std) }
        )

        let (status, ribbon) = deriveStatusAndRibbon(boot: boot)

        return DerivedState(
            glance: glance,
            status: status,
            ribbon: ribbon,
            readSeries: readSeries,
            writeSeries: writeSeries
        )
    }

    private static func resolveBootVolume(in sample: DiskSample?) -> VolumeCapacity? {
        guard let s = sample else { return nil }
        return s.volumes.first(where: { $0.mountPoint == "/" })
            ?? s.volumes.max(by: { $0.total < $1.total })
    }

    private func formatFreeSpace(_ bytes: UInt64, standard: Units.ByteUnitStandard) -> (Double, String, String) {
        let base: Double = standard == .si ? 1000.0 : 1024.0
        let suffixes = standard == .si ? ["B", "KB", "MB", "GB", "TB", "PB"] : ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var val = Double(bytes)
        var idx = 0
        while val >= base && idx < suffixes.count - 1 {
            val /= base
            idx += 1
        }
        let formatStr = (idx > 0 && val < 10.0) ? "%.1f" : "%.0f"
        return (val, "\(suffixes[idx]) free", formatStr)
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

            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                // Section 1: Boot Volume Storage
                bootStorageSection(volume: boot, status: derived.status, std: std)

                // Section 2: Live Throughput & IOPS
                throughputSection(io: s.io, derived: derived, std: std)
            }
        } else {
            InsetEmptyState(
                systemImage: "internaldrive",
                title: "No Disk Data",
                reason: "Disk storage and I/O metrics are currently unavailable."
            )
        }
    }

    // MARK: - Section 1: Boot Volume Storage

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
                    spacing: 6
                ) {
                    ForEach(breakdown.legendItems) { item in
                        storageLegendCell(item: item, std: std)
                    }
                }
                .padding(.top, 2)
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

    // MARK: - Section 2: Live Throughput & IOPS

    @ViewBuilder
    private func throughputSection(
        io: DiskIO?,
        derived: DerivedState,
        std: Units.ByteUnitStandard
    ) -> some View {
        Section("Live Throughput & IOPS") {
            if let io {
                VStack(spacing: 0) {
                    MetricRow(
                        label: "Read Throughput",
                        valueText: Units.formatCompactRate(io.bytesReadPerSec, standard: std),
                        sparklineHistory: derived.readSeries,
                        sparklineColor: CategoryPalette.Series.diskRead,
                        showHairline: true
                    )
                    MetricRow(
                        label: "Write Throughput",
                        valueText: Units.formatCompactRate(io.bytesWrittenPerSec, standard: std),
                        sparklineHistory: derived.writeSeries,
                        sparklineColor: CategoryPalette.Series.diskWrite,
                        showHairline: true
                    )
                    MetricRow(
                        label: "Read IOPS",
                        valueText: "\(formatIOPS(io.readOpsPerSec)) ops/s",
                        showHairline: true
                    )
                    MetricRow(
                        label: "Write IOPS",
                        valueText: "\(formatIOPS(io.writeOpsPerSec)) ops/s",
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

    private func formatIOPS(_ value: Double) -> String {
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

            Section("Mounted Volumes") {
                Text("\(s.volumes.count)")
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } content: {
                VStack(spacing: 0) {
                    ForEach(Array(s.volumes.enumerated()), id: \.element.mountPoint) { index, vol in
                        volumeRow(vol: vol, std: std)
                            .padding(.vertical, 8)

                        if index < s.volumes.count - 1 {
                            Rectangle()
                                .fill(Instrument.Surface.hairline)
                                .frame(height: 0.5)
                        }
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

    @ViewBuilder
    private func volumeRow(vol: VolumeCapacity, std: Units.ByteUnitStandard) -> some View {
        let isHovered = (hoveredVolumePoint == vol.mountPoint)
        let isBoot = (vol.mountPoint == "/")
        let total = max(1.0, Double(vol.total))
        let usedFraction = min(1.0, max(0.0, Double(vol.used) / total))
        let usedPct = usedFraction * 100.0
        let volStatus = StatusThresholds.disk(usedPercent: usedPct)
        let meterTint = volStatus.isQuiet ? CategoryPalette.color(for: .disk) : volStatus.color

        VStack(alignment: .leading, spacing: 6) {
            // Header: icon + mount name + role badge + Finder button / % used
            HStack(spacing: 6) {
                Image(systemName: isBoot ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.system(size: 11, weight: .medium))
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
                            .font(.system(size: 11))
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
            HStack(spacing: 8) {
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
        let coordinator = MetricsCoordinator.shared
        coordinator.handleReading(.disk(Sample(value: sample)))
        return coordinator
    }
}
#endif
