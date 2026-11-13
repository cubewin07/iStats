import SwiftUI
import iStatsCore

/// Compact inline status pill displayed on the trailing side of the Glance numeral row when `status >= .elevated` (Task 8.5.6b).
public struct InlineStatusChip: View {
    public let status: StatusLevel
    public var detail: String?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(status: StatusLevel, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }

    public static func glyph(for status: StatusLevel) -> String {
        switch status {
        case .fine: return "●"
        case .elevated: return "●"
        case .warning: return "▲"
        case .critical: return "◆"
        }
    }

    public static func title(for status: StatusLevel) -> String {
        switch status {
        case .fine: return "Normal"
        case .elevated: return "Elevated"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    public static func displayText(for status: StatusLevel) -> String {
        "\(glyph(for: status)) \(title(for: status))"
    }

    public var body: some View {
        let tint = CategoryPalette.statusColor(for: status)
        let titleText = Self.title(for: status)

        HStack(spacing: 4) {
            Text(Self.glyph(for: status))
                .font(.system(size: 8, weight: .bold))
            Text(titleText)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .fixedSize()
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(colorSchemeContrast == .increased ? 0.22 : 0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            tint.opacity(colorSchemeContrast == .increased ? 0.65 : 0.22),
                            lineWidth: colorSchemeContrast == .increased ? 0.75 : 0.5
                        )
                )
        )
        .help(detail ?? titleText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(titleText)")
        .accessibilityValue(detail ?? "")
    }
}

/// Severity-tinted actionable alert strip reserved for actionable states such as paused sampling or explicit action buttons (Task 8.5.6b / ADR 0010).
public struct StatusRibbon: View {
    public let status: StatusLevel
    public let message: String
    public var actionTitle: String?
    public var action: (() -> Void)?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
                                .fill(tint.opacity(colorSchemeContrast == .increased ? 0.26 : 0.18))
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
                .fill(tint.opacity(colorSchemeContrast == .increased ? 0.18 : 0.12))
                .overlay {
                    if colorSchemeContrast == .increased {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(tint.opacity(0.55), lineWidth: 0.75)
                    }
                }
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
        case .elevated, .warning, .critical:
            return CategoryPalette.statusColor(for: status)
        }
    }
}

