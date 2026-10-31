import SwiftUI

/// Accessible loading placeholder that shines when motion is enabled, and displays a static neutral card when Reduce Motion is active.
public struct SkeletonView: View {
    public var width: CGFloat?
    public var height: CGFloat
    public var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    public init(
        width: CGFloat? = nil,
        height: CGFloat = 16,
        cornerRadius: CGFloat = 4
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                reduceMotion
                    ? Color(nsColor: .quaternaryLabelColor).opacity(0.15)
                    : Color(nsColor: .quaternaryLabelColor).opacity(0.12 + 0.08 * Double(sin(phase)))
            )
            .frame(width: width, height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    phase = .pi
                }
            }
            .accessibilityLabel("Loading metric")
    }
}

#Preview("SkeletonView") {
    VStack(alignment: .leading, spacing: 10) {
        SkeletonView(width: 120, height: 28, cornerRadius: 6)
        SkeletonView(height: 12)
        SkeletonView(width: 180, height: 12)
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}

