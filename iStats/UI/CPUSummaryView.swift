import SwiftUI
import iStatsCore

/// Authentic iStat Menus style CPU view featuring:
/// 1. Stacked vertical bar history chart (User in Blue + System in Magenta/Pink)
/// 2. Per-core circular ring gauge cluster (E-cores in Pink, P-cores in Blue) with cluster averages
/// 3. Collapsible high-readability diagnostics (Enhanced Load Average and System Uptime cards).
public struct CPUSummaryView: View {
    public let sample: CPUSample?
    public let history: [Sample<CPUSample>]
    @State private var isDetailsExpanded: Bool = false

    public init(sample: CPUSample? = nil, history: [Sample<CPUSample>] = []) {
        self.sample = sample
        self.history = history
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateCPU(sample)
    }

    private var uptimeString: String {
        Units.formatUptime(ProcessInfo.processInfo.systemUptime)
    }

    // Colors matching authentic iStat Menus
    private let userColor = Color(red: 0.05, green: 0.55, blue: 1.0)       // Vivid Blue
    private let systemColor = Color(red: 0.96, green: 0.28, blue: 0.58)    // Vivid Magenta / Pink

    public var body: some View {
        VStack(spacing: 8) {
            // MARK: - Top Card: Stacked History Graph & User/System Legend
            VStack(alignment: .leading, spacing: 8) {
                // Header inside the card: "CPU" and Clock / Load
                HStack(alignment: .firstTextBaseline) {
                    Text("CPU")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(userColor)

                    Spacer()

                    if let sample = sample {
                        HStack(spacing: 4) {
                            if let freq = sample.frequencyHz, freq > 0 {
                                Text(Units.formatFrequencyHz(freq, fractionDigits: 2))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            } else if let load = sample.loadAverage {
                                Text(String(format: "Load: %.2f", load.oneMinute))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Authentic iStat Menus Stacked History Bar Graph
                stackedHistoryGraph
                    .frame(height: 58)

                // User / System Breakdown Legend Row
                if let sample = sample {
                    HStack {
                        // User %
                        HStack(spacing: 4) {
                            Circle().fill(userColor).frame(width: 6, height: 6)
                            Text("User")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", sample.user))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        // System %
                        HStack(spacing: 4) {
                            Circle().fill(systemColor).frame(width: 6, height: 6)
                            Text("System")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", sample.system))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        // Total Usage
                        HStack(spacing: 2) {
                            Text(String(format: "%.0f%%", sample.totalUsage))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                            Text("Total")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
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

            // MARK: - Middle Card: Per-Core Circular Rings Cluster
            if let sample = sample, !sample.perCore.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Row of circular donut rings
                    coreRingsCluster(sample: sample)

                    // Cluster Averages Legend (E-cores vs P-cores)
                    if let eAvg = sample.efficiencyUsage, let pAvg = sample.performanceUsage {
                        VStack(spacing: 4) {
                            HStack {
                                HStack(spacing: 4) {
                                    Circle().fill(systemColor).frame(width: 6, height: 6)
                                    Text("Efficiency Cores")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.0f%%", eAvg))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }

                            HStack {
                                HStack(spacing: 4) {
                                    Circle().fill(userColor).frame(width: 6, height: 6)
                                    Text("Performance Cores")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.0f%%", pAvg))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
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
            }

            // MARK: - Collapsible Diagnostics (Enhanced Readability Cards)
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

    // MARK: - Stacked Vertical Bar History Graph

    private var stackedHistoryGraph: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let capacity = 60
            let barWidth = max(2.0, (width - CGFloat(capacity - 1) * 1.5) / CGFloat(capacity))
            let samples = history.suffix(capacity)

            ZStack(alignment: .bottomLeading) {
                // Background well
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.03))

                // Render vertical bars
                HStack(alignment: .bottom, spacing: 1.5) {
                    // Prepend empty space if history not filled yet
                    if samples.count < capacity {
                        Spacer(minLength: 0)
                    }

                    ForEach(Array(samples.enumerated()), id: \.offset) { _, sampleItem in
                        let s = sampleItem.value
                        let userHeight = height * CGFloat(min(max(s.user / 100.0, 0.0), 1.0))
                        let sysHeight = height * CGFloat(min(max(s.system / 100.0, 0.0), 1.0))

                        VStack(spacing: 0) {
                            // System (Pink/Magenta) top segment
                            Rectangle()
                                .fill(systemColor)
                                .frame(height: sysHeight)

                            // User (Blue) bottom segment
                            Rectangle()
                                .fill(userColor)
                                .frame(height: userHeight)
                        }
                        .frame(width: barWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                    }
                }
            }
        }
    }

    // MARK: - Per-Core Donut Rings Cluster

    private func coreRingsCluster(sample: CPUSample) -> some View {
        let eCount = sample.efficiencyCoreCount ?? 0
        let count = sample.perCore.count
        let ringSize: CGFloat = count > 16 ? 16 : (count > 10 ? 18 : 22)

        return HStack(spacing: count > 12 ? 3 : 5) {
            ForEach(0..<count, id: \.self) { index in
                let usage = sample.perCore[index]
                let isE = index < eCount
                let ringColor = isE ? systemColor : userColor

                ZStack {
                    // Background ring track
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: ringSize * 0.2)

                    // Active load arc
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(max(usage / 100.0, 0.0), 1.0)))
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: ringSize * 0.2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: ringSize, height: ringSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }

    // MARK: - Enhanced Diagnostics Cards

    @ViewBuilder
    private func diagnosticsContent(sample: CPUSample) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            // Enhanced Load Average Card
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(userColor)
                    Text("Load Average")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.primary)
                }

                if let load = sample.loadAverage {
                    HStack(spacing: 8) {
                        loadColumn(label: "1m", value: String(format: "%.2f", load.oneMinute))
                        loadColumn(label: "5m", value: String(format: "%.2f", load.fiveMinute))
                        loadColumn(label: "15m", value: String(format: "%.2f", load.fifteenMinute))
                    }
                    .padding(.top, 1)
                } else {
                    Text("N/A")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            // Enhanced System Uptime Card
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                    Text("System Uptime")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.primary)
                }

                Text(uptimeString)
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.top, 1)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 4, height: 4)
                    Text("Running")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .padding(.top, 2)
    }

    private func loadColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}
