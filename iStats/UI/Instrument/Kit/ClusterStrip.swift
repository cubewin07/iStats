import SwiftUI
import iStatsCore

public struct ClusterBarData: Identifiable, Sendable {
    public let id: String
    public let index: Int
    public let utilization: Double // 0.0 ... 1.0
    public let color: Color
    public let label: String?

    public init(id: String? = nil, index: Int, utilization: Double, color: Color, label: String? = nil) {
        self.id = id ?? "\(index)"
        self.index = index
        self.utilization = max(0.0, min(1.0, utilization))
        self.color = color
        self.label = label
    }
}

/// Row of vertical capsule bars representing a cluster or core map (ADR 0009 / Task 8.5).
public struct ClusterStrip: View {
    public let title: String?
    public let bars: [ClusterBarData]
    public var barWidth: CGFloat
    public var barHeight: CGFloat
    public var onHover: ((_ index: Int?, _ bar: ClusterBarData?) -> Void)?

    @State private var hoveredBarIndex: Int?

    public init(
        title: String? = nil,
        bars: [ClusterBarData],
        barWidth: CGFloat = 8,
        barHeight: CGFloat = 32,
        onHover: ((_ index: Int?, _ bar: ClusterBarData?) -> Void)? = nil
    ) {
        self.title = title
        self.bars = bars
        self.barWidth = barWidth
        self.barHeight = barHeight
        self.onHover = onHover
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                Text(title)
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(bars) { bar in
                    let isHovered = (hoveredBarIndex == bar.index)
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            // Track
                            Capsule()
                                .fill(Instrument.Surface.inset)
                                .frame(width: barWidth, height: barHeight)

                            // Fill
                            let fillH = bar.utilization <= 0.005 ? 0.0 : max(barWidth, barHeight * CGFloat(bar.utilization))
                            Capsule()
                                .fill(bar.color)
                                .frame(width: barWidth, height: fillH)
                                .easedProgress(bar.utilization, interval: 1.0)
                        }
                        .scaleEffect(isHovered ? 1.1 : 1.0)

                        // Micro index label
                        Text("\(bar.index)")
                            .font(Instrument.Typography.micro)
                            .foregroundColor(isHovered ? .primary : .secondary)
                    }
                    .onHover { hovering in
                        withAnimation(Motion.snappy) {
                            hoveredBarIndex = hovering ? bar.index : nil
                            onHover?(hovering ? bar.index : nil, hovering ? bar : nil)
                        }
                    }
                    .help(bar.label ?? "Core \(bar.index): \(Int(bar.utilization * 100))%")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title ?? "Cluster strip")
        .accessibilityValue(bars.map { "Core \($0.index): \(Int($0.utilization * 100))%" }.joined(separator: ", "))
    }
}

#if DEBUG
struct ClusterStrip_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ClusterStrip(
                title: "PERFORMANCE CORES (P-CLUSTER)",
                bars: (0..<8).map { i in
                    ClusterBarData(index: i, utilization: Double.random(in: 0.1...0.9), color: .blue)
                }
            )

            ClusterStrip(
                title: "EFFICIENCY CORES (E-CLUSTER)",
                bars: (0..<4).map { i in
                    ClusterBarData(index: i, utilization: Double.random(in: 0.05...0.4), color: .teal)
                }
            )
        }
        .padding()
        .background(Instrument.Surface.module)
    }
}
#endif

