import SwiftUI
import iStatsCore

public struct CapsuleSegment: Identifiable, Sendable {
    public let id: String
    public let value: Double
    public let color: Color
    public let label: String
    public let formattedValue: String?

    public init(id: String? = nil, value: Double, color: Color, label: String, formattedValue: String? = nil) {
        self.id = id ?? label
        self.value = value
        self.color = color
        self.label = label
        self.formattedValue = formattedValue
    }
}

/// Multi-segment capsule bar with 1 pt gaps, hover lift and tooltip (ADR 0009 / Task 8.5).
public struct SplitCapsule: View {
    public let segments: [CapsuleSegment]
    public var height: CGFloat
    public var minVisibleWidth: CGFloat
    public var gap: CGFloat
    public var onHoverSegment: ((CapsuleSegment?) -> Void)? = nil

    @State private var hoveredSegmentId: String?

    public init(
        segments: [CapsuleSegment],
        height: CGFloat = 8,
        minVisibleWidth: CGFloat = 4,
        gap: CGFloat = 1,
        onHoverSegment: ((CapsuleSegment?) -> Void)? = nil
    ) {
        self.segments = segments
        self.height = height
        self.minVisibleWidth = minVisibleWidth
        self.gap = gap
        self.onHoverSegment = onHoverSegment
    }

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let values = segments.map { max(0.0, $0.value) }
            let widths = SegmentLayout.widths(
                values: values,
                totalWidth: Double(totalWidth),
                minVisible: Double(minVisibleWidth),
                gap: Double(gap)
            )

            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let w = index < widths.count ? CGFloat(widths[index]) : 0.0
                    if w > 0 {
                        let isHovered = (hoveredSegmentId == segment.id)
                        RoundedRectangle(cornerRadius: height / 2.0, style: .continuous)
                            .fill(segment.color)
                            .frame(width: w, height: height)
                            .scaleEffect(isHovered ? 1.05 : 1.0)
                            .offset(y: isHovered ? -1.0 : 0.0)
                            .help(segment.formattedValue ?? "\(segment.label): \(String(format: "%.1f", segment.value))")
                            .onHover { hovering in
                                withAnimation(Motion.snappy) {
                                    hoveredSegmentId = hovering ? segment.id : nil
                                    onHoverSegment?(hovering ? segment : nil)
                                }
                            }
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Breakdown bar")
        .accessibilityValue(segments.map { "\($0.label): \(String(format: "%.1f", $0.value))" }.joined(separator: ", "))
    }
}

#if DEBUG
struct SplitCapsule_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Memory composition preview
            SplitCapsule(
                segments: [
                    CapsuleSegment(value: 8.4, color: .blue, label: "App"),
                    CapsuleSegment(value: 3.2, color: .yellow, label: "Wired"),
                    CapsuleSegment(value: 2.1, color: .orange, label: "Compressed"),
                    CapsuleSegment(value: 2.3, color: .gray.opacity(0.3), label: "Free")
                ],
                height: 10
            )

            // CPU breakdown
            SplitCapsule(
                segments: [
                    CapsuleSegment(value: 35.0, color: .blue, label: "User"),
                    CapsuleSegment(value: 12.0, color: .cyan, label: "System"),
                    CapsuleSegment(value: 53.0, color: .gray.opacity(0.2), label: "Idle")
                ],
                height: 8
            )
        }
        .padding()
        .frame(width: 300)
        .background(Instrument.Surface.module)
    }
}
#endif

