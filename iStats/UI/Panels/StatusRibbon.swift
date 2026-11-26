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

        HStack(spacing: Instrument.Space.xs) {
            Text(Self.glyph(for: status))
                .font(Instrument.Typography.eyebrow)
            Text(titleText)
                .font(Instrument.Typography.eyebrow)
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

    @State private var isActionHovered: Bool = false
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

        HStack(spacing: Instrument.Space.m) {
            Image(systemName: status.symbolNameFilled)
                .font(Instrument.Typography.icon(Instrument.Icon.regular, weight: .semibold))
                .foregroundColor(tint)

            Text(message)
                .font(Instrument.Typography.caption)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let title = actionTitle, let action = action {
                let baseAlpha: Double = colorSchemeContrast == .increased ? 0.26 : 0.18
                Button(action: action) {
                    Text(title)
                        .font(Instrument.Typography.eyebrow)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: Instrument.Radius.inline, style: .continuous)
                                .fill(tint.opacity(isActionHovered ? min(1.0, baseAlpha + 0.10) : baseAlpha))
                        )
                        .foregroundColor(tint)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(Motion.snappy) {
                        isActionHovered = hovering
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Instrument.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.control, style: .continuous)
                .fill(tint.opacity(colorSchemeContrast == .increased ? 0.18 : 0.12))
                .overlay {
                    if colorSchemeContrast == .increased {
                        RoundedRectangle(cornerRadius: Instrument.Radius.control, style: .continuous)
                            .strokeBorder(tint.opacity(0.55), lineWidth: 0.75)
                    }
                }
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        ))
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

