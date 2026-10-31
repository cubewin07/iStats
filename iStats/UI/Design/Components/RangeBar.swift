import SwiftUI
import iStatsCore

/// Standard range indicator bar showing a value relative to minimum and maximum physical bounds.
public struct RangeBar: View {
    public let value: Double
    public let minValue: Double
    public let maxValue: Double
    public var tintColor: Color?
    public var height: CGFloat

    public init(
        value: Double,
        min: Double,
        max: Double,
        tintColor: Color? = nil,
        height: CGFloat = 6
    ) {
        self.value = value
        self.minValue = min
        self.maxValue = max
        self.tintColor = tintColor
        self.height = height
    }

    public var body: some View {
        let span = maxValue > minValue ? (maxValue - minValue) : 1.0
        let fraction = Swift.max(0.0, Swift.min(1.0, (value - minValue) / span))
        let effectiveColor = tintColor ?? Color.accentColor

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
                    .frame(height: height)

                // Fill Bar
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(effectiveColor)
                    .frame(width: Swift.max(height, proxy.size.width * CGFloat(fraction)), height: height)

                // Indicator Thumb Marker
                Circle()
                    .fill(Color.white)
                    .frame(width: height + 2, height: height + 2)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
                    .offset(x: Swift.max(0, Swift.min(proxy.size.width - height - 2, proxy.size.width * CGFloat(fraction) - (height + 2) / 2)))
            }
        }
        .frame(height: Swift.max(height, height + 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(format: "%.1f", value)) (Range: \(String(format: "%.1f", minValue)) to \(String(format: "%.1f", maxValue)))")
    }
}

#Preview("RangeBar") {
    VStack(spacing: 16) {
        RangeBar(value: 3600, min: 1200, max: 6000, tintColor: .cyan)
        RangeBar(value: 82, min: 20, max: 110, tintColor: .orange)
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}
