import SwiftUI

/// Hero metric presentation displaying a 28 pt prominent reading, unit, context line, and optional accessory chart.
public struct HeroMetric<Accessory: View>: View {
    public let primaryValue: String
    public let unit: String?
    public let contextLine: String?
    public let valueColor: Color
    public let accessory: () -> Accessory

    public init(
        primaryValue: String,
        unit: String? = nil,
        contextLine: String? = nil,
        valueColor: Color = .primary,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.primaryValue = primaryValue
        self.unit = unit
        self.contextLine = contextLine
        self.valueColor = valueColor
        self.accessory = accessory
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Tokens.md) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(primaryValue)
                        .font(Tokens.heroValue)
                        .foregroundColor(valueColor)

                    if let u = unit, !u.isEmpty {
                        Text(u)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                if let ctx = contextLine, !ctx.isEmpty {
                    Text(ctx)
                        .font(Tokens.bodyLabel)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            accessory()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(primaryValue) \(unit ?? "") \(contextLine ?? "")")
    }
}

public extension HeroMetric where Accessory == EmptyView {
    init(
        primaryValue: String,
        unit: String? = nil,
        contextLine: String? = nil,
        valueColor: Color = .primary
    ) {
        self.init(
            primaryValue: primaryValue,
            unit: unit,
            contextLine: contextLine,
            valueColor: valueColor,
            accessory: { EmptyView() }
        )
    }
}

#Preview("HeroMetric") {
    VStack(spacing: 20) {
        HeroMetric(
            primaryValue: "34",
            unit: "%",
            contextLine: "on 10 cores · 3.2 GHz"
        )
        HeroMetric(
            primaryValue: "11.2",
            unit: "GB",
            contextLine: "of 16 GB · 68% used",
            valueColor: .mint
        ) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.mint.opacity(0.2))
                .frame(width: 80, height: 32)
        }
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}

