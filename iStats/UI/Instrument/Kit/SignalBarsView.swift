import SwiftUI
import iStatsCore

/// 4-bar signal glyph driven by signalPercent with smooth easing transitions (ADR 0009 / Task 8.8f).
public struct SignalBarsView: View {
    public let signalPercent: Int?
    public let activeColor: Color
    public let inactiveColor: Color

    public init(
        signalPercent: Int?,
        activeColor: Color = CategoryPalette.color(for: .network),
        inactiveColor: Color = Color.secondary.opacity(0.2)
    ) {
        self.signalPercent = signalPercent
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
    }

    private var activeBars: Int {
        guard let p = signalPercent, p > 0 else { return 0 }
        if p >= 75 { return 4 }
        if p >= 50 { return 3 }
        if p >= 25 { return 2 }
        return 1
    }

    private let heights: [CGFloat] = [4, 7, 10, 14]

    public var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index < activeBars ? activeColor : inactiveColor)
                    .frame(width: 3.5, height: heights[index])
                    .animation(Motion.smooth, value: activeBars)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal strength: \(signalPercent ?? 0)%")
    }
}

#if DEBUG
struct SignalBarsView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            SignalBarsView(signalPercent: 95)
            SignalBarsView(signalPercent: 65)
            SignalBarsView(signalPercent: 35)
            SignalBarsView(signalPercent: 15)
            SignalBarsView(signalPercent: 0)
        }
        .padding()
        .background(Color.black)
    }
}
#endif
