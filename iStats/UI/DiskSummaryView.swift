import SwiftUI
import iStatsCore

/// A comprehensive Disk metrics view displaying mounted volume storage capacities, usage gauges,
/// and live I/O throughput rates with rolling history graph (Requirements 7.1-7.3, 10.1, 11.3).
public struct DiskSummaryView: View {
    public let sample: DiskSample?
    public let history: [Sample<DiskSample>]
    public let byteStandard: Units.ByteUnitStandard

    @State private var isVolumesExpanded: Bool = true

    public init(
        sample: DiskSample? = nil,
        history: [Sample<DiskSample>] = [],
        byteStandard: Units.ByteUnitStandard = .iec
    ) {
        self.sample = sample
        self.history = history
        self.byteStandard = byteStandard
    }

    /// History values of combined read + write I/O throughput.
    private var historyIORates: [Double] {
        history.map { s in
            if let io = s.value.io {
                return io.bytesReadPerSec + io.bytesWrittenPerSec
            }
            return 0.0
        }
    }

    private var currentIORate: Double {
        guard let io = sample?.io else { return 0.0 }
        return io.bytesReadPerSec + io.bytesWrittenPerSec
    }

    private var peakIORate: Double {
        let maxHist = historyIORates.max() ?? 0.0
        return max(maxHist, currentIORate, 1.0)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Category Icon, Name, Live I/O Throughput or Volume Count
            HStack {
                Label {
                    Text("Disk")
                        .font(.headline)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "internaldrive")
                        .foregroundColor(.indigo)
                }

                Spacer()

                if let sample = sample {
                    if let io = sample.io {
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.indigo)
                                Text("R: \(Units.formatDiskRate(io.bytesReadPerSec, standard: byteStandard, fractionDigits: 1))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .fontWeight(.semibold)
                            }

                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.purple)
                                Text("W: \(Units.formatDiskRate(io.bytesWrittenPerSec, standard: byteStandard, fractionDigits: 1))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .fontWeight(.semibold)
                            }
                        }
                    } else {
                        Text("\(sample.volumes.count) Volumes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Sampling...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Disk I/O Rolling Graph (if I/O statistics available, Requirement 7.2)
            if let sample = sample, let io = sample.io {
                VStack(alignment: .leading, spacing: 4) {
                    RollingGraphView(
                        values: historyIORates,
                        minValue: 0.0,
                        maxValue: peakIORate,
                        tintColor: .indigo,
                        capacity: 60,
                        height: 48,
                        showGrid: true
                    )

                    HStack {
                        Text("60s I/O throughput")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Peak: \(Units.formatDiskRate(peakIORate, standard: byteStandard))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Ops/sec Badges
                HStack(spacing: 12) {
                    metricBadge(
                        title: "Read Ops",
                        value: String(format: "%.0f /s", io.readOpsPerSec),
                        color: .indigo
                    )
                    metricBadge(
                        title: "Write Ops",
                        value: String(format: "%.0f /s", io.writeOpsPerSec),
                        color: .purple
                    )
                }
                .padding(.top, 2)
            }

            // Mounted Volumes Capacity Section (Requirement 7.1, 7.3)
            if let sample = sample, !sample.volumes.isEmpty {
                volumesSection(volumes: sample.volumes)
            } else if sample == nil {
                Text("Waiting for disk sample...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Mounted Volumes Section

    private func volumesSection(volumes: [VolumeCapacity]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVolumesExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Mounted Volumes (\(volumes.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isVolumesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isVolumesExpanded {
                VStack(spacing: 8) {
                    ForEach(volumes, id: \.mountPoint) { volume in
                        volumeRow(volume: volume)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    private func volumeRow(volume: VolumeCapacity) -> some View {
        let usedRatio = volume.total > 0 ? min(1.0, Double(volume.used) / Double(volume.total)) : 0.0

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: volumeIcon(for: volume.mountPoint))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(volume.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.1f%%", usedRatio * 100.0))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(gaugeColor(ratio: usedRatio))
            }

            // Capacity Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(gaugeColor(ratio: usedRatio))
                        .frame(width: max(0, geo.size.width * CGFloat(usedRatio)), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Units.formatBytes(volume.used, standard: byteStandard)) of \(Units.formatBytes(volume.total, standard: byteStandard))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Units.formatBytes(volume.free, standard: byteStandard)) free")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Helpers

    private func metricBadge(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title):")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gaugeColor(ratio: Double) -> Color {
        if ratio >= 0.95 {
            return .red
        } else if ratio >= 0.85 {
            return .orange
        } else {
            return .indigo
        }
    }

    private func volumeIcon(for mountPoint: String) -> String {
        if mountPoint == "/" {
            return "internaldrive.fill"
        } else if mountPoint.hasPrefix("/Volumes") {
            return "externaldrive.fill"
        } else {
            return "folder.fill"
        }
    }
}
