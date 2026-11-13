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

/// Row of vertical rounded columns representing a cluster or core map (ADR 0009 / Task 8.5 / Task 8.5.8a).
public struct ClusterStrip: View {
    public let title: String?
    public let bars: [ClusterBarData]
    public var barWidth: CGFloat
    public var barHeight: CGFloat
    public var onHover: ((_ index: Int?, _ bar: ClusterBarData?) -> Void)?

    @State private var hoveredBarIndex: Int?
    @Environment(\.motionPolicy) private var motionPolicy

    public init(
        title: String? = nil,
        bars: [ClusterBarData],
        barWidth: CGFloat = 10,
        barHeight: CGFloat = 36,
        onHover: ((_ index: Int?, _ bar: ClusterBarData?) -> Void)? = nil
    ) {
        self.title = title
        self.bars = bars
        self.barWidth = barWidth
        self.barHeight = barHeight
        self.onHover = onHover
    }

    public var body: some View {
        let cornerRadius = min(barWidth / 2.0, 4.0)
        let barSpacing: CGFloat = bars.count > 16 ? 3 : 4

        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                Text(title)
                    .font(Instrument.Typography.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(bars) { bar in
                    let isHovered = (hoveredBarIndex == bar.index)
                    let isDimmed = (hoveredBarIndex != nil && !isHovered)
                    let columnShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            // Track
                            columnShape
                                .fill(isHovered ? Color.primary.opacity(0.12) : Instrument.Surface.inset)
                                .frame(width: barWidth, height: barHeight)

                            // Fill
                            let fillH = bar.utilization <= 0.005 ? 0.0 : max(barWidth, barHeight * CGFloat(bar.utilization))
                            columnShape
                                .fill(bar.color)
                                .opacity(isDimmed ? 0.45 : 1.0)
                                .frame(width: barWidth, height: fillH)
                                .easedProgress(bar.utilization, interval: 1.0)
                        }
                        .overlay {
                            columnShape
                                .strokeBorder(Color.primary.opacity(isHovered ? 0.55 : 0.0), lineWidth: 1.0)
                        }

                        // Micro index label
                        Text("\(bar.index)")
                            .font(Instrument.Typography.micro)
                            .foregroundColor(isHovered ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(motionPolicy.allowsEasing ? Motion.snappy : nil) {
                            if hovering {
                                hoveredBarIndex = bar.index
                                onHover?(bar.index, bar)
                            } else if hoveredBarIndex == bar.index {
                                hoveredBarIndex = nil
                                onHover?(nil, nil)
                            }
                        }
                    }
                    .help(bar.label ?? "Core \(bar.index): \(Int(round(bar.utilization * 100)))%")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title ?? "Cluster strip")
        .accessibilityValue(bars.map { "Core \($0.index): \(Int(round($0.utilization * 100)))%" }.joined(separator: ", "))
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

