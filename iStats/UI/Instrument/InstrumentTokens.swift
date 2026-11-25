import SwiftUI
import AppKit

/// Instrument Design System Tokens (ADR 0009 / Phase 8)
public enum Instrument {

    // MARK: - Spacing Scale (8 pt grid aligned)
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 6
        public static let m: CGFloat = 8
        public static let l: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let xxl: CGFloat = 20
        public static let xxxl: CGFloat = 24

        // Semantic aliases
        public static let modulePadding: CGFloat = l
        public static let eyebrowGap: CGFloat = s
        public static let stackSpacing: CGFloat = m
        /// Gap between page sections (signature instrument, consumers, ...).
        public static let sectionGap: CGFloat = l
    }

    // MARK: - Corner Radii
    public enum Radius {
        public static let panel: CGFloat = 16
        public static let module: CGFloat = 12
        public static let control: CGFloat = 8
        /// Small inline shapes: pills, chips, row highlights.
        public static let chip: CGFloat = 6
        /// Smallest rounded shape (hairline badges).
        public static let inline: CGFloat = 4
        public static let capsule: CGFloat = 999
    }

    // MARK: - Panel Dimensions
    public enum Size {
        public static let panelWidth: CGFloat = 352
        public static let contentWidth: CGFloat = 320
        public static let maxHeight: CGFloat = 560
        /// Header strip / title row band at the top of a panel.
        public static let headerStripHeight: CGFloat = 28
        /// Slim footer band at the bottom of a panel.
        public static let footerHeight: CGFloat = 24
        /// Chart height variants: compact (scaffold default), standard (Fans, Network, Disk), tall (History).
        public static let chartHeightCompact: CGFloat = 72
        public static let chartHeightStandard: CGFloat = 84
        public static let chartHeightTall: CGFloat = 140
    }

    // MARK: - Typography Scale (semantic ramp; SF Pro with tabular digits, SF Mono for identifiers)
    // Panels and the Kit never go below 10 pt (ADR 0011 rule 4). Use these tokens, not literal sizes.
    public enum Typography {
        /// Glance display numeral (44 pt, regular, monospaced digits)
        public static let display = Font.system(size: 44, weight: .regular).monospacedDigit()
        /// Unit symbol on baseline (17 pt, medium)
        public static let unit = Font.system(size: 17, weight: .medium)
        /// Secondary hero value / compact ticker (30 pt, regular, monospaced digits)
        public static let displayCompact = Font.system(size: 30, weight: .regular).monospacedDigit()
        /// Panel title / modal title (15 pt, semibold)
        public static let title = Font.system(size: 15, weight: .semibold)
        /// Prominent numeric readout (15 pt, medium, monospaced digits)
        public static let titleNumeric = Font.system(size: 15, weight: .medium).monospacedDigit()
        /// Glance headline / verdict summary (13 pt, regular)
        public static let headline = Font.system(size: 13, weight: .regular)
        /// Emphasized headline (13 pt, semibold)
        public static let headlineStrong = Font.system(size: 13, weight: .semibold)
        /// Table and row labels (12 pt, regular)
        public static let body = Font.system(size: 12, weight: .regular)
        /// Table and row values (12 pt, medium, monospaced digits)
        public static let value = Font.system(size: 12, weight: .medium).monospacedDigit()
        /// Insights, helper captions, section titles (11 pt, regular)
        public static let caption = Font.system(size: 11, weight: .regular)
        /// Emphasized caption: section titles, selected chips (11 pt, medium)
        public static let captionMedium = Font.system(size: 11, weight: .medium)
        /// Strong caption: selected chip/segment, ribbon title (11 pt, semibold)
        public static let captionStrong = Font.system(size: 11, weight: .semibold)
        /// Section headers and category labels (10 pt, semibold, uppercase)
        public static let eyebrow = Font.system(size: 10, weight: .semibold)
        /// Axis ticks and compact matrix indices (10 pt, medium, monospaced digits)
        public static let micro = Font.system(size: 10, weight: .medium).monospacedDigit()
        /// Monospaced identifiers: IP, MAC, BSD interfaces (11 pt SF Mono)
        public static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)

        /// SF Symbol glyph size (not text). Use the `Icon` presets where one fits.
        public static func icon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            Font.system(size: size, weight: weight)
        }
    }

    /// Standard SF Symbol glyph sizes.
    public enum Icon {
        public static let small: CGFloat = 10
        public static let regular: CGFloat = 11
        public static let medium: CGFloat = 13
        public static let large: CGFloat = 22
        public static let hero: CGFloat = 28
    }

    /// Convenience alias
    public typealias Fonts = Typography

    // MARK: - Surfaces & Depth
    public enum Surface {
        /// Panel base surface backing
        public static var panel: Color {
            Color(nsColor: NSColor.windowBackgroundColor)
        }

        /// Module background fill (4.5% light / 6.0% dark, no border)
        public static var module: Color {
            Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor.textColor.withAlphaComponent(isDark ? 0.06 : 0.045)
            }))
        }

        /// Hover elevation (+3% opacity)
        public static var moduleHover: Color {
            Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor.textColor.withAlphaComponent((isDark ? 0.06 : 0.045) + 0.03)
            }))
        }

        /// Inset meter tracks and gauge troughs
        public static var inset: Color {
            Color(nsColor: NSColor.textColor.withAlphaComponent(0.07))
        }

        /// Subtle top-inner highlight on dark surfaces (0.5 pt)
        public static var edgeHighlight: Color {
            Color.white.opacity(0.08)
        }

        /// Table row divider hairline (0.5 pt, 6% primary)
        public static let hairline = Color.primary.opacity(0.06)
    }
}

// MARK: - Previews

#Preview("Instrument palette") {
    VStack(alignment: .leading, spacing: 12) {
        Text("INSTRUMENT PALETTE").font(Instrument.Typography.eyebrow).tracking(0.8)
        HStack(spacing: 8) {
            ForEach([
                CategoryPalette.cpu,
                CategoryPalette.memory,
                CategoryPalette.gpu,
                CategoryPalette.thermal,
                CategoryPalette.fan,
                CategoryPalette.network,
                CategoryPalette.disk,
                CategoryPalette.power
            ], id: \.self) { color in
                RoundedRectangle(cornerRadius: Instrument.Radius.control)
                    .fill(color)
                    .frame(width: 32, height: 32)
            }
        }
    }
    .padding(Instrument.Space.xl)
    .frame(width: Instrument.Size.panelWidth)
    .background(Instrument.Surface.module)
}

#Preview("Type ramp") {
    VStack(alignment: .leading, spacing: 8) {
        Text("42%").font(Instrument.Typography.display)
        Text("Moderate load · 10 cores · 3.2 GHz").font(Instrument.Typography.headline).foregroundStyle(.secondary)
        Text("Peak 92% · 3m ago").font(Instrument.Typography.caption).foregroundStyle(.tertiary)
        Divider()
        HStack {
            Text("Xcode").font(Instrument.Typography.body)
            Spacer()
            Text("38.4%").font(Instrument.Typography.value)
        }
        HStack {
            Text("en0").font(Instrument.Typography.mono)
            Spacer()
            Text("192.168.1.100").font(Instrument.Typography.mono)
        }
    }
    .padding(Instrument.Space.xl)
    .frame(width: Instrument.Size.panelWidth)
}
