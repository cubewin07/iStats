import SwiftUI
import AppKit
import iStatsCore

/// A macOS-style tinted squircle icon badge.
public struct SettingsBadge: View {
    public let icon: String
    public let color: Color
    public let size: CGFloat

    public init(icon: String, color: Color = .accentColor, size: CGFloat = 26) {
        self.icon = icon
        self.color = color
        self.size = size
    }

    /// Category identity badge (symbol and tint from `CategoryIdentity` / `CategoryPalette`).
    public init(category: MetricCategory, symbol: String? = nil, size: CGFloat = 26) {
        self.init(
            icon: symbol ?? category.identity.symbol(),
            color: CategoryPalette.color(for: category),
            size: size
        )
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26)
                .fill(color.opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

/// A compact badge indicating the hardware subcomponent source for a widget (e.g. Temperature source).
public struct MetricSourceBadge: View {
    public let source: MetricSource

    public init(source: MetricSource) {
        self.source = source
    }

    public var body: some View {
        Text(source.shortLabel)
            .font(Instrument.Typography.micro)
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}

