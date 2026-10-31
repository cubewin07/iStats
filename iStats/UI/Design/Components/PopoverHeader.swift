import SwiftUI
import iStatsCore

/// Standard popover header displaying category branding, dynamic status sentence, and severity badge.
public struct PopoverHeader: View {
    public let category: MetricCategory
    public let title: String
    public let subtitle: String
    public let statusLevel: StatusLevel
    public let badgeText: String

    public init(
        category: MetricCategory,
        title: String? = nil,
        subtitle: String,
        statusLevel: StatusLevel,
        badgeText: String
    ) {
        self.category = category
        self.title = title ?? category.displayName
        self.subtitle = subtitle
        self.statusLevel = statusLevel
        self.badgeText = badgeText
    }

    public init(category: MetricCategory, verdict: MetricVerdict, title: String? = nil) {
        self.init(
            category: category,
            title: title,
            subtitle: verdict.dadSentence,
            statusLevel: verdict.level,
            badgeText: verdict.badgeText
        )
    }

    public var body: some View {
        HStack(spacing: Tokens.sm) {
            // Category Icon Badge Chip
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.chipRadius, style: .continuous)
                    .fill(CategoryPalette.color(for: category).opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: category.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CategoryPalette.color(for: category))
            }
            .accessibilityHidden(true)

            // Category Title + Verdict Sentence
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Tokens.headerTitle)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(Tokens.bodyLabel)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Severity Status Pill
            HStack(spacing: 4) {
                Circle()
                    .fill(statusLevel.color)
                    .frame(width: 6, height: 6)

                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusLevel.color)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusLevel.color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(statusLevel.color.opacity(0.25), lineWidth: 0.5)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.displayName): \(subtitle). Status: \(badgeText)")
    }
}

#Preview("PopoverHeader - Light & Dark") {
    VStack(spacing: 16) {
        PopoverHeader(
            category: .cpu,
            subtitle: "The processor is working normally",
            statusLevel: .fine,
            badgeText: "Fine"
        )
        PopoverHeader(
            category: .thermal,
            subtitle: "macOS is throttling CPU to cool down",
            statusLevel: .critical,
            badgeText: "Too hot"
        )
    }
    .padding()
    .frame(width: Tokens.popoverWidth)
}
