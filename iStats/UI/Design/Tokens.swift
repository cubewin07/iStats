import SwiftUI

/// Shared layout, spacing, typography, and visual styling tokens for iStats UI.
public enum Tokens {
    // MARK: - Layout Bounds
    public static let popoverWidth: CGFloat = 330
    public static let maxPopoverContentHeight: CGFloat = 480

    // MARK: - Spacing Scale
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16

    // MARK: - Corner Radii
    public static let chipRadius: CGFloat = 6
    public static let cardRadius: CGFloat = 10

    // MARK: - Typography
    public static let heroValue: Font = .system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
    public static let headerTitle: Font = .system(size: 13, weight: .semibold)
    public static let sectionTitle: Font = .system(size: 11, weight: .semibold)
    public static let bodyLabel: Font = .system(size: 11, weight: .regular)
    public static let monoValue: Font = .system(size: 11, weight: .medium, design: .monospaced)

    // MARK: - Card Surface
    public static let cardFill = Color(nsColor: .quaternaryLabelColor).opacity(0.12)
    public static let cardBorder = Color(nsColor: .separatorColor).opacity(0.25)
}

/// View modifier applying the standardized card background styling.
public struct CardBackgroundModifier: ViewModifier {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = Tokens.cardRadius) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Tokens.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Tokens.cardBorder, lineWidth: 0.5)
                    )
            )
    }
}

public extension View {
    func cardBackground(cornerRadius: CGFloat = Tokens.cardRadius) -> some View {
        modifier(CardBackgroundModifier(cornerRadius: cornerRadius))
    }
}
