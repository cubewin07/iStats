import SwiftUI
import iStatsCore

/// Visual badge component displaying the current memory pressure level with semantic status color.
public struct MemoryPressureBadgeView: View {
    public let pressure: MemoryPressure

    public init(pressure: MemoryPressure) {
        self.pressure = pressure
    }

    private var badgeColor: Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 5.5, height: 5.5)

            Text(pressure.displayName)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(badgeColor.opacity(0.12))
        .clipShape(Capsule())
    }
}

/// Alert banner surfaced when memory pressure reaches warning or critical state.
public struct MemoryPressureAlertBanner: View {
    public let pressure: MemoryPressure

    public init(pressure: MemoryPressure) {
        self.pressure = pressure
    }

    public var body: some View {
        if pressure.isElevated {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: pressure == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(pressure == .critical ? .red : .orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(pressure == .critical ? "Memory Critical" : "Memory Pressure Warning")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(pressure == .critical ? .red : .orange)

                    Text(pressure == .critical
                         ? "The Mac is out of usable memory. Close some apps."
                         : "macOS is reclaiming memory. Apps may feel slower.")
                        .font(.system(size: 9.5))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(pressure == .critical ? Color.red.opacity(0.12) : Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(pressure == .critical ? Color.red.opacity(0.35) : Color.orange.opacity(0.35), lineWidth: 0.75)
            )
        }
    }
}

/// A clean Memory metrics view with horizontal segmented composition bar:
/// 1. Memory pressure hero & Allocation totals (Used of Total)
/// 2. Full-width horizontal multi-segment composition bar (Apps, Wired, Compressed, Cached, Free) + Chips
/// 3. 60-sample memory rolling graph & collapsible diagnostics.
public struct MemorySummaryView: View {
    public let sample: MemorySample?
    public let history: [Sample<MemorySample>]
    public let byteStandard: Units.ByteUnitStandard

    @State private var isDetailsExpanded: Bool = false

    public init(
        sample: MemorySample?,
        history: [Sample<MemorySample>] = [],
        byteStandard: Units.ByteUnitStandard = .iec
    ) {
        self.sample = sample
        self.history = history
        self.byteStandard = byteStandard
    }

    private var historyPercentages: [Double] {
        history.map { s in
            s.value.total > 0 ? (Double(s.value.used) / Double(s.value.total)) * 100.0 : 0.0
        }
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateMemory(sample, standard: byteStandard)
    }

    // Segment Colors
    private let appColor = Color.blue
    private let wiredColor = Color.purple
    private let compressedColor = Color.orange
    private let cachedColor = Color.teal
    private let freeColor = Color.secondary.opacity(0.2)

