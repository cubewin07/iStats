import SwiftUI
import iStatsCore

/// Standard contextual warning or status notification banner shown at the top of a popover.
public struct StatusBanner: View {
    public let iconName: String
    public let message: String
    public let level: StatusLevel
    public var actionTitle: String?
    public var action: (() -> Void)?

    public init(
        iconName: String,
        message: String,
        level: StatusLevel,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.iconName = iconName
        self.message = message
        self.level = level
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: Tokens.sm) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(level.color)

            Text(message)
                .font(Tokens.bodyLabel)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            if let title = actionTitle, let act = action {
                Button(action: act) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(level.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(level.color.opacity(0.18))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(level.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.chipRadius, style: .continuous)
                .strokeBorder(level.color.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message)")
    }
}

#Preview("StatusBanner") {
    VStack(spacing: 8) {
        StatusBanner(
            iconName: "pause.circle.fill",
            message: "Sampling paused while on Low Power Mode",
            level: .elevated,
            actionTitle: "Resume",
            action: {}
        )
        StatusBanner(
            iconName: "exclamationmark.triangle.fill",
            message: "1 GPU recovery event recorded since boot",
            level: .warning
        )
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}

