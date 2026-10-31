import SwiftUI
import iStatsCore

/// Standard diagnostic key-value row with optional status dot or hint.
public struct StatRow: View {
    public let label: String
    public let value: String
    public var statusLevel: StatusLevel?
    public var tooltip: String?

    public init(
        label: String,
        value: String,
        statusLevel: StatusLevel? = nil,
        tooltip: String? = nil
    ) {
        self.label = label
        self.value = value
        self.statusLevel = statusLevel
        self.tooltip = tooltip
    }

    public var body: some View {
        HStack(spacing: Tokens.sm) {
            Text(label)
                .font(Tokens.bodyLabel)
                .foregroundColor(.secondary)

            Spacer()

            if let level = statusLevel {
                Circle()
                    .fill(level.color)
                    .frame(width: 6, height: 6)
            }

            Text(value)
                .font(Tokens.monoValue)
                .foregroundColor(.primary)
        }
        .help(tooltip ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview("StatRow") {
    VStack(spacing: 8) {
        StatRow(label: "Load Average (1/5/15)", value: "2.14 · 1.82 · 1.54")
        StatRow(label: "CPU Frequency", value: "3.20 GHz")
        StatRow(label: "GPU Recovery Count", value: "1 fault", statusLevel: .warning)
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}