    public var body: some View {
        VStack(spacing: 8) {
            // MARK: - Main Memory Card: Pressure Hero, Horizontal Bar & Chips
            VStack(alignment: .leading, spacing: 8) {
                // Header Row: Pressure Status & Used/Total
                HStack(alignment: .firstTextBaseline) {
                    if let sample = sample {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(verdict.level.color)
                                .frame(width: 7, height: 7)

                            Text("Pressure \(sample.pressure.displayName)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(verdict.level.color)
                        }

                        Spacer()

                        let usedRatio = sample.total > 0 ? (Double(sample.used) / Double(sample.total)) * 100.0 : 0.0
                        Text("\(Units.formatBytes(sample.used, standard: byteStandard)) of \(Units.formatBytes(sample.total, standard: byteStandard, fractionDigits: 0)) (\(String(format: "%.0f%%", usedRatio)))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Sampling Memory...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                // Alert banner if elevated
                if let sample = sample {
                    MemoryPressureAlertBanner(pressure: sample.pressure)
                }

                // Horizontal Segmented Memory Composition Bar
                if let sample = sample, sample.total > 0 {
                    horizontalCompositionBar(sample: sample)
                        .frame(height: 10)

                    // Horizontal Legend Chips Row
                    horizontalLegendRow(sample: sample)
                }

                // Swap Active Note (if swap used > 0)
                if let sample = sample, sample.swapUsed > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 8.5))
                            .foregroundColor(.orange)
                        Text("Using disk as extra memory (\(Units.formatBytes(sample.swapUsed, standard: byteStandard)))")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )

            // MARK: - 60-Sample Memory History Graph
            VStack(alignment: .leading, spacing: 4) {
                RollingGraphView(
                    values: historyPercentages,
                    minValue: 0.0,
                    maxValue: 100.0,
                    tintColor: verdict.level.color,
                    capacity: 60,
                    height: 44,
                    showGrid: true
                )

                HStack {
                    Text("last 2 min")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let sample = sample {
                        let usedRatio = sample.total > 0 ? (Double(sample.used) / Double(sample.total)) * 100.0 : 0.0
                        Text(String(format: "peak %.0f%% allocated", historyPercentages.max() ?? usedRatio))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )

            // MARK: - Collapsible Diagnostics
            if let sample = sample {
                CollapsibleSection(
                    title: "More details",
                    count: nil,
                    isExpanded: $isDetailsExpanded
                ) {
                    diagnosticsContent(sample: sample)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Horizontal Multi-Segment Composition Bar

    private func horizontalCompositionBar(sample: MemorySample) -> some View {
        GeometryReader { geo in
            let total = Double(sample.total)
            let app = Double(sample.appMemory ?? (sample.used >= (sample.wired + sample.compressed) ? sample.used - sample.wired - sample.compressed : sample.used))
            let wired = Double(sample.wired)
            let compressed = Double(sample.compressed)
            let cached = Double(sample.cached)
            let free = Double(sample.free)

            let sum = max(total, app + wired + compressed + cached + free)
            let w = geo.size.width

            let appW = max(0, w * CGFloat(app / sum))
            let wiredW = max(0, w * CGFloat(wired / sum))
            let compW = max(0, w * CGFloat(compressed / sum))
            let cachedW = max(0, w * CGFloat(cached / sum))
            let freeW = max(0, w - appW - wiredW - compW - cachedW)

            HStack(spacing: 1.5) {
                // Apps (Blue)
                RoundedRectangle(cornerRadius: 2)
                    .fill(appColor)
                    .frame(width: max(0, appW - 1))

                // Wired (Purple)
                RoundedRectangle(cornerRadius: 2)
                    .fill(wiredColor)
                    .frame(width: max(0, wiredW - 1))

                // Compressed (Orange)
                RoundedRectangle(cornerRadius: 2)
                    .fill(compressedColor)
                    .frame(width: max(0, compW - 1))

                // Cached (Teal)
                RoundedRectangle(cornerRadius: 2)
                    .fill(cachedColor)
                    .frame(width: max(0, cachedW - 1))

                // Free (Empty well)
                RoundedRectangle(cornerRadius: 2)
                    .fill(freeColor)
                    .frame(width: max(0, freeW))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    // MARK: - Horizontal Legend Chips Row

    private func horizontalLegendRow(sample: MemorySample) -> some View {
        HStack(spacing: 8) {
            chip(label: "Apps", color: appColor)
            chip(label: "Wired", color: wiredColor)
            chip(label: "Compressed", color: compressedColor)
            chip(label: "Cached", color: cachedColor)
            chip(label: "Free", color: freeColor)
        }
    }

    private func chip(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Diagnostics Content

    @ViewBuilder
    private func diagnosticsContent(sample: MemorySample) -> some View {
        let appMem = sample.appMemory ?? (sample.used >= (sample.wired + sample.compressed) ? sample.used - sample.wired - sample.compressed : sample.used)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
            breakdownCard(title: "Apps", value: Units.formatBytes(appMem, standard: byteStandard), color: appColor)
            breakdownCard(title: "System (Wired)", value: Units.formatBytes(sample.wired, standard: byteStandard), color: wiredColor)
            breakdownCard(title: "Compressed", value: Units.formatBytes(sample.compressed, standard: byteStandard), color: compressedColor)
            breakdownCard(title: "Cached (Reusable)", value: Units.formatBytes(sample.cached, standard: byteStandard), color: cachedColor)
            breakdownCard(title: "Swap Used", value: Units.formatBytes(sample.swapUsed, standard: byteStandard), color: sample.swapUsed > 0 ? .orange : .secondary)
            breakdownCard(title: "Free Memory", value: Units.formatBytes(sample.free, standard: byteStandard), color: .green)
        }
        .padding(.top, 4)
    }

    private func breakdownCard(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 4.5, height: 4.5)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
    }
}
