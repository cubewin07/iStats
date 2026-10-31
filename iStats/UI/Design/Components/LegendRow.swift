import SwiftUI

/// Standard row displaying a color dot swatch, label, formatted value, and optional secondary percentage.
public struct LegendRow: View {
    public let color: Color
    public let label: String
    public let value: String
    public let shareText: String?

    public init(
        color: Color,
        label: String,
        value: String,
        shareText: String? = nil
    ) {
        self.color = color
        self.label = label
        self.value = value
        self.shareText = shareText
    }

    public var body: some View {
        HStack(spacing: Tokens.sm) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(label)
                .font(Tokens.bodyLabel)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(Tokens.monoValue)
                .foregroundColor(.primary)

            if let share = shareText, !share.isEmpty {
                Text(share)
                    .font(Tokens.monoValue)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 38, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(shareText.map { ", \($0)" } ?? "")")
    }
}

#Preview("LegendRow") {
    VStack(spacing: 6) {
        LegendRow(color: .mint, label: "App Memory", value: "7.4 GB", shareText: "46%")
        LegendRow(color: .mint.opacity(0.7), label: "Wired Memory", value: "2.1 GB", shareText: "13%")
        LegendRow(color: .mint.opacity(0.45), label: "Compressed", value: "1.2 GB", shareText: "7%")
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}
