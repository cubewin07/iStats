import SwiftUI
import iStatsCore

/// Severity-tinted alert strip displayed only when a metric reaches `.elevated` or worse (Task 8.6 / ADR 0009).
public struct StatusRibbon: View {
    public let status: StatusLevel
    public let message: String
    public var actionTitle: String?
    public var action: (() -> Void)?

    public init(
        status: StatusLevel,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.status = status
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        let tint = statusColor(for: status)

        HStack(spacing: 8) {
            Image(systemName: iconName(for: status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)

            Text(message)
                .font(Instrument.Typography.caption)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let title = actionTitle, let action = action {
                Button(action: action) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(tint.opacity(0.18))
                        )
                        .foregroundColor(tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        ))
    }

    private func iconName(for status: StatusLevel) -> String {
        switch status {
        case .fine:
            return "checkmark.circle"
        case .elevated:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "exclamationmark.octagon.fill"
        }
    }

    private func statusColor(for status: StatusLevel) -> Color {
        switch status {
        case .fine:
            return .secondary
        case .elevated:
            return Color(red: 0.85, green: 0.65, blue: 0.1) // Amber
        case .warning:
            return Color(red: 0.95, green: 0.5, blue: 0.15) // Orange
        case .critical:
            return Color(red: 0.9, green: 0.25, blue: 0.25) // Red
        }
    }
}
