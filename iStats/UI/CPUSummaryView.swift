import SwiftUI
import iStatsCore

/// A comprehensive CPU metrics card view displaying aggregate utilization, live rolling history graph,
/// user/system/idle breakdown, load average, clock frequency, and per-core distribution
/// (Requirements 10.1, 10.2, 10.3).
public struct CPUSummaryView: View {
    public let sample: CPUSample?
    public let history: [Sample<CPUSample>]
    @State private var isPerCoreExpanded: Bool = true

    public init(sample: CPUSample? = nil, history: [Sample<CPUSample>] = []) {
        self.sample = sample
        self.history = history
    }

    private var historyPercentages: [Double] {
        history.map { $0.value.totalUsage }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Icon, Category Name, Aggregate Percentage
            HStack {
                Label {
                    Text("CPU")
                        .font(.headline)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "cpu")
                        .foregroundColor(.blue)
                }

                Spacer()

                if let sample = sample {
                    Text(String(format: "%.1f%%", sample.totalUsage))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(usageColor(for: sample.totalUsage))
                } else {
                    Text("Sampling...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Rolling Short-Term History Graph (Requirement 10.2)
            VStack(alignment: .leading, spacing: 4) {
                RollingGraphView(
                    values: historyPercentages,
                    minValue: 0.0,
                    maxValue: 100.0,
                    tintColor: .blue,
                    capacity: 60,
                    height: 48,
                    showGrid: true
                )

                HStack {
                    Text("60s history")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let sample = sample {
                        Text(String(format: "Peak: %.1f%%", historyPercentages.max() ?? sample.totalUsage))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let sample = sample {
                // Usage Breakdown Bar
                breakdownBar(sample: sample)

                // Breakdown Labels (User, System, Idle)
                HStack(spacing: 8) {
                    metricBadge(title: "User", value: String(format: "%.1f%%", sample.user), color: .blue)
                    metricBadge(title: "System", value: String(format: "%.1f%%", sample.system), color: .orange)
                    metricBadge(title: "Idle", value: String(format: "%.1f%%", sample.idle), color: .secondary)
                }

                // Load Average & Frequency Info
                HStack(spacing: 12) {
                    if let load = sample.loadAverage {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Load Avg:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f  %.2f  %.2f", load.oneMinute, load.fiveMinute, load.fifteenMinute))
                                .font(.system(size: 10, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    }

                    Spacer()

                    if let freq = sample.frequencyHz {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Clock:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(Units.formatFrequencyHz(freq))
                                .font(.system(size: 10, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    }
                }
                .padding(.top, 2)

                // Per-Core Utilization Section
                if !sample.perCore.isEmpty {
                    perCoreSection(perCore: sample.perCore)
                }
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

    // MARK: - Breakdown Bar

    private func breakdownBar(sample: CPUSample) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let userWidth = max(0, width * CGFloat(sample.user / 100.0))
            let sysWidth = max(0, width * CGFloat(sample.system / 100.0))
            let idleWidth = max(0, width - userWidth - sysWidth)

            HStack(spacing: 1) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: userWidth)
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: sysWidth)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: idleWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
    }

    // MARK: - Per-Core Section

    private func perCoreSection(perCore: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPerCoreExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Cores (\(perCore.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isPerCoreExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isPerCoreExpanded {
                let columns = [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ]

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<perCore.count, id: \.self) { index in
                        let coreUsage = perCore[index]
                        HStack(spacing: 4) {
                            Text(String(format: "C%d", index))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 22, alignment: .leading)

                            ProgressView(value: min(max(coreUsage, 0), 100), total: 100)
                                .progressViewStyle(.linear)
                                .tint(usageColor(for: coreUsage))

                            Text(String(format: "%2.0f%%", coreUsage))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 26, alignment: .trailing)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Subcomponents & Helpers

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

    private func usageColor(for usage: Double) -> Color {
        if usage >= 85.0 {
            return .red
        } else if usage >= 60.0 {
            return .orange
        } else {
            return .blue
        }
    }
}
