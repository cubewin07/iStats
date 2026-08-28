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
            // Dual Hero I/O Cards (Read & Write)
            if let sample = sample, let io = sample.io {
                HStack(spacing: 8) {
                    ioCard(
                        title: "Disk Read",
                        rateString: Units.formatDiskRate(io.bytesReadPerSec, standard: byteStandard, fractionDigits: 1),
                        iops: io.readOpsPerSec,
                        icon: "arrow.down.circle.fill",
                        color: .indigo
                    )

                    ioCard(
                        title: "Disk Write",
                        rateString: Units.formatDiskRate(io.bytesWrittenPerSec, standard: byteStandard, fractionDigits: 1),
                        iops: io.writeOpsPerSec,
                        icon: "arrow.up.circle.fill",
                        color: .purple
                    )
                }

                // Rolling 60s Disk I/O Graph
                VStack(alignment: .leading, spacing: 4) {
                    RollingGraphView(
                        values: historyIORates,
                        minValue: 0.0,
                        maxValue: peakIORate,
                        tintColor: .indigo,
                        capacity: 60,
                        height: 44,
                        showGrid: true
                    )

                    HStack {
                        Text("60s I/O Activity")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Peak: \(Units.formatDiskRate(peakIORate, standard: byteStandard, fractionDigits: 1))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Mounted Volumes Section
            if let sample = sample, !sample.volumes.isEmpty {
                volumesSection(volumes: sample.volumes)
            } else if sample == nil {
                Text("Waiting for disk telemetry...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - I/O Card

    private func ioCard(title: String, rateString: String, iops: Double, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Text(rateString)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(String(format: "%.0f IOPS", iops))
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.2), lineWidth: 0.75)
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mounted Volumes Section

    private func volumesSection(volumes: [VolumeCapacity]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVolumesExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Mounted Volumes (\(volumes.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isVolumesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isVolumesExpanded {
                VStack(spacing: 6) {
                    ForEach(volumes, id: \.mountPoint) { volume in
                        volumeRow(volume: volume)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
    }

    private func volumeRow(volume: VolumeCapacity) -> some View {
        let usedRatio = volume.total > 0 ? min(1.0, Double(volume.used) / Double(volume.total)) : 0.0

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: volumeIcon(for: volume.mountPoint))
                    .font(.system(size: 11))
                    .foregroundColor(.indigo)

                VStack(alignment: .leading, spacing: 0) {
                    Text(volume.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(volume.mountPoint)
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.1f%%", usedRatio * 100.0))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(gaugeColor(ratio: usedRatio))

                    Text("\(Units.formatBytes(volume.free, standard: byteStandard, fractionDigits: 1)) free")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
            }

            // Capacity Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 5)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo.opacity(0.8), gaugeColor(ratio: usedRatio)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(usedRatio)), height: 5)
                }
            }
            .frame(height: 5)

            HStack {
                Text("\(Units.formatBytes(volume.used, standard: byteStandard, fractionDigits: 1)) used")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Units.formatBytes(volume.total, standard: byteStandard, fractionDigits: 1)) total")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Helpers

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
        if mountPoint == "/" || mountPoint.contains("Data") {
            return "internaldrive.fill"
        } else if mountPoint.hasPrefix("/Volumes") {
            return "externaldrive.fill"
        } else {
            return "folder.fill"
        }
    }
}

