import SwiftUI

/// A proportional multi-segment horizontal capsule bar.
public struct SegmentedBar: View {
    public struct Segment: Identifiable, Sendable {
        public let id: String
        public let value: Double
        public let color: Color
        public let label: String

        public init(id: String = UUID().uuidString, value: Double, color: Color, label: String) {
            self.id = id
            self.value = max(0.0, value)
            self.color = color
            self.label = label
        }
    }

    public let segments: [Segment]
    public var height: CGFloat
    public var cornerRadius: CGFloat

    public init(
        segments: [Segment],
        height: CGFloat = 8,
        cornerRadius: CGFloat = 4
    ) {
        self.segments = segments
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let total = segments.map(\.value).reduce(0, +)
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            HStack(spacing: 1) {
                if total > 0 {
                    ForEach(segments) { seg in
                        let fraction = seg.value / total
                        let segWidth = max(0.0, totalWidth * CGFloat(fraction) - 1.0)
                        if segWidth > 0.5 {
                            seg.color
                                .frame(width: segWidth, height: height)
                        }
                    }
                } else {
                    Color(nsColor: .quaternaryLabelColor).opacity(0.2)
                        .frame(maxWidth: .infinity, maxHeight: height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            segments.map { "\($0.label): \(String(format: "%.1f", $0.value))" }.joined(separator: ", ")
        )
    }
}

#Preview("SegmentedBar") {
    VStack(spacing: 12) {
        SegmentedBar(segments: [
            .init(value: 42, color: .blue, label: "User"),
            .init(value: 18, color: .red.opacity(0.7), label: "System"),
            .init(value: 40, color: Color(nsColor: .quaternaryLabelColor), label: "Idle")
        ])

        SegmentedBar(segments: [
            .init(value: 6.2, color: .mint, label: "App"),
            .init(value: 2.1, color: .mint.opacity(0.7), label: "Wired"),
            .init(value: 1.4, color: .mint.opacity(0.45), label: "Compressed"),
            .init(value: 6.3, color: Color(nsColor: .quaternaryLabelColor), label: "Free")
        ], height: 10)
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}
